# cicd — reusable Tekton CI/CD substrate

The **reusable, project-agnostic** half of the on-cluster CI/CD: Tekton itself,
the build identity, the BuildKit backend, and the generic Tasks. Follows the
`infra/<category>/{controllers,configs}` split used by `storage`/`database`.

The **app-specific** half (doghouse's lint-realms / verify / publish-auth-svc
pipelines, the pin-release Task, the on-demand runs, and the CI secrets) is
private IP and lives in the doghouse repo at `ci/doghouse`, reconciled by the
`doghouse-ci` Flux Kustomization (`k8s/clusters/doghouse/apps.yaml`). Same
public/private boundary as the apps tree: pointers + reusable infra are public
here, doghouse pipelines are private.

## Layout

```
cicd/
  configs/tekton-ci/         # REUSABLE CI layer (Flux: cicd-configs)
    namespace.yaml  rbac.yaml  buildkit.yaml
    tasks/      clone-and-version · build-image · just-recipe   (project-agnostic;
                caller supplies url / target / dockerfile / context / workdir / recipe)
  images/ci-builder/         # build image (pants + buildx + git + just + uv); bootstrap once
  controllers/               # Tekton itself (Flux: cicd-controllers)
    tekton-pipelines/   CDF Helm chart (Pipelines + tekton.dev CRDs)
    tekton-dashboard/   vendored upstream read-only release.yaml + Traefik Ingress
    tekton-triggers/    vendored upstream release.yaml + interceptors.yaml (v0.33.0)
    cloudflared/        Cloudflare Tunnel → EventListener (Flux: cloudflare-controllers)
```

## Controllers (Flux-managed)

`cicd/controllers/` installs Tekton itself, reconciled by the `cicd-controllers`
Flux Kustomization (in `k8s/clusters/doghouse/infra.yaml`):

- **`tekton-pipelines/`** — Tekton **Pipelines** via the CDF Helm chart
  (`tekton-pipeline`, repo <https://cdfoundation.github.io/tekton-helm-chart/>).
  The HelmRelease installs the `tekton.dev` CRDs (`crds: CreateReplace`) into the
  `tekton-pipelines` namespace, then marks Ready. `cicd-configs`
  `dependsOn cicd-controllers`, so the `tekton.dev/v1` Task CRs only apply once
  those CRDs exist (same controllers→configs gating as `storage`/`database`).
- **`tekton-dashboard/`** — the **read-only** Dashboard. No Helm chart exists for
  it, so the pinned upstream `release.yaml` (v0.69.0) is vendored verbatim and
  exposed at `tekton.doghouse.lan` via a Traefik Ingress (the DNS override lives in
  the Ansible repo, like the other UIs).

- **`tekton-triggers/`** — Tekton **Triggers**, vendored verbatim (pinned
  v0.33.0 `release.yaml` + `interceptors.yaml`; no chart on the CDF repo). Adds
  the Triggers controller/webhook, the EventListener/TriggerBinding/Template CRDs,
  the `github`/`cel` ClusterInterceptors, and the `tekton-triggers-eventlistener-*`
  ClusterRoles. The shared `github-listener` EventListener + its SA/bindings (the
  GitHub-webhook entrypoint) are project-agnostic and live in
  `configs/tekton-ci/github-listener.yaml`; it binds per-project Trigger CRs by
  label, and those Triggers are doghouse IP in the private repo, next to source.

- **`cloudflared/`** — the **Cloudflare Tunnel** that gives GitHub a public path
  to the internal-only cluster: `cloudflared` dials out to Cloudflare's edge and
  forwards the webhook hostname to the `el-github-listener` Service. Reconciled by
  its own `cloudflare-controllers` Flux Kustomization — the only one here with
  SOPS decryption (for the committed tunnel token); `cicd-controllers` never sees
  it (not listed in the controllers kustomization).

## Reusable configs (Flux-managed)

`cicd/configs/tekton-ci/` is reconciled by `cicd-configs`. It carries no app
assumptions:

- **`namespace.yaml`** — the `tekton-ci` namespace (privileged PSA for rootless
  BuildKit's `/dev/fuse` + unconfined seccomp).
- **`rbac.yaml`** — `tekton-ci-bot`, the identity every PipelineRun runs as. Its
  only right is the `gar-pull` imagePullSecret (applied by `doghouse-ci`; the SA
  tolerates it being absent until then).
- **`buildkit.yaml`** — the long-lived rootless `buildkitd` that pants' buildx
  `remote` driver targets (k3s nodes are containerd, no docker daemon).
- **`tasks/clone-and-version.yaml`** — clone a repo at a revision and derive the
  CalVer tag from git (UTC commit timestamp → `YYYY.MM.DD.HHMMSS` + short sha).
- **`tasks/build-image.yaml`** — build (`push=false`, no-export buildx) or publish
  (`push=true`, `pants publish`) an image. The caller supplies `target` /
  `dockerfile` / `context`.
- **`tasks/just-recipe.yaml`** — run a `just` recipe in a project dir of the
  checkout (`test` / `build` / `publish`). The project's justfile owns what each
  verb does (pants + twine); the caller supplies `workdir` / `recipe` (and an
  optional `version` → `VERSION`, plus a `gar-creds` workspace →
  `GOOGLE_APPLICATION_CREDENTIALS` for twine publishes). Used by the
  service-utils pipelines.

## Architecture

```
PipelineRun (on demand)                       buildkitd (rootless, in-cluster)
  └─ clone-and-version  git → CalVer + sha            ▲ remote driver (tcp 1234)
       └─ lint-realms   (doghouse) realm guardrail    │
            └─ build-image                            │
                 verify  : buildx build (no push) ────┘
                 publish : pants publish → GAR (latest + CalVer)
                      └─ pin-release  (doghouse) tag → git push main → Flux rollout
```

- **Build engine: pants + BuildKit.** k3s nodes are amd64/containerd (no docker
  daemon), so a rootless `buildkitd` runs in-cluster and pants' buildx `remote`
  driver targets it. The publish path stays on `pants publish`; PR verify is a
  no-export `buildx build` (the remote driver can't `--load` without a daemon).
- **CalVer from git.** CI re-derives the tag from the git checkout (UTC commit
  timestamp → `YYYY.MM.DD.HHMMSS`).
- **Webhooks live (service-utils).** The shared `github-listener` EventListener
  (`configs/tekton-ci/github-listener.yaml`) fires `verify`/`publish` on GitHub
  PR/push events by binding per-project Trigger CRs by label; a Cloudflare Tunnel
  bridges GitHub to the internal-only cluster. service-utils' Triggers + pipelines
  are doghouse IP, next to the source in the private repo
  (`src/libraries/service-utils/ci`). On-demand `PipelineRun`s remain for manual
  kicks; the auth-svc pipelines are still on-demand only.

## Activation

1. **Bootstrap the build image** (one-time; defaults to amd64 for the cluster
   nodes, `FROM --platform` pins the manifest even from an arm64 host):
   ```sh
   just ci-builder          # build + push amd64 to GAR (just ci-builder arm64 for arm64)
   ```
2. **Flux is already wired** — `cicd-controllers` + `cicd-configs` (this repo) and
   `doghouse-ci` (private repo). Commit and reconcile; Flux installs Tekton, then
   the reusable substrate, then the doghouse pipelines + secrets.
3. **Author the doghouse CI secrets** — see `ci/doghouse/secrets/README.md` in the
   doghouse repo.
4. **Run on demand** — from the doghouse repo:
   ```sh
   kubectl create -n tekton-ci -f ci/doghouse/runs/publish-auth-svc.run.yaml
   kubectl create -n tekton-ci -f ci/doghouse/runs/verify.run.yaml
   ```
   Watch in the dashboard at <http://tekton.doghouse.lan> (read-only) or with
   `tkn -n tekton-ci pipelinerun logs --last -f`.

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
    tasks/      clone-and-version · build-image   (project-agnostic; caller
                supplies url / target / dockerfile / context)
  images/ci-builder/         # build image (pants + buildx + git); bootstrap once
  controllers/               # Tekton itself (Flux: cicd-controllers)
    tekton-pipelines/   CDF Helm chart (Pipelines + tekton.dev CRDs)
    tekton-dashboard/   vendored upstream read-only release.yaml + Traefik Ingress
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

Tekton **Triggers**/webhooks are still deferred (MVP is on-demand `PipelineRun`s).

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
- **Webhook deferred.** MVP is on-demand `PipelineRun`s (in the doghouse repo at
  `ci/doghouse/runs`). The `verify` pipeline is the eventual PR-webhook target.

## Activation

1. **Bootstrap the build image** (one-time):
   ```sh
   docker buildx build --platform linux/amd64 \
     -t us-east4-docker.pkg.dev/adept-fountain-498903-t7/poochella/ci-builder:latest \
     --push k8s/infra/cicd/images/ci-builder
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

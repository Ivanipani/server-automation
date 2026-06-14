# cicd — Tekton CI/CD for doghouse

On-cluster build/test/publish pipelines for the doghouse apps. Follows the
`infra/<category>/{controllers,configs}` split used by `storage`/`database`.

## Layout

```
cicd/
  configs/tekton-ci/         # the CI layer (this is what Flux reconciles)
    namespace.yaml  rbac.yaml  buildkit.yaml
    tasks/      clone-and-version · lint-realms · build-image · pin-release
    pipelines/  verify · publish-auth-svc
    runs/       on-demand PipelineRun templates (NOT reconciled by Flux)
    secrets/    SOPS secrets (author from *.example — see secrets/README.md)
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
  `dependsOn cicd-controllers`, so the `tekton.dev/v1` Task/Pipeline CRs only apply
  once those CRDs exist (same controllers→configs gating as `storage`/`database`).
- **`tekton-dashboard/`** — the **read-only** Dashboard. No Helm chart exists for
  it, so the pinned upstream `release.yaml` (v0.69.0) is vendored verbatim and
  exposed at `tekton.doghouse.lan` via a Traefik Ingress (the DNS override lives in
  the Ansible repo, like the other UIs).

Tekton **Triggers**/webhooks are still deferred (MVP is on-demand `PipelineRun`s).

## Architecture

```
PipelineRun (on demand)                       buildkitd (rootless, in-cluster)
  └─ clone-and-version  git → CalVer + sha            ▲ remote driver (tcp 1234)
       └─ lint-realms   doghouse realm guardrail      │
            └─ build-image                            │
                 verify  : buildx build (no push) ────┘
                 publish : pants publish → GAR (latest + CalVer)
                      └─ pin-release  GNU sed tag → git push main → Flux rollout
```

- **Build engine: pants + BuildKit.** k3s nodes are amd64/containerd (no docker
  daemon), so a rootless `buildkitd` runs in-cluster and pants' buildx `remote`
  driver targets it. The publish path stays on `pants publish` (tags + OCI labels
  from doghouse `images/BUILD`); PR verify is a no-export `buildx build` (the
  remote driver can't `--load` without a daemon).
- **CalVer from git.** doghouse derives the tag from `jj`; CI re-derives it from
  the git checkout (UTC commit timestamp → `YYYY.MM.DD.HHMMSS`).
- **GitOps loop.** On publish, `pin-release` rewrites the image tag in
  `apps/doghouse/keycloak/release.yaml` (GNU-sed port of the BSD `_pin` recipe)
  and pushes to `main`; Flux reconciles the rollout.
- **Webhook deferred.** MVP is on-demand `PipelineRun`s. The `verify` pipeline is
  the eventual PR-webhook target (add Tekton Triggers + an EventListener, reached
  via a smee/gosmee relay since the cluster is `.lan`-only).

## Activation

1. **Bootstrap the build image** (one-time):
   ```sh
   docker buildx build --platform linux/amd64 \
     -t us-east4-docker.pkg.dev/adept-fountain-498903-t7/poochella/ci-builder:latest \
     --push k8s/infra/cicd/images/ci-builder
   ```
2. **Author the secrets** — see `configs/tekton-ci/secrets/README.md`, then
   uncomment them in `configs/tekton-ci/kustomization.yaml`.
3. **Flux is already wired** — `cicd-controllers` + `cicd-configs` live in
   `k8s/clusters/doghouse/infra.yaml`. Just commit and reconcile; Flux installs
   Tekton, then applies the CI definitions.
4. **Run on demand**:
   ```sh
   kubectl create -n tekton-ci -f configs/tekton-ci/runs/publish-auth-svc.run.yaml
   kubectl create -n tekton-ci -f configs/tekton-ci/runs/verify.run.yaml
   ```
   Watch progress in the dashboard at <http://tekton.doghouse.lan> (read-only) or
   with `tkn -n tekton-ci pipelinerun logs --last -f`.

# CI/CD — Tekton Pipelines as Code

Projects own their `.tekton/` PipelineRuns. Pipelines as Code receives GitHub
App events, resolves the pipeline from the triggering revision, executes it
with Tekton, and reports GitHub checks. Doghouse is the first enrolled repository.

See [activation and project enrollment](controllers/pipelines-as-code/README.md)
for GitHub App credentials, Cloudflare routing, a smoke pipeline, and cutover.
The manifests are prepared; activation requires those external steps.

## Platform ownership

- `controllers/tekton-pipelines`: Tekton execution engine via Helm, including
  PVC workspace co-scheduling.
- `controllers/pipelines-as-code`: pinned upstream controller, watcher and
  admission webhook, reconciled after Tekton is Ready.
- `controllers/tekton-dashboard`: read-only UI at <http://tekton.doghouse.lan>.
- `controllers/tekton-pruner`: existing Tekton run cleanup.
- `controllers/cloudflared`: outbound Cloudflare Tunnel; configure its remote
  ingress to the Pipelines as Code controller service.
- `configs/pipelines-as-code`: Repository enrollment, reconciled after PaC and
  the shared build substrate are Ready.
- `configs/tekton-ci`: build identity, rootless BuildKit, Pants cache, and
  reusable `clone-and-version`, `build-image` and `just-recipe` Tasks.

Doghouse's application-specific pipelines and secrets remain private. Flux
owns persistent resources; PaC owns event-driven PipelineRuns. The private
`doghouse-ci` Flux import is suspended until its old Trigger resources are
removed and its pipelines are migrated to `.tekton/`.

## Build substrate

Builds use Pants and a remote rootless BuildKit daemon because the k3s nodes
run containerd. `build-image` supports verification and publishing; `just-recipe`
runs a project-owned recipe. The SSH-based `clone-and-version` task derives
CalVer from the checked-out commit. See the enrollment guide before switching
checkout to PaC's HTTPS App token.

The `tekton-ci-bot` account references the private repo's `gar-pull` Secret.
BuildKit requires the existing privileged namespace policy. The shared Pants
cache uses a Longhorn RWO PVC; concurrent runs on different nodes can contend.
Keep runs using this cache on the same worker or migrate the cache to RWX.

The old Triggers and custom GitHub status implementation are removed. Its
pre-migration revision is retained as local Jujutsu bookmark `legacy-tekton-ci`.

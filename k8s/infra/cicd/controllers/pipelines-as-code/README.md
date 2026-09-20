# Pipelines as Code

Vendored Kubernetes release: [v0.51.0](https://github.com/tektoncd/pipelines-as-code/releases/tag/v0.51.0).
`release.yaml` is the unmodified upstream `release.k8s.yaml`, SHA-256
`a460b4dbd55e04175092242d17524fa2f3681209c6df359e9bf83a99f92de4a8`.
Keep local changes in `kustomization.yaml` when upgrading.

Flux installs this separately after `cicd-controllers` is Ready. Enrollment
reconciles after this controller and `cicd-configs`, so both the Repository CRD
and execution namespace exist. Do not add these directories to the existing
controllers/configs roots: they have separate Flux owners.

## GitHub App activation

1. Add a public hostname to the existing Cloudflare Tunnel with service
   `http://pipelines-as-code-controller.pipelines-as-code.svc.cluster.local:8080`.
   Replace the old EventListener route with this service.
   Cloudflare manages this tunnel's ingress remotely. TLS terminates at its edge.
   The webhook route must accept GitHub POSTs without interactive authentication.
2. Create a GitHub App using the upstream
   [GitHub App setup](https://pipelinesascode.com/docs/providers/github-app/).
   Set its webhook URL to the public HTTPS hostname. Follow the documented
   permissions and event subscriptions, generate its private key and a webhook
   secret, and install it on **Ivanipani/doghouse**.
3. Create `github-app.sops.yaml` in this directory containing a Secret named
   `pipelines-as-code-secret` in namespace `pipelines-as-code`. Supply these
   `stringData` keys from the App setup:
   - `github-application-id`: the App ID (quoted string, not installation ID)
   - `github-private-key`: the PEM private key (YAML block scalar)
   - `webhook.secret`: the same secret configured in GitHub

   Encrypt before adding the file to version control, from the `k8s` directory:

   ```sh
   sops --encrypt --in-place infra/cicd/controllers/pipelines-as-code/github-app.sops.yaml
   ```

   Add `github-app.sops.yaml` to this directory's `resources`. The Flux
   Kustomization already enables SOPS decryption. Credentials are deliberately
   absent from the initial setup; no events can authenticate until supplied.
4. Reconcile the infrastructure and check readiness:

   ```sh
   flux get kustomizations -n flux-system
   kubectl -n pipelines-as-code get deployments
   kubectl -n tekton-ci get repositories.pipelinesascode.tekton.dev
   ```

The dashboard URL is LAN-only; GitHub users need LAN/VPN access to open run
details there. GitHub checks still report status independently.

## Project enrollment and pipeline ownership

Doghouse is enrolled by `configs/pipelines-as-code/doghouse.yaml`. A project
needs both an App installation and a `Repository` CR with its HTTPS URL in the
execution namespace. One Repository represents the whole repository, including
all projects in a monorepo. Additional independent repositories should have
their own namespace, service account and secrets; `tekton-ci` currently shares
doghouse's credentials and caches and is not an isolation boundary.

The private doghouse repository owns `.tekton/*.yaml` PipelineRuns. PaC reads
them from the event's source revision, so a PR exercises its own pipeline edits.
Flux continues to manage persistent infrastructure and secrets; do not include
these event-driven PipelineRuns in the private repo's Flux resources.

Start with this `.tekton/pac-smoke.yaml` in **doghouse**, outside this public repo:

```yaml
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: doghouse-pac-smoke-
  annotations:
    pipelinesascode.tekton.dev/on-event: "[pull_request, push]"
    pipelinesascode.tekton.dev/on-target-branch: "[main]"
    pipelinesascode.tekton.dev/target-namespace: tekton-ci
    pipelinesascode.tekton.dev/max-keep-runs: "5"
spec:
  taskRunTemplate:
    serviceAccountName: tekton-ci-bot
  pipelineSpec:
    tasks:
      - name: smoke
        taskSpec:
          steps:
            - name: smoke
              image: alpine:3.22
              script: |
                #!/bin/sh
                echo "Pipelines as Code received the GitHub event."
```

Open a PR and confirm the check reaches success. Exercise `/retest` and a new
push, and check the App's webhook delivery history for successful responses.
This smoke run validates event handling, execution and checks, not checkout or
the project's build. Then migrate each actual verify/publish PipelineRun into
`.tekton/`, matching PRs and pushes with PaC annotations. Keep publish runs
restricted to pushes on the release branch.

Use `{{ repo_url }}` and `{{ revision }}` for checkout. PaC provides a scoped,
short-lived App token through `{{ git_auth_secret }}`; use its `basic-auth`
workspace with a compatible HTTPS clone task. The existing `clone-and-version`
task requires an SSH workspace and does not consume that secret directly.
Existing namespaced tasks remain callable, while project-owned tasks/pipelines
can be resolved from `.tekton/` using the
[PaC resolver](https://pipelinesascode.com/docs/guides/pipeline-resolution/).
Preserve workspace paths and CalVer results when replacing the clone task.

PaC applies its contributor authorization rules before running PR code. Keep
default authorization in place and review pipeline changes before authorizing
outside contributors: doghouse runs can access namespace secrets and BuildKit.

## Cutover

The pre-migration implementation is preserved by the local Jujutsu bookmark
`legacy-tekton-ci` at `2f24e955`. The bookmark has not been pushed to a remote.

This change removes Tekton Triggers, the EventListener, custom CloudEvent status
sink, status PAT Secret, explicit status Task and resolver PAT configuration.
Flux pruning removes their managed resources, including the Triggers CRDs and
legacy Trigger objects. Existing webhook CI stops at reconciliation until the
App, tunnel route and private `.tekton/` definitions are ready.

`doghouse-ci` is suspended to prevent the private `./ci` tree from reconciling
obsolete Trigger resources. Its existing secrets and other resources remain.
In the private repository, remove legacy Triggers/TriggerTemplates/Bindings and
migrate event pipelines into `.tekton/`. Keep persistent build secrets and any
shared tasks under `./ci`. Then remove `spec.suspend` from `doghouse-ci` here.
Update GitHub branch protection to the new check names after a successful run,
remove old repository webhooks, and revoke the unused status/resolver PATs.
The public repo cannot remove secrets still owned by the private Flux source.

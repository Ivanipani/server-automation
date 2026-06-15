# tekton-ci secrets

Two SOPS-encrypted Secrets gate the pipelines. Author them, encrypt with the
cluster age key (`k8s/.sops.yaml`), then list them in `../kustomization.yaml`.
Encrypt with `sops -e -i <file>.sops.yaml` (only `data`/`stringData` is
encrypted, per the repo `.sops.yaml`).

| Secret         | Type             | Used by | Notes |
|----------------|------------------|---------|-------|
| `gar-pull`     | dockerconfigjson | SA `tekton-ci-bot` imagePullSecret **and** the `build-image` push step | **One** GAR **Writer** credential for both pull and push. The SA uses it to pull the private `ci-builder` image; the publish run projects its `.dockerconfigjson` to `config.json` for the push (`DOCKER_CONFIG`). A Writer can pull, so no separate pull-only secret. |
| `doghouse-git` | Opaque (`id_ed25519`) | `clone-and-version`, `pin-release` | **Write**-capable SSH deploy key, registered on `Ivanipani/doghouse`. |

`gar-pull` — create from the Writer service-account key (a dockerconfigjson
Secret, valid as both an imagePullSecret and a docker `config.json`):

```sh
kubectl create secret docker-registry gar-pull \
  --docker-server=us-east4-docker.pkg.dev \
  --docker-username=_json_key \
  --docker-password="$(cat gar-secret.json)" \
  --namespace=tekton-ci --dry-run=client -o yaml > gar-pull.sops.yaml
sops -e -i gar-pull.sops.yaml
```

Until these exist, the Flux Kustomization still reconciles (namespace, buildkitd,
Task/Pipeline defs are valid without them) — only `PipelineRun`s fail.

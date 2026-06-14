# tekton-ci secrets

Three SOPS-encrypted Secrets gate the pipelines. They are **not** committed yet —
author them from the `*.example` templates, encrypt with the cluster age key
(`k8s/.sops.yaml`), then uncomment them in
`../kustomization.yaml`. Encrypt with `sops -e -i <file>.sops.yaml` (only
`data`/`stringData` is encrypted, per the repo `.sops.yaml`).

| Secret          | Type                | Used by                          | Notes |
|-----------------|---------------------|----------------------------------|-------|
| `gar-pull`      | dockerconfigjson    | ServiceAccount `tekton-ci-bot`   | Pull-only creds for the private `ci-builder` image. Mirror the doghouse `gar-pull` secret. |
| `gar-push`      | Opaque (`config.json`) | `build-image` (push)          | Artifact Registry **Writer** creds, mounted as `DOCKER_CONFIG`. From `gar-push.sops.yaml.example`. |
| `doghouse-git`  | Opaque (`id_ed25519`) | `clone-and-version`, `pin-release` | **Write**-capable SSH deploy key. From `doghouse-git.sops.yaml.example`. |

`gar-pull` (create from the writer or a pull-only SA key):

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

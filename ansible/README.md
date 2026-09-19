# Ansible execution environment

Build and load the image with Docker running, Pants, uv, and just installed:

```sh
just ee-build
just ee ansible --version
just ee ansible-galaxy collection list
just ee ansible-playbook --syntax-check components/kube/site.yml \
  --vault-password-file /workspace/secrets/ansible-pass
```

`just ee` mounts the checkout and `~/.ssh` read-only and runs from `ansible/`
using the repository configuration. Stage `~/.ssh/ansible` and the vault password
on the host first. Playbooks that write local files need a writable mount;
host provisioning through `connection: local` operates inside the container.
Host tools such as kubectl, helm, and flux are not included.

Edit `execution-environment.yaml` for system and Python dependencies, and
`requirements.yml` for Galaxy collections. Run `just ee-context` and include
the regenerated `context/` files in the same change. Ansible Builder 3.1.1
generates the context; Pants builds the image:

```sh
pants package ansible/context:ee
```

Only the Dockerfile and declared `_build/` files enter the Pants build context.
The image defaults to the local Docker architecture and tag `ansible-ee:latest`.
Set `ANSIBLE_EE_TAG` for a different tag. Dependencies currently use upstream
version ranges; reuse the same built image for consistent runs, and pin versions
and the base image digest if reproducible rebuilds are required.

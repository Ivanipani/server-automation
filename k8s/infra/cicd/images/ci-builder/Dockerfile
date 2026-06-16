# CI build image for the doghouse Tekton pipelines: the docker CLI + buildx
# plugin (talks to the in-cluster rootless buildkitd over the `remote` driver,
# no docker daemon), scie-pants (pants builds/tests/packages — it bootstraps its
# own python via python-build-standalone), `just` (the recipe runner the project
# pipelines call), `uv` (runs twine to publish wheels to the GAR python repo and
# auto-provisions a python for it), git + openssh for clone/push-back, and GNU
# sed for the manifest pin step.
#
# Built amd64 for the cluster nodes. Bootstrap once, then it's pulled by every
# Task (see k8s/infra/cicd/README.md):
#   docker buildx build --platform linux/amd64 \
#     -t us-east4-docker.pkg.dev/adept-fountain-498903-t7/poochella/ci-builder:latest \
#     --push k8s/infra/cicd/images/ci-builder
FROM debian:12-slim

ARG DOCKER_VERSION=29.5.1
ARG BUILDX_VERSION=0.34.1
ARG JUST_VERSION=1.51.0
ARG UV_VERSION=0.11.14

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git openssh-client bash sed coreutils \
    && rm -rf /var/lib/apt/lists/*

# docker CLI (static) — only the client; the engine is the remote buildkitd.
RUN curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz" \
        | tar -xz -C /usr/local/bin --strip-components=1 docker/docker

# buildx plugin.
RUN mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -fsSL -o /usr/local/lib/docker/cli-plugins/docker-buildx \
        "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-amd64" \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

# scie-pants launcher (resolves the repo-pinned pants version at first run).
RUN curl -fsSL https://static.pantsbuild.org/setup/get-pants.sh -o /tmp/get-pants.sh \
    && bash /tmp/get-pants.sh -d /usr/local/bin \
    && rm /tmp/get-pants.sh

# just — the recipe runner the project justfiles expose (test / build / publish).
RUN curl -fsSL "https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
        | tar -xz -C /usr/local/bin just

# uv — runs twine (with the GAR keyring backend) to publish wheels and provisions
# an ephemeral python for it.
COPY --from=ghcr.io/astral-sh/uv:${UV_VERSION} /uv /usr/local/bin/uv

ENV DOCKER_BUILDKIT=1
WORKDIR /workspace

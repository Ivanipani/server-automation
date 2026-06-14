# CI build image for the doghouse Tekton pipelines: the docker CLI + buildx
# plugin (talks to the in-cluster rootless buildkitd over the `remote` driver,
# no docker daemon), scie-pants (the publish path stays on pants), git + openssh
# for clone/push-back, and GNU sed for the manifest pin step.
#
# Built amd64 for the cluster nodes. Bootstrap once, then it's pulled by every
# Task (see k8s/infra/cicd/README.md):
#   docker buildx build --platform linux/amd64 \
#     -t us-east4-docker.pkg.dev/adept-fountain-498903-t7/poochella/ci-builder:latest \
#     --push k8s/infra/cicd/images/ci-builder
FROM debian:12-slim

ARG DOCKER_VERSION=27.5.1
ARG BUILDX_VERSION=0.18.2

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

ENV DOCKER_BUILDKIT=1
WORKDIR /workspace

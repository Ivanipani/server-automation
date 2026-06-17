# CI build image for the doghouse Tekton pipelines: the docker CLI + buildx
# plugin (talks to the in-cluster rootless buildkitd over the `remote` driver,
# no docker daemon), scie-pants (pants builds/tests/packages — it bootstraps its
# own python via python-build-standalone), `just` (the recipe runner the project
# pipelines call), `uv` (runs twine to publish wheels to the GAR python repo and
# auto-provisions a python for it), git + openssh for clone/push-back, and GNU
# sed for the manifest pin step, and jq (the discover-changed-images task emits
# its change-detection results as JSON array/count).
#
# Built + pushed by Pants via buildx — the target arch comes from the
# docker_image `build_platform` field (see BUILD), which sets buildx's
# `--platform`; buildx then populates $TARGETARCH below to pick the per-arch
# binaries. Defaults to amd64 (the cluster nodes); see `just ci-builder`.
ARG UV_VERSION=0.11.14

# Named stage so the uv image tag can be parameterized — `--from` does not
# support variable expansion, so it must reference a stage, not an ARG'd ref.
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM debian:12-slim

# Provided automatically by buildx from the build platform (amd64 | arm64).
ARG TARGETARCH
ARG DOCKER_VERSION=29.5.1
ARG BUILDX_VERSION=0.34.1
ARG JUST_VERSION=1.51.0

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git openssh-client bash sed coreutils jq \
    && rm -rf /var/lib/apt/lists/*

# docker CLI (static) — only the client; the engine is the remote buildkitd.
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) dockerArch=x86_64 ;; \
        arm64) dockerArch=aarch64 ;; \
        *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://download.docker.com/linux/static/stable/${dockerArch}/docker-${DOCKER_VERSION}.tgz" \
        | tar -xz -C /usr/local/bin --strip-components=1 docker/docker

# buildx plugin.
RUN set -eux; \
    mkdir -p /usr/local/lib/docker/cli-plugins; \
    curl -fsSL -o /usr/local/lib/docker/cli-plugins/docker-buildx \
        "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-${TARGETARCH}"; \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

# scie-pants launcher (resolves the repo-pinned pants version at first run;
# get-pants.sh auto-detects the host architecture).
RUN curl -fsSL https://static.pantsbuild.org/setup/get-pants.sh -o /tmp/get-pants.sh \
    && bash /tmp/get-pants.sh -d /usr/local/bin \
    && rm /tmp/get-pants.sh

# just — the recipe runner the project justfiles expose (test / build / publish).
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64) justArch=x86_64-unknown-linux-musl ;; \
        arm64) justArch=aarch64-unknown-linux-musl ;; \
    esac; \
    curl -fsSL "https://github.com/casey/just/releases/download/${JUST_VERSION}/just-${JUST_VERSION}-${justArch}.tar.gz" \
        | tar -xz -C /usr/local/bin just

# uv — runs twine (with the GAR keyring backend) to publish wheels and provisions
# an ephemeral python for it.
COPY --from=uv /uv /usr/local/bin/uv

ENV DOCKER_BUILDKIT=1
WORKDIR /workspace

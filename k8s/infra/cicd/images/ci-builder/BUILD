# Tekton CI builder image. Built + pushed with `pants publish` over buildx
# ([docker].use_buildx). `build_platform` sets buildx's `--platform`, so the
# image is built for the target arch regardless of the host (e.g. amd64 from an
# arm64 Mac); buildx feeds $TARGETARCH to the Dockerfile to select per-arch
# binaries.
#
# Defaults to the cluster nodes' amd64; override the arch per-invocation with the
# CI_BUILDER_PLATFORM env var (the `just ci-builder [arch]` recipe does this):
#   CI_BUILDER_PLATFORM=linux/arm64 pants publish k8s/infra/cicd/images/ci-builder:ci-builder
# For a multi-arch manifest, hardcode several here, e.g.
# build_platform=["linux/amd64", "linux/arm64"].
docker_image(
    name="ci-builder",
    repository="ci-builder",
    registries=["@poochella"],
    image_tags=[env("CI_BUILDER_TAG", "latest")],
    build_platform=[env("CI_BUILDER_PLATFORM", "linux/amd64")],
)

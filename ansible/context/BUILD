# Regenerate Dockerfile and _build with `just ee-context`.
files(
    name="build-context",
    sources=["_build/**/*"],
)

docker_image(
    name="ee",
    repository="ansible-ee",
    registries=[],
    image_tags=[env("ANSIBLE_EE_TAG", "latest")],
    context_root="./",
    dependencies=[":build-context"],
)

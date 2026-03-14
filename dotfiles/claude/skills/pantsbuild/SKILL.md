# Pantsbuild Skill

This skill provides expert guidance for working with Pantsbuild — a fast, scalable build system for monorepos. Use it when helping users write BUILD files, configure `pants.toml`, or run Pants goals for Python, Docker, Shell, and Ad-Hoc tool integrations.

## Documentation

- Welcome: https://www.pantsbuild.org/stable/docs/introduction/welcome-to-pants
- Targets & BUILD files: https://www.pantsbuild.org/stable/docs/using-pants/key-concepts/targets-and-build-files
- Python: https://www.pantsbuild.org/stable/docs/python/overview
- Docker: https://www.pantsbuild.org/stable/docs/docker
- Shell: https://www.pantsbuild.org/stable/docs/shell
- Ad-hoc tools: https://www.pantsbuild.org/stable/docs/ad-hoc-tools/ad-hoc-tool-overview

---

## Core Concepts

### Target Addressing

```
path/to/dir:name      # fully qualified
:name                 # relative to current BUILD file
//:name               # root of repo
path/to/dir           # shorthand when target name == directory name
path/to/file.py       # generated target from a generator (e.g. python_sources)
path/to:gen#dep       # generated third-party dep target
```

### BUILD File Builtins

```python
# Apply defaults across a directory subtree
__defaults__({
    python_sources: {"resolve": "python-default"},
    python_tests: {"timeout": 60},
})

# Parametrize a target (creates multiple variants)
shunit2_tests(
    name="tests",
    shell=parametrize("bash", "zsh"),
)

# Read environment variables
docker_image(
    name="app",
    extra_build_args=[f"VERSION={env('BUILD_VERSION', 'dev')}"],
)
```

### Dependency Syntax

```python
python_sources(
    name="lib",
    dependencies=[
        "other/dir:lib",           # first-party target
        "3rdparty:reqs#django",    # third-party requirement
        "!helloworld/other:lib",   # exclude inferred dep (single !)
    ],
)

pex_binary(
    name="app",
    dependencies=["!!some/transitive:dep"],  # transitive exclusion (leaf targets only)
)
```

---

## `pants.toml` Configuration

### Full Example

```toml
[GLOBAL]
pants_version = "2.31.0"
backend_packages = [
  # Python
  "pants.backend.python",
  "pants.backend.python.lint.ruff",
  "pants.backend.python.lint.black",
  "pants.backend.python.lint.isort",
  "pants.backend.python.lint.pylint",
  "pants.backend.python.lint.bandit",
  "pants.backend.python.typecheck.mypy",
  # Docker
  "pants.backend.docker",
  "pants.backend.docker.lint.hadolint",
  # Shell
  "pants.backend.shell",
  "pants.backend.shell.lint.shfmt",
  "pants.backend.shell.lint.shellcheck",
  # Ad-hoc tools
  "pants.backend.experimental.adhoc",
  # BUILD file formatting
  "pants.backend.build_files.fmt.black",
]

[source]
root_patterns = ["/"]   # or ["src", "src/python"]

[python]
interpreter_constraints = ["==3.12.*"]
enable_resolves = true
default_resolve = "python-default"
resolves = { python-default = "python-default.lock" }
invalid_lockfile_behavior = "error"   # "warn" | "ignore"

[python-bootstrap]
search_path = ["<PATH>", "<PYENV>"]

[docker]
default_repository = "{parent_directory}/{name}"
use_buildx = true
build_args = ["BUILDKIT_INLINE_CACHE=1"]

[docker.registries.my-registry]
address = "gcr.io/myproject"
default = true
extra_image_tags = ["{build_args.GIT_SHA}"]

[test]
output = "failed"       # "all" | "failed" | "never"
timeout_default = 60
timeout_maximum = 600

[ruff]
args = ["--line-length=100"]

[black]
args = ["--line-length=100"]

[isort]
args = ["--profile=black"]

[mypy]
args = ["--strict"]

[shellcheck]
args = ["--external-sources"]

[shfmt]
args = ["-i 2", "-ci"]
```

---

## Python Integration

### BUILD Targets

```python
# python_sources — one python_source target per .py file
python_sources(
    name="lib",
    sources=["*.py", "!generated_*.py"],
    resolve="python-default",
    interpreter_constraints=["==3.12.*"],
    skip_mypy=True,
    skip_ruff=False,
)

# python_tests
python_tests(
    name="tests",
    timeout=120,
    batch_compatibility_tag="my_batch",
    xdist_concurrency=4,
    extra_env_vars=["MY_VAR=value", "INHERITED_VAR"],
    runtime_package_dependencies=[":my_pex"],
)

# python_requirements — generates targets from requirements.txt
python_requirements(
    name="reqs",
    source="requirements.txt",
    resolve="python-default",
    module_mapping={"PIL": ["Pillow"]},
    overrides={
        "django": {"dependencies": ["#setuptools"]},
    },
)

# pex_binary — hermetic executable
pex_binary(
    name="app",
    entry_point="mypackage.main:main",
    resolve="python-default",
    execution_mode="zipapp",    # "venv" | "zipapp"
    layout="zipapp",            # "loose" | "packed" | "zipapp"
    output_path="dist/app.pex",
    # Cross-platform:
    complete_platforms=[":linux_x86_64_complete_platform"],
)

# python_distribution — sdist / wheel
python_distribution(
    name="dist",
    dependencies=[":lib"],
    wheel=True,
    sdist=True,
    provides=setup_py(
        name="myapp",
        version="1.0.0",
    ),
    entry_points={
        "console_scripts": {"myapp": "myapp.cli:main"},
    },
)
```

### Python CLI Commands

```bash
pants generate-lockfiles                    # Generate lockfiles for all resolves
pants generate-lockfiles --resolve=python-default

pants test ::                              # Run all tests
pants test src/myapp/tests::
pants test src/myapp/tests/test_foo.py
pants test --force ::                      # Bypass cache

pants lint ::                              # Run all linters
pants fmt ::                               # Run all formatters
pants check ::                             # Type-check (mypy / pyright)

pants package src/myapp:app                # Build PEX binary
pants run src/myapp:app                    # Run a PEX
pants run src/myapp:app -- --arg1 val      # With arguments

pants tailor ::                            # Auto-generate BUILD files
pants tailor --check ::                    # CI: fail if BUILD files are missing
```

---

## Docker Integration

### BUILD Targets

```python
docker_image(
    name="app",
    source="Dockerfile",                   # default
    dependencies=[
        ":app_pex",                        # pex_binary → COPY into image
        ":config_file",
        ":base_image",                     # another docker_image (base)
    ],
    image_tags=["latest", "{build_args.GIT_SHA}"],
    repository="{parent_directory}/{name}",
    registries=["@my-registry", "docker.io/myorg"],
    extra_build_args=["VERSION=1.0"],
    build_platform=["linux/amd64", "linux/arm64"],
    target_stage="production",             # multi-stage build
    context_root=".",
    skip_push=False,
    skip_hadolint=False,
    image_labels={
        "org.opencontainers.image.version": "{build_args.VERSION}",
    },
    # BuildKit secrets
    secrets={"mysecret": "/run/secrets/my_secret"},
    # BuildKit cache
    cache_from=[{"type": "registry", "ref": "myregistry/myapp:cache"}],
    cache_to={"type": "registry", "ref": "myregistry/myapp:cache"},
)
```

### Image Tag Interpolation Placeholders

| Placeholder | Meaning |
|---|---|
| `{name}` | target name |
| `{directory}` | BUILD file directory name |
| `{parent_directory}` | parent of BUILD file directory |
| `{full_directory}` | full path to BUILD file directory |
| `{build_args.ARG}` | Docker build argument value |
| `{pants.hash}` | unique hash of build inputs |
| `{tags.<stage>}` | tags from a named FROM stage |

### Dockerfile Dependency Inference

```dockerfile
# Inferred dependency on pex_binary at src/python/helloworld:bin
COPY src.python.helloworld/bin.pex /app/

# Dynamic base image via ARG
ARG BASE_IMAGE=:base
FROM ${BASE_IMAGE}
```

### Docker CLI Commands

```bash
pants package src/myapp::                  # Build image(s)
pants run src/myapp:app                    # Run container locally
pants run src/myapp:app -- --port 8080
pants publish src/myapp:app                # Push to configured registries
pants lint src/myapp::                     # Lint Dockerfiles (hadolint)

# Inject git SHA at build time
GIT_SHA=$(git rev-parse HEAD) pants package src/myapp:docker_image
```

---

## Shell Integration

### BUILD Targets

```python
# shell_sources — declare shell scripts
shell_sources(
    name="scripts",
    sources=["*.sh"],
)

# shunit2_tests — unit-test shell scripts
shunit2_tests(
    name="tests",
    sources=["test_*.sh"],
    shell=parametrize("bash", "zsh"),    # test with multiple shells
    timeout=60,
    extra_env_vars=["MY_VAR=value"],
    runtime_package_dependencies=[":my_pex"],
    overrides={
        "test_slow.sh": {"timeout": 120},
    },
)

# shell_command — run a script as a code-gen / side-effect step
shell_command(
    name="generate-code",
    command="./scripts/generate.sh --output generated/",
    tools=["bash", "curl", "tar", "env"],
    execution_dependencies=[":scripts", "data:input_files"],
    output_files=["generated/output.py"],
    output_directories=["generated/"],
    extra_env_vars=["API_KEY"],
    timeout=120,
    log_output=True,
    cache_scope="success",   # "session" | "from_environment" | "success_per_pantsd_restart"
)

# test_shell_command — run a shell command as a test
test_shell_command(
    name="integration-test",
    command="test -r $CHROOT/some-data-file.txt",
    tools=["test", "bash"],
    execution_dependencies=["src/project/files:data"],
    timeout=30,
    extra_env_vars=["TEST_ENV=ci"],
)
```

### Shellcheck Dependency Hints

For dynamically-sourced scripts, add hints so Pants can infer deps:

```bash
# shellcheck source=dir/other_script.sh
source "${DYNAMIC_PATH}"
```

### Shell CLI Commands

```bash
pants fmt src/scripts::                    # Format with shfmt
pants lint src/scripts::                   # Lint with shellcheck
pants test src/scripts::                   # Run shunit2 tests
pants run src/scripts:generate             # Run shell_command
pants test 'src/scripts:tests@shell=zsh'  # Test with specific shell variant
```

---

## Ad-Hoc Tools Integration

Ad-hoc tools let you integrate any external executable into the Pants build graph without writing a plugin — useful for code generators, custom linters, or any tool not natively supported.

### BUILD Targets

```python
# system_binary — wrap an OS-managed executable
system_binary(
    name="bash",
    binary_name="bash",
    extra_search_paths=["/usr/local/bin", "/usr/bin"],
    fingerprint=r"GNU bash, version \d+\.\d+",
    fingerprint_args=["--version"],
)

system_binary(
    name="jq",
    binary_name="jq",
    fingerprint=r"jq-\d+\.\d+",
    fingerprint_args=["--version"],
)

# adhoc_tool — run any runnable target as a build step
adhoc_tool(
    name="run-codegen",
    runnable=":my_python_script",          # any "runnable" target address
    args=["--input", "schema.json", "--output", "generated/"],
    execution_dependencies=[
        ":schema_files",                   # files needed at runtime
        "src/tools:helper_lib",
    ],
    output_files=["generated/output.py"],
    output_directories=["generated/"],
    stdout="logs/codegen.log",             # capture stdout to file
    stderr="logs/codegen_err.log",
    extra_env_vars=["API_KEY", "ENV=production"],
    timeout=120,
    log_output=True,
    workdir=".",
    runnable_dependencies=[":bash_binary"], # additional tools on PATH
    cache_scope="success",
)
```

### Pattern: Run a Shell Script via `adhoc_tool`

`shell_source` targets are not directly runnable, so use `system_binary` + `adhoc_tool`:

```python
# 1. Wrap bash
system_binary(name="bash", binary_name="bash")

# 2. Declare the shell script
shell_sources(name="scripts", sources=["my_script.sh"])

# 3. Combine with adhoc_tool
adhoc_tool(
    name="run-my-script",
    runnable=":bash",
    args=["my_script.sh", "--flag", "value"],
    execution_dependencies=[":scripts"],
    output_files=["output.txt"],
    timeout=60,
)
```

### Pattern: Chaining for Better Caching

```python
# Step 1: fetch (rarely invalidated)
adhoc_tool(
    name="fetch-deps",
    runnable=":downloader",
    output_directories=["vendor/"],
    cache_scope="success",
)

# Step 2: compile (invalidated when sources change)
adhoc_tool(
    name="compile",
    runnable=":compiler",
    execution_dependencies=[":fetch-deps", ":sources"],
    output_directories=["build/"],
)
```

### Ad-Hoc CLI Commands

```bash
pants run src/tools:run-codegen            # Execute adhoc_tool
pants package src/tools:run-codegen        # Package output artifacts
```

---

## Universal CLI Reference

### Target Selectors

```bash
pants <goal> ::                            # All targets in repo
pants <goal> src/::                        # All targets under src/
pants <goal> src/myapp:                    # All targets in one BUILD file
pants <goal> src/myapp:lib                 # Specific named target
```

### Core Goals

```bash
pants lint ::
pants fmt ::
pants check ::                             # Type-check
pants test ::
pants package ::
pants run src/myapp:app
pants publish src/myapp:docker_image
```

### Introspection

```bash
pants list ::                              # List all target addresses
pants dependencies src/myapp:lib           # Direct + transitive deps
pants dependents src/myapp:lib             # Reverse deps
pants peek src/myapp:lib                   # Target metadata as JSON
pants help python_sources                  # Field docs for a target type
pants help goals                           # List available goals
pants help backends                        # List loaded backends
```

### Filtering

```bash
pants list --filter-target-type=python_tests ::
pants lint --only=ruff ::
pants test --filter-tag=integration ::
```

---

## Auto-generation with `tailor`

`pants tailor ::` auto-creates BUILD files for:

| File | Generated target |
|---|---|
| `*.py` | `python_sources` |
| `test_*.py` / `*_test.py` | `python_tests` |
| `requirements.txt` | `python_requirements` |
| `Dockerfile` | `docker_image` |
| `*.sh` | `shell_sources` |
| shunit2 test files | `shunit2_tests` |

```bash
pants tailor ::                            # Generate everywhere
pants tailor src/::                        # Generate in subtree
pants tailor --check ::                    # CI: fail if anything is missing
```

---

## Tips

1. **Use `::` selectors** to operate on entire subtrees — Pants only rebuilds what changed.
2. **Lockfiles are mandatory** when `enable_resolves = true` — always commit them.
3. **`pants tailor --check ::`** in CI catches BUILD files that are out of date.
4. **`pants peek :target`** is the fastest way to debug dependency resolution issues.
5. **`cache_scope = "success"`** on `adhoc_tool` / `shell_command` is safe for most generators — results are reused across runs until inputs change.
6. **Parametrize** shell tests with `shell=parametrize("bash", "zsh")` to catch portability bugs early.
7. **`system_binary` fingerprinting** (`fingerprint` + `fingerprint_args`) ensures Pants validates the correct tool version before running.
8. **Use `runnable_dependencies`** on `adhoc_tool` to inject additional binaries onto `$PATH` without making them the primary runnable.
9. **Inline Dockerfiles** via `instructions=[...]` on `docker_image` for simple images that don't need a standalone `Dockerfile`.
10. **`pants help <target-type>`** shows every available field with documentation — always check before guessing.

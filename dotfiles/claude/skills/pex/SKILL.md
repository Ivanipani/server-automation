# PEX Skill

This skill provides expert guidance for working with PEX (Python EXecutable) files — self-contained, executable Python virtual environments packaged as zip archives. Use it when building, running, inspecting, or deploying PEX artifacts, whether via the `pex` CLI directly or through Pants.

## Documentation

- PEX overview: https://docs.pex-tool.org/
- Building PEX files: https://docs.pex-tool.org/buildingpex.html
- PEX recipes: https://docs.pex-tool.org/recipes.html

---

## What Is a PEX File?

A PEX file is a carefully constructed zip file with a `#!/usr/bin/env python` shebang and a special `__main__.py`. It bundles a Python application together with all its dependencies into a single portable executable — analogous to a virtualenv that can be copied and run anywhere.

Key properties:
- **Self-contained**: dependencies are embedded; no `pip install` needed at runtime
- **Executable**: `chmod +x app.pex && ./app.pex` just works
- **Portable**: works across systems with a compatible Python interpreter
- **Hermetic**: isolated from system site-packages by default

---

## Building PEX Files

### With the `pex` CLI

```bash
# Install pex
pip install pex

# Basic: package flask with a gunicorn entry point
pex flask gunicorn -c gunicorn -o server.pex

# With requirements file
pex -r requirements.txt -m myapp.main -o myapp.pex

# Specific Python interpreter
pex flask --python=python3.12 -m myapp.main -o myapp.pex

# Cross-platform (build for linux even on mac)
pex flask \
  --platform linux_x86_64-cp-312-cp312 \
  -m myapp.main \
  -o myapp-linux.pex

# With complete platform JSON (most reliable cross-platform)
pex flask \
  --complete-platform linux_x86_64_cp312.json \
  -m myapp.main \
  -o myapp.pex

# Include tools for venv installation
pex flask -m myapp.main --include-tools -o myapp.pex

# From local find-links repository (no PyPI)
pex -f ./wheelhouse -r requirements.txt --no-index -o myapp.pex
```

### Entry Point Methods

```bash
# 1. Console script (from package's entry_points)
pex flask gunicorn -c gunicorn -o server.pex

# 2. Module (-m flag, like python -m)
pex flask -m flask -o flask.pex

# 3. package:callable format
pex mypackage -e mypackage.main:app -o myapp.pex

# 4. Script passed at runtime (no entry point baked in)
pex flask -o flask-env.pex
./flask-env.pex run_server.py
```

### Build Flags Reference

| Flag | Description |
|------|-------------|
| `-o PATH` | Output file path |
| `-r FILE` | Requirements file |
| `-c SCRIPT` | Console script entry point |
| `-m MODULE` | Module entry point (`python -m` style) |
| `-e pkg:func` | Callable entry point |
| `--python PATH` | Interpreter to use |
| `--python-shebang PATH` | Override shebang in output |
| `--platform PLATFORM` | Target platform string |
| `--complete-platform JSON` | Full platform spec (recommended) |
| `-f/--find-links URL` | Extra package index |
| `--no-index` | Disable PyPI fetching |
| `--include-tools` | Bundle venv install tooling |
| `--inject-args ARGS` | Bake in default CLI arguments |
| `--inject-env VAR=VAL` | Bake in default env vars |
| `--inherit-path` | Include system site-packages (avoid) |
| `--ignore-errors` | Run despite missing deps (avoid) |

---

## Building PEX via Pants

In this repo, PEX artifacts are built via Pants using the `pex_binary` target. **Do not invoke `pex` directly** — always go through Pants.

### BUILD File Target

```python
pex_binary(
    name="app",
    entry_point="mypackage.main:main",      # module:callable
    resolve="python-default",
    execution_mode="venv",                  # "venv" (slower start, faster run) or "zipapp" (fast start)
    layout="zipapp",                        # "loose" | "packed" | "zipapp"
    output_path="dist/app.pex",
    # For cross-platform Docker builds:
    complete_platforms=[":linux_x86_64_complete_platform"],
)

# Complete platform target (generate with: pex3 interpreter inspect --markers --tags)
file(
    name="linux_x86_64_complete_platform",
    source="linux_x86_64_cp312.json",
)
```

### Pants Commands

```bash
# Build the PEX artifact
pants package pantry/services/api-gateway-svc:gatewaysvc

# Run directly (dev)
pants run pantry/services/api-gateway-svc:gatewaysvc

# Run with arguments
pants run pantry/services/api-gateway-svc:gatewaysvc -- --port 4000

# Build all packages
pants package ::
```

### `pex_binary` Field Reference

| Field | Values | Description |
|-------|--------|-------------|
| `entry_point` | `"module"`, `"module:func"` | Python entry point |
| `execution_mode` | `"zipapp"`, `"venv"` | How PEX unpacks at runtime |
| `layout` | `"zipapp"`, `"loose"`, `"packed"` | Output layout |
| `resolve` | resolve name | Which lockfile to use |
| `complete_platforms` | list of target addresses | Cross-platform build specs |
| `output_path` | path string | Where to write the `.pex` |
| `interpreter_constraints` | `["==3.12.*"]` | Overrides global setting |
| `dependencies` | list of addresses | Additional explicit deps |

### Execution Modes

- **`zipapp`** (default): Imports run directly from the zip. Fastest startup, slightly slower import (zip overhead). Good for short-lived CLI tools.
- **`venv`**: Extracts to `~/.pex/` on first run, then reuses. Slower cold start, native import speed. Best for long-running servers.

---

## Running PEX Files

```bash
# Direct execution (requires executable bit)
./myapp.pex

# Via Python
python myapp.pex

# With arguments
./myapp.pex --host 0.0.0.0 --port 4000

# Override module at runtime (if no baked entry point)
PEX_MODULE=myapp.other_main ./myapp.pex

# Open a REPL inside the PEX environment
PEX_INTERPRETER=1 ./myapp.pex

# Inspect PEX contents
PEX_TOOLS=1 ./myapp.pex info
```

---

## Runtime Environment Variables

| Variable | Description |
|----------|-------------|
| `PEX_ROOT` | Cache directory for extracted PEXes (default: `~/.pex`) |
| `PEX_PYTHON` | Override the Python interpreter to use |
| `PEX_PATH` | Colon-separated list of additional PEXes to merge into the environment |
| `PEX_MODULE` | Override the entry point module at runtime |
| `PEX_SCRIPT` | Override the entry point console script at runtime |
| `PEX_INTERPRETER` | Set to `1` to launch a REPL instead of running the entry point |
| `PEX_TOOLS` | Set to `1` to access built-in PEX tools (requires `--include-tools`) |
| `PEX_VERBOSE` | Set to `1`–`9` for verbose debug output |
| `PEX_ALWAYS_WRITE_CACHE` | Force re-extraction even if cached |
| `PEX` | (Read-only) Absolute path to the running PEX file, set by the runtime |

---

## Inspecting PEX Files

```bash
# List contents of a PEX
unzip -l myapp.pex

# Open a shell in the PEX environment
PEX_INTERPRETER=1 ./myapp.pex

# Inspect metadata (requires --include-tools at build time)
PEX_TOOLS=1 ./myapp.pex info
PEX_TOOLS=1 ./myapp.pex venv /tmp/my-venv

# Install PEX as a venv (useful in Docker)
PEX_TOOLS=1 ./myapp.pex venv /app/venv
/app/venv/bin/python -m myapp.main
```

---

## Cross-Platform Builds (Docker)

When building on macOS for a Linux container, you need a complete platform file. Generate it from inside a matching container:

```bash
# 1. Generate the platform spec from a matching Python environment
docker run --rm python:3.12-slim \
  pip install pex && pex3 interpreter inspect --markers --tags \
  > linux_x86_64_cp312.json

# 2. Declare it in BUILD
file(
    name="linux_x86_64_complete_platform",
    source="linux_x86_64_cp312.json",
)

pex_binary(
    name="app",
    entry_point="myapp.main:main",
    complete_platforms=[":linux_x86_64_complete_platform"],
)
```

---

## Docker Integration Patterns

### Pattern: Multi-Stage with PEX venv (smallest image)

```dockerfile
FROM python:3.12-slim AS builder
COPY app.pex /app.pex
RUN PEX_TOOLS=1 python /app.pex venv /app/venv

FROM python:3.12-slim
COPY --from=builder /app/venv /app/venv
ENTRYPOINT ["/app/venv/bin/python", "-m", "myapp.main"]
```

### Pattern: Direct PEX execution

```dockerfile
FROM python:3.12-slim
COPY app.pex /app/app.pex
RUN chmod +x /app/app.pex
ENTRYPOINT ["/app/app.pex"]
```

### Pants + Docker

Pants can copy a `pex_binary` into a `docker_image` automatically via Dockerfile dependency inference:

```dockerfile
# Pants infers the pex_binary dependency from this COPY path
COPY pantry.services.api-gateway-svc/gatewaysvc.pex /app/
```

```python
docker_image(
    name="api-gateway",
    dependencies=[":gatewaysvc"],   # explicit dep on pex_binary
)
```

---

## Server Application Patterns

### Gunicorn / Uvicorn

Since servers cannot access code inside a PEX directly, bundle them as dependencies:

```bash
pex myapp gunicorn -c gunicorn --inject-args="-w 4 myapp.wsgi:application" -o server.pex
```

In Pants BUILD:

```python
pex_binary(
    name="server",
    entry_point="gunicorn",
    dependencies=[":app_lib", "3rdparty:reqs#gunicorn"],
)
```

### Process Visibility

Make long-running PEX processes identifiable in `ps`:

```python
pex_binary(
    name="server",
    entry_point="myapp.main:main",
    dependencies=["3rdparty:reqs#setproctitle"],  # adds PEX path to ps output
)
```

---

## Detecting PEX at Runtime

```python
import os

if "PEX" in os.environ:
    pex_path = os.environ["PEX"]  # absolute path to the running .pex file
    print(f"Running from PEX: {pex_path}")
else:
    print("Running from regular Python environment")
```

---

## Tips

1. **Use `execution_mode="venv"`** for long-running servers — native import speed after first run.
2. **Use `execution_mode="zipapp"`** for CLIs and short-lived tools — no extraction overhead.
3. **Always use `complete_platforms`** for cross-platform builds (e.g., macOS → Linux) rather than `--platform` strings — it's more reliable.
4. **Commit complete platform JSON files** to the repo alongside BUILD files.
5. **Use `--include-tools`** (or `include_tools=True` in Pants) when you need to install PEX as a venv in Docker.
6. **`PEX_INTERPRETER=1`** is invaluable for debugging — gives you a REPL with all PEX dependencies available.
7. **`PEX_VERBOSE=9`** dumps detailed startup/resolution logs — essential when a PEX fails to launch.
8. **In Pants, prefer `pants run :target`** over building and running manually — it avoids stale artifacts.
9. **`PEX_ROOT`** can be pointed at a shared cache directory in CI to speed up repeated runs.
10. **Use `pants peek :target`** to inspect all resolved fields on a `pex_binary` before packaging.

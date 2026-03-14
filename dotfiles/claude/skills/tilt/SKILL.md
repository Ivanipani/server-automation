# Tilt Skill

This skill provides comprehensive guidance for authoring Tiltfiles using Tilt's Starlark-based API. Use this when helping users create, debug, or improve Tiltfiles for local Kubernetes, Docker Compose, or hybrid development environments.

## Documentation

- Tiltfile authoring: https://docs.tilt.dev/tiltfile_authoring.html
- API reference: https://docs.tilt.dev/api.html
- API server reference: https://api.tilt.dev/

## Philosophy

1. **Fast feedback loops**: Tilt exists to make inner dev loops as fast as possible — prefer live updates over full rebuilds
2. **Declarative**: Express what you want; Tilt figures out ordering and dependencies
3. **Composable**: Break complex Tiltfiles into helper functions and loaded files
4. **Developer-friendly**: Expose config options so devs can customize without editing the Tiltfile

## Tiltfile Basics

Tiltfiles are written in **Starlark**, a Python dialect. Every Tiltfile is re-executed when it or any watched file changes.

```python
# Minimal Kubernetes Tiltfile
docker_build('my-registry/my-app', '.')
k8s_yaml('k8s/deployment.yaml')
k8s_resource('my-app', port_forwards=8080)
```

```python
# Minimal Docker Compose Tiltfile
docker_compose('./docker-compose.yml')
```

---

## Docker Build

### Signature

```python
docker_build(
    ref,                    # Image name, e.g. 'myregistry/myapp'
    context,                # Build context path
    build_args={},          # --build-arg key=value pairs
    dockerfile='Dockerfile',
    dockerfile_contents='', # Inline Dockerfile (mutually exclusive with dockerfile)
    live_update=[],         # Live update steps (see Live Update section)
    match_in_env_vars=False,# Also inject image into env vars referencing this image
    ignore=[],              # Paths to exclude (dockerignore syntax)
    only=[],                # Only include these paths in the context
    entrypoint=[],          # Override container entrypoint
    target='',              # Multi-stage build target
    ssh='',                 # SSH agent socket for build
    secret='',              # Build secrets
    network='',             # Build network mode
    extra_tag='',           # Additional tag to apply post-build
    cache_from=[],          # Images to use as cache source
    pull=False,             # Always pull latest base image
    platform='',            # Target platform, e.g. 'linux/amd64'
)
```

### Common Patterns

```python
# Basic build
docker_build('gcr.io/myproject/backend', './backend')

# Multi-stage build targeting a specific stage
docker_build('gcr.io/myproject/backend', './backend', target='development')

# Build with args
docker_build('gcr.io/myproject/app', '.',
    build_args={'NODE_ENV': 'development', 'API_URL': 'http://localhost:8080'})

# Restrict context to only necessary files (speeds up builds)
docker_build('gcr.io/myproject/app', '.',
    only=['src/', 'package.json', 'package-lock.json'])

# Custom Dockerfile location
docker_build('gcr.io/myproject/app', '.', dockerfile='./docker/Dockerfile.dev')
```

### Custom Build (non-Docker toolchains)

```python
custom_build(
    'gcr.io/myproject/app',
    'bazel build //app:image && bazel run //app:image -- --norun',
    deps=['./app'],
)
```

---

## Docker Compose

### Signature

```python
docker_compose(
    configPaths,            # Path(s) to compose file(s), or list
    env_file='',            # .env file path
    project_name='',        # Override compose project name
    profiles=[],            # Compose profiles to enable
    project_dir='',         # Override project directory
)
```

### Basic Setup

```python
# Single compose file
docker_compose('./docker-compose.yml')

# Multiple compose files (merged)
docker_compose(['./docker-compose.yml', './docker-compose.override.yml'])

# With profiles
docker_compose('./docker-compose.yml', profiles=['debug', 'monitoring'])
```

### Overriding Images with docker_build

Tilt replaces Docker Compose's build with its own optimized build + live update:

```python
docker_compose('./docker-compose.yml')

# Override the 'app' service's image with Tilt's build pipeline
docker_build('myapp-image', '.',
    live_update=[
        sync('.', '/app'),
        run('npm install', trigger='package.json'),
    ])
```

The image ref in `docker_build` must match the `image:` field in the compose file.

### dc_resource — Configure Compose Services

```python
dc_resource(
    name,                   # Service name from docker-compose.yml
    trigger_mode=TRIGGER_MODE_AUTO,
    resource_deps=[],       # Wait for these resources before starting
    labels=[],              # UI grouping labels
    auto_init=True,         # Set False to not start automatically
    links=[],               # External links shown in Tilt UI
)
```

```python
docker_compose('./docker-compose.yml')

# Group services with labels
dc_resource('postgres', labels=['database'])
dc_resource('redis',    labels=['database'])
dc_resource('api',      labels=['backend'], resource_deps=['postgres', 'redis'])
dc_resource('frontend', labels=['frontend'], resource_deps=['api'])

# Opt-in only service (e.g. storybook, admin panel)
dc_resource('storybook', auto_init=False)
```

### Inline Compose Override

```python
base = read_file('./docker-compose.yml')
override = encode_yaml({
    'services': {
        'app': {
            'environment': {'DEBUG': 'true'},
        }
    }
})
docker_compose([base, override])
```

---

## Kubernetes Resources

### k8s_yaml — Register Manifests

```python
k8s_yaml(
    yaml,                   # File path, list of paths, or Blob
    allow_duplicates=False,
)
```

```python
# Single file
k8s_yaml('k8s/deployment.yaml')

# Multiple files
k8s_yaml(['k8s/deployment.yaml', 'k8s/service.yaml', 'k8s/ingress.yaml'])

# Glob all YAML in a directory
k8s_yaml(listdir('k8s/'))

# From a command
k8s_yaml(local('kustomize build ./overlays/dev'))

# From kustomize built-in
k8s_yaml(kustomize('./overlays/dev'))
```

### k8s_resource — Configure K8s Resources

```python
k8s_resource(
    workload,               # Name of the K8s workload (Deployment, StatefulSet, etc.)
    new_name='',            # Rename in Tilt UI
    port_forwards=[],       # Port forwarding: 8080 or '8080:8080' or port_forward(8080, 8080)
    extra_pod_selectors=[], # Additional pod label selectors
    pod_readiness='wait',   # 'wait' or 'ignore'
    trigger_mode=TRIGGER_MODE_AUTO,
    resource_deps=[],       # Wait for these resources first
    labels=[],              # UI grouping labels
    objects=[],             # Additional K8s objects to associate
    auto_init=True,
    links=[],               # External links shown in UI
)
```

```python
# Port forwarding
k8s_resource('frontend', port_forwards=3000)
k8s_resource('backend',  port_forwards=[8080, 9090])  # multiple ports

# Named port forward (local:container)
k8s_resource('backend', port_forwards='8080:80')

# Resource dependencies (deploy db before app)
k8s_resource('api', resource_deps=['postgres'])

# UI organization
k8s_resource('postgres', labels=['database'])
k8s_resource('redis',    labels=['database'])
k8s_resource('api',      labels=['backend'])

# Rename a resource
k8s_resource('my-app-deployment', new_name='app')

# Associate a ConfigMap with a Deployment so they deploy together
k8s_resource('api', objects=['api-config:configmap'])
```

### Filtering Resources

```python
# Only deploy a subset of resources
k8s_yaml('k8s/all.yaml')
k8s_resource('expensive-job', auto_init=False)  # opt-in only
```

---

## Helm

### helm() — Render Chart Locally

Best for **iterating on your own charts** — bypasses hooks, works offline.

```python
helm(
    path,                   # Path to chart directory
    name='',                # Helm release name
    namespace='',           # Target namespace
    values=[],              # List of values file paths
    set=[],                 # --set overrides: ['key=val', 'other=val']
    kube_version='',        # Kubernetes version for capabilities
    skip_crds=False,
)
```

```python
# Render and deploy a local chart
yaml = helm('./charts/myapp',
    name='myapp',
    namespace='dev',
    values=['./charts/myapp/values.yaml', './values-dev.yaml'],
    set=['replicaCount=1', 'image.pullPolicy=Never'],
)
k8s_yaml(yaml)
k8s_resource('myapp', port_forwards=8080)
```

```python
# Override specific values based on environment
cfg = config.parse()
env = cfg.get('env', 'dev')

yaml = helm('./charts/myapp',
    name='myapp',
    namespace=env,
    values=['./charts/myapp/values.yaml', './values-%s.yaml' % env],
)
k8s_yaml(yaml)
```

### helm_remote() Extension — Install Off-the-Shelf Charts

```python
load('ext://helm_remote', 'helm_remote')

helm_remote('prometheus',
    repo_url='https://prometheus-community.github.io/helm-charts',
    repo_name='prometheus-community',
    namespace='monitoring',
    values=['./values/prometheus.yaml'],
)
```

### helm_resource() Extension — Full Helm Lifecycle

Unlike `helm()`, this runs `helm install`/`upgrade` and shows logs/health:

```python
load('ext://helm_resource', 'helm_resource', 'helm_repo')

helm_repo('bitnami', 'https://charts.bitnami.com/bitnami')
helm_resource('postgres',
    chart='bitnami/postgresql',
    namespace='dev',
    flags=['--set', 'auth.postgresPassword=devpassword'],
)
```

---

## Local Resources

### local_resource() — Run Commands on the Host

```python
local_resource(
    name,                   # Resource name shown in Tilt UI
    cmd='',                 # Command to run (build step)
    serve_cmd='',           # Long-running process to keep alive
    deps=[],                # File paths that trigger re-execution
    ignore=[],              # Paths to ignore within deps
    trigger_mode=TRIGGER_MODE_AUTO,
    resource_deps=[],       # Run after these resources are ready
    env={},                 # Environment variables for cmd
    serve_env={},           # Environment variables for serve_cmd
    allow_parallel=False,   # Run concurrently with other resources
    readiness_probe=None,   # Probe to check serve_cmd readiness
    auto_init=True,
    labels=[],
    links=[],
)
```

### Build-Only Resources (run once or on file change)

```python
# Code generation that reruns when proto files change
local_resource('proto-gen',
    cmd='buf generate',
    deps=['./proto'],
    labels=['codegen'],
)

# Database migrations that run after postgres is ready
local_resource('db-migrate',
    cmd='go run ./cmd/migrate up',
    resource_deps=['postgres'],
    env={'DATABASE_URL': 'postgres://dev:dev@localhost:5432/dev'},
)

# Run tests automatically when source changes
local_resource('unit-tests',
    cmd='go test ./...',
    deps=['./internal', './pkg'],
    allow_parallel=True,
    labels=['tests'],
)
```

### Long-Running Services (serve_cmd)

```python
# Local API server (not containerized)
local_resource('api',
    cmd='go build -o ./bin/api ./cmd/api',  # build step
    serve_cmd='./bin/api',                  # runs after build succeeds
    deps=['./cmd/api', './internal'],
    serve_env={'PORT': '8080', 'LOG_LEVEL': 'debug'},
    readiness_probe=probe(
        http_get=http_get_action(port=8080, path='/healthz'),
        period_secs=5,
        failure_threshold=3,
    ),
    resource_deps=['db-migrate'],
)

# Run a webpack dev server
local_resource('webpack',
    serve_cmd='npm run dev',
    deps=['./src', 'webpack.config.js'],
    serve_env={'NODE_ENV': 'development'},
)
```

### Readiness Probes

```python
# HTTP probe
readiness_probe=probe(
    http_get=http_get_action(port=8080, path='/health'),
    period_secs=5,
    initial_delay_secs=2,
    failure_threshold=5,
)

# TCP probe
readiness_probe=probe(
    tcp_socket=tcp_socket_action(port=5432),
    period_secs=3,
)

# Exec probe
readiness_probe=probe(
    exec=exec_action(['pg_isready', '-U', 'postgres']),
    period_secs=5,
)
```

---

## Live Update

Live update patches running containers in-place, bypassing image rebuilds.

### Steps

| Step | Description |
|------|-------------|
| `sync(src, dest)` | Copy files from local `src` to container `dest` |
| `run(cmd, trigger=[])` | Run a command inside the container; `trigger` limits when it runs |
| `restart_container()` | Restart the container process (for compiled languages) |
| `fall_back_on(files)` | Trigger a full rebuild if these files change |

### Interpreted Language (Node/Python/Ruby)

```python
docker_build('gcr.io/myproject/frontend', './frontend',
    live_update=[
        fall_back_on(['package.json', 'package-lock.json']),
        sync('./frontend/src', '/app/src'),
        run('npm install', trigger=['package.json', 'package-lock.json']),
    ])
```

### Compiled Language (Go)

```python
docker_build('gcr.io/myproject/backend', './backend',
    live_update=[
        fall_back_on(['go.mod', 'go.sum']),
        sync('./backend', '/app'),
        run('go build -o /usr/local/bin/app ./cmd/app', trigger=['./backend']),
        restart_container(),
    ])
```

### Python/Django

```python
docker_build('gcr.io/myproject/django', '.',
    live_update=[
        sync('.', '/app'),
        run('pip install -r requirements.txt', trigger='requirements.txt'),
        # Django reloads automatically on .py changes (debug mode)
    ])
```

---

## Configuration & Parameterization

Make Tiltfiles configurable for different developers or environments:

```python
# Define config flags
config.define_string('env', usage='Target environment (dev/staging)')
config.define_bool('with-monitoring', usage='Enable Prometheus/Grafana stack')
config.define_string_list('services', args=True, usage='Services to run')

cfg = config.parse()

env = cfg.get('env', 'dev')
with_monitoring = cfg.get('with-monitoring', False)
services = cfg.get('services', ['api', 'frontend', 'postgres'])

# Use config values
if with_monitoring:
    k8s_yaml('k8s/monitoring/')

# Only enable requested services
all_services = ['api', 'frontend', 'postgres', 'redis', 'worker']
for svc in all_services:
    if svc not in services:
        k8s_resource(svc, auto_init=False)
```

Usage:
```sh
# Start specific services only
tilt up -- api postgres

# With monitoring enabled
tilt up -- --with-monitoring --env staging
```

### tilt_config.json (persistent per-developer settings)

```json
{
  "env": "dev",
  "with-monitoring": false,
  "services": ["api", "frontend", "postgres"]
}
```

---

## Utilities

### File and YAML Operations

```python
# Read a file as a string
contents = read_file('./config/app.yaml')

# Read YAML into a dict
data = read_yaml('./config/values.yaml')

# Decode YAML string
obj = decode_yaml(some_string)

# Encode dict to YAML string
yaml_str = encode_yaml({'key': 'value'})

# Run a local command and capture output
version = str(local('git describe --tags --always')).strip()
```

### Environment Variables

```python
import os

registry = os.environ.get('IMAGE_REGISTRY', 'localhost:5000')
docker_build('%s/myapp' % registry, '.')
```

### Watch Additional Files

```python
# Re-execute Tiltfile when this file changes
watch_file('./scripts/generate.sh')
```

### Load Extensions and Helper Files

```python
# Load a local helper file
load('./tilt/helpers.star', 'build_service')

# Load an official extension
load('ext://restart_process', 'docker_build_with_restart')
load('ext://helm_remote', 'helm_remote')
load('ext://namespace', 'namespace_create', 'namespace_inject')
```

---

## Common Patterns

### Microservices Monorepo

```python
# tilt/build.star
def service(name, port=None, deps=None):
    docker_build(
        'gcr.io/myproject/' + name,
        './services/' + name,
        live_update=[
            fall_back_on(['go.mod', 'go.sum']),
            sync('./services/' + name, '/app'),
            run('go build -o /usr/local/bin/' + name + ' .'),
            restart_container(),
        ],
    )
    k8s_yaml('./k8s/' + name + '.yaml')
    if port:
        k8s_resource(name, port_forwards=port, labels=['services'])
    if deps:
        k8s_resource(name, resource_deps=deps)
```

```python
# Tiltfile
load('./tilt/build.star', 'service')

# Infrastructure first
k8s_yaml(['k8s/postgres.yaml', 'k8s/redis.yaml'])
k8s_resource('postgres', labels=['infra'])
k8s_resource('redis',    labels=['infra'])

# Services
service('api',      port=8080, deps=['postgres', 'redis'])
service('worker',             deps=['postgres', 'redis'])
service('frontend', port=3000, deps=['api'])
```

### Hybrid Local + Kubernetes

```python
# Run postgres in Kubernetes, run the app locally
k8s_yaml('k8s/postgres.yaml')
k8s_resource('postgres',
    port_forwards='5432:5432',
    labels=['infra'],
)

local_resource('api',
    cmd='go build -o ./bin/api ./cmd/api',
    serve_cmd='./bin/api',
    deps=['./cmd', './internal'],
    serve_env={'DATABASE_URL': 'postgres://dev:dev@localhost:5432/dev'},
    readiness_probe=probe(http_get=http_get_action(port=8080, path='/health')),
    resource_deps=['postgres'],
)
```

### Namespace Management

```python
load('ext://namespace', 'namespace_create', 'namespace_inject')

namespace_create('dev')
k8s_yaml(namespace_inject(kustomize('./overlays/dev'), 'dev'))
```

### Secrets from Local Files (dev only)

```python
# Load secrets from a local .env file (never commit this)
load('ext://dotenv', 'dotenv')
dotenv()  # loads .env into os.environ

k8s_yaml(helm('./charts/myapp',
    set=[
        'secrets.apiKey=' + os.environ.get('API_KEY', ''),
        'secrets.dbPassword=' + os.environ.get('DB_PASSWORD', ''),
    ]
))
```

---

## Trigger Modes

```python
# Auto: rebuild/rerun when dependencies change (default)
k8s_resource('api', trigger_mode=TRIGGER_MODE_AUTO)

# Manual: only rebuild when user clicks in Tilt UI or runs `tilt trigger`
k8s_resource('expensive-job', trigger_mode=TRIGGER_MODE_MANUAL)

# Same for local resources
local_resource('integration-tests',
    cmd='go test ./tests/integration/...',
    trigger_mode=TRIGGER_MODE_MANUAL,
    labels=['tests'],
)
```

---

## Tips

1. **Use `only=[]` in `docker_build`** to send minimal context and speed up builds
2. **Prefer live_update** over full rebuilds for interpreted languages — it's orders of magnitude faster
3. **Use `resource_deps`** to control initialization order and avoid race conditions
4. **Use `labels`** to organize the Tilt UI into logical groups
5. **Use `auto_init=False`** for optional/expensive services developers can enable on demand
6. **Use `fall_back_on`** to trigger full image rebuilds only when truly necessary (e.g., dependency files)
7. **Extract repeated patterns** into helper `.star` files and `load()` them
8. **Use `config.parse()`** so each developer can customize their local setup without editing the Tiltfile
9. **Use `allow_parallel=True`** on `local_resource` for independent tasks (tests, linting) to speed up startup
10. **Use `links=[]`** to surface relevant URLs (docs, dashboards) directly in the Tilt UI

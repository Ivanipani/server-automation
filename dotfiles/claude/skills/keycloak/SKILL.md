# Keycloak Server Configuration & Management Skill

This skill provides comprehensive guidance for configuring, deploying, and managing Keycloak — an open-source Identity and Access Management solution. Use this when the user asks about Keycloak setup, Docker/Kubernetes deployment, realm management, database configuration, TLS, reverse proxy, or any server operation.

**Official docs:** https://www.keycloak.org/guides#server
**Current stable version:** 26.x (image: `quay.io/keycloak/keycloak:latest`)

---

## Core Concepts

- **Realm**: An isolated tenant with its own users, clients, roles, and settings. The `master` realm is for Keycloak administration only — never use it for applications.
- **Client**: An application registered in a realm that uses Keycloak for auth (OIDC, SAML).
- **Build options**: Persisted configuration baked at image/build time (e.g., `--db`). Stored in plain text — never use for secrets.
- **Runtime options**: Applied at startup (e.g., `--db-password`). Support keystore-based secret storage.
- **Two startup modes**:
  - `start-dev` — development mode, insecure defaults, HTTP only, no hostname required. **Never use in production.**
  - `start` — production mode, TLS mandatory, hostname required.

---

## Configuration Sources (Priority: Highest → Lowest)

| Source | Format | Example |
|---|---|---|
| CLI parameters | `--<key>=<value>` | `--db=postgres` |
| Environment variables | `KC_<KEY>=<value>` | `KC_DB=postgres` |
| `conf/keycloak.conf` | `<key>=<value>` | `db=postgres` |
| Java KeyStore | PKCS12 password entry | `kc.db-password` |

### Interpolation in `keycloak.conf`

```ini
# Reference env var with optional default
hostname=${HOSTNAME_ENV_VAR:localhost}

# Escape literal dollar sign
some-option=\$literal
```

---

## Docker

### Development (local only — NOT production)

```bash
docker run --name keycloak -p 127.0.0.1:8080:8080 \
  -e KC_BOOTSTRAP_ADMIN_USERNAME=admin \
  -e KC_BOOTSTRAP_ADMIN_PASSWORD=change_me \
  quay.io/keycloak/keycloak:latest \
  start-dev
```

Access Admin Console at: `http://localhost:8080/admin`

### Production-Optimized Image (Recommended Pattern)

Build a custom image with configuration baked in — dramatically faster startup:

```dockerfile
FROM quay.io/keycloak/keycloak:latest

# Copy custom providers (optional)
COPY providers/ /opt/keycloak/providers/

# Bake build options into the image
ENV KC_DB=postgres
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true

RUN /opt/keycloak/bin/kc.sh build

ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
```

```bash
# Build image
docker build -t my-keycloak .

# Run with runtime options (credentials, hostname, etc.)
docker run --name keycloak -p 8443:8443 -p 9000:9000 \
  -e KC_BOOTSTRAP_ADMIN_USERNAME=admin \
  -e KC_BOOTSTRAP_ADMIN_PASSWORD=change_me \
  -e KC_DB_URL=jdbc:postgresql://db:5432/keycloak \
  -e KC_DB_USERNAME=keycloak \
  -e KC_DB_PASSWORD=secret \
  my-keycloak \
  start --optimized --hostname=https://keycloak.example.com
```

### Docker Compose (Full Stack)

```yaml
services:
  postgres:
    image: postgres:17
    environment:
      POSTGRES_DB: keycloak
      POSTGRES_USER: keycloak
      POSTGRES_PASSWORD: change_me
    volumes:
      - postgres_data:/var/lib/postgresql/data

  keycloak:
    image: quay.io/keycloak/keycloak:latest
    command: start-dev  # use 'start --optimized' for production
    environment:
      KC_BOOTSTRAP_ADMIN_USERNAME: admin
      KC_BOOTSTRAP_ADMIN_PASSWORD: change_me
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://postgres:5432/keycloak
      KC_DB_USERNAME: keycloak
      KC_DB_PASSWORD: change_me
    ports:
      - "8080:8080"
    depends_on:
      - postgres

volumes:
  postgres_data:
```

### Realm Import via Volume

```bash
docker run --name keycloak -p 127.0.0.1:8080:8080 \
  -e KC_BOOTSTRAP_ADMIN_USERNAME=admin \
  -e KC_BOOTSTRAP_ADMIN_PASSWORD=change_me \
  -v /path/to/realm-data:/opt/keycloak/data/import \
  quay.io/keycloak/keycloak:latest \
  start-dev --import-realm
```

### JVM Memory Tuning

```bash
docker run --name keycloak -p 8080:8080 -m 1g \
  -e KC_BOOTSTRAP_ADMIN_USERNAME=admin \
  -e KC_BOOTSTRAP_ADMIN_PASSWORD=change_me \
  -e JAVA_OPTS_KC_HEAP="-XX:MaxHeapFreeRatio=30 -XX:MaxRAMPercentage=65" \
  quay.io/keycloak/keycloak:latest \
  start-dev
```

Defaults: max heap = 70% of container memory, initial = 50%. Minimum container memory: 750 MB; recommended: 2 GB+.

---

## Kubernetes — Getting Started (Minikube)

### Enable Ingress

```bash
minikube addons enable ingress
```

### Deploy Keycloak (StatefulSet + Service)

```bash
kubectl create -f https://raw.githubusercontent.com/keycloak/keycloak-quickstarts/refs/heads/main/kubernetes/keycloak.yaml
```

### Expose via Ingress

```bash
wget -q -O - https://raw.githubusercontent.com/keycloak/keycloak-quickstarts/refs/heads/main/kubernetes/keycloak-ingress.yaml | \
  sed "s/KEYCLOAK_HOST/keycloak.$(minikube ip).nip.io/" | \
  kubectl create -f -
```

### Get URLs

```bash
KEYCLOAK_URL=https://keycloak.$(minikube ip).nip.io
echo "Admin Console:    $KEYCLOAK_URL/admin"
echo "Account Console:  $KEYCLOAK_URL/realms/myrealm/account"
```

---

## Kubernetes — Keycloak Operator

### Prerequisites

1. Install the Keycloak Operator into your namespace.
2. Provision a PostgreSQL database separately (Operator does not create databases).
3. Create required Kubernetes Secrets.

### Step-by-Step Deployment

```bash
# 1. Create database credentials secret
kubectl create secret generic keycloak-db-secret \
  --from-literal=username=keycloak \
  --from-literal=password=change_me

# 2. Generate self-signed TLS cert (dev/test only)
openssl req -subj '/CN=keycloak.example.com/O=MyOrg/C=US' \
  -newkey rsa:2048 -nodes -keyout key.pem -x509 -days 365 -out certificate.pem

# 3. Create TLS secret
kubectl create secret tls keycloak-tls-secret --cert certificate.pem --key key.pem
```

### Keycloak Custom Resource (`keycloak.yaml`)

```yaml
apiVersion: k8s.keycloak.org/v2alpha1
kind: Keycloak
metadata:
  name: example-kc
spec:
  instances: 2                          # min 2 for production HA
  db:
    vendor: postgres
    host: postgres-db
    usernameSecret:
      name: keycloak-db-secret
      key: username
    passwordSecret:
      name: keycloak-db-secret
      key: password
  http:
    tlsSecret: keycloak-tls-secret      # direct TLS termination
  hostname:
    hostname: keycloak.example.com
  proxy:
    headers: xforwarded                 # or 'forwarded' for RFC 7239
```

```bash
kubectl apply -f keycloak.yaml

# Verify ready status
kubectl get keycloaks/example-kc -o go-template='{{range .status.conditions}}CONDITION: {{.type}}{{"\n"}}  STATUS: {{.status}}{{"\n"}}  MESSAGE: {{.message}}{{"\n"}}{{end}}'
```

Expected output:
```
CONDITION: Ready         STATUS: true
CONDITION: HasErrors     STATUS: false
CONDITION: RollingUpdate STATUS: false
```

### Retrieve Auto-Generated Admin Credentials

```bash
kubectl get secret example-kc-initial-admin -o jsonpath='{.data.username}' | base64 --decode
kubectl get secret example-kc-initial-admin -o jsonpath='{.data.password}' | base64 --decode
```

### Ingress Variants

**TLS edge termination (Ingress-terminated):**
```yaml
spec:
  http:
    httpEnabled: true
  ingress:
    tlsSecret: keycloak-tls-secret
```

**Custom IngressClass (e.g., OpenShift):**
```yaml
spec:
  ingress:
    className: openshift-default
```

**Disable default Ingress (manage manually):**
```yaml
spec:
  ingress:
    enabled: false
```

**Local access via port-forward:**
```bash
kubectl port-forward service/example-kc-service 8443:8443
```

---

## Realm Import with Operator

```yaml
apiVersion: k8s.keycloak.org/v2alpha1
kind: KeycloakRealmImport
metadata:
  name: my-realm-import
spec:
  keycloakCRName: example-kc           # must match Keycloak CR name in same namespace
  placeholders:
    SMTP_PASSWORD:
      secret:
        name: smtp-secret
        key: password
  realm:
    id: my-realm
    realm: my-realm
    displayName: My Realm
    enabled: true
    # ... full RealmRepresentation fields ...
```

```bash
kubectl apply -f realm-import.yaml

# Check import status
kubectl get keycloakrealmimports/my-realm-import -o go-template='{{range .status.conditions}}CONDITION: {{.type}}{{"\n"}}  STATUS: {{.status}}{{"\n"}}  MESSAGE: {{.message}}{{"\n"}}{{end}}'

# Clean up after successful import
kubectl delete keycloakrealmimport my-realm-import
```

**Limitations:**
- No overwrite — if realm exists, import is skipped.
- Create only — updates and deletions via CR are not supported.
- Must be in the same namespace as the Keycloak CR.

---

## Database Configuration

### Supported Databases

| Vendor | `KC_DB` Value | Notes |
|---|---|---|
| PostgreSQL (recommended) | `postgres` | Tested with v18 and Aurora v17.5 |
| MariaDB | `mariadb` | Use `utf8mb3` charset |
| MySQL | `mysql` | Set `sql_generate_invisible_primary_key=OFF` |
| MS SQL Server | `mssql` | Requires `READ_COMMITTED_SNAPSHOT ON` |
| Oracle | `oracle` | Must add JDBC JAR manually |

### Configuration Options

| CLI Flag | Env Variable | Default | Description |
|---|---|---|---|
| `--db` | `KC_DB` | `dev-file` | Database vendor (build option) |
| `--db-url-host` | `KC_DB_URL_HOST` | — | DB hostname |
| `--db-url-port` | `KC_DB_URL_PORT` | — | DB port |
| `--db-url-database` | `KC_DB_URL_DATABASE` | — | DB name |
| `--db-url` | `KC_DB_URL` | — | Full JDBC URL (overrides above) |
| `--db-username` | `KC_DB_USERNAME` | — | DB username |
| `--db-password` | `KC_DB_PASSWORD` | — | DB password |
| `--db-schema` | `KC_DB_SCHEMA` | `keycloak` | Schema name |
| `--db-pool-max-size` | `KC_DB_POOL_MAX_SIZE` | `100` | Max DB connections |
| `--db-pool-min-size` | `KC_DB_POOL_MIN_SIZE` | — | Min DB connections |
| `--db-pool-max-lifetime` | `KC_DB_POOL_MAX_LIFETIME` | — | Max connection lifetime |

### `conf/keycloak.conf` Example

```ini
db=postgres
db-username=keycloak
db-password=change_me
db-url-host=postgres-host
db-url-database=keycloak
```

### PostgreSQL with TLS

```bash
bin/kc.sh start --db=postgres \
  --db-url="jdbc:postgresql://host/keycloak?sslmode=verify-full&sslrootcert=/path/to/ca.pem" \
  --db-username=keycloak --db-password=secret
```

### Oracle (Dockerfile — manual JDBC JAR required)

```dockerfile
FROM quay.io/keycloak/keycloak:latest
ADD --chown=keycloak:keycloak --chmod=644 \
  https://repo1.maven.org/maven2/com/oracle/database/jdbc/ojdbc17/23.6.0.24.10/ojdbc17-23.6.0.24.10.jar \
  /opt/keycloak/providers/ojdbc17.jar
ENV KC_DB=oracle
RUN /opt/keycloak/bin/kc.sh build
```

---

## Hostname Configuration

```bash
# Hostname only (scheme inferred)
bin/kc.sh start --hostname=keycloak.example.com

# Full URL with custom port/path
bin/kc.sh start --hostname=https://keycloak.example.com:443/auth

# Separate admin hostname (requires full URL in --hostname)
bin/kc.sh start \
  --hostname=https://keycloak.example.com \
  --hostname-admin=https://admin.internal.example.com:8443

# Behind TLS-terminating reverse proxy (HTTP listener)
bin/kc.sh start \
  --hostname=https://keycloak.example.com \
  --http-enabled=true

# Dynamic backchannel (requires full URL in --hostname)
bin/kc.sh start \
  --hostname=https://keycloak.example.com \
  --hostname-backchannel-dynamic=true

# Debug hostname resolution
bin/kc.sh start --hostname=keycloak.example.com --hostname-debug=true
# Then access: https://keycloak.example.com/realms/master/hostname-debug
```

| Option | Env Variable | Default | Description |
|---|---|---|---|
| `--hostname` | `KC_HOSTNAME` | — | Public hostname or full URL |
| `--hostname-admin` | `KC_HOSTNAME_ADMIN` | — | Separate admin console address |
| `--hostname-strict` | `KC_HOSTNAME_STRICT` | `true` | Enforce hostname; disable in dev |
| `--hostname-backchannel-dynamic` | `KC_HOSTNAME_BACKCHANNEL_DYNAMIC` | `false` | Resolve backchannel from request |
| `--hostname-debug` | `KC_HOSTNAME_DEBUG` | `false` | Enable debug page |

---

## TLS / HTTPS

```bash
# Start with certificate files
bin/kc.sh start \
  --hostname=keycloak.example.com \
  --https-certificate-file=/path/to/cert.pem \
  --https-certificate-key-file=/path/to/key.pem

# Or using a PKCS12 keystore
bin/kc.sh start \
  --hostname=keycloak.example.com \
  --https-key-store-file=/path/to/keystore.p12 \
  --https-key-store-password=keystorepass
```

**Storing secrets in a Java KeyStore (recommended for production):**

```bash
# Store DB password in keystore
keytool -importpass -alias kc.db-password -keystore keycloak.p12 \
  -storepass keystorepass -storetype PKCS12

# Start referencing the keystore
bin/kc.sh start \
  --config-keystore=/path/to/keycloak.p12 \
  --config-keystore-password=keystorepass
```

---

## Reverse Proxy

```bash
# RFC 7239 Forwarded header
bin/kc.sh start --proxy-headers=forwarded

# X-Forwarded-* headers
bin/kc.sh start --proxy-headers=xforwarded

# Restrict to specific trusted proxy IPs
bin/kc.sh start --proxy-headers=forwarded \
  --proxy-trusted-addresses=10.0.0.0/8,172.16.0.0/12

# HA PROXY protocol (HTTPS passthrough; cannot combine with --proxy-headers)
bin/kc.sh start --proxy-protocol-enabled=true

# Set context path
bin/kc.sh start --http-relative-path=/auth
```

### Paths to Expose / Block at Reverse Proxy

| Path | Expose? | Reason |
|---|---|---|
| `/realms/` | Yes | Required for OIDC/SAML |
| `/resources/` | Yes | Static assets |
| `/.well-known/` | Yes | RFC 8414 discovery |
| `/admin/` | No | Admin attack surface |
| `/metrics` | No | Sensitive metrics |
| `/health` | No | Internal use only |
| `/` (root) | No | Exposes admin paths |

---

## Health Checks

```bash
# Enable at build time
bin/kc.sh build --health-enabled=true --metrics-enabled=true

# Endpoints (port 9000 by default)
curl --head -fsS http://localhost:9000/health/ready
curl --head -fsS http://localhost:9000/health/live
curl --head -fsS http://localhost:9000/health/started
curl http://localhost:9000/health
```

| Endpoint | Kubernetes Probe | Triggers |
|---|---|---|
| `/health/started` | `startupProbe` | Initial startup |
| `/health/live` | `livenessProbe` | Restart container on failure |
| `/health/ready` | `readinessProbe` | Route traffic only when UP |
| `/health` | General monitoring | Aggregate of all checks |

### Kubernetes Probe Example

```yaml
startupProbe:
  httpGet:
    path: /health/started
    port: 9000
  failureThreshold: 30
  periodSeconds: 10
livenessProbe:
  httpGet:
    path: /health/live
    port: 9000
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /health/ready
    port: 9000
  periodSeconds: 10
```

**Note:** The Keycloak container image removes `curl` for security. Use TCP probes or probe from outside the container.

```bash
# TCP-only health check (no curl needed)
{ printf 'HEAD /health/ready HTTP/1.0\r\n\r\n' >&0; grep 'HTTP/1.0 200'; } 0<>/dev/tcp/localhost/9000
```

---

## Import / Export Realms (CLI)

```bash
# Export all realms to directory (recommended for large datasets)
bin/kc.sh export --dir /path/to/export/

# Export all realms to single file
bin/kc.sh export --file /path/to/realm.json

# Export specific realm only
bin/kc.sh export --dir /path/to/export/ --realm my-realm

# Export with user data split into files (50 users per file)
bin/kc.sh export --dir /path/to/export/ --users different_files --users-per-file 100

# Import from directory
bin/kc.sh import --dir /path/to/export/

# Import from single file
bin/kc.sh import --file /path/to/realm.json

# Import without overwriting existing realms
bin/kc.sh import --dir /path/to/export/ --override false

# Import at startup (reads from data/import/)
bin/kc.sh start --import-realm
```

**Critical warnings:**
- All Keycloak nodes must be stopped before running `import` or `export`.
- Admin Console exports mask passwords with asterisks — not suitable for backup/migration. Use CLI export.
- For datasets with >50,000 users, always export to a directory, not a single file.

---

## Production Checklist

1. **TLS enabled** for all communication (public, admin, inter-node).
2. **Hostname set** explicitly with `--hostname`.
3. **Separate admin hostname** (`--hostname-admin`) isolated from public.
4. **Reverse proxy** configured; admin paths blocked from public internet.
5. **Production database** (PostgreSQL recommended); `dev-file` removed.
6. **DB credentials** stored in environment variables or Java KeyStore, not in command line.
7. **`--http-max-queued-requests`** set to protect against traffic spikes (returns 503 when exceeded).
8. **At least 2 instances** for HA clustering.
9. **Memory limits** set on containers (`-m` in Docker, `resources.limits` in K8s).
10. **Health endpoints** enabled (`--health-enabled=true`) and wired to probes.
11. **Admin credentials** changed from defaults, MFA enabled.
12. **Ingress/proxy** configured to overwrite (not pass through) `Forwarded` headers.

---

## Key Environment Variables Reference

| Variable | Description | Example |
|---|---|---|
| `KC_BOOTSTRAP_ADMIN_USERNAME` | Initial admin username | `admin` |
| `KC_BOOTSTRAP_ADMIN_PASSWORD` | Initial admin password | `change_me` |
| `KC_DB` | Database vendor (build option) | `postgres` |
| `KC_DB_URL` | Full JDBC URL | `jdbc:postgresql://host/db` |
| `KC_DB_URL_HOST` | DB hostname | `postgres` |
| `KC_DB_USERNAME` | DB username | `keycloak` |
| `KC_DB_PASSWORD` | DB password | `secret` |
| `KC_HOSTNAME` | Public hostname or URL | `keycloak.example.com` |
| `KC_HOSTNAME_ADMIN` | Separate admin hostname | `admin.internal.example.com` |
| `KC_HTTP_ENABLED` | Enable HTTP listener | `true` |
| `KC_HTTPS_CERTIFICATE_FILE` | TLS certificate path | `/certs/tls.crt` |
| `KC_HTTPS_CERTIFICATE_KEY_FILE` | TLS key path | `/certs/tls.key` |
| `KC_PROXY_HEADERS` | Proxy header type | `xforwarded` |
| `KC_HEALTH_ENABLED` | Enable health endpoints | `true` |
| `KC_METRICS_ENABLED` | Enable metrics endpoint | `true` |
| `KC_HTTP_MAX_QUEUED_REQUESTS` | Max queued requests before 503 | `1000` |
| `KC_LOG_LEVEL` | Log verbosity | `INFO`, `DEBUG`, `WARN` |
| `JAVA_OPTS_KC_HEAP` | Override JVM heap settings | `-XX:MaxRAMPercentage=70` |
| `JAVA_OPTS_APPEND` | Append JVM flags | `-Djava.net.preferIPv4Stack=true` |

---

## CLI Command Reference

```bash
# Development startup
bin/kc.sh start-dev

# Production startup
bin/kc.sh start

# Bake build options (run before start --optimized)
bin/kc.sh build

# Start with pre-built image (skip build step at runtime)
bin/kc.sh start --optimized

# Use custom config file
bin/kc.sh --config-file=/path/to/myconfig.conf start

# Export realms
bin/kc.sh export --dir <dir> [--realm <name>]

# Import realms
bin/kc.sh import --file <file> [--override false]

# Show all configuration options
bin/kc.sh start --help
bin/kc.sh build --help
```

---

## IPv4 / IPv6 Explicit Configuration

```bash
# Force IPv4 (typical Docker/K8s)
export JAVA_OPTS_APPEND="-Djava.net.preferIPv4Stack=true"

# Force IPv6 (for distributed caches)
export JAVA_OPTS_APPEND="-Djava.net.preferIPv4Stack=false -Djava.net.preferIPv6Addresses=true"
```

---

## Common Workflows for Claude Code

When helping users with Keycloak:

1. **Identify the deployment target first**: Docker (single node dev/prod), Docker Compose (full stack), Kubernetes (plain manifests), or Kubernetes with Operator.
2. **Separate build vs. runtime options**: Build options (`--db`, `--health-enabled`, `--features`) belong in `Dockerfile`/`kc.sh build`. Runtime options (credentials, hostname, TLS certs) go in environment variables or `keycloak.conf`.
3. **Never put secrets in build options**: They are stored in plain text in the image layer.
4. **Always confirm TLS for production**: `start-dev` implies HTTP — production requires certificates.
5. **Prefer optimized images**: Run `kc.sh build` in Dockerfile so `start --optimized` skips build at container startup.
6. **For Kubernetes Operator**: Always provision the database first; the Operator does not create databases.
7. **Check hostname strictly**: Most token/redirect issues trace back to hostname misconfiguration. Use `--hostname-debug=true` to diagnose.
8. **For realm export/import**: Use CLI export (not Admin Console export) for backup — console export masks secrets.
9. **Memory**: Always set container memory limits. Default heap is 70% of container RAM.
10. **Cluster minimum**: Recommend 2+ instances for any production deployment.

# Justfile Skill

This skill provides guidance for writing user-friendly, discoverable justfile targets with fuzzy finding integration and robust error handling. Use this when helping users create or modify justfiles.

## Philosophy

1. **Discoverability**: Users should easily find and understand available commands
2. **Fuzzy Finding**: Interactive selection for complex inputs using fzf
3. **Error Prevention**: Validate inputs and provide helpful error messages
4. **Self-Documenting**: Every recipe should explain itself

## Documentation

- Just: https://github.com/casey/just
- fzf: https://github.com/junegunn/fzf

## Basic Syntax

```just
# Recipe with documentation comment (shown in --list)
recipe-name:
    command

# Recipe with parameters
greet name:
    echo "Hello, {{name}}!"

# Recipe with default parameter
test count="5":
    pytest -n {{count}}

# Recipe with dependencies
build: lint test
    cargo build --release
```

## Documentation Best Practices

### Use Documentation Comments

Comments immediately before a recipe appear in `just --list`:

```just
# Run the test suite with coverage reporting
test:
    pytest --cov

# Deploy to production (requires VPN connection)
deploy:
    ./scripts/deploy.sh
```

### Group Related Recipes

Use comment headers to organize recipes:

```just
# ============================================================================
# Development
# ============================================================================

# Start development server with hot reload
dev:
    npm run dev

# Run linter and formatter
lint:
    npm run lint

# ============================================================================
# Testing
# ============================================================================

# Run full test suite
test:
    npm test
```

### Default Recipe

Always define a helpful default that shows available commands:

```just
# Show available recipes
[private]
default:
    @just --list --unsorted
```

Or with fzf for interactive selection:

```just
# Interactively select and run a recipe
[private]
default:
    @just --list --unsorted | tail -n +2 | fzf --height 40% --reverse | awk '{print $1}' | xargs -r just
```

## fzf Integration Patterns

### Basic Interactive Selection

```just
# Interactively select a file to edit
edit:
    #!/usr/bin/env bash
    set -euo pipefail
    file=$(find . -type f -name "*.ts" | fzf --height 40% --reverse --preview 'head -50 {}')
    [[ -n "$file" ]] && ${EDITOR:-vim} "$file"
```

### Selection with Preview

```just
# Select and view a log file
logs:
    #!/usr/bin/env bash
    set -euo pipefail
    log=$(find ./logs -name "*.log" 2>/dev/null | fzf \
        --height 60% \
        --reverse \
        --preview 'tail -100 {}' \
        --preview-window right:60%:wrap)
    [[ -n "$log" ]] && less "$log"
```

### Multi-Select with fzf

```just
# Select multiple files to delete
clean-select:
    #!/usr/bin/env bash
    set -euo pipefail
    files=$(find . -name "*.tmp" -o -name "*.log" | fzf \
        --multi \
        --height 40% \
        --reverse \
        --header "Select files to delete (TAB to multi-select)")
    if [[ -n "$files" ]]; then
        echo "$files" | xargs -r rm -v
    fi
```

### Git Branch Selection

```just
# Switch to a branch using fuzzy finder
checkout:
    #!/usr/bin/env bash
    set -euo pipefail
    branch=$(git branch -a | sed 's/^[* ]*//' | sed 's|remotes/origin/||' | sort -u | \
        fzf --height 40% --reverse --preview 'git log --oneline -20 {}')
    [[ -n "$branch" ]] && git checkout "$branch"
```

### Docker Container Selection

```just
# Attach to a running container
docker-attach:
    #!/usr/bin/env bash
    set -euo pipefail
    container=$(docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | \
        fzf --height 40% --reverse --header "Select container" | \
        awk '{print $1}')
    [[ -n "$container" ]] && docker exec -it "$container" /bin/sh
```

### Process Selection

```just
# Kill a process interactively
kill-process:
    #!/usr/bin/env bash
    set -euo pipefail
    pid=$(ps aux | fzf --height 40% --reverse --header-lines=1 | awk '{print $2}')
    if [[ -n "$pid" ]]; then
        echo "Killing process $pid..."
        kill "$pid"
    fi
```

### Environment Selection

```just
# Deploy to selected environment
deploy:
    #!/usr/bin/env bash
    set -euo pipefail
    env=$(echo -e "development\nstaging\nproduction" | \
        fzf --height 20% --reverse --header "Select environment")
    [[ -n "$env" ]] && ./scripts/deploy.sh "$env"
```

### With Parameter Fallback

```just
# Run tests - uses fzf if no pattern provided
test pattern="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "{{pattern}}" ]]; then
        pattern=$(find tests -name "test_*.py" | \
            fzf --height 40% --reverse --preview 'head -30 {}' | \
            xargs -r basename | sed 's/\.py$//')
    else
        pattern="{{pattern}}"
    fi
    [[ -n "$pattern" ]] && pytest -k "$pattern" -v
```

## Error Handling Patterns

### Dependency Checks

```just
# Check required tools exist
[private]
check-deps:
    #!/usr/bin/env bash
    set -euo pipefail
    missing=()
    for cmd in docker kubectl fzf jq; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: Missing required tools: ${missing[*]}" >&2
        echo "Install with: brew install ${missing[*]}" >&2
        exit 1
    fi
```

### Input Validation

```just
# Deploy with environment validation
deploy env:
    #!/usr/bin/env bash
    set -euo pipefail
    valid_envs=("development" "staging" "production")
    if [[ ! " ${valid_envs[*]} " =~ " {{env}} " ]]; then
        echo "Error: Invalid environment '{{env}}'" >&2
        echo "Valid options: ${valid_envs[*]}" >&2
        exit 1
    fi
    echo "Deploying to {{env}}..."
    ./scripts/deploy.sh "{{env}}"
```

### Confirmation Prompts

```just
# Destructive action with confirmation
reset-db:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "WARNING: This will delete all data in the database!"
    read -p "Type 'yes' to confirm: " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Aborted."
        exit 1
    fi
    ./scripts/reset-db.sh
```

### Production Safety

```just
# Production deployment with multiple safeguards
deploy-prod: check-deps
    #!/usr/bin/env bash
    set -euo pipefail

    # Ensure clean git state
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "Error: Working directory is not clean" >&2
        git status --short >&2
        exit 1
    fi

    # Ensure on main branch
    branch=$(git branch --show-current)
    if [[ "$branch" != "main" ]]; then
        echo "Error: Must be on 'main' branch, currently on '$branch'" >&2
        exit 1
    fi

    # Double confirmation for production
    echo "You are about to deploy to PRODUCTION"
    read -p "Type the current branch name to confirm: " confirm
    if [[ "$confirm" != "main" ]]; then
        echo "Aborted."
        exit 1
    fi

    ./scripts/deploy.sh production
```

### Graceful Failure with Suggestions

```just
# Run a script with helpful error handling
run-script name:
    #!/usr/bin/env bash
    set -euo pipefail
    script="./scripts/{{name}}.sh"
    if [[ ! -f "$script" ]]; then
        echo "Error: Script '$script' not found" >&2
        echo ""
        echo "Available scripts:" >&2
        find ./scripts -name "*.sh" -exec basename {} .sh \; | sort | sed 's/^/  /' >&2
        exit 1
    fi
    bash "$script"
```

### fzf Fallback When Not Installed

```just
# Edit file with fzf if available, otherwise prompt
edit:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v fzf &>/dev/null; then
        file=$(find . -type f -name "*.py" | fzf --height 40% --reverse)
    else
        echo "Available files:"
        find . -type f -name "*.py" | head -20 | nl
        read -p "Enter file path: " file
    fi
    [[ -n "$file" ]] && ${EDITOR:-vim} "$file"
```

## Parameter Patterns

### Required vs Optional

```just
# Required parameter (no default)
greet name:
    echo "Hello, {{name}}!"

# Optional with default
test threads="4":
    pytest -n {{threads}}

# Variadic parameters (all remaining args)
run *args:
    npm run {{args}}
```

### Environment-Based Defaults

```just
# Use environment variable with fallback
deploy target=`echo ${DEPLOY_TARGET:-staging}`:
    ./scripts/deploy.sh {{target}}
```

### Choice Parameters with Validation

```just
# Log level with validation
log level="info":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{level}}" in
        debug|info|warn|error) ;;
        *)
            echo "Error: Invalid log level '{{level}}'" >&2
            echo "Options: debug, info, warn, error" >&2
            exit 1
            ;;
    esac
    ./app --log-level={{level}}
```

## Shebang Recipes

Use shebang recipes for complex logic:

```just
# Complex logic with proper error handling
complex-task:
    #!/usr/bin/env bash
    set -euo pipefail

    # Your bash script here
    echo "Running complex task..."
```

### Python Recipe

```just
# Generate report using Python
report:
    #!/usr/bin/env python3
    import json
    from pathlib import Path

    data = json.loads(Path("data.json").read_text())
    print(f"Total items: {len(data)}")
```

### Node Recipe

```just
# Quick Node script
calc expr:
    #!/usr/bin/env node
    console.log(eval("{{expr}}"));
```

## Complete Example Justfile

```just
# Default: show available commands with fuzzy selection
[private]
default:
    @just --list --unsorted

# ============================================================================
# Setup & Dependencies
# ============================================================================

# Install all dependencies
setup: check-deps
    npm install
    pip install -r requirements.txt

# Verify required tools are installed
[private]
check-deps:
    #!/usr/bin/env bash
    set -euo pipefail
    missing=()
    for cmd in node npm python3 fzf; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: Missing tools: ${missing[*]}" >&2
        exit 1
    fi

# ============================================================================
# Development
# ============================================================================

# Start development server
dev:
    npm run dev

# Run linter and fix issues
lint:
    npm run lint:fix

# Format all code
fmt:
    npm run format

# ============================================================================
# Testing
# ============================================================================

# Run all tests
test:
    npm test

# Run specific test file (fuzzy select if not provided)
test-file file="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "{{file}}" ]]; then
        file=$(find tests -name "*.test.ts" | fzf --height 40% --reverse \
            --preview 'head -50 {}')
    else
        file="{{file}}"
    fi
    [[ -n "$file" ]] && npm test -- "$file"

# Run tests with coverage
test-cov:
    npm run test:coverage

# ============================================================================
# Database
# ============================================================================

# Run database migrations
db-migrate:
    npm run db:migrate

# Seed database with test data
db-seed:
    npm run db:seed

# Reset database (DESTRUCTIVE)
db-reset:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "WARNING: This will delete all data!"
    read -p "Type 'reset' to confirm: " confirm
    [[ "$confirm" == "reset" ]] || { echo "Aborted."; exit 1; }
    npm run db:reset

# ============================================================================
# Docker
# ============================================================================

# Build Docker image
docker-build tag="latest":
    docker build -t myapp:{{tag}} .

# Run Docker container
docker-run tag="latest":
    docker run -it --rm -p 3000:3000 myapp:{{tag}}

# Shell into a running container (fuzzy select)
docker-shell:
    #!/usr/bin/env bash
    set -euo pipefail
    container=$(docker ps --format '{{.Names}}' | fzf --height 30% --reverse)
    [[ -n "$container" ]] && docker exec -it "$container" /bin/sh

# ============================================================================
# Deployment
# ============================================================================

# Deploy to environment (fuzzy select if not provided)
deploy env="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -z "{{env}}" ]]; then
        env=$(printf "development\nstaging\nproduction" | \
            fzf --height 20% --reverse --header "Select environment")
    else
        env="{{env}}"
    fi
    [[ -z "$env" ]] && exit 0

    if [[ "$env" == "production" ]]; then
        echo "Deploying to PRODUCTION"
        read -p "Type 'deploy' to confirm: " confirm
        [[ "$confirm" == "deploy" ]] || { echo "Aborted."; exit 1; }
    fi

    echo "Deploying to $env..."
    ./scripts/deploy.sh "$env"

# ============================================================================
# Utilities
# ============================================================================

# Edit a source file (fuzzy find)
edit:
    #!/usr/bin/env bash
    set -euo pipefail
    file=$(find src -type f \( -name "*.ts" -o -name "*.tsx" \) | \
        fzf --height 50% --reverse --preview 'head -80 {}')
    [[ -n "$file" ]] && ${EDITOR:-code} "$file"

# Search codebase
search pattern:
    rg --color=always "{{pattern}}" | fzf --ansi --height 80%

# Clean build artifacts
clean:
    rm -rf dist node_modules/.cache coverage
```

## Just Settings

Useful settings at the top of your justfile:

```just
# Use bash with strict mode
set shell := ["bash", "-euo", "pipefail", "-c"]

# Load .env file
set dotenv-load

# Don't print recipe before running
set quiet

# Allow positional arguments
set positional-arguments
```

## Tips

1. **Always test with `just --dry-run`** before running destructive commands
2. **Use `@` prefix** to suppress command echoing: `@echo "quiet"`
3. **Use `set -euo pipefail`** in bash shebangs for robust error handling
4. **Provide `--help` style documentation** via comments
5. **Group recipes by category** with comment headers
6. **Use fzf `--height`** to keep context visible
7. **Add `--preview`** to fzf for better discoverability
8. **Use `--header`** in fzf to explain what user is selecting
9. **Always handle empty fzf selection** (user pressed Escape)
10. **Provide fallbacks** when fzf is not installed

# Conventional Commits Skill

This skill provides guidance for writing commit messages following the Conventional Commits specification (v1.0.0). Use this when helping users write commit messages for Git or Jujutsu (jj) workflows.

## Specification

Commit messages MUST follow this structure:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

## Rules

1. Commits MUST be prefixed with a type noun (`feat`, `fix`, etc.), followed by optional scope, optional `!`, and REQUIRED colon and space
2. The type `feat` MUST be used for new features (correlates with MINOR in SemVer)
3. The type `fix` MUST be used for bug fixes (correlates with PATCH in SemVer)
4. A scope MAY be provided after the type in parentheses: `feat(parser):`
5. A description MUST immediately follow the colon and space after the type/scope prefix
6. A longer body MAY be provided after the description, separated by one blank line
7. A body is free-form and MAY consist of any number of newline-separated paragraphs
8. One or more footers MAY be provided one blank line after the body
9. Footers MUST use git trailer format: `token: value` or `token #value`
10. Footer tokens MUST use `-` in place of whitespace (except `BREAKING CHANGE`)
11. Breaking changes MUST be indicated by:
    - `!` after type/scope: `feat(api)!: change endpoint`
    - Footer: `BREAKING CHANGE: description`
    - Or both
12. `BREAKING CHANGE` MUST be uppercase; the description may follow `BREAKING CHANGE:` or `BREAKING-CHANGE:`
13. Breaking changes correlate with MAJOR in SemVer
14. Types other than `feat` and `fix` MAY be used
15. Conventional Commits are case-insensitive, EXCEPT `BREAKING CHANGE` which MUST be uppercase

## Commit Types

| Type | Description | SemVer |
|------|-------------|--------|
| `feat` | New feature | MINOR |
| `fix` | Bug fix | PATCH |
| `docs` | Documentation only | - |
| `style` | Formatting, white-space, semicolons (no code change) | - |
| `refactor` | Code change that neither fixes a bug nor adds a feature | - |
| `perf` | Performance improvement | - |
| `test` | Adding or correcting tests | - |
| `build` | Build system or external dependencies | - |
| `ci` | CI configuration files and scripts | - |
| `chore` | Other changes that don't modify src or test files | - |
| `revert` | Reverts a previous commit | - |

## Examples

### Simple feature
```
feat: add user authentication
```

### Feature with scope
```
feat(auth): add OAuth2 login support
```

### Bug fix with body
```
fix(api): prevent race condition in request handler

Introduce a mutex lock around the shared resource access
to prevent concurrent modification issues.
```

### Breaking change with `!`
```
feat(api)!: remove deprecated endpoints

BREAKING CHANGE: The /v1/users endpoint has been removed.
Use /v2/users instead.
```

### Breaking change in footer only
```
chore: drop support for Node 12

BREAKING CHANGE: Node 12 is no longer supported due to EOL.
```

### Commit with multiple footers
```
fix(auth): resolve token refresh issue

The refresh token was not being properly validated against
the stored hash, causing intermittent auth failures.

Fixes #123
Reviewed-by: Jane Doe
```

### Revert commit
```
revert: feat(auth): add OAuth2 login support

This reverts commit abc1234.
```

## Best Practices

1. **Keep the description concise**: First line should be under 72 characters
2. **Use imperative mood**: "add feature" not "added feature" or "adds feature"
3. **Don't capitalize first letter of description**: `feat: add thing` not `feat: Add thing`
4. **No period at the end of subject line**: `feat: add thing` not `feat: add thing.`
5. **Separate subject from body with blank line**
6. **Use body to explain what and why, not how**
7. **Wrap body at 72 characters**
8. **Reference issues in footers**: `Fixes #123` or `Closes #456`

## Git Usage

```bash
# Simple commit
git commit -m "feat: add user profile page"

# Commit with body (use editor)
git commit

# Commit with body inline
git commit -m "feat(auth): add password reset" -m "Implements the forgot password flow with email verification."
```

## Jujutsu (jj) Usage

```bash
# Describe current change
jj describe -m "feat: add user profile page"

# Commit with message
jj commit -m "feat: add user profile page"

# Multi-line description (use editor)
jj describe

# Set description on specific revision
jj describe -r <revset> -m "fix(api): handle null response"
```

## When Writing Commit Messages

1. Identify the type of change (feature, fix, refactor, etc.)
2. Determine if there's a logical scope (component, module, file)
3. Write a clear, concise description in imperative mood
4. Add body if the "why" isn't obvious from the description
5. Include footers for issue references, breaking changes, or co-authors
6. Check if it's a breaking change and mark appropriately

## Reference

Full specification: https://www.conventionalcommits.org/en/v1.0.0/

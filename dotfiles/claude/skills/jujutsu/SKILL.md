# Jujutsu (jj) Version Control Skill

This skill provides comprehensive guidance for working with Jujutsu (jj), a modern version control system. Use this when users ask about jj operations, version control with jj, or when working in jj repositories.

## Core Concepts

### What is Jujutsu?
Jujutsu is an experimental VCS that:
- Tracks changes automatically (automatic snapshotting)
- Uses a change-centric model (changes have IDs independent of commits)
- Supports conflict-first workflows
- Has powerful revset expressions for selecting commits
- Maintains an operation log for undo/redo at any time
- Can work as a Git-compatible frontend

### Key Differences from Git
- **Working copy commit (`@`)**: Your current work is always a commit
- **Change IDs**: Changes are tracked independently of commits
- **Operation log**: Every command creates an operation that can be undone
- **Automatic snapshots**: Working copy is snapshotted before every command
- **Conflict tracking**: Conflicts are first-class citizens stored in commits
- **No staging area**: Changes are committed directly

## Revsets: Selecting Commits

Revsets are a functional language for selecting commits. Master these for powerful queries.

### Basic Symbols
- `@`: The working copy commit
- `@-`: Parent of working copy (equivalent to Git's `HEAD`)
- `<workspace>@`: Working copy in another workspace
- `<name>@<remote>`: Remote-tracking bookmark
- Commit IDs, change IDs, tags, bookmarks, Git refs

### Operators (in order of precedence)
- `x-`: Parents of x
- `x+`: Children of x
- `x::`: Descendants of x (including x)
- `x..`: Revisions that are not ancestors of x
- `::x`: Ancestors of x (including x)
- `..x`: Ancestors of x excluding root
- `x::y`: Descendants of x that are also ancestors of y
- `x..y`: Ancestors of y but not ancestors of x
- `::`: All visible commits
- `..`: All visible commits except root
- `~x`: Revisions not in x
- `x & y`: Intersection (revisions in both)
- `x ~ y`: Difference (revisions in x but not y)
- `x | y`: Union (revisions in either or both)

### Essential Functions
- `parents(x, [depth])`: Parents at given depth (e.g., `parents(@, 3)` = `@---`)
- `children(x, [depth])`: Children at given depth
- `ancestors(x, [depth])`: Ancestors limited to depth
- `descendants(x, [depth])`: Descendants limited to depth
- `all()`: All visible commits
- `none()`: Empty set
- `heads(x)`: Commits in x with no descendants in x
- `roots(x)`: Commits in x with no ancestors in x
- `latest(x, [count])`: Most recent commits by timestamp
- `fork_point(x)`: Common ancestor(s) where commits in x diverged
- `merges()`: Merge commits only
- `empty()`: Commits with no changes
- `conflicts()`: Commits with unresolved conflicts

### Author and Description Queries
- `author(pattern)`: Match author name or email
- `author_email(pattern)`: Match author email
- `mine()`: Commits by current user
- `description(pattern)`: Match full description
- `subject(pattern)`: Match first line of description
- `author_date(pattern)`: Match author date
- `committer_date(pattern)`: Match committer date

### File and Diff Queries
- `files(expression)`: Commits modifying paths matching fileset
- `diff_contains(text, [files])`: Commits with diffs containing text

### Bookmark and Tag Functions
- `bookmarks([pattern])`: Local bookmarks matching pattern
- `remote_bookmarks([bookmark_pattern], [[remote=]remote_pattern])`: Remote bookmarks
- `tracked_remote_bookmarks([pattern], [[remote=]remote_pattern])`: Tracked remotes
- `tags([pattern])`: Tags matching pattern

### Advanced Functions
- `reachable(srcs, domain)`: All commits reachable from srcs within domain
- `connected(x)`: Same as `x::x`, connects all commits in x
- `present(x)`: Returns x, or none() if x doesn't exist (no error)
- `coalesce(x, y, z, ...)`: First revset that isn't none()
- `exactly(x, count)`: Errors if x doesn't have exactly count commits
- `at_operation(op, x)`: Evaluate x at a specific operation
- `bisect(x)`: Find midpoint commits for bisection

### String Patterns
Functions support pattern matching:
- `exact:"string"`: Exact match
- `glob:"pattern"`: Unix shell wildcards (default)
- `regex:"pattern"`: Regular expressions
- `substring:"string"`: Contains substring
- Add `-i` suffix for case-insensitive: `glob-i:"fix*"`

Patterns can be combined:
- `~pattern`: NOT pattern
- `pattern1 & pattern2`: AND
- `pattern1 ~ pattern2`: pattern1 but not pattern2
- `pattern1 | pattern2`: OR

### Date Patterns
- `after:"2024-01-01"`: At or after date
- `before:"2024-01-01"`: Before date
- Supports: ISO dates, "2 days ago", "yesterday 5pm", etc.

### Common Revset Examples

```bash
# Show parent of working copy (like git log -1 HEAD)
jj log -r @-

# Show all ancestors of working copy (like git log)
jj log -r ::@

# Show commits not on any remote bookmark
jj log -r 'remote_bookmarks()..'

# Show commits not on origin
jj log -r 'remote_bookmarks(remote=origin)..'

# Show initial commits (Git's "root commits")
jj log -r 'root()+'

# Show important commits (like git log --simplify-by-decoration)
jj log -r 'tags() | bookmarks()'

# Local work and descendants
jj log -r '(remote_bookmarks()..@)::'

# Commits by author with keyword in description
jj log -r 'author(*smith*) & description(*bug*)'

# Commits from last week
jj log -r 'committer_date(after:"1 week ago")'

# Empty commits (ready to be abandoned)
jj log -r 'empty() ~ root()'

# All merge commits
jj log -r 'merges()'

# Changes to specific files
jj log -r 'files("src/**/*.rs")'

# My unmerged work
jj log -r 'mine() & remote_bookmarks()..'
```

## Change History and Log

### Viewing History
```bash
# Show log (default: mutable revisions + context)
jj log

# Show all revisions
jj log -r ::

# Limit to n commits
jj log -n 10

# Show in reverse (oldest first)
jj log --reversed

# Show without graph
jj log -G

# Custom template
jj log -T 'commit_id.short() ++ " " ++ description.first_line()'

# Show patch
jj log -p

# Show with stats
jj log --stat

# Show summary
jj log -s

# Show specific revision details
jj show <revset>
jj show @
jj show @-
jj show <change-id>
```

### Evolution Log (Change History)
Track how a change has evolved over time:

```bash
# Show evolution of current change
jj evolog

# Show evolution of specific change
jj evolog -r <change-id>

# Show with patches between versions
jj evolog -p

# Limit entries
jj evolog -n 5
```

### Comparing Revisions
```bash
# Diff between two revisions
jj diff -r <from>..<to>
jj diff -r @-..<change-id>

# Diff current change against parent
jj diff

# Diff specific files
jj diff <path>

# Interdiff (compare diffs between two revisions)
jj interdiff --from <rev1> --to <rev2>

# Show what changed in an operation
jj operation diff <op-id>
```

## Operation Log

The operation log records every command. Each operation can be undone or the repo can be restored to any past state.

### Viewing Operations
```bash
# Show operation log
jj op log
jj operation log

# Show specific operation details
jj op show <op-id>
jj operation show <op-id>

# Show what changed in an operation
jj op diff <op-id>
```

### Undo and Redo
```bash
# Undo last operation
jj undo

# Redo last undone operation
jj redo

# Undo multiple operations back
jj undo  # run multiple times
# OR restore to specific operation:
jj op restore <op-id>

# View repo at past operation (read-only)
jj --at-op=<op-id> log
jj --at-op=<op-id> status
```

### Operation Restoration
```bash
# Restore repo to a past operation
jj op restore <op-id>

# Revert a specific operation (create inverse operation)
jj op revert <op-id>

# Abandon old operations (clean up)
jj op abandon <op-id-range>
```

### Loading at Past Operations
Use `--at-op` to view or query the repo state at any past operation:

```bash
# See what status was at previous operation
jj --at-op=@- status

# See log as it was 3 operations ago
jj --at-op=@--- log

# Find when a change was created
jj op log | grep "create change"
```

## Working with Workspaces

Workspaces are additional working copies attached to the same repo, useful for parallel work.

### Workspace Commands
```bash
# List workspaces
jj workspace list

# Add new workspace
jj workspace add <path> [--name <name>]
jj workspace add ../jj-feature-x

# Forget workspace (stop tracking)
jj workspace forget [<workspace>]

# Rename current workspace
jj workspace rename <new-name>

# Show workspace root
jj workspace root

# Update stale workspace
jj workspace update-stale
```

### Working with Multiple Workspaces
- Each workspace has its own working-copy commit: `<workspace>@`
- Each workspace has independent sparse patterns
- Changes are shared across all workspaces
- Useful for running long builds/tests while continuing work

```bash
# Reference another workspace's working copy
jj log -r feature-workspace@

# Edit a commit in another workspace
jj edit <workspace>@

# Create new workspace for feature work
jj workspace add ../feature-branch --name feature

# In workspace, commits show as "feature@" in log
jj log  # shows <workspace>@ for each workspace
```

## Fixing Divergent Changes

Divergent changes occur when a change ID points to multiple commits (often from conflicting operations).

### Identifying Divergence
```bash
# Divergent changes show with "??" in log
jj log  # look for "??" markers

# List all divergent changes
jj log -r 'divergent()'  # Note: may need custom alias

# Show specific divergent change
jj show <change-id>  # will show all commits with that change ID
```

### Resolving Divergence

**Option 1: Abandon unwanted divergent commits**
```bash
# List divergent commits for a change
jj log -r <change-id>

# Abandon the unwanted one(s)
jj abandon <commit-id-to-abandon>
```

**Option 2: Merge divergent commits**
```bash
# Create a merge of divergent commits
jj merge <change-id>/<offset1> <change-id>/<offset2>

# Or use commit IDs directly
jj merge <commit-id-1> <commit-id-2>
```

**Option 3: Duplicate and abandon**
```bash
# Duplicate the one you want to keep
jj duplicate <commit-id-to-keep>

# Abandon the original divergent change entirely
jj abandon <change-id>  # abandons all commits with this change ID
```

### Change Offsets
Access specific divergent commits using offsets:
```bash
# <change-id>/0 is the first commit
# <change-id>/1 is the second commit
jj show <change-id>/0
jj show <change-id>/1

# Use in commands
jj new <change-id>/0
jj squash --from <change-id>/1
```

## Conflict Resolution

Jujutsu stores conflicts in commits. You can commit and share conflicted states.

### Identifying Conflicts
```bash
# Show commits with conflicts
jj log -r 'conflicts()'

# Check current status
jj status

# List conflicted files in current change
jj resolve --list
jj resolve -l
```

### Resolving Conflicts

**Interactive resolution with merge tool:**
```bash
# Resolve all conflicts interactively
jj resolve

# Resolve specific files
jj resolve <path>

# Use specific merge tool
jj resolve --tool <tool-name>

# Use builtin tools to pick a side
jj resolve --tool :ours  # pick "our" side
jj resolve --tool :theirs  # pick "their" side
```

**Manual resolution:**
Edit the conflict markers directly in files:
```
<<<<<<< Side #1 (Conflict 1/1)
content from first parent
||||||| Base
original content
=======
content from second parent
>>>>>>> Side #2 (Conflict 1/1 ends)
```

After editing, the file is automatically marked as resolved on next snapshot.

### Advanced Conflict Handling
```bash
# Create a merge commit
jj merge <rev1> <rev2>

# Rebase (may create conflicts)
jj rebase -d <destination>

# Continue working with conflicts
jj new  # creates new change on top of conflict

# Abandon conflicted change
jj abandon <revset>

# Diff with conflict markers
jj diff  # shows conflict markers as diff
```

## Commit Descriptions (Conventional Commits)

All jj change descriptions MUST follow the Conventional Commits specification (v1.0.0).

### Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | Description | SemVer |
|------|-------------|--------|
| `feat` | New feature | MINOR |
| `fix` | Bug fix | PATCH |
| `docs` | Documentation only | - |
| `style` | Formatting, white-space (no logic change) | - |
| `refactor` | Code change that neither fixes nor adds | - |
| `perf` | Performance improvement | - |
| `test` | Adding or correcting tests | - |
| `build` | Build system or external dependencies | - |
| `ci` | CI configuration files and scripts | - |
| `chore` | Other changes that don't modify src or test files | - |
| `revert` | Reverts a previous change | - |

### Rules

1. MUST be prefixed with a type, followed by optional scope, optional `!`, then `: description`
2. `feat` MUST be used for new features (MINOR in SemVer)
3. `fix` MUST be used for bug fixes (PATCH in SemVer)
4. Scope MAY be provided in parentheses: `feat(parser):`
5. Description MUST immediately follow the colon+space
6. Body MAY follow description after one blank line
7. Footers MAY follow body after one blank line, using `token: value` format
8. Breaking changes MUST be indicated by `!` after type/scope and/or `BREAKING CHANGE:` footer
9. `BREAKING CHANGE` MUST be uppercase (correlates with MAJOR in SemVer)
10. Description: imperative mood, no capital first letter, no trailing period, under 72 chars
11. Body: explain what and why (not how), wrap at 72 chars

### Examples

```
feat: add user authentication

fix(api): prevent race condition in request handler

Introduce a mutex lock around the shared resource access
to prevent concurrent modification issues.

feat(api)!: remove deprecated endpoints

BREAKING CHANGE: The /v1/users endpoint has been removed.
Use /v2/users instead.

fix(auth): resolve token refresh issue

Fixes #123
Reviewed-by: Jane Doe

revert: feat(auth): add OAuth2 login support

This reverts change abc1234.
```

### Writing Descriptions in jj

```bash
# Describe current change
jj describe -m "feat: add user profile page"

# Commit with message
jj commit -m "feat: add user profile page"

# Multi-line description (opens editor)
jj describe

# Set description on specific revision
jj describe -r <revset> -m "fix(api): handle null response"

# Identify the change type, then describe
jj describe -m "refactor(auth): extract token validation logic"
```

### Choosing a Description

1. Identify the type (feat, fix, refactor, etc.)
2. Determine if there's a logical scope (component, module, subsystem)
3. Write a clear description in imperative mood
4. Add body if the "why" isn't obvious from the description
5. Include footers for issue references, breaking changes, or reviewers
6. Mark breaking changes with `!` and/or `BREAKING CHANGE:` footer

## Change Management

### Creating and Editing Changes

```bash
# Create new empty change (becomes new @)
jj new

# Create new change with specific parent(s)
jj new <revset>
jj new @--  # new change on grandparent

# Create new change after specific revision
jj new --after <revset>

# Edit a specific revision (make it @)
jj edit <revset>

# Update description (must follow Conventional Commits format)
jj describe
jj describe -m "feat: add new endpoint"
jj describe <revset> -m "fix(parser): handle empty input"

# Commit current change (create description and new empty @)
jj commit -m "feat: add user profile page"
```

### Moving and Rebasing Changes

```bash
# Rebase onto new parent
jj rebase -d <destination>
jj rebase -r <revset> -d <destination>

# Rebase onto multiple parents (create merge)
jj rebase -d <parent1> -d <parent2>

# Rebase entire branch
jj rebase -s <source> -d <destination>

# Rebase descendants onto parents (remove commit from history)
jj rebase --skip-empty -s <revset> -d <revset>-

# Move individual changes
jj move --from <source> --to <destination>
```

### Squashing and Splitting

```bash
# Squash current change into parent
jj squash

# Squash specific change into parent
jj squash -r <revset>

# Squash change into specific target
jj squash --into <revset>

# Squash from specific source
jj squash --from <revset>

# Squash only specific paths
jj squash <paths>

# Interactive squashing
jj squash -i

# Split a change
jj split

# Split interactively
jj split -i

# Split specific paths into new change
jj split <paths>
```

### Duplicating and Abandoning

```bash
# Duplicate a change (create copy)
jj duplicate <revset>

# Abandon changes (remove without keeping contents)
jj abandon <revset>

# Abandon empty changes
jj abandon -r 'empty() ~ root()'

# Restore abandoned change (use operation log)
jj undo
```

### Advanced Change Manipulation

```bash
# Absorb changes from @ into ancestors
jj absorb

# Parallelize commits (make siblings instead of linear)
jj parallelize <revset>

# Simplify parent edges
jj simplify-parents <revset>

# Edit change without changing content (metadata only)
jj metaedit
jj metaedit -m "new description"

# Touch up content with diff editor
jj diffedit
jj diffedit -r <revset>

# Apply reverse of a change
jj revert -r <revset>

# Restore paths from another revision
jj restore --from <revset> <paths>
```

## Bookmarks and Tags

### Bookmark Management
```bash
# List bookmarks
jj bookmark list

# Create bookmark
jj bookmark create <name>
jj bookmark create <name> -r <revset>

# Move bookmark
jj bookmark move <name> -r <revset>

# Delete bookmark
jj bookmark delete <name>

# Rename bookmark
jj bookmark rename <old> <new>

# Track remote bookmark
jj bookmark track <name>@<remote>

# Untrack remote bookmark
jj bookmark untrack <name>@<remote>
```

### Tag Management
```bash
# List tags
jj tag list

# Create tag
jj tag create <name>
jj tag create <name> -r <revset>

# Delete tag
jj tag delete <name>
```

## Git Integration

When working with Git repositories:

```bash
# Fetch from Git remote
jj git fetch
jj git fetch --remote <remote>

# Push to Git remote
jj git push
jj git push --bookmark <bookmark>
jj git push --all
jj git push --change <change-id>  # creates bookmark automatically

# Clone Git repository
jj git clone <url> [<destination>]

# Initialize jj in existing Git repo
jj git init --git-repo .

# Export to Git
jj git export

# Import from Git
jj git import
```

## Best Practices for Claude Code

When helping users with jj:

1. **Always check if in jj repo**: Run `jj status` to verify
2. **Use revsets for precision**: Prefer specific revsets over vague references
3. **Leverage operation log**: Remind users that any operation can be undone
4. **Explain change IDs vs commit IDs**: Clarify when discussing revisions
5. **Use `--at-op` for investigation**: Show repo state at different times
6. **Check for conflicts**: Run `jj status` or `jj log -r 'conflicts()'`
7. **Handle divergence carefully**: Identify and resolve divergent changes properly
8. **Combine operations**: Chain commands when appropriate (e.g., `jj commit -m "feat: add thing" && jj new`)
9. **Test revsets**: Use `jj log -r <revset>` to verify before destructive operations
10. **Preserve user intent**: Use `present()` and `coalesce()` for robust scripts
11. **Always use Conventional Commits**: Every `jj describe` or `jj commit -m` MUST use the `type[(scope)][!]: description` format. Suggest the correct type when helping users write descriptions.

## Common Workflows

### Making a change
```bash
jj new                                    # create new change
# edit files
jj describe -m "feat: add login button"   # set description (Conventional Commits)
jj squash                                 # squash into parent (or)
jj commit -m "feat: add login button"     # commit and start new change
```

### Reviewing changes
```bash
jj status                 # see current state
jj diff                   # see changes in @
jj diff -r <revset>       # see changes in specific revision
jj show <revset>          # show commit details and diff
jj log                    # see history
```

### Fixing up history
```bash
jj edit <revset>          # edit old change
# make changes
jj squash -r <revset>     # squash changes into old commit
jj diffedit -r <revset>   # interactively edit old commit
```

### Resolving conflicts
```bash
jj rebase -d <dest>       # may create conflicts
jj resolve                # resolve interactively
# or edit markers manually
jj status                 # verify resolution
```

### Working with Git
```bash
jj git fetch              # fetch from remotes
jj rebase -d main@origin  # rebase onto origin/main
jj git push --change @    # push current change (creates bookmark)
```

## Reference: All Commands

See `jj help` for comprehensive list. Key commands:

- `abandon`: Abandon a revision
- `absorb`: Move changes into mutable revision stack
- `bisect`: Find bad revision by bisection
- `bookmark`: Manage bookmarks
- `commit`: Create commit with description and new empty change
- `describe`: Update change description
- `diff`: Compare file contents
- `diffedit`: Edit changes with diff editor
- `duplicate`: Create new changes with same content
- `edit`: Set revision as working-copy
- `evolog`: Show change evolution
- `log`: Show revision history
- `merge`: Merge revisions
- `new`: Create new empty change
- `next`: Move to child revision
- `operation`: Work with operation log
- `parallelize`: Make revisions siblings
- `prev`: Move to parent revision
- `rebase`: Move revisions to different parents
- `redo`: Redo undone operation
- `resolve`: Resolve conflicts
- `restore`: Restore paths from another revision
- `revert`: Apply reverse of revision
- `show`: Show commit details
- `split`: Split a revision
- `squash`: Move changes between revisions
- `status`: Show repo status
- `workspace`: Manage workspaces
- `undo`: Undo last operation

## Getting Help

```bash
jj help                   # list all commands
jj help <command>         # help for specific command
jj help -k revsets        # keyword help for revsets
jj help -k templates      # keyword help for templates
jj help -k tutorial       # tutorial
```

For more information, see the official documentation at https://docs.jj-vcs.dev/

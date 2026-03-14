#!/usr/bin/env zsh
# Zellij Session Manager
# Switch to existing sessions or create new ones with layout selection
#
# Usage:
#   zellij-sessionizer          # Interactive mode: select project with fzf
#   zellij-sessionizer <path>   # Direct mode: open session for specified path
set -e
# Configuration
PROJECT_ROOTS=(
    "${HOME}/github"
)
# Single directories to include directly (not searched within)
PROJECT_DIRS=(
    # Add specific directories here
    "${HOME}/dotfiles"
)
ZELLIJ_CONFIG_DIR="${HOME}/.config/zellij"
ZELLIJ_SWITCH_PLUGIN="file:${HOME}/.config/zellij/plugins/zellij-switch.wasm"
ZELLIJ_LAYOUT_DIR="${HOME}/.config/zellij/layouts"
# Performance settings
FD_MAX_DEPTH=2  # Limit directory search depth
FD_EXCLUDES=(
    "node_modules"
    ".git"
    "target"
    "build"
    "dist"
    ".cache"
    ".next"
    ".venv"
    "venv"
    "__pycache__"
)
# Check if we're currently in a Zellij session
is_in_zellij_session() {
    [[ -n "${ZELLIJ:-}" ]]
}
# Get list of active Zellij sessions
get_active_sessions() {
    zellij ls -sn 2>/dev/null || echo ""
}
# Check if directory is a jujutsu workspace
is_jj_workspace() {
    local selected="$1"
    local dir_name=$(basename "$selected")
    # Check if folder is called default and contains .jj folder
    if [[ "$dir_name" == "default" ]] && [[ -d "$selected/.jj" ]]; then
        return 0
    fi
    # Check if parent directory has default/.jj
    local parent_dir=$(dirname "$selected")
    if [[ -d "$parent_dir/default/.jj" ]]; then
        return 0
    fi
    # Check if there's a .jj directory but no .git directory
    if [[ -d "$selected/.jj" ]] && [[ ! -d "$selected/.git" ]]; then
        return 0
    fi
    return 1
}
# Generate session name for a given directory
# This follows the same logic used when creating sessions:
# - For worktrees/workspaces: parent--child format
# - For regular directories: basename only
# - Dots are replaced with underscores
get_session_name_for_directory() {
    local dir="$1"
    local session_name
    local parent=$(dirname "$dir")
    local dir_name=$(basename "$dir")
    # Fast path: check for .bare directory in parent (git worktree)
    if [[ -d "$parent/.bare" ]]; then
        local parent_name=$(basename "$parent")
        session_name="${parent_name}--${dir_name}"
    # Check for jujutsu workspace markers (only if not a git worktree)
    elif [[ "$dir_name" == "default" && -d "$dir/.jj" ]] || \
         [[ -d "$parent/default/.jj" ]] || \
         [[ -d "$dir/.jj" && ! -d "$dir/.git" ]]; then
        # For jj workspaces, use parent--child naming
        local parent_name=$(basename "$parent")
        session_name="${parent_name}--${dir_name}"
    else
        # For regular directories, just use the basename
        session_name="$dir_name"
    fi
    # Replace dots with underscores in session name
    echo "$session_name" | tr . _
}
# Strip ANSI color codes and bullet prefix from a string
strip_ansi_codes() {
    echo "$1" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^[●◉] //'
}
# Select a project directory using fzf
select_project_directory() {
    local all_projects=()
    # Add single directories from PROJECT_DIRS
    for dir in "${PROJECT_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            all_projects+=("$dir")
        fi
    done
    # Build fd command with multiple search paths for PROJECT_ROOTS
    local fd_args=("--type" "directory" "--max-depth" "$FD_MAX_DEPTH")
    # Add exclude patterns
    for exclude in "${FD_EXCLUDES[@]}"; do
        fd_args+=("--exclude" "$exclude")
    done
    local valid_roots=0
    for root in "${PROJECT_ROOTS[@]}"; do
        if [[ -d "$root" ]]; then
            fd_args+=("--search-path" "$root")
            ((valid_roots++))
        fi
    done
    # Collect all project directories
    if [[ $valid_roots -gt 0 ]]; then
        local fd_results
        fd_results=$(fd "${fd_args[@]}" 2>/dev/null)
        if [[ -n "$fd_results" ]]; then
            while IFS= read -r dir; do
                all_projects+=("$dir")
            done <<< "$fd_results"
        fi
    fi
    [[ ${#all_projects[@]} -eq 0 ]] && return 1
    # Get active sessions
    local active_sessions
    active_sessions=$(get_active_sessions)
    # Early exit if no active sessions - use simple list
    if [[ -z "$active_sessions" ]]; then
        local selected_project
        selected_project=$(printf '%s\n' "${all_projects[@]}" | fzf --header="Select project")
        [[ -z "$selected_project" ]] && return 1
        echo "$selected_project"
        return 0
    fi
    # Build hash map of active sessions for fast lookup
    declare -A active_map
    while IFS= read -r session; do
        [[ -n "$session" ]] && active_map[$session]=1
    done <<< "$active_sessions"
    # Get current session name if we're in a Zellij session
    local current_session_name="${ZELLIJ_SESSION_NAME:-}"
    # Build colored list - inline session name generation for speed
    # Separate into current, other active, and inactive
    local current_output=""
    local active_output=""
    local inactive_output=""
    local dir dir_clean parent_dir dir_name parent_name session_name is_workspace
    for dir in "${all_projects[@]}"; do
        # Strip trailing slash if present (fd may add trailing slashes)
        dir_clean="${dir%/}"
        # Inline basename/dirname to avoid subshells
        dir_name="${dir_clean##*/}"
        parent_dir="${dir_clean%/*}"
        parent_name="${parent_dir##*/}"
        # Check for workspace patterns - minimize filesystem checks with short-circuit logic
        is_workspace=0
        # Fast path: check for .bare first (most common for git worktrees)
        if [[ -d "$parent_dir/.bare" ]]; then
            is_workspace=1
        # Only if dir is named "default", check for jj workspace markers
        elif [[ "$dir_name" == "default" && -d "$dir_clean/.jj" ]]; then
            is_workspace=1
        # Check for sibling default/.jj only if neither above matched
        elif [[ -d "$parent_dir/default/.jj" ]]; then
            is_workspace=1
        fi
        # Generate session name
        if [[ $is_workspace -eq 1 ]]; then
            session_name="${parent_name}--${dir_name}"
        else
            session_name="$dir_name"
        fi
        # Replace dots with underscores
        session_name="${session_name//\./_}"
        # Add with color based on active status
        if [[ -n "${active_map[$session_name]}" ]]; then
            # Check if this is the current session
            if [[ "$session_name" == "$current_session_name" ]]; then
                # Current session: green bullseye
                current_output+=$'\033[32m◉ '"$dir_clean"$'\033[0m\n'
            else
                # Other active session: orange (256 color code 208)
                active_output+=$'\033[38;5;208m● '"$dir_clean"$'\033[0m\n'
            fi
        else
            inactive_output+=$'\033[2m'"$dir_clean"$'\033[0m\n'
        fi
    done
    # Combine: current first, then other active, then inactive
    local output="${current_output}${active_output}${inactive_output}"
    [[ -z "$output" ]] && return 1
    # Select with fzf using --ansi to preserve colors
    local selected_project
    selected_project=$(echo -n "$output" | fzf --ansi --header=$'Select project (\033[32m◉ current\033[0m, \033[38;5;208m● active\033[0m, \033[2minactive\033[0m)')
    [[ -z "$selected_project" ]] && return 1
    # Strip ANSI codes and bullet prefix from selection
    selected_project=$(strip_ansi_codes "$selected_project")
    echo "$selected_project"
}
# Select a Zellij layout from available options
select_zellij_layout() {
    local layouts_dir="${ZELLIJ_CONFIG_DIR}/layouts"
    local layout_paths=()
    local layout_names=()
    # Check if layouts directory exists and gather available layouts
    if [[ -d "$layouts_dir" ]]; then
        local layouts=("$layouts_dir"/*.kdl(N) "$layouts_dir"/*.yaml(N) "$layouts_dir"/*.yml(N))
        for layout in "${layouts[@]}"; do
            if [[ -f "$layout" ]]; then
                layout_paths+=("$layout")
                local layout_basename=$(basename "$layout")
                layout_names+=("${layout_basename%.*}")
            fi
        done
    fi
    # Build selection list with "No layout" first
    local selection_list="Simple Shell - No layout"
    for layout_name in "${layout_names[@]}"; do
        selection_list="${layout_name}\n${selection_list}"
    done
    # Use fzf to select
    local selected
    selected=$(echo -e "$selection_list" | fzf --height=50% --padding=1% --border=double --header="Select layout")
    [[ -z "$selected" ]] && return 1
    # If "No layout" is selected, return empty string
    if [[ "$selected" == "No layout" ]]; then
        echo ""
    else
        # Find the corresponding path (zsh arrays are 1-indexed)
        for i in {1..${#layout_names[@]}}; do
            if [[ "${layout_names[$i]}" == "$selected" ]]; then
                echo "${layout_paths[$i]}"
                return 0
            fi
        done
    fi
}
# Check if a session with the given name exists
session_exists() {
    local session_name="$1"
    local active_sessions="$2"
    echo "$active_sessions" | grep -q "^${session_name}$"
}
# Switch to an existing session
switch_to_session() {
    local session_name="$1"
    local in_active_session="$2"
    echo "Switching to existing session: $session_name"
    if [[ "$in_active_session" == "true" ]]; then
        # Use the switch plugin when already in a session
        zellij pipe -p "$ZELLIJ_SWITCH_PLUGIN" -- "--session $session_name"
    else
        # Attach directly when not in any session
        zellij attach "$session_name"
    fi
}
# Create a new session with the specified layout
create_new_session() {
    local session_name="$1"
    local layout_path="$2"
    local target_project="$3"
    local in_active_session="$4"
    local layout_name=$(basename "$layout_path")
    echo "Creating new session: $session_name with layout: $layout_name"
    # Change to the project directory
    if ! cd "$target_project" 2>/dev/null; then
        echo "Warning: Could not change to directory: $target_project" >&2
    fi
    if [[ "$in_active_session" == "true" ]]; then
        # Use the switch plugin to create a new session when already in one
        local layout_name_no_ext="${layout_path%.*}"  # Remove extension from path
        zellij pipe -p "$ZELLIJ_SWITCH_PLUGIN" -- "-s $session_name -l $layout_name_no_ext -c $target_project"
    else
        # Create session directly when not in any session
        # Change to the project directory and create the session
        zellij --session "$session_name" --new-session-with-layout "$layout_path"
    fi
}
# Main entry point for the session manager
main() {
    local provided_path="$1"
    # Check current session status
    local in_active_session="false"
    if is_in_zellij_session; then
        in_active_session="true"
    fi
    # Get active sessions
    local active_sessions
    active_sessions=$(get_active_sessions)
    # Select target project
    local target_project
    if [[ -n "$provided_path" ]]; then
        # Use the provided path directly
        # Expand tilde and resolve to absolute path
        target_project="${provided_path/#\~/$HOME}"
        # Verify the path exists
        if [[ ! -d "$target_project" ]]; then
            echo "Error: Directory does not exist: $target_project" >&2
            return 1
        fi
        # Convert to absolute path if it's relative
        target_project=$(cd "$target_project" && pwd)
    else
        # Use interactive selection
        target_project=$(select_project_directory)
        if [[ $? -ne 0 ]]; then
            return 1
        fi
    fi
    # Generate session name for the target project
    local session_name
    session_name=$(get_session_name_for_directory "$target_project")
    # Decide whether to switch to existing or create new session
    if session_exists "$session_name" "$active_sessions"; then
        switch_to_session "$session_name" "$in_active_session"
    else
        local layout
        layout=$(select_zellij_layout)
        if [[ $? -ne 0 ]]; then
            return 1
        fi
        create_new_session "$session_name" "$layout" "$target_project" "$in_active_session"
    fi
}
# Run main function if script is executed directly
if [[ "${ZSH_EVAL_CONTEXT:-}" == "toplevel" ]] || [[ "${(%):-%x}" == "$0" ]]; then
    if ! main "$@"; then
        exit 1
    fi
fi


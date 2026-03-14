#!/usr/bin/env zsh
# Zellij Session Manager - Zsh version
# Switch to existing sessions or create new ones with layout selection

# Configuration
PROJECT_ROOT="${HOME}"
PROJECT_SEARCH_DEPTH=3
ZELLIJ_CONFIG_DIR="${HOME}/.config/zellij"
ZELLIJ_SWITCH_PLUGIN="file:${ZELLIJ_CONFIG_DIR}/plugins/zellij-switch.wasm"
ZELLIJ_LAYOUT_DIR="${ZELLIJ_CONFIG_DIR}/layouts"

# ANSI Color codes (using $'...' syntax for escape sequences)
COLOR_GREEN=$'\033[32m'
COLOR_RED=$'\033[31m'
COLOR_YELLOW=$'\033[33m'
COLOR_RESET=$'\033[0m'

# Check if required dependencies are installed
check_dependencies() {
  local missing=()

  command -v fd >/dev/null 2>&1 || missing+=("fd")
  command -v fzf >/dev/null 2>&1 || missing+=("fzf")
  command -v zellij >/dev/null 2>&1 || missing+=("zellij")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "${COLOR_RED}Error: Missing required dependencies: ${missing[*]}${COLOR_RESET}" >&2
    echo "Install with: brew install ${missing[*]}" >&2
    return 1
  fi

  return 0
}

# Check if we're currently in a Zellij session
is_in_zellij_session() {
  [[ -n "${ZELLIJ}" ]]
}

# Get list of active Zellij sessions
get_active_sessions() {
  local sessions
  sessions=$(zellij ls -sn 2>/dev/null)
  echo "${sessions}"
}

# Annotate project directories with active session status
# Takes active sessions as parameter (newline-separated)
annotate_projects_with_status() {
  local active_sessions="$1"

  [[ ! -d "$PROJECT_ROOT" ]] && {
    echo -e "${COLOR_RED}Error: Project root does not exist: ${PROJECT_ROOT}${COLOR_RESET}" >&2
    return 1
  }

  # Build array of active sessions for this function
  local -a session_array
  session_array=("${(@f)active_sessions}")

  while IFS= read -r dir; do
    local basename="${dir##*/}"
    local is_active=0

    # Check if basename matches any active session
    for session in "${session_array[@]}"; do
      if [[ "$session" == "$basename" ]]; then
        is_active=1
        break
      fi
    done

    if [[ $is_active -eq 1 ]]; then
      echo -e "${COLOR_GREEN}●${COLOR_RESET} ${dir}"
    else
      echo "  ${dir}"
    fi
  done < <(fd --type directory --max-depth "$PROJECT_SEARCH_DEPTH" --search-path "$PROJECT_ROOT")
}

# Select a project directory using fzf
# Takes active sessions as parameter
select_project_directory() {
  local active_sessions="$1"
  local selection
  selection=$(annotate_projects_with_status "$active_sessions" | \
    fzf --ansi \
        --height=50% \
        --padding=1% \
        --border=double \
        --header="Select project (CTRL-C or ESC to quit)") || return 1

  # Strip the prefix (● or spaces) and return clean path
  echo "${selection#* }"
}

# Select a Zellij layout from available options
select_zellij_layout() {
  [[ ! -d "$ZELLIJ_LAYOUT_DIR" ]] && {
    echo -e "${COLOR_RED}Error: Zellij layouts directory not found: ${ZELLIJ_LAYOUT_DIR}${COLOR_RESET}" >&2
    return 1
  }

  local layout
  layout=$(fd --type file --extension kdl --search-path "$ZELLIJ_LAYOUT_DIR" | \
    fzf --height=40% \
        --padding=1% \
        --border=double \
        --header="Choose a Zellij layout") || return 1

  echo "$layout"
}

# Check if a session with the given name exists
# Takes session name and active sessions list as parameters
session_exists() {
  local session_name="$1"
  local active_sessions="$2"

  # Check if session_name appears in the active_sessions list
  echo "$active_sessions" | grep -q "^${session_name}$"
}

# Switch to an existing session
switch_to_session() {
  local session_name="$1"
  local in_active_session="$2"

  echo -e "${COLOR_GREEN}Switching to existing session: ${session_name}${COLOR_RESET}"

  if [[ "$in_active_session" == "true" ]]; then
    zellij pipe -p "$ZELLIJ_SWITCH_PLUGIN" -- "--session ${session_name}"
  else
    zellij attach "$session_name"
  fi
}

# Create a new session with the specified layout
create_new_session() {
  local session_name="$1"
  local layout_path="$2"
  local target_project="$3"
  local in_active_session="$4"

  local layout_basename="${layout_path:t}"  # Get filename
  local layout_name="${layout_basename:r}"   # Remove extension

  echo -e "${COLOR_GREEN}Creating new session: ${session_name} with layout: ${layout_name}${COLOR_RESET}"

  if [[ "$in_active_session" == "true" ]]; then
    zellij pipe -p "$ZELLIJ_SWITCH_PLUGIN" -- "-s ${session_name} -l ${layout_name} -c ${target_project}"
  else
    cd "$target_project" || {
      echo -e "${COLOR_RED}Error: Could not change to directory: ${target_project}${COLOR_RESET}" >&2
      return 1
    }
    zellij -s "$session_name" -n "$layout_name"
  fi
}

# Main entry point for the session manager
main() {
  # Enable local options
  emulate -L zsh
  setopt pipefail

  # Check dependencies
  check_dependencies || return 1

  # Check if in active session
  local in_active_session="false"
  if is_in_zellij_session; then
    in_active_session="true"
    echo "Currently in Zellij session: true"
  else
    echo "Currently in Zellij session: false"
  fi

  # Get active sessions
  local sessions_output
  sessions_output=$(get_active_sessions)
  echo "Active sessions: ${sessions_output:-none}"

  # Select target project
  local target_project
  target_project=$(select_project_directory "$sessions_output") || {
    echo -e "${COLOR_YELLOW}Project selection cancelled${COLOR_RESET}" >&2
    return 130
  }

  local session_name="${target_project##*/}"
  echo "Target project: ${target_project}"
  echo "Session name: ${session_name}"

  # Switch to existing or create new session
  if session_exists "$session_name" "$sessions_output"; then
    switch_to_session "$session_name" "$in_active_session"
  else
    local layout
    layout=$(select_zellij_layout) || {
      echo -e "${COLOR_YELLOW}Layout selection cancelled${COLOR_RESET}" >&2
      return 130
    }
    create_new_session "$session_name" "$layout" "$target_project" "$in_active_session"
  fi

  echo -e "${COLOR_GREEN}Successfully switched to session: ${session_name}${COLOR_RESET}"
}

# Run main function
main "$@"

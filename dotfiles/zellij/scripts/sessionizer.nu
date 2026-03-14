use std log

# Zellij Session Manager
# Switch to existing sessions or create new ones with layout selection

# Configuration - easy to modify for different environments
const PROJECT_ROOT = "~/github"
const ZELLIJ_CONFIG_DIR = "~/.config/zellij"
const ZELLIJ_SWITCH_PLUGIN = "file:~/.config/zellij/plugins/zellij-switch.wasm"
const ZELLIJ_LAYOUT_DIR = "~/.config/zellij/layouts"

def run_external [cmd: string] {
    try {
        let result = ^$cmd | complete
        {
            stdout: ($result.stdout | default ""),
            stderr: ($result.stderr | default ""),
            exit_code: ($result.exit_code | default 0)
        }
    } catch { |err|
        {
            stdout: "",
            stderr: ($err.msg | default "Unknown error"),
            exit_code: 1
        }
    }
}
# Check if we're currently in a Zellij session
def is_in_zellij_session [] {
    ($env | get -i ZELLIJ | is-not-empty)
}

# Get list of active Zellij sessions
def get_active_sessions [] {
    try {
        zellij ls -sn | parse "{name}" | get name
    } catch {
        print "Warning: Could not get active sessions. Zellij might not be running."
        []
    }
}

# Select a project directory using fzf
def select_project_directory [
    search_path: string = $PROJECT_ROOT  # Base path to search for projects
] {
    let expanded_path = ($search_path | path expand)

    if not ($expanded_path | path exists) {
        error make {msg: $"Project root directory does not exist: ($expanded_path)"}
    }

    try {
        fd --type directory --search-path $expanded_path
        | fzf --height=50% --padding=1% --border=double --header="Select project (CTRL-C or ESC to quit)"
    } catch {
        error make {msg: "Project selection was cancelled or failed"}
    }
}

# Select a Zellij layout from available options
def select_zellij_layout []  {
    let layouts_dir = ($ZELLIJ_CONFIG_DIR | path join "layouts" | path expand)

    if not ($layouts_dir | path exists) {
        error make {msg: $"Zellij layouts directory not found: ($layouts_dir)"}
    }

    let layout_options = try {
        ls $layouts_dir | where type == file
    } catch {
        error make {msg: $"Could not read layouts from: ($layouts_dir)"}
    }

    if ($layout_options | is-empty) {
        error make {msg: $"No layouts found in: ($layouts_dir)"}
    }

    $layout_options | input list -f -d name "Choose a Zellij layout"
}

# Check if a session with the given name exists
def session_exists [
    session_name: string,
    active_sessions: list
] {
    $session_name in $active_sessions
}

# Switch to an existing session
def switch_to_session [
    session_name: string,
    in_active_session: bool
] {
    print $"Switching to existing session: ($session_name)"

    if $in_active_session {
        # Use the switch plugin when already in a session
        zellij pipe -p $ZELLIJ_SWITCH_PLUGIN -- $'--session ($session_name)'
    } else {
        # Attach directly when not in any session
        zellij attach $session_name
    }
}

# Create a new session with the specified layout
def create_new_session [
    session_name: string,
    layout: record,
    target_project: string,
    in_active_session: bool
] {
    print $"Creating new session: ($session_name) with layout: ($layout.name)"

    # Change to the project directory
    try {
        cd $target_project
    } catch {
        print $"Warning: Could not change to directory: ($target_project)"
    }

    if $in_active_session {
        # Use the switch plugin to create a new session when already in one
        let project_root = ($target_project | path expand)
        let layout_name_no_extension = $layout.name | path expand | path parse
        let layout_name = $layout_name_no_extension.parent + "/" + $layout_name_no_extension.stem
        zellij pipe -p $ZELLIJ_SWITCH_PLUGIN -- $'-s ($session_name) -l ($layout_name) -c ($project_root)'
    } else {
        # Create session directly when not in any session
        zellij -s $session_name -n $layout.name
    }
}

# Main entry point for the session manager
def main [ ] {
    try {
        # Check current session status
        let in_active_session = is_in_zellij_session
        print  $"Currently in Zellij session: ($in_active_session)"

        # Get active sessions
        let active_sessions = get_active_sessions
        print $"Active sessions: ($active_sessions)"

        # Select target project
        let target_project = select_project_directory
        let session_name = ($target_project | path basename)

        print $"Target project: ($target_project)"
        print $"Session name: ($session_name)"

        # Decide whether to switch to existing or create new session
        if (session_exists $session_name $active_sessions) {
            switch_to_session $session_name $in_active_session
        } else {
            let layout = select_zellij_layout
            create_new_session $session_name $layout $target_project $in_active_session
        }

        print $"Successfully switched to session: ($session_name)"

    } catch { |err|
        print $"Error: ($err.msg)"
        exit 1
    }
}

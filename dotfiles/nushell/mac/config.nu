load-env {"SHELL": "nu"}

alias l = ls
alias la = ls -a
def lt [] {ls | sort-by modified}
def lat [] {ls -a | sort-by modified}

alias v = nvim
alias vim = nvim
alias vimdiff = nvim -d

mkdir ($nu.data-dir | path join "vendor/autoload")
starship init nu | save -f ($nu.data-dir | path join "vendor/autoload/starship.nu")

$env.config = {
    hooks : {
        pre_prompt: [{ ||
            if (which direnv | is-empty) {return}
            direnv export json | from json | default {} | load-env
            if 'ENV_CONVERSION' in $env and 'PATH' in $env.ENV_CONVERSIONS {
                $env.PATH = do $env.ENV_CONVERSIONS.PATH.from_string $env.PATH
            }
        }]
    }
}

const atuin_cfg = "~/.atuin.nu"
if ($atuin_cfg | path exists) {source $atuin_cfg}

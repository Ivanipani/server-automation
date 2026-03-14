# dotfiles

Personal configuration files for development tools and shell environments for macOS and Linux.

## Contents

This repository is organized by tool/component:

- **`zsh/`** - Zsh shell configuration with Oh My Zsh and plugins (autosuggestions, syntax highlighting, vi-mode)
- **`nvim/`** - Neovim configuration with LSP support, plugins (Telescope, Neo-tree, Lualine, etc.), and language servers
- **`wez/`** - WezTerm terminal emulator configuration with Nerd Fonts
- **`zellij/`** - Zellij terminal multiplexer configuration with layouts and plugins (sessionizer, autolock, vim navigation)
- **`vcs/`** - Version control system configurations:
  - Git configuration files
  - Jujutsu (jj) configuration
- **`nushell/`** - Nushell shell configuration (platform-specific)
- **`tools/`** - Additional development tools (starship, fzf, atuin, ripgrep, fd)

## Prerequisites

### Required Software

- **`just`** - Command runner (install via `cargo install just` or `brew install just`)
- **Cargo** (Rust toolchain) - Required for installing several tools
- **Homebrew** (macOS) or **apt** (Linux) - Package managers

### Optional (but recommended)

- **Rust toolchain** - For building tools from source
- **Python/uv** - For Python language servers and formatters
- **Nushell** - If you want to use the nushell configuration

## Quick Start

### 1. Install all tools

This will install all required tools and dependencies:

```bash
just install
```

This runs installation commands for:
- Zsh plugins (Oh My Zsh, autosuggestions, syntax highlighting, vi-mode)
- Neovim and language servers
- WezTerm and Nerd Fonts
- Zellij and plugins
- VCS tools (jj, difftastic, lazygit, lazyjj)
- Development tools (starship, fzf, atuin, ripgrep, fd)

### 2. Setup all configurations

This creates symlinks to all configuration files:

```bash
just setup
```

This sets up:
- Zsh configuration (`~/.zshrc`)
- Neovim configuration (`~/.config/nvim`)
- WezTerm configuration (`~/.config/wezterm`)
- Zellij configuration (`~/.config/zellij`)
- Git and Jujutsu configurations
- Nushell configuration (if installed)

## Individual Tool Setup

You can also set up or install individual tools:

### Zsh
```bash
just zsh/setup      # Create symlinks
just zsh/install    # Install Oh My Zsh and plugins
```

### Neovim
```bash
just nvim/setup     # Create symlinks
just nvim/install   # Install Neovim and language servers
```

### WezTerm
```bash
just wez/setup      # Create symlinks
just wez/install    # Install WezTerm and Nerd Fonts
```

### Zellij
```bash
just zellij/setup   # Create symlinks
just zellij/install # Install Zellij and plugins
```

### Version Control
```bash
just vcs/setup      # Create symlinks for git and jj configs
just vcs/install    # Install jj, difftastic, lazygit, lazyjj
```

### Nushell
```bash
just nushell/setup  # Create symlinks
just nushell/install # Install Nushell
```

### Tools
```bash
just tools/install  # Install starship, fzf, atuin, ripgrep, fd
```

## Platform Support

The `just` targets automatically detect your platform (macOS or Linux) and use the appropriate configuration:

- **macOS**: Uses Homebrew for package installation
- **Linux**: Uses apt for package installation

Some configurations are platform-specific:
- Zsh config: `zsh/mac/` or `zsh/linux/`
- Nushell config: `nushell/mac/` or `nushell/linux/`

## Customization

All configuration files are symlinked from this repository, so you can:

1. Edit files directly in this repository
2. Changes will be reflected immediately (no need to re-run setup)
3. Commit changes to version control

## Maintenance

To see all available commands:

```bash
just
```

Or for a specific tool:

```bash
just zsh/
just nvim/
# etc.
```

## Notes

- The setup process creates symlinks, so your original config files may be overwritten
- Make sure to backup any existing configurations before running `just setup`
- Some tools require manual installation if they're not available via package managers
- Language servers and formatters are installed per the Neovim configuration requirements

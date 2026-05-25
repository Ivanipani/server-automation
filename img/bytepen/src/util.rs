use std::io::{self, BufRead, Write};
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, anyhow, bail};

pub fn confirm(prompt: &str) -> Result<bool> {
    print!("{prompt} [y/N] ");
    io::stdout().flush().context("flushing stdout")?;
    let mut line = String::new();
    io::stdin()
        .lock()
        .read_line(&mut line)
        .context("reading confirmation")?;
    Ok(matches!(line.trim(), "y" | "Y"))
}

pub fn require_root() -> Result<()> {
    if nix::unistd::geteuid().is_root() {
        Ok(())
    } else {
        Err(anyhow!(
            "this operation modifies a block device and must run as root. Re-run with sudo."
        ))
    }
}

/// Accept either `disk4` / `sdb` shortcuts or a full `/dev/...` path and
/// return the canonical `/dev/...` path. Does not check that the path exists.
pub fn canonical_device_path(device: &str) -> PathBuf {
    if device.starts_with('/') {
        PathBuf::from(device)
    } else {
        PathBuf::from(format!("/dev/{device}"))
    }
}

pub fn ensure_block_device(path: &Path) -> Result<()> {
    let meta = path
        .metadata()
        .with_context(|| format!("stat {}", path.display()))?;
    let file_type = meta.file_type();
    let is_block = std::os::unix::fs::FileTypeExt::is_block_device(&file_type);
    let is_char = std::os::unix::fs::FileTypeExt::is_char_device(&file_type);
    if !is_block && !is_char {
        bail!("{} is not a block (or character) device", path.display());
    }
    Ok(())
}

pub fn ensure_regular_file(path: &Path) -> Result<()> {
    if !path.is_file() {
        bail!("image not found or not a regular file: {}", path.display());
    }
    Ok(())
}

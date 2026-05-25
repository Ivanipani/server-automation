use std::path::{Path, PathBuf};

use anyhow::Result;

#[cfg(target_os = "linux")]
mod linux;
#[cfg(target_os = "linux")]
use linux as inner;

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
use macos as inner;

#[cfg(not(any(target_os = "linux", target_os = "macos")))]
compile_error!("bytepen supports Linux and macOS only");

/// Print the host's candidate disks to stdout.
pub fn list_disks() -> Result<()> {
    inner::list_disks()
}

/// Print info for a single device to stdout.
pub fn info(device: &Path) -> Result<()> {
    inner::info(device)
}

/// Unmount every partition mounted from `device`. Idempotent: a clean device is a no-op.
pub fn unmount_all(device: &Path) -> Result<()> {
    inner::unmount_all(device)
}

/// On macOS, map `/dev/diskN` → `/dev/rdiskN` for ~10x write throughput. On Linux, identity.
pub fn raw_device_path(device: &Path) -> PathBuf {
    inner::raw_device_path(device)
}

/// Path of the binary used by `bytepen format` for a given filesystem.
#[cfg(target_os = "linux")]
pub fn format_tool(fs: crate::cli::Filesystem) -> &'static str {
    inner::format_tool(fs)
}

use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result, bail};

pub fn list_disks() -> Result<()> {
    run_inheriting("diskutil", &["list"])
}

pub fn info(device: &Path) -> Result<()> {
    // Filter to the keys burn-to-disc.sh used to surface.
    let output = Command::new("diskutil")
        .args(["info", &device.display().to_string()])
        .output()
        .context("spawning diskutil info")?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!("diskutil info failed: {stderr}");
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    for line in stdout.lines() {
        let needle = line.trim_start();
        if needle.starts_with("Device")
            || needle.starts_with("Total Size")
            || needle.starts_with("Media Name")
            || needle.starts_with("Protocol")
            || needle.starts_with("Mount Point")
        {
            println!("{line}");
        }
    }
    Ok(())
}

pub fn unmount_all(device: &Path) -> Result<()> {
    println!("Unmounting all volumes on {}...", device.display());
    // `diskutil unmountDisk` is idempotent enough — fails loudly if anything is busy.
    let status = Command::new("diskutil")
        .args(["unmountDisk", &device.display().to_string()])
        .status()
        .context("spawning diskutil unmountDisk")?;
    if !status.success() {
        bail!("diskutil unmountDisk {} failed", device.display());
    }
    Ok(())
}

/// `/dev/disk4` → `/dev/rdisk4` for direct, much faster writes (bypasses the buffer cache).
pub fn raw_device_path(device: &Path) -> PathBuf {
    let s = device.display().to_string();
    if let Some(rest) = s.strip_prefix("/dev/disk") {
        return PathBuf::from(format!("/dev/rdisk{rest}"));
    }
    device.to_path_buf()
}

fn run_inheriting<I, S>(cmd: &str, args: I) -> Result<()>
where
    I: IntoIterator<Item = S>,
    S: AsRef<std::ffi::OsStr>,
{
    let status = Command::new(cmd)
        .args(args)
        .status()
        .with_context(|| format!("spawning {cmd}"))?;
    if !status.success() {
        bail!("{cmd} exited with {status}");
    }
    Ok(())
}

use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{Context, Result, bail};

use crate::cli::Filesystem;

pub fn format_tool(fs: Filesystem) -> &'static str {
    match fs {
        Filesystem::Ext4 => "mkfs.ext4",
        Filesystem::Vfat => "mkfs.vfat",
        Filesystem::Exfat => "mkfs.exfat",
    }
}

pub fn list_disks() -> Result<()> {
    run_inheriting("lsblk", &["-d", "-o", "NAME,SIZE,MODEL,TRAN"])
}

pub fn info(device: &Path) -> Result<()> {
    run_inheriting(
        "lsblk",
        &[
            &device.display().to_string(),
            "-o",
            "NAME,SIZE,MODEL,TRAN,MOUNTPOINT",
        ],
    )
}

pub fn unmount_all(device: &Path) -> Result<()> {
    let stem = device
        .file_name()
        .and_then(|s| s.to_str())
        .context("device path has no file name")?;

    let mounts = std::fs::read_to_string("/proc/mounts").context("reading /proc/mounts")?;
    let mut targets = Vec::new();
    for line in mounts.lines() {
        let dev = match line.split_whitespace().next() {
            Some(d) => d,
            None => continue,
        };
        if let Some(name) = dev.strip_prefix("/dev/") {
            if name == stem || name.starts_with(stem) {
                targets.push(dev.to_string());
            }
        }
    }

    for t in targets {
        println!("Unmounting {t}...");
        let status = Command::new("umount").arg(&t).status()?;
        if !status.success() {
            bail!("umount {t} failed");
        }
    }
    Ok(())
}

pub fn raw_device_path(device: &Path) -> PathBuf {
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

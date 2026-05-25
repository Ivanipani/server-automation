use std::process::Command;

use anyhow::{Context, Result, bail};

use crate::cli::Filesystem;
use crate::util::{canonical_device_path, confirm, ensure_block_device, require_root};

pub fn run(device: &str, fs: Filesystem, label: Option<&str>, yes: bool) -> Result<()> {
    require_root()?;
    let device_path = canonical_device_path(device);
    ensure_block_device(&device_path)?;

    let device_str = device_path.display().to_string();
    if !is_whole_disk(&device_str) {
        bail!(
            "format does a full erase and only accepts a whole disk, got {device_str}. \
             Pass the whole disk (e.g. /dev/disk6 or /dev/sdb) instead of a slice."
        );
    }

    println!(
        "WARNING: This will WIPE all partitions and filesystems on {} \
         and create a fresh {:?} filesystem.",
        device_path.display(),
        fs
    );
    if let Some(l) = label {
        println!("Label:  {l}");
    }
    println!();

    if !yes && !confirm("Continue?")? {
        println!("Aborted.");
        return Ok(());
    }

    crate::platform::unmount_all(&device_path)?;

    #[cfg(target_os = "linux")]
    {
        run_full_erase_linux(&device_path, fs, label)
    }
    #[cfg(target_os = "macos")]
    {
        run_diskutil_erase(&device_path, fs, label)
    }
}

/// True if `device_str` names a whole disk (not a slice/partition) on either OS.
///
/// macOS: `/dev/disk6` is whole, `/dev/disk6s1` is a slice.
/// Linux: `/dev/sdb`, `/dev/nvme0n1`, `/dev/vda` are whole; `/dev/sdb1`, `/dev/nvme0n1p1`,
/// `/dev/vda1` are partitions.
fn is_whole_disk(device_str: &str) -> bool {
    let stem = device_str.strip_prefix("/dev/").unwrap_or(device_str);

    // macOS: disk6 / rdisk6 = whole disk; disk6s1 / rdisk6s1 = slice.
    if let Some(rest) = stem
        .strip_prefix("rdisk")
        .or_else(|| stem.strip_prefix("disk"))
    {
        return !rest.is_empty() && rest.chars().all(|c| c.is_ascii_digit());
    }

    // Linux: a partition's name ends with a digit. sdb / vda / xvda are whole disks
    // (don't end in a digit); sdb1 ends in a digit. nvme0n1 is whole; nvme0n1p1 is
    // a partition (the 'p' separator before the digit is the giveaway).
    if let Some(last) = stem.chars().last() {
        if !last.is_ascii_digit() {
            return true;
        }
        // Ends with a digit — could be nvmeXnY (whole) or nvmeXnYpZ (partition) or sdXN (partition).
        // The standard rule: an nvme/mmc whole-disk name matches /^(nvme|mmcblk)\d+n\d+$/;
        // a partition on those devices has a 'p' before the trailing digits.
        if stem.starts_with("nvme") || stem.starts_with("mmcblk") {
            // Whole disk if the chars between the trailing digits and the rest don't include 'p'.
            // Simpler: a partition slice always contains "pN" at the end.
            let trimmed = stem.trim_end_matches(|c: char| c.is_ascii_digit());
            return !trimmed.ends_with('p');
        }
        return false;
    }
    false
}

#[cfg(target_os = "linux")]
fn run_full_erase_linux(
    device: &std::path::Path,
    fs: Filesystem,
    label: Option<&str>,
) -> Result<()> {
    // 1. Remove all filesystem signatures the kernel might still recognise.
    let status = Command::new("wipefs")
        .args(["--all", "--force"])
        .arg(device)
        .status()
        .context("spawning wipefs")?;
    if !status.success() {
        bail!("wipefs --all failed");
    }

    // 2. Wipe any partition table (both GPT and MBR).
    let status = Command::new("sgdisk")
        .arg("--zap-all")
        .arg(device)
        .status()
        .context("spawning sgdisk --zap-all")?;
    if !status.success() {
        bail!("sgdisk --zap-all failed");
    }

    // 3. mkfs the whole disk as a superfloppy (no partition table).
    let tool = crate::platform::format_tool(fs);
    let label_flag: &str = match fs {
        Filesystem::Ext4 | Filesystem::Exfat => "-L",
        Filesystem::Vfat => "-n",
    };

    let mut cmd = Command::new(tool);
    cmd.arg("-F"); // ext4/vfat: don't ask "this isn't a partition, continue?"
    if let Some(l) = label {
        cmd.args([label_flag, l]);
    }
    cmd.arg(device);
    let status = cmd.status().with_context(|| format!("spawning {tool}"))?;
    if !status.success() {
        bail!("{tool} failed");
    }
    Ok(())
}

#[cfg(target_os = "macos")]
fn run_diskutil_erase(
    device: &std::path::Path,
    fs: Filesystem,
    label: Option<&str>,
) -> Result<()> {
    let fs_str = match fs {
        Filesystem::Ext4 => bail!("ext4 is not natively supported by diskutil on macOS"),
        Filesystem::Vfat => "MS-DOS FAT32",
        Filesystem::Exfat => "ExFAT",
    };
    let name = label.unwrap_or("UNTITLED");

    // `eraseDisk` wipes the partition table, creates a fresh GPT with one volume,
    // and formats it. That IS the full erase.
    let status = Command::new("diskutil")
        .args(["eraseDisk", fs_str, name, &device.display().to_string()])
        .status()
        .context("spawning diskutil eraseDisk")?;
    if !status.success() {
        bail!("diskutil eraseDisk failed");
    }
    Ok(())
}

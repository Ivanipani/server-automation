use std::process::Command;

use anyhow::{Context, Result, bail};

use crate::cli::TableStyle;
use crate::util::{canonical_device_path, confirm, ensure_block_device, require_root};

pub fn run(device: &str, table: TableStyle, layout: &str, yes: bool) -> Result<()> {
    require_root()?;
    let device_path = canonical_device_path(device);
    ensure_block_device(&device_path)?;

    println!(
        "WARNING: This will overwrite the partition table on {}",
        device_path.display()
    );
    crate::platform::info(&device_path)?;
    println!();

    if !yes && !confirm("Continue?")? {
        println!("Aborted.");
        return Ok(());
    }

    crate::platform::unmount_all(&device_path)?;

    #[cfg(target_os = "linux")]
    {
        run_sgdisk(&device_path, table, layout)
    }
    #[cfg(target_os = "macos")]
    {
        run_diskutil_partition(&device_path, table, layout)
    }
}

#[cfg(target_os = "linux")]
fn run_sgdisk(device: &std::path::Path, table: TableStyle, layout: &str) -> Result<()> {
    // Zap any existing tables first; --clear writes a fresh GPT.
    let zap = match table {
        TableStyle::Gpt => &["--zap-all", "--clear", "--mbrtogpt"][..],
        TableStyle::Mbr => &["--zap-all"][..],
    };
    let status = Command::new("sgdisk")
        .args(zap)
        .arg(device)
        .status()
        .context("spawning sgdisk")?;
    if !status.success() {
        bail!("sgdisk zap failed");
    }

    // --layout is one or more comma-separated `N:start:end:typecode` entries,
    // which we translate to repeated `--new` + `--typecode` flags.
    for spec in layout.split(',') {
        let parts: Vec<&str> = spec.split(':').collect();
        if parts.len() != 4 {
            bail!(
                "partition spec must be N:start:end:typecode, got {:?}",
                spec
            );
        }
        let (n, start, end, typecode) = (parts[0], parts[1], parts[2], parts[3]);
        let status = Command::new("sgdisk")
            .args([
                &format!("--new={n}:{start}:{end}"),
                &format!("--typecode={n}:{typecode}"),
            ])
            .arg(device)
            .status()
            .context("spawning sgdisk --new")?;
        if !status.success() {
            bail!("sgdisk --new {spec} failed");
        }
    }

    println!("Partition table written to {}.", device.display());
    Ok(())
}

#[cfg(target_os = "macos")]
fn run_diskutil_partition(
    device: &std::path::Path,
    table: TableStyle,
    layout: &str,
) -> Result<()> {
    let scheme = match table {
        TableStyle::Gpt => "GPT",
        TableStyle::Mbr => "MBR",
    };
    // diskutil layout: `Format Name Size [Format Name Size ...]` separated by spaces.
    let mut args: Vec<String> = vec!["partitionDisk".into(), device.display().to_string(), scheme.into()];
    for tok in layout.split_whitespace() {
        args.push(tok.into());
    }
    let status = Command::new("diskutil")
        .args(&args)
        .status()
        .context("spawning diskutil partitionDisk")?;
    if !status.success() {
        bail!("diskutil partitionDisk failed");
    }
    Ok(())
}

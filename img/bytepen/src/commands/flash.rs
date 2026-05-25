use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
#[cfg(target_os = "linux")]
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::io::AsRawFd;
use std::path::Path;
use std::time::Duration;

use anyhow::{Context, Result};
use humansize::{BINARY, format_size};
use indicatif::{ProgressBar, ProgressStyle};

use crate::util::{
    canonical_device_path, confirm, ensure_block_device, ensure_regular_file, require_root,
};

const BUF_SIZE: usize = 4 * 1024 * 1024; // 4 MiB, matches burn-to-disc.sh `bs=4M`

pub fn run(image: &Path, device: &str, yes: bool) -> Result<()> {
    require_root()?;

    let device_path = canonical_device_path(device);
    ensure_regular_file(image)?;
    ensure_block_device(&device_path)?;

    let image_len = image.metadata()?.len();

    println!("WARNING: This will erase ALL data on {}", device_path.display());
    println!();
    println!(
        "Image:  {} ({})",
        image.display(),
        format_size(image_len, BINARY)
    );
    println!("Target: {}", device_path.display());
    println!();
    crate::platform::info(&device_path)?;
    println!();

    if !yes && !confirm("Continue?")? {
        println!("Aborted.");
        return Ok(());
    }

    crate::platform::unmount_all(&device_path)?;

    let raw_path = crate::platform::raw_device_path(&device_path);
    println!(
        "Writing {} to {} (this may take several minutes)...",
        image.display(),
        raw_path.display()
    );

    write_with_progress(image, &raw_path, image_len)?;

    println!("Done. {} is ready.", device_path.display());
    Ok(())
}

fn write_with_progress(image: &Path, device: &Path, image_len: u64) -> Result<()> {
    let mut src = File::open(image).with_context(|| format!("opening {}", image.display()))?;

    // O_SYNC on Linux matches the original `dd ... oflag=sync`. macOS doesn't need it
    // when writing to /dev/rdiskN (the raw device is unbuffered by definition).
    let mut opts = OpenOptions::new();
    opts.write(true);
    #[cfg(target_os = "linux")]
    opts.custom_flags(nix::libc::O_SYNC);
    let mut dst = opts
        .open(device)
        .with_context(|| format!("opening {}", device.display()))?;

    let pb = ProgressBar::new(image_len);
    pb.set_style(
        ProgressStyle::with_template(
            "{spinner:.green} [{elapsed_precise}] [{wide_bar:.cyan/blue}] \
             {bytes}/{total_bytes} ({bytes_per_sec}, {eta})",
        )
        .expect("static template parses")
        .progress_chars("=> "),
    );
    pb.enable_steady_tick(Duration::from_millis(100));

    let mut buf = vec![0u8; BUF_SIZE];
    let mut total: u64 = 0;
    loop {
        let n = src.read(&mut buf).context("reading image")?;
        if n == 0 {
            break;
        }
        dst.write_all(&buf[..n])
            .with_context(|| format!("writing to {}", device.display()))?;
        total += n as u64;
        pb.set_position(total);
    }

    pb.set_message("syncing...");
    dst.flush().context("flushing device")?;
    // fsync the device fd — the buffer cache on Linux still needs a flush even with O_SYNC
    // for the final partial buffer's metadata; macOS rdisk is a no-op but harmless.
    nix::unistd::fsync(dst.as_raw_fd()).context("fsync(device)")?;

    pb.finish_with_message(format!("wrote {}", format_size(total, BINARY)));
    Ok(())
}

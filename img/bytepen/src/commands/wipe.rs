use std::fs::OpenOptions;
use std::io::{Seek, SeekFrom, Write};
use std::os::unix::io::AsRawFd;
use std::time::Duration;

use anyhow::{Context, Result};
use humansize::{BINARY, format_size};
use indicatif::{ProgressBar, ProgressStyle};

use crate::util::{canonical_device_path, confirm, ensure_block_device, require_root};

const HEAD_TAIL_BYTES: u64 = 10 * 1024 * 1024; // 10 MiB
const BUF_SIZE: usize = 4 * 1024 * 1024;

pub fn run(device: &str, full: bool, yes: bool) -> Result<()> {
    require_root()?;

    let device_path = canonical_device_path(device);
    ensure_block_device(&device_path)?;

    let raw_path = crate::platform::raw_device_path(&device_path);

    println!(
        "WARNING: This will {} on {}",
        if full {
            "ZERO THE ENTIRE DEVICE"
        } else {
            "destroy partition tables / filesystem superblocks"
        },
        device_path.display()
    );
    println!();
    crate::platform::info(&device_path)?;
    println!();

    if !yes && !confirm("Continue?")? {
        println!("Aborted.");
        return Ok(());
    }

    crate::platform::unmount_all(&device_path)?;

    let mut dst = OpenOptions::new()
        .write(true)
        .open(&raw_path)
        .with_context(|| format!("opening {}", raw_path.display()))?;

    let dev_len = dst
        .seek(SeekFrom::End(0))
        .with_context(|| format!("seeking to end of {}", raw_path.display()))?;
    dst.seek(SeekFrom::Start(0))?;

    if full {
        zero_range(&mut dst, 0, dev_len, "wiping")?;
    } else {
        let head_n = HEAD_TAIL_BYTES.min(dev_len);
        zero_range(&mut dst, 0, head_n, "wiping head")?;

        if dev_len > HEAD_TAIL_BYTES {
            let tail_start = dev_len.saturating_sub(HEAD_TAIL_BYTES);
            dst.seek(SeekFrom::Start(tail_start))
                .context("seeking to tail")?;
            zero_range(&mut dst, tail_start, HEAD_TAIL_BYTES, "wiping tail")?;
        }
    }

    dst.flush().context("flushing device")?;
    nix::unistd::fsync(dst.as_raw_fd()).context("fsync(device)")?;

    println!("Done. {} wiped.", device_path.display());
    Ok(())
}

fn zero_range(
    dst: &mut std::fs::File,
    _offset: u64,
    length: u64,
    label: &str,
) -> Result<()> {
    let zeros = vec![0u8; BUF_SIZE];
    let pb = ProgressBar::new(length);
    pb.set_style(
        ProgressStyle::with_template(
            "{msg} [{elapsed_precise}] [{wide_bar:.red/blue}] \
             {bytes}/{total_bytes} ({bytes_per_sec}, {eta})",
        )
        .expect("static template parses")
        .progress_chars("=> "),
    );
    pb.set_message(label.to_string());
    pb.enable_steady_tick(Duration::from_millis(100));

    let mut written: u64 = 0;
    while written < length {
        let remaining = length - written;
        let n = (BUF_SIZE as u64).min(remaining) as usize;
        dst.write_all(&zeros[..n])
            .with_context(|| format!("writing zeros to device"))?;
        written += n as u64;
        pb.set_position(written);
    }
    pb.finish_with_message(format!("{label}: {}", format_size(length, BINARY)));
    Ok(())
}

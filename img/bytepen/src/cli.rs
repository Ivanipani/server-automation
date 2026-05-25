use std::path::PathBuf;

use clap::{Parser, Subcommand, ValueEnum};

#[derive(Parser, Debug)]
#[command(
    name = "bytepen",
    version,
    about = "Disk-prep CLI: flash images, partition, format, wipe.",
    long_about = "bytepen is a Rust replacement for img/burn-to-disc.sh that also covers \
                  partition/format/wipe. Linux + macOS only. Destructive subcommands \
                  require root."
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Subcommand, Debug)]
pub enum Command {
    /// List candidate disks on this host.
    List,

    /// Show info for a specific device.
    Info {
        /// Device path or short name (e.g. /dev/disk4, disk4, /dev/sdb, sdb).
        device: String,
    },

    /// Write an image to a block device (dd-equivalent).
    Flash {
        /// Path to the .iso / .img file.
        image: PathBuf,
        /// Target device (e.g. /dev/disk4 or sdb).
        device: String,
        /// Skip the confirmation prompt.
        #[arg(long)]
        r#yes: bool,
    },

    /// Destroy partition tables / filesystem superblocks on a device.
    Wipe {
        /// Target device.
        device: String,
        /// Zero the entire device instead of just the head + tail.
        #[arg(long)]
        full: bool,
        /// Skip the confirmation prompt.
        #[arg(long)]
        r#yes: bool,
    },

    /// Create a partition table on a device.
    ///
    /// Linux: shells out to sgdisk. macOS: shells out to diskutil partitionDisk.
    Partition {
        /// Target device.
        device: String,
        /// Partition table style.
        #[arg(long, value_enum, default_value_t = TableStyle::Gpt)]
        table: TableStyle,
        /// Partition layout. Forwarded verbatim to the underlying tool — see
        /// `sgdisk(8)` on Linux ("N:start:end:typecode" repeated) or
        /// `diskutil partitionDisk` on macOS ("part1Format part1Name part1Size ...").
        #[arg(long)]
        layout: String,
        /// Skip the confirmation prompt.
        #[arg(long)]
        r#yes: bool,
    },

    /// Full-erase format: wipe partitions + filesystems, then create a fresh FS on the whole disk.
    ///
    /// Linux: wipefs --all + sgdisk --zap-all + mkfs.<fs> directly on the disk (superfloppy).
    /// macOS: diskutil eraseDisk (fresh GPT + one volume, formatted). Only whole disks
    /// are accepted — pass /dev/disk6 or /dev/sdb, not a slice like /dev/disk6s1.
    Format {
        /// Target whole disk (e.g. /dev/disk6, /dev/sdb, /dev/nvme0n1).
        device: String,
        /// Filesystem to create.
        #[arg(long, value_enum)]
        fs: Filesystem,
        /// Volume label.
        #[arg(long)]
        label: Option<String>,
        /// Skip the confirmation prompt.
        #[arg(long)]
        r#yes: bool,
    },
}

#[derive(ValueEnum, Clone, Copy, Debug)]
pub enum TableStyle {
    Gpt,
    Mbr,
}

#[derive(ValueEnum, Clone, Copy, Debug)]
pub enum Filesystem {
    Ext4,
    /// FAT32 (a.k.a. MS-DOS FAT, vfat).
    #[value(name = "vfat", alias = "fat32", alias = "msdos")]
    Vfat,
    Exfat,
}

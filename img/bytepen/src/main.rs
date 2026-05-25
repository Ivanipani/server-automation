mod cli;
mod commands;
mod platform;
mod util;

use anyhow::Result;
use clap::Parser;

use crate::cli::{Cli, Command};

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.command {
        Command::List => commands::list::run(),
        Command::Info { device } => commands::info::run(&device),
        Command::Flash {
            image,
            device,
            r#yes,
        } => commands::flash::run(&image, &device, r#yes),
        Command::Wipe {
            device,
            full,
            r#yes,
        } => commands::wipe::run(&device, full, r#yes),
        Command::Partition {
            device,
            table,
            layout,
            r#yes,
        } => commands::partition::run(&device, table, &layout, r#yes),
        Command::Format {
            device,
            fs,
            label,
            r#yes,
        } => commands::format::run(&device, fs, label.as_deref(), r#yes),
    }
}

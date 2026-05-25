use anyhow::Result;

use crate::util::canonical_device_path;

pub fn run(device: &str) -> Result<()> {
    let path = canonical_device_path(device);
    crate::platform::info(&path)
}

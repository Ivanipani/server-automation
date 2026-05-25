use anyhow::Result;

pub fn run() -> Result<()> {
    crate::platform::list_disks()
}

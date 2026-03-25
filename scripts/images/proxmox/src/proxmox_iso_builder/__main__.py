"""Entry point for proxmox-iso-builder."""

from pathlib import Path

from proxmox_iso_builder.app import ProxmoxISOBuilderApp


def main() -> None:
    # Default to the directory containing this package's project root
    iso_dir = Path(__file__).resolve().parent.parent.parent
    app = ProxmoxISOBuilderApp(iso_dir=iso_dir)
    app.run()


if __name__ == "__main__":
    main()

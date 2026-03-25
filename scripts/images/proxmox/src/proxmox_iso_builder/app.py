"""Main Textual application for Proxmox ISO Builder."""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from textual.app import App, ComposeResult
from textual.widgets import Footer, Header, Label, Static

from rich.text import Text

from proxmox_iso_builder.platform import check_prerequisites, detect_platform


@dataclass
class WizardState:
    iso_dir: Path
    images_dir: Path = field(init=False)
    iso_path: Path | None = None
    answer_path: Path | None = None
    bundled_iso_path: Path | None = None
    target_device: str | None = None
    platform: str = field(default_factory=detect_platform)

    def __post_init__(self) -> None:
        self.images_dir = self.iso_dir / "images"
        self.images_dir.mkdir(parents=True, exist_ok=True)


class ProxmoxISOBuilderApp(App):
    TITLE = "Proxmox ISO Builder"
    BINDINGS = [("q", "quit", "Quit")]

    CSS = """
    Screen { padding: 1; }
    #step-header {
        background: $primary;
        color: $text;
        padding: 0 1;
        text-style: bold;
        width: 100%;
    }
    #status-bar {
        height: auto;
        padding: 0 1;
        margin-bottom: 1;
        background: $surface;
        color: $text-muted;
    }
    #status-bar .status-set {
        color: $success;
        text-style: bold;
    }
    #status-bar .status-unset {
        color: $text-disabled;
    }
    """

    def __init__(self, iso_dir: Path | None = None) -> None:
        super().__init__()
        if iso_dir is None:
            iso_dir = Path.cwd()
        self.state = WizardState(iso_dir=iso_dir.resolve())

    def status_text(self) -> Text:
        """Build a Rich Text showing current selections."""
        s = self.state
        parts: list[tuple[str, str]] = []

        if s.iso_path:
            parts.append((f" ISO: {s.iso_path.name} ", "bold green"))
        else:
            parts.append((" ISO: -- ", "dim"))

        if s.answer_path:
            parts.append((f" Answer: {s.answer_path.name} ", "bold green"))
        else:
            parts.append((" Answer: -- ", "dim"))

        if s.bundled_iso_path:
            parts.append((f" Bundle: {s.bundled_iso_path.name} ", "bold green"))
        else:
            parts.append((" Bundle: -- ", "dim"))

        if s.target_device:
            parts.append((f" Disk: /dev/{s.target_device} ", "bold green"))
        else:
            parts.append((" Disk: -- ", "dim"))

        text = Text()
        for i, (label, style) in enumerate(parts):
            if i > 0:
                text.append("  ", "dim")
            text.append(label, style)
        return text

    def on_mount(self) -> None:
        missing = check_prerequisites(self.state.platform)
        if missing:
            self.notify(
                "Missing prerequisites:\n" + "\n".join(f"  - {m}" for m in missing),
                severity="error",
                timeout=10,
            )

        from proxmox_iso_builder.screens.iso_select import ISOSelectScreen
        self.push_screen(ISOSelectScreen())

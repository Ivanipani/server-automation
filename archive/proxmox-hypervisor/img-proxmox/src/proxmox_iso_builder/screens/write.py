"""Step 6: Write ISO to USB media."""

from __future__ import annotations

import subprocess
from typing import TYPE_CHECKING

from textual.app import ComposeResult
from textual.containers import Horizontal
from textual.screen import Screen
from textual.widgets import Button, Footer, Header, Input, Label, RichLog, Static

from proxmox_iso_builder.platform import build_unmount_cmd, build_write_cmd

if TYPE_CHECKING:
    from proxmox_iso_builder.app import ProxmoxISOBuilderApp


class WriteScreen(Screen):
    BINDINGS = [("q", "quit", "Quit")]

    CSS = """
    #warning { background: $error; color: $text; padding: 1; text-style: bold; }
    #info { padding: 1; }
    #confirm-section { height: auto; padding: 1; }
    #confirm-input { width: 30; }
    #log { height: 1fr; }
    #buttons { height: auto; padding: 1; dock: bottom; }
    #buttons Button { margin-right: 1; }
    """

    def compose(self) -> ComposeResult:
        yield Header()
        yield Static(" Step 6/6: Write ISO to Disk ", id="step-header")
        yield Static("", id="status-bar")
        yield Static("", id="warning")
        yield Static("", id="info")
        yield RichLog(id="log", highlight=True, markup=True)
        with Horizontal(id="confirm-section"):
            yield Label("Type device name to confirm: ")
            yield Input(id="confirm-input", placeholder="")
        with Horizontal(id="buttons"):
            yield Button("Write", id="write-btn", variant="error", disabled=True)
            yield Button("Back", id="back-btn")
            yield Button("Done", id="done-btn", variant="primary", disabled=True)
        yield Footer()

    @property
    def app(self) -> ProxmoxISOBuilderApp:
        return super().app  # type: ignore[return-value]

    def on_mount(self) -> None:
        state = self.app.state
        device = state.target_device or "???"
        iso_name = state.bundled_iso_path.name if state.bundled_iso_path else "???"

        self.query_one("#status-bar", Static).update(self.app.status_text())
        self.query_one("#warning", Static).update(
            f" WARNING: This will ERASE ALL DATA on /dev/{device} "
        )
        self.query_one("#info", Static).update(
            f"ISO: {iso_name}\nTarget: /dev/{device}"
        )

    def on_input_changed(self, event: Input.Changed) -> None:
        if event.input.id == "confirm-input":
            matches = event.value.strip() == self.app.state.target_device
            self.query_one("#write-btn", Button).disabled = not matches

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "write-btn":
            self._do_write()
        elif event.button.id == "back-btn":
            self.app.pop_screen()
        elif event.button.id == "done-btn":
            self.app.exit()

    def _do_write(self) -> None:
        state = self.app.state
        assert state.bundled_iso_path is not None
        assert state.target_device is not None

        log = self.query_one("#log", RichLog)
        log.write("[bold]Writing ISO to disk...[/bold]")
        log.write("The TUI will suspend for the write operation (sudo may prompt for password).\n")

        unmount_cmd = build_unmount_cmd(state.target_device, state.platform)
        write_cmd = build_write_cmd(state.bundled_iso_path, state.target_device, state.platform)

        with self.app.suspend():
            print(f"Unmounting /dev/{state.target_device}...")
            subprocess.run(unmount_cmd, check=False)
            print(f"\nWriting {state.bundled_iso_path.name} to /dev/{state.target_device}...")
            print("This may take several minutes.\n")
            result = subprocess.run(write_cmd)

        if result.returncode == 0:
            log.write("\n[bold green]Write complete! Device is ready.[/bold green]")
            self.query_one("#write-btn", Button).disabled = True
            self.query_one("#done-btn", Button).disabled = False
        else:
            log.write(f"\n[bold red]Write failed (exit code {result.returncode}).[/bold red]")

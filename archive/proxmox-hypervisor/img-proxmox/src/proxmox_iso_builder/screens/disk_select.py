"""Step 5: Disk selection."""

from __future__ import annotations

from typing import TYPE_CHECKING

from textual import work
from textual.app import ComposeResult
from textual.containers import Horizontal
from textual.screen import Screen
from textual.widgets import Button, Footer, Header, Input, Label, RichLog, Static

from proxmox_iso_builder.operations import run_command
from proxmox_iso_builder.platform import build_device_info_cmd, build_list_disks_cmd

if TYPE_CHECKING:
    from proxmox_iso_builder.app import ProxmoxISOBuilderApp


class DiskSelectScreen(Screen):
    BINDINGS = [("q", "quit", "Quit")]

    CSS = """
    #log { height: 1fr; }
    #device-input-section { height: auto; padding: 1; }
    #device-input { width: 30; }
    #device-info { height: auto; max-height: 8; padding: 1; }
    #buttons { height: auto; padding: 1; dock: bottom; }
    #buttons Button { margin-right: 1; }
    """

    def compose(self) -> ComposeResult:
        yield Header()
        yield Static(" Step 5/6: Select Target Disk ", id="step-header")
        yield Static("", id="status-bar")
        yield RichLog(id="log", highlight=True, markup=True)
        with Horizontal(id="device-input-section"):
            yield Label("Device name (e.g. disk4, sdb): ")
            yield Input(id="device-input", placeholder="disk4")
        yield RichLog(id="device-info", highlight=True, markup=True)
        with Horizontal(id="buttons"):
            yield Button("Refresh", id="refresh-btn")
            yield Button("Show Info", id="info-btn", disabled=True)
            yield Button("Back", id="back-btn")
            yield Button("Next", id="next-btn", variant="primary", disabled=True)
        yield Footer()

    @property
    def app(self) -> ProxmoxISOBuilderApp:
        return super().app  # type: ignore[return-value]

    def on_mount(self) -> None:
        self.query_one("#status-bar", Static).update(self.app.status_text())
        self._list_disks()

    def _update_status(self) -> None:
        self.query_one("#status-bar", Static).update(self.app.status_text())

    def on_input_changed(self, event: Input.Changed) -> None:
        if event.input.id == "device-input":
            has_value = bool(event.value.strip())
            self.query_one("#info-btn", Button).disabled = not has_value
            self.query_one("#next-btn", Button).disabled = not has_value
            if has_value:
                self.app.state.target_device = event.value.strip()
            else:
                self.app.state.target_device = None
            self._update_status()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "refresh-btn":
            self.query_one("#log", RichLog).clear()
            self._list_disks()
        elif event.button.id == "info-btn":
            self._show_device_info()
        elif event.button.id == "back-btn":
            self.app.pop_screen()
        elif event.button.id == "next-btn":
            device = self.query_one("#device-input", Input).value.strip()
            if device:
                self.app.state.target_device = device
                from proxmox_iso_builder.screens.write import WriteScreen
                self.app.push_screen(WriteScreen())

    @work(thread=False)
    async def _list_disks(self) -> None:
        log = self.query_one("#log", RichLog)
        cmd = build_list_disks_cmd(self.app.state.platform)

        def write_log(line: str) -> None:
            log.write(line)

        write_log("[bold]Available disks:[/bold]")
        await run_command(cmd, write_log)

    @work(thread=False)
    async def _show_device_info(self) -> None:
        device = self.query_one("#device-input", Input).value.strip()
        if not device:
            return
        info_log = self.query_one("#device-info", RichLog)
        info_log.clear()
        cmd = build_device_info_cmd(device, self.app.state.platform)

        def write_log(line: str) -> None:
            info_log.write(line)

        await run_command(cmd, write_log)

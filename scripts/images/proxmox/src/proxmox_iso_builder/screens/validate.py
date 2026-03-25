"""Step 3: Validate answer file."""

from __future__ import annotations

from typing import TYPE_CHECKING

from textual import work
from textual.app import ComposeResult
from textual.containers import Horizontal
from textual.screen import Screen
from textual.widgets import Button, Footer, Header, RichLog, Static

from proxmox_iso_builder.operations import run_command
from proxmox_iso_builder.platform import build_validate_cmd

if TYPE_CHECKING:
    from proxmox_iso_builder.app import ProxmoxISOBuilderApp


class ValidateScreen(Screen):
    BINDINGS = [("q", "quit", "Quit")]

    CSS = """
    #log { height: 1fr; }
    #buttons { height: auto; padding: 1; dock: bottom; }
    #buttons Button { margin-right: 1; }
    """

    def compose(self) -> ComposeResult:
        yield Header()
        yield Static(" Step 3/6: Validate Answer File ", id="step-header")
        yield Static("", id="status-bar")
        yield RichLog(id="log", highlight=True, markup=True)
        with Horizontal(id="buttons"):
            yield Button("Re-validate", id="retry-btn")
            yield Button("Back", id="back-btn")
            yield Button("Next", id="next-btn", variant="primary", disabled=True)
        yield Footer()

    @property
    def app(self) -> ProxmoxISOBuilderApp:
        return super().app  # type: ignore[return-value]

    def on_mount(self) -> None:
        self.query_one("#status-bar", Static).update(self.app.status_text())
        self._run_validation()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "retry-btn":
            self.query_one("#log", RichLog).clear()
            self._run_validation()
        elif event.button.id == "back-btn":
            self.app.pop_screen()
        elif event.button.id == "next-btn":
            from proxmox_iso_builder.screens.bundle import BundleScreen
            self.app.push_screen(BundleScreen())

    @work(thread=False)
    async def _run_validation(self) -> None:
        log = self.query_one("#log", RichLog)
        state = self.app.state
        assert state.answer_path is not None

        cmd = build_validate_cmd(state.answer_path, state.platform)

        def write_log(line: str) -> None:
            log.write(line)

        write_log("[bold]Validating answer file...[/bold]")
        rc = await run_command(cmd, write_log, cwd=state.iso_dir)

        if rc == 0:
            write_log("\n[bold green]Validation passed.[/bold green]")
            self.query_one("#next-btn", Button).disabled = False
        else:
            write_log(f"\n[bold red]Validation failed (exit code {rc}).[/bold red]")

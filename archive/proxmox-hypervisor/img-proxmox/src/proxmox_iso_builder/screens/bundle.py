"""Step 4: Bundle answer file into ISO."""

from __future__ import annotations

import shutil
from typing import TYPE_CHECKING

from textual import work
from textual.app import ComposeResult
from textual.containers import Horizontal
from textual.screen import Screen
from textual.widgets import Button, Footer, Header, RichLog, Static

from proxmox_iso_builder.operations import run_command
from proxmox_iso_builder.platform import build_bundle_cmd, build_docker_image_cmd

if TYPE_CHECKING:
    from proxmox_iso_builder.app import ProxmoxISOBuilderApp


class BundleScreen(Screen):
    BINDINGS = [("q", "quit", "Quit")]

    CSS = """
    #log { height: 1fr; }
    #buttons { height: auto; padding: 1; dock: bottom; }
    #buttons Button { margin-right: 1; }
    """

    def compose(self) -> ComposeResult:
        yield Header()
        yield Static(" Step 4/6: Bundle ISO ", id="step-header")
        yield Static("", id="status-bar")
        yield RichLog(id="log", highlight=True, markup=True)
        with Horizontal(id="buttons"):
            yield Button("Back", id="back-btn")
            yield Button("Next", id="next-btn", variant="primary", disabled=True)
        yield Footer()

    @property
    def app(self) -> ProxmoxISOBuilderApp:
        return super().app  # type: ignore[return-value]

    def on_mount(self) -> None:
        self.query_one("#status-bar", Static).update(self.app.status_text())
        self._run_bundle()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "back-btn":
            self.app.pop_screen()
        elif event.button.id == "next-btn":
            from proxmox_iso_builder.screens.disk_select import DiskSelectScreen
            self.app.push_screen(DiskSelectScreen())

    @work(thread=False)
    async def _run_bundle(self) -> None:
        log = self.query_one("#log", RichLog)
        state = self.app.state

        assert state.iso_path is not None
        assert state.answer_path is not None

        def write_log(line: str) -> None:
            log.write(line)

        # Derive output path in images/, including the host name so each host
        # produces a distinct ISO and subsequent builds don't overwrite.
        iso_stem = state.iso_path.stem
        host_stem = state.answer_path.stem
        output_path = state.images_dir / f"{iso_stem}-{host_stem}-autoinstall.iso"

        # On macOS, copy source ISO to output path first (Docker mounts it in-place)
        if state.platform == "darwin":
            write_log("[bold]Building Docker image...[/bold]")
            dockerfile_dir = state.iso_dir / "macos"
            rc = await run_command(
                build_docker_image_cmd(dockerfile_dir), write_log, cwd=state.iso_dir,
            )
            if rc != 0:
                write_log("[bold red]Docker build failed.[/bold red]")
                return

            # The Docker prepare-iso command modifies the ISO in-place via mount
            # Copy the source ISO to the output location first
            write_log(f"Copying {state.iso_path.name} -> {output_path.name}...")
            shutil.copy2(state.iso_path, output_path)

        write_log("[bold]Bundling answer file into ISO...[/bold]")
        cmd = build_bundle_cmd(state.iso_path, state.answer_path, output_path, state.platform)
        rc = await run_command(cmd, write_log, cwd=state.iso_dir)

        if rc == 0:
            state.bundled_iso_path = output_path
            write_log(f"\n[bold green]Bundle complete: {output_path.name}[/bold green]")
            self.query_one("#next-btn", Button).disabled = False
            self.query_one("#status-bar", Static).update(self.app.status_text())
        else:
            write_log(f"\n[bold red]Bundle failed (exit code {rc}).[/bold red]")

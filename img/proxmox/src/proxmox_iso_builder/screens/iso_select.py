"""Step 1: ISO selection and download."""

from __future__ import annotations

import datetime
from pathlib import Path
from typing import TYPE_CHECKING

from textual import work
from textual.app import ComposeResult
from textual.containers import Horizontal, Vertical
from textual.screen import Screen
from textual.widgets import Button, DataTable, Footer, Header, Input, Label, ProgressBar, Static

from proxmox_iso_builder.operations import download_iso

if TYPE_CHECKING:
    from proxmox_iso_builder.app import ProxmoxISOBuilderApp

DEFAULT_ISO_URL = "https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso"


class ISOSelectScreen(Screen):
    BINDINGS = [("q", "quit", "Quit")]

    CSS = """
    #iso-table { height: 1fr; }
    #download-section { height: auto; padding: 1; }
    #url-input { width: 1fr; }
    #progress-label { margin-top: 1; }
    #buttons { height: auto; padding: 1; dock: bottom; }
    #buttons Button { margin-right: 1; }
    """

    def compose(self) -> ComposeResult:
        yield Header()
        yield Static(" Step 1/6: Select ISO ", id="step-header")
        yield Static("", id="status-bar")
        yield DataTable(id="iso-table")
        with Vertical(id="download-section"):
            yield Label("Download URL:")
            yield Input(value=DEFAULT_ISO_URL, id="url-input")
            yield ProgressBar(total=100, show_eta=True, id="download-progress")
            yield Label("", id="progress-label")
        with Horizontal(id="buttons"):
            yield Button("Download", id="download-btn", variant="default")
            yield Button("Next", id="next-btn", variant="primary", disabled=True)
        yield Footer()

    @property
    def app(self) -> ProxmoxISOBuilderApp:
        return super().app  # type: ignore[return-value]

    def on_mount(self) -> None:
        table = self.query_one("#iso-table", DataTable)
        table.add_columns("Name", "Size (MB)", "Modified")
        table.cursor_type = "row"
        self._refresh_table()
        self._update_status()

    def _update_status(self) -> None:
        self.query_one("#status-bar", Static).update(self.app.status_text())

    def _refresh_table(self) -> None:
        table = self.query_one("#iso-table", DataTable)
        table.clear()
        images_dir: Path = self.app.state.images_dir
        isos = sorted(images_dir.glob("*.iso"))
        for iso in isos:
            stat = iso.stat()
            size_mb = f"{stat.st_size / (1024 * 1024):.0f}"
            modified = datetime.datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M")
            table.add_row(iso.name, size_mb, modified, key=str(iso))
        if isos:
            self.query_one("#next-btn", Button).disabled = False

    def on_data_table_row_selected(self, event: DataTable.RowSelected) -> None:
        if event.row_key and event.row_key.value:
            self.app.state.iso_path = Path(event.row_key.value)
            self.query_one("#next-btn", Button).disabled = False
            self._update_status()

    def on_data_table_row_highlighted(self, event: DataTable.RowHighlighted) -> None:
        if event.row_key and event.row_key.value:
            self.app.state.iso_path = Path(event.row_key.value)
            self.query_one("#next-btn", Button).disabled = False
            self._update_status()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "download-btn":
            self._start_download()
        elif event.button.id == "next-btn":
            from proxmox_iso_builder.screens.answer_select import AnswerSelectScreen
            self.app.push_screen(AnswerSelectScreen())

    @work(thread=False)
    async def _start_download(self) -> None:
        url = self.query_one("#url-input", Input).value.strip()
        if not url:
            return
        filename = url.rsplit("/", 1)[-1]
        dest = self.app.state.images_dir / filename
        label = self.query_one("#progress-label", Label)
        progress = self.query_one("#download-progress", ProgressBar)
        btn = self.query_one("#download-btn", Button)
        btn.disabled = True
        label.update("Downloading...")
        progress.update(progress=0)

        def on_progress(downloaded: int, total: int | None) -> None:
            if total:
                pct = int(downloaded * 100 / total)
                progress.update(progress=pct)
                mb = downloaded / (1024 * 1024)
                total_mb = total / (1024 * 1024)
                label.update(f"{mb:.0f} / {total_mb:.0f} MB")
            else:
                mb = downloaded / (1024 * 1024)
                label.update(f"{mb:.0f} MB downloaded")

        try:
            await download_iso(url, dest, on_progress)
            label.update(f"Downloaded: {filename}")
            self.app.state.iso_path = dest
            self._refresh_table()
            self._update_status()
        except Exception as e:
            label.update(f"Error: {e}")
        finally:
            btn.disabled = False

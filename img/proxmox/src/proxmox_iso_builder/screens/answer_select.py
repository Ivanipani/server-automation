"""Step 2: Answer file selection and editing."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import TYPE_CHECKING

from textual.app import ComposeResult
from textual.containers import Horizontal
from textual.screen import Screen
from textual.widgets import Button, Footer, Header, Label, ListView, ListItem, Static, TextArea

if TYPE_CHECKING:
    from proxmox_iso_builder.app import ProxmoxISOBuilderApp


class AnswerSelectScreen(Screen):
    BINDINGS = [("q", "quit", "Quit")]

    CSS = """
    #file-list { height: 1fr; max-height: 10; }
    #preview { height: 1fr; }
    #buttons { height: auto; padding: 1; dock: bottom; }
    #buttons Button { margin-right: 1; }
    """

    def compose(self) -> ComposeResult:
        yield Header()
        yield Static(" Step 2/6: Select Answer File ", id="step-header")
        yield Static("", id="status-bar")
        yield Label("TOML files:")
        yield ListView(id="file-list")
        yield TextArea(id="preview", read_only=True, language="toml")
        with Horizontal(id="buttons"):
            yield Button("Edit in $EDITOR", id="edit-btn", variant="default", disabled=True)
            yield Button("Back", id="back-btn")
            yield Button("Next", id="next-btn", variant="primary", disabled=True)
        yield Footer()

    @property
    def app(self) -> ProxmoxISOBuilderApp:
        return super().app  # type: ignore[return-value]

    def on_mount(self) -> None:
        self._refresh_list()
        self._update_status()

    def _update_status(self) -> None:
        self.query_one("#status-bar", Static).update(self.app.status_text())

    def _refresh_list(self) -> None:
        lv = self.query_one("#file-list", ListView)
        lv.clear()
        iso_dir: Path = self.app.state.iso_dir
        self._toml_files = sorted(iso_dir.glob("*.toml"))
        for f in self._toml_files:
            lv.append(ListItem(Label(f.name), name=str(f)))
        if self._toml_files:
            self.app.state.answer_path = self._toml_files[0]
            self._show_preview(self._toml_files[0])
            self.query_one("#edit-btn", Button).disabled = False
            self.query_one("#next-btn", Button).disabled = False
            self._update_status()

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        path = Path(event.item.name) if event.item.name else None
        if path:
            self.app.state.answer_path = path
            self._show_preview(path)
            self.query_one("#edit-btn", Button).disabled = False
            self.query_one("#next-btn", Button).disabled = False
            self._update_status()

    def on_list_view_highlighted(self, event: ListView.Highlighted) -> None:
        if event.item and event.item.name:
            path = Path(event.item.name)
            self.app.state.answer_path = path
            self._show_preview(path)
            self.query_one("#edit-btn", Button).disabled = False
            self.query_one("#next-btn", Button).disabled = False
            self._update_status()

    def _show_preview(self, path: Path) -> None:
        try:
            content = path.read_text()
            self.query_one("#preview", TextArea).text = content
        except Exception:
            self.query_one("#preview", TextArea).text = "(unable to read file)"

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "edit-btn":
            self._edit_file()
        elif event.button.id == "back-btn":
            self.app.pop_screen()
        elif event.button.id == "next-btn":
            from proxmox_iso_builder.screens.validate import ValidateScreen
            self.app.push_screen(ValidateScreen())

    def _edit_file(self) -> None:
        answer_path = self.app.state.answer_path
        if not answer_path:
            return
        editor = os.environ.get("EDITOR", "vi")
        with self.app.suspend():
            subprocess.run([editor, str(answer_path)])
        self._show_preview(answer_path)

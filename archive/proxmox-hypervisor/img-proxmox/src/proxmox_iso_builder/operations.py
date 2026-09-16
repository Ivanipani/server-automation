"""Async subprocess wrappers for ISO operations."""

from __future__ import annotations

import asyncio
from collections.abc import Callable
from pathlib import Path

import httpx


async def run_command(
    cmd: list[str],
    log_callback: Callable[[str], None],
    cwd: Path | None = None,
) -> int:
    """Run a command and stream output line-by-line to callback. Returns exit code."""
    log_callback(f"$ {' '.join(cmd)}")
    process = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
        cwd=cwd,
    )
    assert process.stdout is not None
    async for line in process.stdout:
        log_callback(line.decode(errors="replace").rstrip())
    await process.wait()
    return process.returncode or 0


async def download_iso(
    url: str,
    dest: Path,
    progress_callback: Callable[[int, int | None], None],
) -> None:
    """Download an ISO with streaming progress."""
    async with httpx.AsyncClient(follow_redirects=True, timeout=None) as client:
        async with client.stream("GET", url) as response:
            response.raise_for_status()
            total = int(response.headers.get("content-length", 0)) or None
            downloaded = 0
            with open(dest, "wb") as f:
                async for chunk in response.aiter_bytes(chunk_size=1024 * 256):
                    f.write(chunk)
                    downloaded += len(chunk)
                    progress_callback(downloaded, total)

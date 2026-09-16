"""Platform detection and command builders for Proxmox ISO operations."""

from __future__ import annotations

import shutil
import sys
from pathlib import Path


def detect_platform() -> str:
    if sys.platform == "darwin":
        return "darwin"
    elif sys.platform.startswith("linux"):
        return "linux"
    raise RuntimeError(f"Unsupported platform: {sys.platform}")


def docker_available() -> bool:
    return shutil.which("docker") is not None


def assistant_available() -> bool:
    return shutil.which("proxmox-auto-install-assistant") is not None


def check_prerequisites(platform: str) -> list[str]:
    """Return list of missing prerequisites."""
    missing = []
    if platform == "darwin":
        if not docker_available():
            missing.append(
                "docker (required on macOS to run proxmox-auto-install-assistant)"
            )
    else:
        if not assistant_available():
            missing.append(
                "proxmox-auto-install-assistant (apt install proxmox-auto-install-assistant)"
            )
        if not shutil.which("xorriso"):
            missing.append("xorriso (apt install xorriso)")
    return missing


def build_docker_image_cmd(dockerfile_dir: Path) -> list[str]:
    return ["docker", "build", "-q", "-t", "proxmox-iso-builder", str(dockerfile_dir)]


def build_validate_cmd(answer_path: Path, platform: str) -> list[str]:
    if platform == "darwin":
        return [
            "docker",
            "run",
            "--rm",
            "-v",
            f"{answer_path}:/work/answer.toml:ro",
            "proxmox-iso-builder",
            "validate-answer",
            "/work/answer.toml",
        ]
    return ["proxmox-auto-install-assistant", "validate-answer", str(answer_path)]


def build_bundle_cmd(
    iso_path: Path,
    answer_path: Path,
    output_path: Path,
    platform: str,
) -> list[str]:
    if platform == "darwin":
        return [
            "docker",
            "run",
            "--rm",
            "-v",
            f"{output_path}:/work/target.iso",
            "-v",
            f"{answer_path}:/work/answer.toml:ro",
            "proxmox-iso-builder",
            "prepare-iso",
            "/work/target.iso",
            "--fetch-from",
            "iso",
            "--answer-file",
            "/work/answer.toml",
        ]
    return [
        "proxmox-auto-install-assistant",
        "prepare-iso",
        str(iso_path),
        "--fetch-from",
        "iso",
        "--answer-file",
        str(answer_path),
        # Canonical baseline (users / sshd hardening / apt-no-auto-upgrades
        # / root-lock) — the SAME script every other medium runs. Render it
        # next to the answer with:
        #   ansible-playbook --vault-password-file ../../ansible/ansible-pass \
        #     ../../ansible/playbooks/poochella/img/render-image-baseline-to-controller.yml
        #   cp /var/tmp/poochella-image-baseline.sh <answer-dir>/image-baseline.sh
        "--on-first-boot",
        str(answer_path.parent / "image-baseline.sh"),
        "--output",
        str(output_path),
    ]


def build_list_disks_cmd(platform: str) -> list[str]:
    if platform == "darwin":
        return ["diskutil", "list"]
    return ["lsblk", "-d", "-o", "NAME,SIZE,MODEL,TRAN"]


def build_device_info_cmd(device: str, platform: str) -> list[str]:
    if platform == "darwin":
        return ["diskutil", "info", f"/dev/{device}"]
    return ["lsblk", f"/dev/{device}", "-o", "NAME,SIZE,MODEL,TRAN,MOUNTPOINT"]


def build_unmount_cmd(device: str, platform: str) -> list[str]:
    if platform == "darwin":
        return ["diskutil", "unmountDisk", f"/dev/{device}"]
    return ["umount", f"/dev/{device}"]


def build_write_cmd(iso_path: Path, device: str, platform: str) -> list[str]:
    if platform == "darwin":
        raw_device = device.replace("disk", "rdisk")
        return [
            "sudo",
            "dd",
            f"if={iso_path}",
            f"of=/dev/{raw_device}",
            "bs=4m",
            "status=progress",
        ]
    return [
        "sudo",
        "dd",
        f"if={iso_path}",
        f"of=/dev/{device}",
        "bs=4M",
        "status=progress",
        "oflag=sync",
    ]

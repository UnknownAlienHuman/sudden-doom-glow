#!/usr/bin/env python3
"""Create a deterministic, allowlisted Sudden Doom Glow install archive."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


PROJECT_ROOT = Path(__file__).resolve().parent.parent
ADDON_DIR = "SuddenDoomGlow"
RUNTIME_FILES = ("Core.lua", "Debug.lua", "Options.lua")
PACKAGE_FILES = (
    "Core.lua",
    "Debug.lua",
    "Options.lua",
    "SuddenDoomGlow.toc",
    "README.md",
    "CHANGELOG.md",
    "LICENSE",
)
TOC_ENTRY = re.compile(r"^[A-Za-z0-9_.-]+\.lua$")


def addon_version() -> str:
    toc = (PROJECT_ROOT / "SuddenDoomGlow.toc").read_text(encoding="utf-8")
    match = re.search(r"^## Version:\s*(\d+\.\d+\.\d+)\s*$", toc, re.MULTILINE)
    if not match:
        raise ValueError("missing or malformed TOC version")
    return match.group(1)


def runtime_entries(toc_text: str) -> list[str]:
    entries = []
    for raw_line in toc_text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if not TOC_ENTRY.fullmatch(line):
            raise ValueError(f"unexpected TOC runtime entry: {line!r}")
        entries.append(line)
    return entries


def validate_package() -> None:
    toc_path = PROJECT_ROOT / "SuddenDoomGlow.toc"
    if not toc_path.is_file():
        raise ValueError("missing SuddenDoomGlow.toc")

    entries = runtime_entries(toc_path.read_text(encoding="utf-8"))
    if tuple(entries) != RUNTIME_FILES:
        raise ValueError(
            "TOC runtime entries must match the package allowlist in order; "
            f"expected {RUNTIME_FILES!r}, found {tuple(entries)!r}"
        )

    for name in PACKAGE_FILES:
        path = PROJECT_ROOT / name
        if not path.is_file():
            raise ValueError(f"missing allowlisted package file: {name}")


def zip_entry(archive: ZipFile, name: str, data: bytes, is_dir: bool = False) -> None:
    info = ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
    info.compress_type = ZIP_DEFLATED
    info.create_system = 3
    info.external_attr = (0o40755 if is_dir else 0o100644) << 16
    if is_dir:
        info.external_attr |= 0x10
    archive.writestr(info, data, compresslevel=9)


def build_archive(output: Path) -> Path:
    validate_package()
    output = output.resolve()
    if output.suffix.lower() != ".zip":
        raise ValueError("output must be a .zip file")
    output.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(output, mode="w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
        zip_entry(archive, f"{ADDON_DIR}/", b"", is_dir=True)
        for name in PACKAGE_FILES:
            data = (PROJECT_ROOT / name).read_bytes()
            zip_entry(archive, f"{ADDON_DIR}/{name}", data)
    return output


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "output",
        nargs="?",
        help="output ZIP path (default: dist/SuddenDoomGlow-<TOC version>.zip)",
    )
    args = parser.parse_args(argv)
    try:
        output = Path(args.output).expanduser() if args.output else (
            PROJECT_ROOT / "dist" / f"{ADDON_DIR}-{addon_version()}.zip"
        )
        if not output.is_absolute():
            output = Path.cwd() / output
        result = build_archive(output)
    except (OSError, ValueError) as exc:
        print(f"package: ERROR: {exc}", file=sys.stderr)
        return 1
    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

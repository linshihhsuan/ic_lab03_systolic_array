#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TOOLS_ROOT = REPO_ROOT / ".tools" / "verible"
RULES_CONFIG = REPO_ROOT / ".veriblelintrc"


def _prefer_windows_exe(path_str: str) -> str:
    """On Windows, prefer sibling .exe over shell wrappers."""
    p = Path(path_str)
    if sys.platform != "win32":
        return path_str

    if p.suffix.lower() == ".exe":
        return path_str

    exe_candidate = p.with_suffix(".exe")
    if exe_candidate.exists():
        return str(exe_candidate)

    return path_str


def _find_in_tools(exe_name: str) -> str | None:
    if not TOOLS_ROOT.exists():
        return None

    # Prefer newest directory by name (works for versioned folder names).
    version_dirs = sorted(
        (
            p
            for p in TOOLS_ROOT.iterdir()
            if p.is_dir() and p.name.startswith("verible-")
        ),
        reverse=True,
    )

    for d in version_dirs:
        exe = d / f"{exe_name}.exe"
        if exe.exists():
            return str(exe)

        direct = d / exe_name
        if direct.exists():
            return str(direct)

        bin_path = d / "bin" / exe_name
        if bin_path.exists():
            return str(bin_path)

        bin_exe = d / "bin" / f"{exe_name}.exe"
        if bin_exe.exists():
            return str(bin_exe)

    return None


def find_verible_tool(exe_name: str) -> str | None:
    if sys.platform == "win32":
        # On Windows, always run native .exe to avoid WinError 193
        # when PATH points at shell wrapper scripts.
        path_hit = shutil.which(exe_name)
        if path_hit:
            preferred = _prefer_windows_exe(path_hit)
            if Path(preferred).suffix.lower() == ".exe":
                return preferred

        path_hit_exe = shutil.which(f"{exe_name}.exe")
        if path_hit_exe:
            return path_hit_exe

        tool_from_repo = _find_in_tools(exe_name)
        if tool_from_repo and Path(tool_from_repo).suffix.lower() == ".exe":
            return tool_from_repo

        return None

    path_hit = shutil.which(exe_name)
    if path_hit:
        return path_hit

    return _find_in_tools(exe_name)


def run_format(files: list[str]) -> int:
    tool = find_verible_tool("verible-verilog-format")
    if not tool:
        print("Error: verible-verilog-format not found.")
        print(
            "Install with: powershell -NoProfile -\
                ExecutionPolicy Bypass -File .\\install_verible_windows.ps1"
        )
        return 1

    cmd = [tool, "--inplace", *files]
    return subprocess.run(cmd, cwd=str(REPO_ROOT)).returncode


def run_lint(files: list[str]) -> int:
    tool = find_verible_tool("verible-verilog-lint")
    if not tool:
        print("Error: verible-verilog-lint not found.")
        print(
            "Install with: powershell -NoProfile -\
                ExecutionPolicy Bypass -File .\\install_verible_windows.ps1"
        )
        return 1

    cmd = [tool, f"--rules_config={RULES_CONFIG}", *files]
    return subprocess.run(cmd, cwd=str(REPO_ROOT)).returncode


def main() -> int:
    if len(sys.argv) < 2:
        print(
            "Usage: python scripts/run_verible.py\
               [format|lint] <files...>"
        )
        return 2

    mode = sys.argv[1]
    files = sys.argv[2:]

    if not files:
        return 0

    if mode == "format":
        return run_format(files)
    if mode == "lint":
        return run_lint(files)

    print(f"Unknown mode: {mode}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())

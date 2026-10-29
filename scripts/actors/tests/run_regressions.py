"""Run Godot regression scripts with real rendering and isolated user settings.

Usage: python scripts/actors/tests/run_regressions.py --godot PATH [test_name ...]
Reports and renderer logs are written to .godot/verification, never into source.
"""
from __future__ import annotations

import argparse
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import time


def terminate_process_tree(process: subprocess.Popen) -> None:
    """Stop this test's console and GUI children without taskkill/WMI hangs."""
    if os.name != "nt":
        process.kill()
        return
    import ctypes
    from ctypes import wintypes

    class ProcessEntry(ctypes.Structure):
        _fields_ = [("size", wintypes.DWORD), ("usage", wintypes.DWORD),
                    ("pid", wintypes.DWORD), ("heap", ctypes.c_size_t),
                    ("module", wintypes.DWORD), ("threads", wintypes.DWORD),
                    ("parent", wintypes.DWORD), ("priority", wintypes.LONG),
                    ("flags", wintypes.DWORD), ("name", wintypes.WCHAR * 260)]

    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateToolhelp32Snapshot.argtypes = [wintypes.DWORD, wintypes.DWORD]
    kernel.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    for name in ("Process32FirstW", "Process32NextW"):
        function = getattr(kernel, name)
        function.argtypes = [wintypes.HANDLE, ctypes.POINTER(ProcessEntry)]
        function.restype = wintypes.BOOL
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    snapshot = kernel.CreateToolhelp32Snapshot(2, 0)
    entries = []
    if snapshot and snapshot != ctypes.c_void_p(-1).value:
        try:
            entry = ProcessEntry()
            entry.size = ctypes.sizeof(entry)
            more = kernel.Process32FirstW(snapshot, ctypes.byref(entry))
            while more:
                entries.append((entry.pid, entry.parent))
                more = kernel.Process32NextW(snapshot, ctypes.byref(entry))
        finally:
            kernel.CloseHandle(snapshot)
    owned = [process.pid]
    for parent in owned:
        owned.extend(pid for pid, owner in entries if owner == parent and pid not in owned)
    for pid in reversed(owned):
        handle = kernel.OpenProcess(1, False, pid)
        if handle:
            try:
                kernel.TerminateProcess(handle, 1)
            finally:
                kernel.CloseHandle(handle)
    if process.poll() is None:
        process.kill()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--renderer", default="gl_compatibility",
                        choices=("gl_compatibility", "forward_plus", "mobile", "headless"))
    parser.add_argument("--timeout", type=float, default=150)
    parser.add_argument("--report", default="regressions")
    parser.add_argument("tests", nargs="*")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    artifacts = root / ".godot" / "verification"
    artifacts.mkdir(parents=True, exist_ok=True)
    cases = [root / "scripts" / "actors" / "tests" / (name if name.endswith(".gd") else name + ".gd")
             for name in args.tests] or sorted((root / "scripts" / "actors" / "tests").glob("*_test.gd"))
    missing = [case.name for case in cases if not case.is_file()]
    if missing:
        parser.error("Unknown regression script(s): " + ", ".join(missing))
    environment = os.environ.copy()
    # Avoid modifying the editor user's preferences, favorites and recent lists.
    # Concurrent suites must never share favorites, presets or test projects.
    profile = Path(tempfile.gettempdir()) / ("kiwi-" + re.sub(r"[^a-zA-Z0-9_-]", "_", args.report)[:64] + "-profile")
    profile.mkdir(exist_ok=True)
    environment["APPDATA"] = str(profile)
    results = []
    for case in cases:
        command = [args.godot, "--path", str(root), "--script", str(case)]
        if args.renderer == "headless":
            command.append("--headless")
        else:
            command += ["--rendering-method", args.renderer, "--position", "0,0"]
        started = time.monotonic()
        timed_out = False
        options = {}
        if os.name == "nt":
            options["creationflags"] = subprocess.CREATE_NO_WINDOW
            options["startupinfo"] = subprocess.STARTUPINFO()
            options["startupinfo"].dwFlags |= subprocess.STARTF_USESHOWWINDOW
            options["startupinfo"].wShowWindow = subprocess.SW_HIDE
        log_path = artifacts / f"{args.report}_{case.stem}.log"
        with log_path.open("wb") as log:
            process = subprocess.Popen(command, cwd=root, env=environment,
                                       stdout=log, stderr=subprocess.STDOUT, **options)
            compile_failed = False
            try:
                deadline = time.monotonic() + args.timeout
                while True:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise subprocess.TimeoutExpired(command, args.timeout)
                    try:
                        code = process.wait(timeout=min(.5, remaining))
                        break
                    except subprocess.TimeoutExpired:
                        # A script that never compiled cannot reach its own
                        # quit(). Stop only this runner's process tree promptly.
                        with log_path.open("rb") as diagnostics:
                            prefix = diagnostics.read(262144)
                        compile_failed = (b"SCRIPT ERROR: Parse Error:" in prefix
                                          or b"SCRIPT ERROR: Compile Error:" in prefix)
                        if compile_failed:
                            terminate_process_tree(process)
                            code = process.wait(timeout=10)
                            break
            except subprocess.TimeoutExpired:
                timed_out = True
                terminate_process_tree(process)
                code = process.wait(timeout=10)
        text = log_path.read_text(encoding="utf-8", errors="replace")
        script_errors = "SCRIPT ERROR:" in text or "Parse Error:" in text
        # Negative compiler tests explicitly delimit their expected diagnostics.
        checked_text = re.sub(r"EXPECTED_SHADER_COMPILER_ERROR_BEGIN.*?EXPECTED_SHADER_COMPILER_ERROR_END",
                              "", text, flags=re.S)
        shader_error = "SHADER ERROR:" in checked_text
        passed = code == 0 and not timed_out and not script_errors and not shader_error
        result = {"test": case.stem, "passed": passed, "exit_code": code,
                  "timeout": timed_out, "compile_error": compile_failed,
                  "seconds": round(time.monotonic() - started, 3),
                  "renderer": args.renderer, "log": str(log_path.relative_to(root))}
        results.append(result)
        print(json.dumps(result), flush=True)
        (artifacts / f"{args.report}.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    failed = sum(not result["passed"] for result in results)
    print(f"{len(results) - failed}/{len(results)} scripts passed; {failed} failed", flush=True)
    return int(failed > 0)


if __name__ == "__main__":
    raise SystemExit(main())

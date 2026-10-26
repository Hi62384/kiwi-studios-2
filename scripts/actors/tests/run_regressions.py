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
            try:
                code = process.wait(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                if os.name == "nt":
                    # Godot's console executable starts a child GUI process.
                    # Stop this test's process tree, not unrelated editor runs.
                    subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
                else:
                    process.kill()
                code = process.wait()
        text = log_path.read_text(encoding="utf-8", errors="replace")
        script_errors = "SCRIPT ERROR:" in text or "Parse Error:" in text
        # Negative compiler tests explicitly delimit their expected diagnostics.
        checked_text = re.sub(r"EXPECTED_SHADER_COMPILER_ERROR_BEGIN.*?EXPECTED_SHADER_COMPILER_ERROR_END",
                              "", text, flags=re.S)
        shader_error = "SHADER ERROR:" in checked_text
        passed = code == 0 and not timed_out and not script_errors and not shader_error
        result = {"test": case.stem, "passed": passed, "exit_code": code,
                  "timeout": timed_out, "seconds": round(time.monotonic() - started, 3),
                  "renderer": args.renderer, "log": str(log_path.relative_to(root))}
        results.append(result)
        print(json.dumps(result), flush=True)
        (artifacts / f"{args.report}.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    failed = sum(not result["passed"] for result in results)
    print(f"{len(results) - failed}/{len(results)} scripts passed; {failed} failed", flush=True)
    return int(failed > 0)


if __name__ == "__main__":
    raise SystemExit(main())

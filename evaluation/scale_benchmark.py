#!/usr/bin/env python3
"""Bounded, paired large-ledger read benchmark; no repository writes."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import statistics
import subprocess
import tempfile
import time
from pathlib import Path

from benchmark import make_ledger


def source_identity(repo: Path) -> dict:
    sha = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    files = [repo / "runledger.kujo", *(sorted((repo / "src").glob("*.kujo")))]
    digest = hashlib.sha256()
    for path in files:
        digest.update(path.name.encode("utf-8") + b"\0" + path.read_bytes())
    return {"revision": sha, "source_sha256": digest.hexdigest()}


def sample(repo: Path, ledger: Path, command: str, kujo: Path, timeout: int,
           page: tuple[int, int] | None = None) -> dict:
    env = dict(os.environ, KUJO=str(kujo), LC_ALL="C", TZ="UTC")
    args = [str(repo / "bin/runledger"), command]
    if command == "list":
        args.append("--json")
    args += ["--ledger", str(ledger)]
    if page:
        args += ["--limit", str(page[0]), "--offset", str(page[1])]
    started = time.perf_counter()
    try:
        result = subprocess.run(
            args, cwd=repo, env=env, stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE, timeout=timeout, check=False,
        )
        return {"seconds": round(time.perf_counter() - started, 3), "exit": result.returncode,
                "error": result.stderr.decode("utf-8", errors="replace")[:500]}
    except subprocess.TimeoutExpired:
        return {"seconds": timeout, "exit": None, "error": f"timeout after {timeout}s"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--current", type=Path, required=True)
    parser.add_argument("--kujo", type=Path, required=True)
    parser.add_argument("--samples", type=int, default=3)
    parser.add_argument("--warmups", type=int, default=1)
    parser.add_argument("--sizes", type=int, nargs="+", default=[100, 1000, 10000])
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--page-limit", type=int, default=0,
                        help="also measure current-revision last-page reads (baseline lacks pagination)")
    parser.add_argument("--page-only", action="store_true")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.samples < 1 or args.warmups < 0 or args.timeout < 1 or args.page_limit < 0 or any(size < 1 for size in args.sizes):
        parser.error("samples and sizes must be positive; warmups must be non-negative")
    if args.page_only and args.page_limit < 1:
        parser.error("--page-only requires --page-limit")

    results = {"baseline": source_identity(args.baseline.resolve()),
               "current": source_identity(args.current.resolve()),
               "baseline_measured": not args.page_only,
               "kujo_version": subprocess.check_output([str(args.kujo.resolve()), "--version"], text=True).strip(),
               "samples": args.samples, "warmups": args.warmups,
               "timeout_seconds": args.timeout, "sizes": {}}
    with tempfile.TemporaryDirectory(prefix="runledger-scale-") as temporary:
        root = Path(temporary)
        for size in args.sizes:
            fixture = make_ledger(root, size)
            results["sizes"][str(size)] = {}
            for command in (() if args.page_only else ("list", "report")):
                samples = {"baseline": [], "current": []}
                for index in range(args.warmups + args.samples):
                    order = ("baseline", "current") if index % 2 == 0 else ("current", "baseline")
                    for label in order:
                        repo = getattr(args, label).resolve()
                        result = sample(repo, fixture, command, args.kujo.resolve(), args.timeout)
                        if index >= args.warmups:
                            samples[label].append(result)
                    if any(row["exit"] != 0 for group in samples.values() for row in group):
                        break
                results["sizes"][str(size)][command] = {
                    label: {"samples": rows,
                            "median_seconds": statistics.median(row["seconds"] for row in rows)
                            if rows and all(row["exit"] == 0 for row in rows) else None}
                    for label, rows in samples.items()
                }
            if args.page_limit:
                page = (min(size, args.page_limit), max(0, size - args.page_limit))
                results["sizes"][str(size)]["current_last_page"] = {
                    command: sample(args.current.resolve(), fixture, command,
                                    args.kujo.resolve(), args.timeout, page)
                    for command in ("list", "report")
                }
            print(f"completed {size} receipts", flush=True)
            if args.output:
                args.output.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    output = json.dumps(results, indent=2) + "\n"
    if args.output:
        args.output.write_text(output, encoding="utf-8")
    else:
        print(output)
    full_ok = all(row["exit"] == 0 for size in results["sizes"].values()
                    for operation in size.values() if "baseline" in operation
                    for label in operation.values()
                    for row in label["samples"])
    page_ok = all(row["exit"] == 0 for size in results["sizes"].values()
                  for row in size.get("current_last_page", {}).values())
    return 0 if full_ok and page_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())

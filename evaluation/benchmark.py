#!/usr/bin/env python3
"""Reproducible before/after benchmark for RunLedger hardening.

The harness executes identical workloads against two immutable Git worktrees.
It uses only the Python standard library and writes one machine-readable result.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import platform
import re
import resource
import shutil
import statistics
import subprocess
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


IMPLEMENTATION_FILES = [
    "cli.kujo",
    "runledger.kujo",
    "src/cli.kujo",
    "src/gitmeta.kujo",
    "src/record.kujo",
    "src/render.kujo",
    "src/storage.kujo",
    "src/util.kujo",
]


def percentile(values: list[float], pct: float) -> float:
    ordered = sorted(values)
    rank = max(0, math.ceil((pct / 100.0) * len(ordered)) - 1)
    return ordered[rank]


def summary(values: list[float], digits: int = 3) -> dict[str, Any]:
    return {
        "n": len(values),
        "min": round(min(values), digits),
        "max": round(max(values), digits),
        "mean": round(statistics.fmean(values), digits),
        "median": round(statistics.median(values), digits),
        "stdev": round(statistics.stdev(values), digits) if len(values) > 1 else 0.0,
        "p95": round(percentile(values, 95), digits),
        "p99": round(percentile(values, 99), digits),
    }


def comparison(baseline: dict[str, Any], current: dict[str, Any]) -> dict[str, Any]:
    before = float(baseline["median"])
    after = float(current["median"])
    return {
        "baseline_median": before,
        "current_median": after,
        "absolute_change": round(after - before, 3),
        "percent_change": round(((after - before) / before) * 100.0, 2) if before else None,
    }


def run_command(
    command: list[str],
    *,
    env: dict[str, str],
    cwd: Path | None = None,
    timeout: float = 120.0,
) -> dict[str, Any]:
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    started = time.perf_counter_ns()
    completed = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )
    elapsed_ms = (time.perf_counter_ns() - started) / 1_000_000.0
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    stdout = completed.stdout
    stderr = completed.stderr
    return {
        "exit_code": completed.returncode,
        "wall_ms": elapsed_ms,
        "cpu_ms": ((after.ru_utime + after.ru_stime) - (before.ru_utime + before.ru_stime)) * 1000.0,
        "stdout": stdout.decode("utf-8", errors="replace"),
        "stderr": stderr.decode("utf-8", errors="replace"),
        "stdout_bytes": len(stdout),
        "stderr_bytes": len(stderr),
        "stdout_lines": len(stdout.splitlines()),
        "stderr_lines": len(stderr.splitlines()),
    }


def measured_runs(fn, warmups: int, runs: int) -> list[dict[str, Any]]:
    for _ in range(warmups):
        fn()
    return [fn() for _ in range(runs)]


def stats_from_runs(runs: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "wall_ms": summary([r["wall_ms"] for r in runs]),
        "cpu_ms": summary([r["cpu_ms"] for r in runs]),
        "stdout_bytes": summary([float(r["stdout_bytes"]) for r in runs]),
        "stderr_bytes": summary([float(r["stderr_bytes"]) for r in runs]),
        "exit_codes": sorted({r["exit_code"] for r in runs}),
        "success_rate": round(sum(r["exit_code"] == 0 for r in runs) / len(runs), 4),
    }


def compact_samples(runs: list[dict[str, Any]]) -> list[dict[str, Any]]:
    retained = {
        "wall_ms", "cpu_ms", "exit_code", "stdout_bytes", "stderr_bytes",
        "stdout_lines", "stderr_lines", "subprocess_count", "successes",
        "failures", "persisted_records", "persisted_notes", "all_preserved",
        "valid_json", "residual_locks", "terminal_record_preserved",
        "peak_rss_bytes",
    }
    return [{key: value for key, value in item.items() if key in retained} for item in runs]


def git_value(repo: Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()


def make_env(kujo: Path) -> dict[str, str]:
    env = dict(os.environ)
    env.update(
        {
            "KUJO": str(kujo),
            "LC_ALL": "C",
            "LANG": "C",
            "TZ": "UTC",
            "RUNLEDGER_LOCK_TIMEOUT_MS": "10000",
        }
    )
    return env


def make_git_fixture(root: Path) -> Path:
    repo = root / "git-fixture"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.email", "benchmark@example.com"], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.name", "RunLedger Benchmark"], check=True)
    (repo / "fixture.txt").write_text("stable fixture\n", encoding="utf-8")
    subprocess.run(["git", "-C", str(repo), "add", "fixture.txt"], check=True)
    subprocess.run(["git", "-C", str(repo), "commit", "-q", "-m", "fixture"], check=True)
    return repo


def record_payload(index: int, task: str = "Scale Fixture") -> dict[str, Any]:
    return {
        "id": f"2026-08-30-fixture-scale-{index:06d}",
        "created_at": "2026-08-30T12:00:00Z",
        "updated_at": "2026-08-30T12:01:00Z",
        "status": "pass" if index % 2 == 0 else "partial",
        "provider": "fixture",
        "model": "deterministic-model",
        "task_name": task,
        "prompt_file": None,
        "repo_path": "/tmp/fixture",
        "start_commit": "a" * 40,
        "end_commit": "b" * 40,
        "git_dirty_start": False,
        "git_dirty_end": False,
        "changed_files": [f"src/file-{index % 25}.kujo"],
        "commands": [],
        "tests": [],
        "usage": {
            "input_tokens": 1000 + index,
            "output_tokens": 100 + index,
            "cache_read_tokens": 0,
            "cache_write_tokens": 0,
        },
        "cost": {
            "currency": "USD",
            "input_cost": 0.01,
            "output_cost": 0.01,
            "cache_cost": 0.0,
            "total_cost": 0.02,
        },
        "verdict": "deterministic fixture verdict",
        "followups": [],
        "notes": [{"at": "2026-08-30T12:00:30Z", "text": "fixture note"}],
    }


def make_ledger(root: Path, count: int) -> Path:
    ledger = root / f"ledger-{count}"
    runs = ledger / "runs"
    runs.mkdir(parents=True)
    for index in range(count):
        payload = record_payload(index)
        (runs / f"{payload['id']}.json").write_text(
            json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
    return ledger


def lifecycle(repo: Path, env: dict[str, str], root: Path, git_fixture: Path, index: int) -> dict[str, Any]:
    ledger = root / f"lifecycle-{index}-{time.time_ns()}"
    launcher = repo / "bin" / "runledger"
    commands = 0
    stdout_bytes = 0
    stderr_bytes = 0
    cpu_ms = 0.0
    started = time.perf_counter_ns()

    def invoke(args: list[str]) -> dict[str, Any]:
        nonlocal commands, stdout_bytes, stderr_bytes, cpu_ms
        result = run_command([str(launcher), *args], env=env, cwd=repo)
        commands += 1
        stdout_bytes += result["stdout_bytes"]
        stderr_bytes += result["stderr_bytes"]
        cpu_ms += result["cpu_ms"]
        return result

    start = invoke(
        [
            "start",
            "--provider",
            "fixture",
            "--model",
            "benchmark-model",
            "--task",
            "Typical Lifecycle",
            "--repo",
            str(git_fixture),
            "--ledger",
            str(ledger),
        ]
    )
    match = re.search(r"^Started run: (.+)$", start["stdout"], re.MULTILINE)
    run_id = match.group(1) if match else "missing"
    results = [start]
    results.append(invoke(["note", run_id, "benchmark note", "--ledger", str(ledger)]))
    results.append(invoke(["usage", run_id, "--input", "1000", "--output", "100", "--ledger", str(ledger)]))
    results.append(invoke(["cost", run_id, "--total", "0.02", "--currency", "USD", "--ledger", str(ledger)]))
    results.append(
        invoke(
            [
                "finish",
                run_id,
                "--status",
                "pass",
                "--verdict",
                "benchmark pass",
                "--repo",
                str(git_fixture),
                "--ledger",
                str(ledger),
            ]
        )
    )
    results.append(invoke(["report", "--task", "Typical Lifecycle", "--ledger", str(ledger)]))
    elapsed_ms = (time.perf_counter_ns() - started) / 1_000_000.0
    return {
        "exit_code": 0 if all(item["exit_code"] == 0 for item in results) else 1,
        "wall_ms": elapsed_ms,
        "cpu_ms": cpu_ms,
        "stdout_bytes": stdout_bytes,
        "stderr_bytes": stderr_bytes,
        "stdout_lines": sum(item["stdout_lines"] for item in results),
        "stderr_lines": sum(item["stderr_lines"] for item in results),
        "subprocess_count": commands,
    }


def parallel_processes(commands: list[list[str]], *, env: dict[str, str], cwd: Path) -> dict[str, Any]:
    started = time.perf_counter_ns()
    processes = [subprocess.Popen(c, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for c in commands]
    completed = []
    for process in processes:
        stdout, stderr = process.communicate(timeout=120)
        completed.append((process.returncode, stdout, stderr))
    return {
        "wall_ms": (time.perf_counter_ns() - started) / 1_000_000.0,
        "successes": sum(code == 0 for code, _, _ in completed),
        "failures": sum(code != 0 for code, _, _ in completed),
        "stdout_bytes": sum(len(stdout) for _, stdout, _ in completed),
        "stderr_bytes": sum(len(stderr) for _, _, stderr in completed),
    }


def concurrent_starts(repo: Path, env: dict[str, str], root: Path, writers: int, trial: int) -> dict[str, Any]:
    ledger = root / f"parallel-start-{trial}-{time.time_ns()}"
    launcher = str(repo / "bin" / "runledger")
    command = [
        launcher,
        "start",
        "--provider",
        "fixture",
        "--model",
        "parallel-model",
        "--task",
        "Concurrent Start",
        "--repo",
        str(root),
        "--ledger",
        str(ledger),
    ]
    result = parallel_processes([command[:] for _ in range(writers)], env=env, cwd=repo)
    files = list((ledger / "runs").glob("*.json")) if (ledger / "runs").exists() else []
    result["persisted_records"] = len(files)
    result["all_preserved"] = len(files) == writers
    return result


def concurrent_notes(repo: Path, env: dict[str, str], root: Path, writers: int, trial: int) -> dict[str, Any]:
    ledger = root / f"parallel-note-{trial}-{time.time_ns()}"
    runs_dir = ledger / "runs"
    runs_dir.mkdir(parents=True)
    payload = record_payload(0, task="Concurrent Note")
    payload["id"] = "parallel-note-target"
    (runs_dir / "parallel-note-target.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    launcher = str(repo / "bin" / "runledger")
    commands = [
        [launcher, "note", "parallel-note-target", f"parallel-{index}", "--ledger", str(ledger)]
        for index in range(writers)
    ]
    result = parallel_processes(commands, env=env, cwd=repo)
    try:
        stored = json.loads((runs_dir / "parallel-note-target.json").read_text(encoding="utf-8"))
        texts = {item.get("text") for item in stored.get("notes", []) if isinstance(item, dict)}
        preserved = sum(f"parallel-{index}" in texts for index in range(writers))
        valid_json = True
    except (OSError, json.JSONDecodeError):
        preserved = 0
        valid_json = False
    result.update(
        {
            "persisted_notes": preserved,
            "all_preserved": preserved == writers,
            "valid_json": valid_json,
            "residual_locks": len(list((ledger / "locks").glob("*"))) if (ledger / "locks").exists() else 0,
        }
    )
    return result


def failure_case(repo: Path, env: dict[str, str], root: Path, case: str, trial: int) -> dict[str, Any]:
    ledger = root / f"failure-{case}-{trial}-{time.time_ns()}"
    runs = ledger / "runs"
    runs.mkdir(parents=True)
    launcher = repo / "bin" / "runledger"
    if case == "unknown_flag":
        return run_command([str(launcher), "list", "--unknown", "value", "--ledger", str(ledger)], env=env, cwd=repo)
    if case == "corrupt_record":
        (runs / "corrupt.json").write_text("{not-json\n", encoding="utf-8")
        return run_command([str(launcher), "show", "corrupt", "--ledger", str(ledger)], env=env, cwd=repo)
    payload = record_payload(0, task="Terminal Fixture")
    payload["id"] = "terminal-record"
    payload["status"] = "pass"
    payload["verdict"] = "original"
    path = runs / "terminal-record.json"
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    result = run_command(
        [
            str(launcher),
            "finish",
            "terminal-record",
            "--status",
            "fail",
            "--verdict",
            "rewritten",
            "--repo",
            str(root),
            "--ledger",
            str(ledger),
        ],
        env=env,
        cwd=repo,
    )
    stored = json.loads(path.read_text(encoding="utf-8"))
    result["terminal_record_preserved"] = stored.get("status") == "pass" and stored.get("verdict") == "original"
    return result


def peak_rss(repo: Path, env: dict[str, str], ledger: Path) -> dict[str, Any]:
    launcher = repo / "bin" / "runledger"
    completed = subprocess.run(
        ["/usr/bin/time", "-l", str(launcher), "report", "--ledger", str(ledger)],
        cwd=repo,
        env=env,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        check=False,
    )
    stderr = completed.stderr.decode("utf-8", errors="replace")
    match = re.search(r"(\d+)\s+maximum resident set size", stderr)
    return {"exit_code": completed.returncode, "peak_rss_bytes": int(match.group(1)) if match else None}


def check_suite(repo: Path, env: dict[str, str]) -> dict[str, Any]:
    started = time.perf_counter_ns()
    outputs = [run_command([env["KUJO"], "check", str(repo / item)], env=env, cwd=repo) for item in IMPLEMENTATION_FILES]
    return {
        "exit_code": 0 if all(item["exit_code"] == 0 for item in outputs) else 1,
        "wall_ms": (time.perf_counter_ns() - started) / 1_000_000.0,
        "cpu_ms": sum(item["cpu_ms"] for item in outputs),
        "stdout_bytes": sum(item["stdout_bytes"] for item in outputs),
        "stderr_bytes": sum(item["stderr_bytes"] for item in outputs),
    }


def native_test(repo: Path, env: dict[str, str]) -> dict[str, Any]:
    return run_command([str(repo / "tests" / "run.sh")], env=env, cwd=repo, timeout=180.0)


def code_metrics(repo: Path) -> dict[str, Any]:
    source_paths = [repo / item for item in IMPLEMENTATION_FILES]
    test_paths = sorted((repo / "tests").glob("*"))

    def metrics(paths: list[Path]) -> dict[str, int]:
        text_parts = [path.read_text(encoding="utf-8") for path in paths if path.is_file()]
        lines = [line for text in text_parts for line in text.splitlines()]
        return {
            "files": len(text_parts),
            "bytes": sum(len(text.encode("utf-8")) for text in text_parts),
            "loc": len(lines),
            "nonblank_loc": sum(bool(line.strip()) for line in lines),
            "comment_loc": sum(line.lstrip().startswith("#") for line in lines),
            "functions": sum(bool(re.match(r"\s*(export\s+)?func\s+", line)) for line in lines),
            "branch_keyword_proxy": sum(len(re.findall(r"\b(if|while|for|except)\b", line)) for line in lines),
            "todo_fixme": sum(bool(re.search(r"\b(TODO|FIXME)\b", line)) for line in lines),
        }

    manifest = (repo / "kujo.toml").read_text(encoding="utf-8")
    dependency_body = manifest.split("[dependencies]", 1)[1] if "[dependencies]" in manifest else ""
    dependencies = [line for line in dependency_body.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    return {
        "source": metrics(source_paths),
        "tests": metrics([p for p in test_paths if p.suffix in {".kujo", ".sh"}]),
        "direct_dependencies": len(dependencies),
        "transitive_dependencies": 0,
        "compiled_binary_bytes": 0,
        "artifact_note": "RunLedger is interpreted by the shared Kujo runtime; it has no repository-built binary.",
    }


def lint_observation(repo: Path, env: dict[str, str]) -> dict[str, Any]:
    warnings = 0
    failures = 0
    output_bytes = 0
    for item in IMPLEMENTATION_FILES:
        result = run_command([env["KUJO"], "lint", str(repo / item)], env=env, cwd=repo)
        warnings += result["stdout"].lower().count("warning") + result["stderr"].lower().count("warning")
        failures += result["exit_code"] != 0
        output_bytes += result["stdout_bytes"] + result["stderr_bytes"]
    return {"warnings": warnings, "failures": failures, "output_bytes": output_bytes}


def evaluate_version(
    label: str,
    repo: Path,
    env: dict[str, str],
    root: Path,
    git_fixture: Path,
    warmups: int,
    runs: int,
    stress_runs: int,
    writers: int,
    scale_sizes: list[int],
) -> dict[str, Any]:
    launcher = repo / "bin" / "runledger"
    version_root = root / label
    version_root.mkdir()
    ledgers = {size: make_ledger(version_root, size) for size in scale_sizes}

    startup_runs = measured_runs(
        lambda: run_command([str(launcher), "version"], env=env, cwd=repo), warmups, runs
    )
    lifecycle_index = 0

    def lifecycle_once() -> dict[str, Any]:
        nonlocal lifecycle_index
        lifecycle_index += 1
        return lifecycle(repo, env, version_root, git_fixture, lifecycle_index)

    lifecycle_runs = measured_runs(lifecycle_once, warmups, runs)
    scale: dict[str, Any] = {}
    for size in scale_sizes:
        list_runs = measured_runs(
            lambda ledger=ledgers[size]: run_command(
                [str(launcher), "list", "--json", "--ledger", str(ledger)], env=env, cwd=repo
            ),
            warmups,
            runs,
        )
        report_runs = measured_runs(
            lambda ledger=ledgers[size]: run_command(
                [str(launcher), "report", "--ledger", str(ledger)], env=env, cwd=repo
            ),
            warmups,
            runs,
        )
        scale[str(size)] = {
            "list_json": stats_from_runs(list_runs),
            "report": stats_from_runs(report_runs),
            "list_records_per_second": round(size / (statistics.median([r["wall_ms"] for r in list_runs]) / 1000.0), 2),
            "report_records_per_second": round(size / (statistics.median([r["wall_ms"] for r in report_runs]) / 1000.0), 2),
        }

    start_trials = [concurrent_starts(repo, env, version_root, writers, index) for index in range(stress_runs)]
    note_trials = [concurrent_notes(repo, env, version_root, writers, index) for index in range(stress_runs)]

    failures: dict[str, Any] = {}
    for case in ["unknown_flag", "corrupt_record", "duplicate_finish"]:
        case_runs = [failure_case(repo, env, version_root, case, index) for index in range(runs)]
        failures[case] = stats_from_runs(case_runs)
        failures[case]["median_total_output_bytes"] = statistics.median(
            [r["stdout_bytes"] + r["stderr_bytes"] for r in case_runs]
        )
        if case == "duplicate_finish":
            failures[case]["preservation_rate"] = round(
                sum(bool(r["terminal_record_preserved"]) for r in case_runs) / len(case_runs), 4
            )

    check_runs = measured_runs(lambda: check_suite(repo, env), 1, runs)
    native_tests = [native_test(repo, env) for _ in range(3)]
    rss_runs = [peak_rss(repo, env, ledgers[max(scale_sizes)]) for _ in range(runs)]
    rss_values = [float(item["peak_rss_bytes"]) for item in rss_runs if item["peak_rss_bytes"] is not None]

    return {
        "git": {
            "sha": git_value(repo, "rev-parse", "HEAD"),
            "timestamp": git_value(repo, "show", "-s", "--format=%cI", "HEAD"),
            "tag": git_value(repo, "describe", "--tags", "--exact-match", "HEAD"),
            "worktree_clean": git_value(repo, "status", "--porcelain") == "",
        },
        "runtime": {
            "startup_version": stats_from_runs(startup_runs),
            "typical_lifecycle": stats_from_runs(lifecycle_runs),
            "check_all_implementation_files": stats_from_runs(check_runs),
            "large_report_peak_rss_bytes": summary(rss_values, 0),
        },
        "scaling": scale,
        "stress": {
            "writers": writers,
            "trials": stress_runs,
            "concurrent_starts": {
                "wall_ms": summary([t["wall_ms"] for t in start_trials]),
                "mean_successful_processes": round(statistics.fmean(t["successes"] for t in start_trials), 2),
                "mean_persisted_records": round(statistics.fmean(t["persisted_records"] for t in start_trials), 2),
                "all_preserved_rate": round(sum(t["all_preserved"] for t in start_trials) / stress_runs, 4),
            },
            "concurrent_notes": {
                "wall_ms": summary([t["wall_ms"] for t in note_trials]),
                "mean_successful_processes": round(statistics.fmean(t["successes"] for t in note_trials), 2),
                "mean_persisted_notes": round(statistics.fmean(t["persisted_notes"] for t in note_trials), 2),
                "all_preserved_rate": round(sum(t["all_preserved"] for t in note_trials) / stress_runs, 4),
                "valid_json_rate": round(sum(t["valid_json"] for t in note_trials) / stress_runs, 4),
                "mean_residual_locks": round(statistics.fmean(t["residual_locks"] for t in note_trials), 2),
            },
        },
        "failure_behavior": failures,
        "reliability": {
            "native_test_runs": 3,
            "native_test_success_rate": round(sum(t["exit_code"] == 0 for t in native_tests) / 3.0, 4),
            "native_test_wall_ms": summary([t["wall_ms"] for t in native_tests]),
            "note": "Native suites differ by revision; timings are recorded but are not a fair speed comparison.",
        },
        "code_metrics": code_metrics(repo),
        "lint": lint_observation(repo, env),
    }


def paired_runs(baseline_fn, current_fn, warmups: int, runs: int) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Run versions back-to-back and reverse order every sample to limit drift."""
    for index in range(warmups):
        if index % 2 == 0:
            baseline_fn()
            current_fn()
        else:
            current_fn()
            baseline_fn()
    baseline_runs: list[dict[str, Any]] = []
    current_runs: list[dict[str, Any]] = []
    for index in range(runs):
        if index % 2 == 0:
            baseline_runs.append(baseline_fn())
            current_runs.append(current_fn())
        else:
            current_runs.append(current_fn())
            baseline_runs.append(baseline_fn())
    return baseline_runs, current_runs


def evaluate_pair(
    baseline_repo: Path,
    current_repo: Path,
    env: dict[str, str],
    root: Path,
    git_fixture: Path,
    warmups: int,
    runs: int,
    stress_runs: int,
    writers: int,
    scale_sizes: list[int],
) -> tuple[dict[str, Any], dict[str, Any]]:
    repos = {"baseline": baseline_repo, "current": current_repo}
    roots = {label: root / label for label in repos}
    for version_root in roots.values():
        version_root.mkdir()
    ledgers = {
        label: {size: make_ledger(roots[label], size) for size in scale_sizes}
        for label in repos
    }
    samples: dict[str, dict[str, Any]] = {"baseline": {}, "current": {}}

    paired = paired_runs(
        lambda: run_command([str(baseline_repo / "bin" / "runledger"), "version"], env=env, cwd=baseline_repo),
        lambda: run_command([str(current_repo / "bin" / "runledger"), "version"], env=env, cwd=current_repo),
        warmups,
        runs,
    )
    samples["baseline"]["startup"] = paired[0]
    samples["current"]["startup"] = paired[1]

    lifecycle_indexes = {"baseline": 0, "current": 0}

    def lifecycle_for(label: str) -> dict[str, Any]:
        lifecycle_indexes[label] += 1
        return lifecycle(repos[label], env, roots[label], git_fixture, lifecycle_indexes[label])

    paired = paired_runs(
        lambda: lifecycle_for("baseline"), lambda: lifecycle_for("current"), warmups, runs
    )
    samples["baseline"]["lifecycle"] = paired[0]
    samples["current"]["lifecycle"] = paired[1]

    for label in samples:
        samples[label]["scale"] = {}
    for size in scale_sizes:
        for operation in ["list_json", "report"]:
            def command_for(label: str, op: str = operation, fixture_size: int = size) -> dict[str, Any]:
                args = ["list", "--json"] if op == "list_json" else ["report"]
                return run_command(
                    [str(repos[label] / "bin" / "runledger"), *args, "--ledger", str(ledgers[label][fixture_size])],
                    env=env,
                    cwd=repos[label],
                )

            paired = paired_runs(
                lambda: command_for("baseline"), lambda: command_for("current"), warmups, runs
            )
            samples["baseline"]["scale"].setdefault(str(size), {})[operation] = paired[0]
            samples["current"]["scale"].setdefault(str(size), {})[operation] = paired[1]

    for label in samples:
        samples[label]["starts"] = []
        samples[label]["notes"] = []
    for trial in range(stress_runs):
        order = ["baseline", "current"] if trial % 2 == 0 else ["current", "baseline"]
        for label in order:
            samples[label]["starts"].append(concurrent_starts(repos[label], env, roots[label], writers, trial))
            samples[label]["notes"].append(concurrent_notes(repos[label], env, roots[label], writers, trial))

    for label in samples:
        samples[label]["failures"] = {}
    for case in ["unknown_flag", "corrupt_record", "duplicate_finish"]:
        paired = paired_runs(
            lambda c=case: failure_case(baseline_repo, env, roots["baseline"], c, time.time_ns()),
            lambda c=case: failure_case(current_repo, env, roots["current"], c, time.time_ns()),
            warmups,
            runs,
        )
        samples["baseline"]["failures"][case] = paired[0]
        samples["current"]["failures"][case] = paired[1]

    paired = paired_runs(
        lambda: check_suite(baseline_repo, env), lambda: check_suite(current_repo, env), 1, runs
    )
    samples["baseline"]["checks"] = paired[0]
    samples["current"]["checks"] = paired[1]

    samples["baseline"]["native_tests"] = []
    samples["current"]["native_tests"] = []
    for trial in range(3):
        order = ["baseline", "current"] if trial % 2 == 0 else ["current", "baseline"]
        for label in order:
            samples[label]["native_tests"].append(native_test(repos[label], env))

    samples["baseline"]["rss"] = []
    samples["current"]["rss"] = []
    for trial in range(runs):
        order = ["baseline", "current"] if trial % 2 == 0 else ["current", "baseline"]
        for label in order:
            samples[label]["rss"].append(peak_rss(repos[label], env, ledgers[label][max(scale_sizes)]))

    outputs: dict[str, dict[str, Any]] = {}
    for label in ["baseline", "current"]:
        repo = repos[label]
        data = samples[label]
        scale: dict[str, Any] = {}
        for size in scale_sizes:
            list_stats = stats_from_runs(data["scale"][str(size)]["list_json"])
            report_stats = stats_from_runs(data["scale"][str(size)]["report"])
            scale[str(size)] = {
                "list_json": list_stats,
                "report": report_stats,
                "list_records_per_second": round(size / (list_stats["wall_ms"]["median"] / 1000.0), 2),
                "report_records_per_second": round(size / (report_stats["wall_ms"]["median"] / 1000.0), 2),
            }
        starts = data["starts"]
        notes = data["notes"]
        failures: dict[str, Any] = {}
        for case, case_runs in data["failures"].items():
            failures[case] = stats_from_runs(case_runs)
            failures[case]["median_total_output_bytes"] = statistics.median(
                [item["stdout_bytes"] + item["stderr_bytes"] for item in case_runs]
            )
            if case == "duplicate_finish":
                failures[case]["preservation_rate"] = round(
                    sum(bool(item["terminal_record_preserved"]) for item in case_runs) / len(case_runs), 4
                )
        rss_values = [float(item["peak_rss_bytes"]) for item in data["rss"] if item["peak_rss_bytes"] is not None]
        native_tests = data["native_tests"]
        outputs[label] = {
            "git": {
                "sha": git_value(repo, "rev-parse", "HEAD"),
                "timestamp": git_value(repo, "show", "-s", "--format=%cI", "HEAD"),
                "tag": git_value(repo, "describe", "--tags", "--exact-match", "HEAD"),
                "worktree_clean": git_value(repo, "status", "--porcelain") == "",
            },
            "runtime": {
                "startup_version": stats_from_runs(data["startup"]),
                "typical_lifecycle": stats_from_runs(data["lifecycle"]),
                "check_all_implementation_files": stats_from_runs(data["checks"]),
                "large_report_peak_rss_bytes": summary(rss_values, 0),
            },
            "scaling": scale,
            "stress": {
                "writers": writers,
                "trials": stress_runs,
                "concurrent_starts": {
                    "wall_ms": summary([item["wall_ms"] for item in starts]),
                    "mean_successful_processes": round(statistics.fmean(item["successes"] for item in starts), 2),
                    "mean_persisted_records": round(statistics.fmean(item["persisted_records"] for item in starts), 2),
                    "all_preserved_rate": round(sum(item["all_preserved"] for item in starts) / stress_runs, 4),
                },
                "concurrent_notes": {
                    "wall_ms": summary([item["wall_ms"] for item in notes]),
                    "mean_successful_processes": round(statistics.fmean(item["successes"] for item in notes), 2),
                    "mean_persisted_notes": round(statistics.fmean(item["persisted_notes"] for item in notes), 2),
                    "all_preserved_rate": round(sum(item["all_preserved"] for item in notes) / stress_runs, 4),
                    "valid_json_rate": round(sum(item["valid_json"] for item in notes) / stress_runs, 4),
                    "mean_residual_locks": round(statistics.fmean(item["residual_locks"] for item in notes), 2),
                },
            },
            "failure_behavior": failures,
            "reliability": {
                "native_test_runs": 3,
                "native_test_success_rate": round(sum(item["exit_code"] == 0 for item in native_tests) / 3.0, 4),
                "native_test_wall_ms": summary([item["wall_ms"] for item in native_tests]),
                "note": "Native suites differ by revision; timings are recorded but are not a fair speed comparison.",
            },
            "code_metrics": code_metrics(repo),
            "lint": lint_observation(repo, env),
            "raw_samples": {
                "startup_version": compact_samples(data["startup"]),
                "typical_lifecycle": compact_samples(data["lifecycle"]),
                "scaling": {
                    str(size): {
                        "list_json": compact_samples(data["scale"][str(size)]["list_json"]),
                        "report": compact_samples(data["scale"][str(size)]["report"]),
                    }
                    for size in scale_sizes
                },
                "concurrent_starts": compact_samples(starts),
                "concurrent_notes": compact_samples(notes),
                "failure_behavior": {
                    case: compact_samples(case_runs) for case, case_runs in data["failures"].items()
                },
                "check_all_implementation_files": compact_samples(data["checks"]),
                "native_tests": compact_samples(native_tests),
                "large_report_peak_rss": compact_samples(data["rss"]),
            },
        }
    return outputs["baseline"], outputs["current"]


def build_eval_input(version: dict[str, Any]) -> dict[str, Any]:
    return {
        "startup_succeeds": version["runtime"]["startup_version"]["success_rate"] == 1.0,
        "typical_lifecycle_succeeds": version["runtime"]["typical_lifecycle"]["success_rate"] == 1.0,
        "large_list_succeeds": version["scaling"]["100"]["list_json"]["success_rate"] == 1.0,
        "large_report_succeeds": version["scaling"]["100"]["report"]["success_rate"] == 1.0,
        "concurrent_starts_preserved": version["stress"]["concurrent_starts"]["all_preserved_rate"] == 1.0,
        "concurrent_notes_preserved": version["stress"]["concurrent_notes"]["all_preserved_rate"] == 1.0,
        "unknown_flag_rejected": version["failure_behavior"]["unknown_flag"]["exit_codes"] == [2],
        "terminal_record_preserved": version["failure_behavior"]["duplicate_finish"]["preservation_rate"] == 1.0,
        "native_tests_pass": version["reliability"]["native_test_success_rate"] == 1.0,
        "lint_clean": version["lint"]["warnings"] == 0 and version["lint"]["failures"] == 0,
    }


def host_environment(kujo: Path) -> dict[str, Any]:
    def output(command: list[str]) -> str:
        return subprocess.check_output(command, text=True, stderr=subprocess.DEVNULL).strip()

    return {
        "captured_at": datetime.now(timezone.utc).isoformat(),
        "os": platform.platform(),
        "kernel": platform.release(),
        "architecture": platform.machine(),
        "cpu": output(["sysctl", "-n", "machdep.cpu.brand_string"]),
        "physical_cores": int(output(["sysctl", "-n", "hw.physicalcpu"])),
        "logical_cores": int(output(["sysctl", "-n", "hw.logicalcpu"])),
        "ram_bytes": int(output(["sysctl", "-n", "hw.memsize"])),
        "filesystem": output(["df", "-h", "."]).splitlines()[-1],
        "load_average": os.getloadavg(),
        "python": platform.python_version(),
        "kujo_path": str(kujo),
        "kujo_version": output([str(kujo), "--version"]),
        "rust_version": output(["rustc", "--version"]),
        "cargo_version": output(["cargo", "--version"]),
        "network": "No benchmark workload makes network calls.",
        "model_provider": "Not applicable; RunLedger contains no LLM/provider execution path.",
        "environment_controls": {"LC_ALL": "C", "LANG": "C", "TZ": "UTC"},
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--current", type=Path, required=True)
    parser.add_argument("--kujo", type=Path, default=Path(shutil.which("kujo") or "kujo"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--eval-input-dir", type=Path, required=True)
    parser.add_argument("--warmups", type=int, default=3)
    parser.add_argument("--runs", type=int, default=12)
    parser.add_argument("--stress-runs", type=int, default=10)
    parser.add_argument("--writers", type=int, default=20)
    args = parser.parse_args()

    for repo in [args.baseline, args.current]:
        if not (repo / "bin" / "runledger").is_file():
            parser.error(f"not a RunLedger checkout: {repo}")

    env = make_env(args.kujo.resolve())
    with tempfile.TemporaryDirectory(prefix="runledger-hardening-eval-") as temp:
        root = Path(temp)
        git_fixture = make_git_fixture(root)
        load_before = os.getloadavg()
        baseline, current = evaluate_pair(
            args.baseline.resolve(), args.current.resolve(), env, root, git_fixture,
            args.warmups, args.runs, args.stress_runs, args.writers, [1, 25, 100]
        )
        load_after = os.getloadavg()

    results = {
        "schema_version": "1.0.0",
        "evaluation": "RunLedger v1.0.0 to v1.1.0 hardening",
        "baseline_selection": {
            "sha": baseline["git"]["sha"],
            "reason": "v1.0.0 is the immediately preceding release; the next commit begins the hardening sequence with stronger storage-contract tests.",
            "alternatives_considered": [
                {
                    "sha": "12bbf2b3723325913eb75ececaba0ce3fdc68b87",
                    "reason_not_selected": "This is the start of the final same-day persistence audit, but it already contains earlier CLI and normalization hardening and would understate the complete release-to-release change.",
                }
            ],
        },
        "current": {"sha": current["git"]["sha"], "reason": "Current released tag v1.1.0."},
        "methodology": {
            "warmups": args.warmups,
            "measured_runs": args.runs,
            "stress_trials": args.stress_runs,
            "stress_writers": args.writers,
            "latency_unit": "milliseconds",
            "percentiles": "nearest-rank",
            "comparison_rule": "Identical commands, fixtures, Kujo runtime, environment controls, and host.",
            "execution_order": "Paired and alternating: revisions run back-to-back and sample order reverses every iteration.",
            "host_load_average_before": load_before,
            "host_load_average_after": load_after,
        },
        "environment": host_environment(args.kujo.resolve()),
        "versions": {"baseline": baseline, "current": current},
        "comparisons": {
            "startup_wall_ms": comparison(baseline["runtime"]["startup_version"]["wall_ms"], current["runtime"]["startup_version"]["wall_ms"]),
            "typical_lifecycle_wall_ms": comparison(baseline["runtime"]["typical_lifecycle"]["wall_ms"], current["runtime"]["typical_lifecycle"]["wall_ms"]),
            "check_wall_ms": comparison(baseline["runtime"]["check_all_implementation_files"]["wall_ms"], current["runtime"]["check_all_implementation_files"]["wall_ms"]),
            "large_list_wall_ms": comparison(baseline["scaling"]["100"]["list_json"]["wall_ms"], current["scaling"]["100"]["list_json"]["wall_ms"]),
            "large_report_wall_ms": comparison(baseline["scaling"]["100"]["report"]["wall_ms"], current["scaling"]["100"]["report"]["wall_ms"]),
            "large_report_peak_rss_bytes": comparison(baseline["runtime"]["large_report_peak_rss_bytes"], current["runtime"]["large_report_peak_rss_bytes"]),
            "concurrent_start_wall_ms": comparison(baseline["stress"]["concurrent_starts"]["wall_ms"], current["stress"]["concurrent_starts"]["wall_ms"]),
            "concurrent_note_wall_ms": comparison(baseline["stress"]["concurrent_notes"]["wall_ms"], current["stress"]["concurrent_notes"]["wall_ms"]),
        },
        "token_context": {
            "input_tokens": None,
            "output_tokens": None,
            "cached_tokens": None,
            "context_size": None,
            "classification": "Not demonstrated / not applicable",
            "reason": "RunLedger records optional user-supplied token counts but does not call an LLM, construct prompts, or manage agent context.",
            "measured_agent_surface": "CLI stdout/stderr bytes and subprocess counts only.",
        },
        "build": {
            "classification": "Not applicable for a repository-local build artifact",
            "reason": "RunLedger is interpreted by the shared Kujo runtime and declares no dependencies; Kujo check time and source footprint are measured instead.",
        },
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(results, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    args.eval_input_dir.mkdir(parents=True, exist_ok=True)
    (args.eval_input_dir / "baseline.json").write_text(
        json.dumps(build_eval_input(baseline), indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    (args.eval_input_dir / "current.json").write_text(
        json.dumps(build_eval_input(current), indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

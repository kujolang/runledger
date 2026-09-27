# Runtime measurement evidence (unreleased)

RunLedger remains a receipt/correlation store. Watchdog validates and observes
Kujo runtime facts; RunLedger retains their content address without another
telemetry bus or workflow state machine.

```sh
runledger correlate RUN_ID --watchdog-trace CANONICAL_TRACE --watchdog-run EXECUTION_ID
runledger runtime-measurement RUN_ID --root TRUSTED_ARTIFACT_ROOT \
  --file RELATIVE_REPORT_JSON --artifact sha256:EXPECTED_LOWERCASE_HEX
```

The command reads at most 8192 UTF-8 bytes with `read_file_beneath`, rejecting
symlinks, path traversal, absolute paths, non-regular files and oversized data.
It recomputes SHA-256 of the exact bytes and requires an exact address match.
It checks JSON object shape and the `kujo.runtime-measurements/v1` marker.
**This is byte-integrity verification, not complete measurement validation**:
Watchdog's adapter owns semantic validation. It does not trust producer assertions
as evidence of execution, sign artifacts, or establish authenticity.

Through the existing locked read-modify-write path it adds one timestamped note
whose text is deterministic JSON:

```json
{"artifact":"sha256:<64 lowercase hex>","bytes":1234,"schema":"kujo.runtime-measurements/v1","verification":"exact_bytes_sha256"}
```

The existing receipt schema is unchanged. No raw path, source, output, prompt,
report extension or runtime counter enters the receipt. Exact repeated attachment
is a no-op; the command rejects appending when a receipt already has 1000 notes.
Other note commands retain their existing behavior. Concurrent receipt mutations
use the existing sidecar lock and atomic writer. Failures print a fixed artifact
error, not raw report content or artifact file paths. The trusted root, ledger
storage and caller-provided correlation identifiers remain the caller's security
responsibility. This does not make an untrusted ledger directory safe.

No artifact bytes are copied into RunLedger. Keep the original in a trusted
content-addressed store and verify its digest when resolving the reference.
Deletion/expiration makes the reference unavailable, never zero or a pass.
A receipt's atomic write guarantees are unchanged; no cross-store transaction,
exactly-once execution, rollback or machine-loss recovery is introduced.

Usage fields remain nullable token counts; cost fields retain their currency and
nullable amounts. This command never changes them or receipt pass/fail/partial
status. Runtime duration is not model cost. The current receipt schema cannot
express rich per-source usage provenance without an extension, so provenance and
counters remain in the referenced Watchdog observation/artifact. Do not interpret
an Agents SDK budget default of zero as observed usage. Use source-aware evidence
and preserve unavailable fields as null.

Tests require Node.js in addition to Kujo. `KUJO=/path/to/source/kujo ./tests/run.sh` includes real CLI reference,
deduplication, tampering, version, oversized, path/symlink, privacy and null tests.
Watchdog's `tests/runtime_measurements_adapter_check.js --integration` runs the
actual measured workload, HTTP ingestion/restart and receipt correlation path.

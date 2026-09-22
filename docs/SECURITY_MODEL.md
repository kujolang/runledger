# RunLedger local security model

RunLedger is a single-operator, local filesystem tool. The operator chooses
the ledger and repository paths and controls who can read/write them. It does
not authenticate users, isolate tenants, encrypt receipts, redact secrets, or
enforce a shared-ledger access policy. Do not expose an untrusted writable
ledger or run the CLI as a network service. Locks prevent cooperative writers
from losing updates; they are not an authorization boundary.

## Data and boundaries

Run JSON may reveal prompt paths, repository paths and commits, model names,
verdicts, free-text notes, manually recorded commands/tests, costs, and token
usage. Avoid entering secrets in free text or command descriptions; commands
are recorded verbatim and never executed. `--repo` triggers read-only Git
subprocesses; only point it at repositories you trust. `--ledger` and
`RUNLEDGER_DIR` are operator-controlled write paths. Reports written with
`--output` are separate files and can be shared explicitly by the operator.

The POSIX `bin/runledger` launcher applies `umask 077`, so newly created
receipt files are owner-readable/writable and new ledger directories are
owner-accessible even if the invoking shell has a permissive umask. It does
not repair existing permissions or secure a preexisting parent directory.
When invoking `kujo run runledger.kujo -- ...` directly, set `umask 077` in
that shell first. Inspect permissions on existing ledgers before importing
private receipts. These defaults do not prevent the owner or privileged local
software from reading or replacing data.

## Operations and recovery

- Put the ledger in a private directory on a trusted local filesystem. Do not
  place it on a multi-user shared mount without an independently designed
  access policy; atomic rename/hard-link and ownership semantics must be
  verified for the chosen filesystem.
- For a consistent backup, stop all writers, copy the entire `.runledger/`
  directory (including `runs/` and any `locks/` entries), and verify the copy
  with `runledger verify --ledger <copy>`. Backups and retention remain the
  operator's responsibility; RunLedger has no automatic restore or purge.
- If an interrupted process leaves a lock, confirm no writer is active before
  removing only the named lock. Never automatically age out or delete another
  process's lock.
- Use `runledger verify` or `--strict` on `list`, `compare`, and `report` in
  automation that must fail on an invalid receipt. The default read behavior
  still skips malformed entries for compatibility.

Platform support currently centers on POSIX shells (macOS/Linux); the Bash
launcher and integration tests have not been validated for native Windows.
None of these operational controls is a multi-tenant or enterprise
certification.

#!/usr/bin/env bash
# Run the RunLedger test suite.
#
#   ./tests/run.sh
#   KUJO=/path/to/kujo/target/release/kujo ./tests/run.sh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUJO="${KUJO:-kujo}"

"$KUJO" run "$PROJECT_DIR/tests/runledger_test.kujo"
bash "$PROJECT_DIR/tests/cli_integration.sh"

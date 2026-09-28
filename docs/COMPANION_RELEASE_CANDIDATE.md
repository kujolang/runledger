# runledger 1.2.0 companion release candidate

Status: candidate, not published. No release tag created by this preparation.

## Runtime evidence

Validated locally with the published macOS x64 Kujo 1.6.0 binary:
`930e0da1fec2562f6990d1226a479330640c8c78eb4c36c148cee3f950b29a47`.
Its source is `44af277848173664f72ca85f2a1b3b98d634ecdd`.
This does not certify other platforms; hosted candidate checks must be inspected separately.

Local canonical gate passed: module tests, CLI integration and runtime-measurement reference regression. The measurement test now declares CommonJS via .cjs, so a parent package.json cannot change its module mode. New CI runs the canonical gate on Linux and macOS. RunLedger records evidence and declared outcomes; it does not authorize execution or verify effect truth.

## Release completion checklist

- Inspect hosted checks for the exact candidate commit.
- Verify clean source-archive consumption and package version consistency.
- Review the candidate changelog and turn its candidate heading into a release date only when publishing.
- Create an immutable tag at the tested final source; do not move an existing tag.
- Publish the GitHub source release and reconcile the Kennel index if this package is distributed there.
- Retain experimental contract labels. Do not publish the separate participant SDK packages.

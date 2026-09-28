# runledger 1.2.0 companion release candidate

Release preparation record. Publication is recorded by the immutable GitHub Release;
this document retains the pre-publication verification scope.

## Runtime evidence

Validated locally with the published macOS x64 Kujo 1.6.0 binary:
`930e0da1fec2562f6990d1226a479330640c8c78eb4c36c148cee3f950b29a47`.
Its source is `44af277848173664f72ca85f2a1b3b98d634ecdd`.
This does not certify other platforms; hosted candidate checks must be inspected separately.

Local canonical gate passed: module tests, CLI integration and runtime-measurement reference regression. The measurement test now declares CommonJS via .cjs, so a parent package.json cannot change its module mode. New CI runs the canonical gate on Linux and macOS. RunLedger records evidence and declared outcomes; it does not authorize execution or verify effect truth.

## Distribution and runtime support

This release supports Kujo 1.6.0 or newer; the package manifest and public
installation docs agree. Earlier runtime versions are not certified by this
release. The GitHub source release is reconciled by the central Kennel publisher;
old package archives remain immutable. Final hosted runs and installed-package
checks are retained in the release receipt, not inferred from historical tests.

# Support Policy

This document declares the supported release streams, support windows, security vulnerability reporting channels, and end-of-life and backport policies for `metanorma/metanorma` (`pkg:gem/metanorma`) in accordance with EU Cyber Resilience Act (CRA) Article 14.

## Supported Release Streams

Each release of `metanorma/metanorma` is supported for two years from its release date unless an explicit `support_until` date is supplied at release time. This two-year support window matches the default `support_until` configuration in `metanorma/ci` (`.github/workflows/rubygems-release.yml`) and `metanorma/metanorma`'s release workflow, which stamps the exact `YYYY-MM-DD` `support-until` date into each release's `lifecycle.json` asset and GitHub Release notes.

| Release Stream | Status | Latest Release | Support Until | Notes |
|---|---|---|---|---|
| `2.5.x` | Supported | `v2.5.25` (2026-11-19) | `2028-11-19` | Active maintenance stream; each release carries a two-year `support-until` date from its release date in `lifecycle.json`. |
| `2.4.x` and earlier | End of life | `v2.4.3` (2026-06-22) | Ended | Superseded by `2.5.x`; users must upgrade to the active `2.5.x` stream. |

## Security Vulnerability Reporting

Security vulnerabilities in `metanorma/metanorma` must not be reported in public GitHub issues. Reports submitted through public issue trackers are visible to everyone before a fix is available.

Security vulnerabilities in `metanorma/metanorma` must be reported through the Ribose security reporting channels documented at [https://cve.ribose.com](https://cve.ribose.com):

- Vulnerability reports are submitted through the [Ribose Security Feedback form](https://www.ribose.com/security/feedback) linked from [https://cve.ribose.com/feedback/](https://cve.ribose.com/feedback/).
- Responsible disclosure rules and scope are documented at [https://cve.ribose.com/cve-policy/](https://cve.ribose.com/cve-policy/).

Published advisories and machine-readable vulnerability feeds for `metanorma/metanorma` are hosted at [https://cve.ribose.com](https://cve.ribose.com):

- The machine-readable OSV feed is published at [https://cve.ribose.com/feeds/osv/metanorma.json](https://cve.ribose.com/feeds/osv/metanorma.json).
- The machine-readable GHSA feed is published at [https://cve.ribose.com/feeds/ghsa/metanorma.json](https://cve.ribose.com/feeds/ghsa/metanorma.json).
- The machine-readable CSAF 2.0 feed is published at [https://cve.ribose.com/feeds/csaf/metanorma.json](https://cve.ribose.com/feeds/csaf/metanorma.json).
- The machine-readable OpenVEX feed is published at [https://cve.ribose.com/feeds/vex/metanorma.json](https://cve.ribose.com/feeds/vex/metanorma.json).

General bug reports and feature requests that do not involve security vulnerabilities should be filed in the public [GitHub issue tracker](https://github.com/metanorma/metanorma/issues).

## End-of-Life and Backport Policy

Only the current active minor release stream (`2.5.x`) receives bug fixes, dependency updates, and security patches. Once a new minor release stream is published, prior minor release streams are superseded and enter end-of-life status.

Security fixes and bug fixes are not backported to superseded minor release streams under normal circumstances. Users running an older release stream are expected to upgrade to the latest release on the active `2.5.x` stream to receive fixes.

When a release reaches its declared `support-until` date, it reaches end of life and receives no further security updates or maintenance releases. Consumers can inspect the exact `supportUntil` date, software bills of materials (`*.spdx.json` and `*.cdx.json`), license notices (`NOTICE`), and SLSA Build Level 3 attestation status for any release on the [Ribose Provenance portal](https://provenance.ribose.com) or by running `gh attestation verify <artifact> -R metanorma/metanorma`.

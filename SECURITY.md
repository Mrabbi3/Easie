# Security policy

## Supported versions

Only the latest release of Easie gets security fixes. Download it from
https://mrabbi3.github.io/Easie/ or the [releases page](https://github.com/Mrabbi3/Easie/releases/latest).

## Reporting a vulnerability

Please report security problems privately, not in a public issue:

1. Open the [Security tab](https://github.com/Mrabbi3/Easie/security) of this repository.
2. Click **Report a vulnerability** and describe the problem, the Easie and macOS versions,
   and a sample file or steps that show it, if you have one.

You'll get a reply within a few days. Once a fix is released, the report is published with
credit to you, unless you'd rather stay anonymous.

## Verifying your download

Each release lists the SHA-256 checksum of `Easie.dmg` on the download page. To check yours:

```bash
shasum -a 256 ~/Downloads/Easie.dmg
```

The result must match the checksum on the page exactly.

## What Easie does to stay safe

- It never connects to the internet; web pages are cleaned of scripts, trackers and remote content before conversion.
- It only writes new files and never overwrites existing ones.
- It refuses hostile files (oversized ZIP parts, huge images, deeply nested JSON) instead of crashing.
- `scripts/security-test.sh` runs these checks against booby-trapped files before every release.

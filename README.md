# Wikipedia ZIM Backup (Kiwix)

Fetches the latest `wikipedia_en_all_maxi_latest.zim` from Kiwix mirrors, verifies the SHA256, and keeps a small rotation of dated copies. Maintains a stable `*_current.zim` symlink.

## Why
- The `*_latest.zim` URL redirects to the current dated file (e.g., `..._2025-08.zim`).
- This script resolves that redirect, downloads the dated file (resumable), verifies it via `*.sha256`, and prunes old versions.

## Requirements
- `bash`, `curl`, `sha256sum`, `awk`, `ln`, `rm`
- (Optional) `systemd` for timer; otherwise use `cron`.

## Quick Start

```bash
git clone <your-repo-url> wikipedia-zim-backup
cd wikipedia-zim-backup
cp .env.example .env  # optional
./backup-wikipedia-zim.sh

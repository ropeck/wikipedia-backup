# Wikipedia ZIM Backup (Kiwix)

A robust Bash script to fetch and verify the latest `wikipedia_en_all_maxi_*.zim`.
Handles mirrors that 404 on HEAD by parsing the directory listing.

## Quick start
```bash
chmod +x backup-wikipedia-zim-backup.sh
./backup-wikipedia-zim-backup.sh
```

Defaults:
- DEST_DIR=/media/fogcat5/MEDIA/wikipedia
- KEEP_VERSIONS=4
- GRAB_TORRENT=1

Override in `.env` or via exported env vars.

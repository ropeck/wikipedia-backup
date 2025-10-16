# Wikipedia ZIM Backup (Kiwix)
A simple Bash script to download and verify the latest `wikipedia_en_all_maxi_latest.zim`
from the Kiwix mirror, maintain a few old versions, and keep a `current.zim` symlink.

## Usage
```bash
./backup-wikipedia-zim.sh
```

## Configuration
Defaults:
- DEST_DIR=/media/fogcat5/MEDIA/wikipedia
- KEEP_VERSIONS=4
- GRAB_TORRENT=1

Override in `.env` or via environment variables.

## Cron Example
Run weekly at 3:15 AM Sunday:
```
15 3 * * 0 /path/to/backup-wikipedia-zim.sh >> /var/log/wikipedia-zim.log 2>&1
```

## License
MIT

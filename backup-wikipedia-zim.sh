#!/usr/bin/env bash
# Purpose: Download and verify latest Wikipedia ZIM ("wikipedia_en_all_maxi_latest.zim"),
#          keep N versions, maintain 'current.zim' symlink, and optional .torrent.
# Robust "latest" resolution supporting mirrors that 404 on HEAD, by parsing directory listing.
# Usage:   ./backup-wikipedia-zim-backup.sh
# Env:     override via .env or environment variables.

set -euo pipefail

: "${DEST_DIR:=/media/fogcat5/MEDIA/wikipedia}"
: "${EDITION:=wikipedia_en_all_maxi}"
: "${MIRROR:=https://download.kiwix.org/zim/wikipedia}"
: "${FALLBACK_MIRROR:=https://mirror.download.kiwix.org/zim/wikipedia}"
: "${KEEP_VERSIONS:=4}"
: "${GRAB_TORRENT:=1}"
: "${CURL_OPTS:=-L --fail --retry 5 --retry-delay 5 --connect-timeout 30}"

log() { printf '[%(%Y-%m-%d %H:%M:%S)T] %s
' -1 "$*"; }

ensure_dest() { [[ -d "$DEST_DIR" ]] || mkdir -p "$DEST_DIR"; }

# Try to resolve the real dated filename eg: ${EDITION}_2025-08.zim
# Strategy:
#   1) Try GET with -L and capture effective URL (some servers 404 on HEAD).
#   2) If that fails, fetch directory listing and pick the newest ${EDITION}_*.zim by version sort.
resolve_latest_from_base() {
  local base="$1"
  local latest_url="${base}/${EDITION}_latest.zim"
  # Attempt to follow redirects and print effective URL without downloading
  if final="$(curl $CURL_OPTS -sS -o /dev/null -w '%{url_effective}' "$latest_url")"; then
    # If server didn't redirect, url_effective == request URL; still OK if file exists.
    if curl $CURL_OPTS -I -sS "$final" >/dev/null; then
      echo "$final"
      return 0
    fi
  fi

  # Fallback: parse directory listing
  # Grep all dated ZIMs like ${EDITION}_YYYY-MM.zim, sort -V, choose latest.
  if html="$(curl -sS "${base}/")"; then
    # Extract candidates
    mapfile -t candidates < <(printf '%s' "$html" | grep -Eo "${EDITION}_[0-9]{4}-[0-9]{2}\.zim" | sort -u -V)
    if [[ ${#candidates[@]} -gt 0 ]]; then
      local latest_fname="${candidates[-1]}"
      echo "${base}/${latest_fname}"
      return 0
    fi
  fi
  return 1
}

resolve_latest_url() {
  # Try primary then fallback
  if url="$(resolve_latest_from_base "$MIRROR")"; then
    echo "$url"; return 0
  fi
  log "Primary mirror failed to resolve; trying fallback…"
  if url="$(resolve_latest_from_base "$FALLBACK_MIRROR")"; then
    echo "$url"; return 0
  fi
  return 1
}

download_file() { curl $CURL_OPTS -C - -o "$2" "$1"; }

sha256_verify() {
  local want have
  want="$(awk '{print $1; exit}' "$2")"
  have="$(sha256sum "$1" | awk '{print $1}')"
  [[ "$want" == "$have" ]]
}

prune_old_versions() {
  mapfile -t files < <(ls -1t "$DEST_DIR"/${EDITION}_*.zim 2>/dev/null || true)
  (( ${#files[@]} <= KEEP_VERSIONS )) && return 0
  for ((i=KEEP_VERSIONS; i<${#files[@]}; i++)); do
    rm -f "${files[$i]}" "${files[$i]}.sha256" "${files[$i]}.torrent" 2>/dev/null || true
    log "Pruned $(basename "${files[$i]}")"
  done
}

main() {
  ensure_dest
  log "Resolving latest URL…"
  local final_url
  if ! final_url="$(resolve_latest_url)"; then
    log "ERROR: Could not resolve latest ZIM URL from mirrors."
    exit 2
  fi

  local fname="${final_url##*/}"
  local base="${fname%.zim}"
  local sha_url="${final_url%.zim}.sha256"
  local tor_url="${final_url%.zim}.torrent"
  local dst_file="$DEST_DIR/$fname"
  local dst_tmp="$dst_file.part"
  local dst_sha="$DEST_DIR/${base}.zim.sha256"
  local dst_tor="$DEST_DIR/${base}.zim.torrent"

  if [[ -f "$dst_file" ]]; then
    log "Already present: $fname"
  else
    log "Downloading $fname…"
    download_file "$final_url" "$dst_tmp"
    log "Downloading SHA256…"
    download_file "$sha_url" "$dst_sha"
    log "Verifying SHA256…"
    if sha256_verify "$dst_tmp" "$dst_sha"; then
      mv "$dst_tmp" "$dst_file"
      log "Verified and saved $fname"
    else
      rm -f "$dst_tmp"
      log "Verification failed!"
      exit 3
    fi
  fi

  if [[ "$GRAB_TORRENT" -eq 1 ]]; then
    curl $CURL_OPTS -sSf -o "$dst_tor" "$tor_url" || log "Torrent not available; continuing."
  fi

  ln -sfn "$fname" "$DEST_DIR/${EDITION}_current.zim"
  prune_old_versions
  log "Done."
}

main "$@"

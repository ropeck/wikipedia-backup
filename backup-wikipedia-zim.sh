#!/usr/bin/env bash
# Purpose: Download and verify latest Wikipedia ZIM ("wikipedia_en_all_maxi_latest.zim"),
#          keep N versions, maintain 'current.zim' symlink, and optional .torrent.
# Usage:   ./backup-wikipedia-zim.sh
# Env:     See defaults below; override via .env or environment.

set -euo pipefail

########################
# Config (defaults)
########################
: "${DEST_DIR:=/media/fogcat5/MEDIA/wikipedia}"     # where .zim files live
: "${EDITION:=wikipedia_en_all_maxi}"               # Kiwix 'edition' base name
: "${MIRROR:=https://download.kiwix.org/zim/wikipedia}"  # primary mirror
: "${FALLBACK_MIRROR:=https://mirror.download.kiwix.org/zim/wikipedia}" # fallback
: "${KEEP_VERSIONS:=4}"                             # how many dated copies to keep
: "${GRAB_TORRENT:=1}"                              # 1=yes, 0=no
: "${CURL_OPTS:=-L --fail --retry 5 --retry-delay 5 --connect-timeout 30}"
: "${DRY_RUN:=0}"                                   # 1 = don't modify filesystem
: "${LOG_TS:=1}"                                    # log with timestamps

# Load optional overrides from ./.env or $XDG_CONFIG_HOME/wikipedia-zim-backup/.env
load_env() {
  local paths=(
    "./.env"
    "${XDG_CONFIG_HOME:-$HOME/.config}/wikipedia-zim-backup/.env"
  )
  for f in "${paths[@]}"; do
    [[ -f "$f" ]] && set -a && source "$f" && set +a
  done
}
load_env

log() {
  if [[ "$LOG_TS" -eq 1 ]]; then
    printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"
  else
    echo "$*"
  fi
}

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "DRY-RUN: $*"
  else
    eval "$@"
  fi
}

ensure_dest() {
  [[ -d "$DEST_DIR" ]] || run "mkdir -p '$DEST_DIR'"
}

# Resolve the "latest" redirect to the concrete dated filename (e.g., wikipedia_en_all_maxi_2025-08.zim)
resolve_latest_url() {
  local base="$1"
  local latest="${base}/${EDITION}_latest.zim"
  # Use curl to follow redirects and print final URL
  curl $CURL_OPTS -sSI "$latest" | awk '/^location:/I{print $2}' | tail -n1 | tr -d '\r'
}

download_file() {
  local url="$1" out="$2"
  # resume if partially downloaded
  run "curl $CURL_OPTS -C - -o '$out' '$url'"
}

sha256_verify() {
  local file="$1" sha_file="$2"
  # Normalize sha file to "HASH  FILENAME" if needed
  # Many kiwix *.sha256 files contain just the hash; handle both styles
  local want have
  want="$(awk '{print $1; exit}' "$sha_file")"
  have="$(sha256sum "$file" | awk '{print $1}')"
  if [[ "$want" != "$have" ]]; then
    log "ERROR: SHA256 mismatch for $(basename "$file")"
    log "       expected: $want"
    log "       actual  : $have"
    return 1
  fi
  return 0
}

prune_old_versions() {
  local pattern="${EDITION}_*.zim"
  local keep="$KEEP_VERSIONS"
  mapfile -t files < <(ls -1t "$DEST_DIR"/$pattern 2>/dev/null || true)
  (( ${#files[@]} <= keep )) && return 0
  for ((i=keep; i<${#files[@]}; i++)); do
    run "rm -f '${files[$i]}' '${files[$i]}.sha256' '${files[$i]}.torrent' 2>/dev/null || true"
    log "Pruned $(basename "${files[$i]}")"
  done
}

main() {
  ensure_dest

  # Prefer primary mirror; fall back if it fails to resolve
  log "Resolving latest URL from primary mirror…"
  local final_url
  if ! final_url="$(resolve_latest_url "$MIRROR")" || [[ -z "$final_url" ]]; then
    log "Primary failed; trying fallback mirror…"
    final_url="$(resolve_latest_url "$FALLBACK_MIRROR")"
  fi

  if [[ -z "$final_url" ]]; then
    log "ERROR: Could not resolve latest ZIM URL from mirrors."
    exit 2
  fi

  local fname="${final_url##*/}"                 # e.g., wikipedia_en_all_maxi_2025-08.zim
  local base="${fname%.zim}"                     # e.g., wikipedia_en_all_maxi_2025-08
  local url_dir="${final_url%/*}"
  local sha_url="${url_dir}/${base}.zim.sha256"
  local tor_url="${url_dir}/${base}.zim.torrent"

  log "Latest file: $fname"
  log "From: $url_dir"

  local dst_file="$DEST_DIR/$fname"
  local dst_tmp="$dst_file.part"
  local dst_sha="$DEST_DIR/${base}.zim.sha256"
  local dst_tor="$DEST_DIR/${base}.zim.torrent"

  # Skip if we already have the full, verified file
  if [[ -f "$dst_file" ]]; then
    log "Already present: $fname (skipping download)."
  else
    log "Downloading ZIM (resumable)…"
    download_file "$final_url" "$dst_tmp"

    log "Downloading SHA256…"
    download_file "$sha_url" "$dst_sha"

    log "Verifying SHA256…"
    if sha256_verify "$dst_tmp" "$dst_sha"; then
      run "mv '$dst_tmp' '$dst_file'"
      log "Verified and moved into place: $fname"
    else
      run "rm -f '$dst_tmp'"
      log "ERROR: Verification failed. Partial file removed."
      exit 3
    fi
  fi

  # Optional torrent sidecar (useful if you prefer seeding later)
  if [[ "$GRAB_TORRENT" -eq 1 ]]; then
    log "Fetching .torrent (optional)…"
    # Don’t fail the whole run if torrent fetch fails
    if curl $CURL_OPTS -sSf -o "$dst_tor" "$tor_url"; then
      log "Saved: $(basename "$dst_tor")"
    else
      log "Note: torrent not available (or fetch failed)."
    fi
  fi

  # Maintain a stable 'current.zim' symlink
  local current_link="$DEST_DIR/${EDITION}_current.zim"
  if [[ -L "$current_link" || -e "$current_link" ]]; then
    run "rm -f '$current_link'"
  fi
  run "ln -s '$fname' '$current_link'"
  log "Updated symlink: $(basename "$current_link") -> $fname"

  # Prune old versions
  prune_old_versions

  log "Done."
}

main "$@"

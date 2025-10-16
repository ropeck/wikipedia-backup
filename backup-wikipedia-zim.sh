#!/usr/bin/env bash
# Purpose: Download and verify latest Wikipedia ZIM ("wikipedia_en_all_maxi_latest.zim"),
#          keep N versions, maintain 'current.zim' symlink, and optional .torrent.
# Usage:   ./backup-wikipedia-zim.sh
# Env:     See defaults below; override via .env or environment.

set -euo pipefail
: "${DEST_DIR:=/media/fogcat5/MEDIA/wikipedia}"
: "${EDITION:=wikipedia_en_all_maxi}"
: "${MIRROR:=https://download.kiwix.org/zim/wikipedia}"
: "${FALLBACK_MIRROR:=https://mirror.download.kiwix.org/zim/wikipedia}"
: "${KEEP_VERSIONS:=4}"
: "${GRAB_TORRENT:=1}"
: "${CURL_OPTS:=-L --fail --retry 5 --retry-delay 5 --connect-timeout 30}"

log() { printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"; }

ensure_dest() { [[ -d "$DEST_DIR" ]] || mkdir -p "$DEST_DIR"; }

resolve_latest_url() {
  local latest="${MIRROR}/${EDITION}_latest.zim"
  curl $CURL_OPTS -sSI "$latest" | awk '/^location:/I{print $2}' | tail -n1 | tr -d '\r'
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
  final_url="$(resolve_latest_url)" || exit 1
  [[ -z "$final_url" ]] && { log "Could not resolve URL."; exit 2; }

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
    curl $CURL_OPTS -sSf -o "$dst_tor" "$tor_url" || true
  fi

  ln -sf "$fname" "$DEST_DIR/${EDITION}_current.zim"
  prune_old_versions
  log "Done."
}

main "$@"

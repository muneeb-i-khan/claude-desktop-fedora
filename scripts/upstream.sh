#!/usr/bin/env bash
# Query and download Claude Desktop from Anthropic's official apt repository,
# verifying the whole trust chain on the way:
#
#   pinned key fingerprint -> InRelease signature -> Packages sha256 -> .deb sha256
#
# Usage:
#   upstream.sh versions <amd64|arm64>              all published versions, ascending
#   upstream.sh latest   <amd64|arm64>              newest version
#   upstream.sh common                              newest version published for BOTH arches
#   upstream.sh fetch    <amd64|arm64> <outdir> [version]
#                                                   download + verify the .deb (default: newest)
#
# Requires: bash, curl, gpg, gpgv (Fedora: gnupg2), awk, sha256sum, sort -V.
set -euo pipefail

BASE_URL="${CLAUDE_APT_BASE:-https://downloads.claude.ai/claude-desktop}"
REPO_URL="$BASE_URL/apt/stable"
# Anthropic Claude Code Release Signing <security@anthropic.com>. This is the
# fingerprint Anthropic documents for the Claude Desktop apt repository.
EXPECTED_FPR="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"

die() { echo "upstream.sh: $*" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
GNUPGHOME="$WORK/gnupg"
export GNUPGHOME
mkdir -m 700 "$GNUPGHOME"

get() { curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$2" "$1"; }

check_arch() {
  case "${1:-}" in amd64 | arm64) ;; *) die "architecture must be amd64 or arm64 (got '${1:-}')" ;; esac
}

# Download the signing key and refuse to continue unless its primary
# fingerprint is exactly the pinned one.
import_key() {
  get "$BASE_URL/key.asc" "$WORK/key.asc"
  gpg --batch --quiet --import "$WORK/key.asc" 2>/dev/null
  local fprs
  fprs="$(gpg --batch --with-colons --fingerprint | awk -F: '$1 == "pub" {p=1; next} p && $1 == "fpr" {print $10; p=0}')"
  [ "$fprs" = "$EXPECTED_FPR" ] ||
    die "signing key fingerprint mismatch: expected $EXPECTED_FPR, got '${fprs:-none}'"
  gpg --batch --export >"$WORK/keyring.gpg"
}

# Verify InRelease against the pinned key and refuse an expired one
# (a stale mirror/replay protection).
fetch_release() {
  [ -s "$WORK/Release" ] && return 0
  import_key
  get "$REPO_URL/dists/stable/InRelease" "$WORK/InRelease"
  gpgv --quiet --homedir "$GNUPGHOME" --keyring "$WORK/keyring.gpg" \
    --output "$WORK/Release" "$WORK/InRelease" 2>"$WORK/gpgv.log" ||
    die "InRelease signature verification FAILED: $(cat "$WORK/gpgv.log")"
  local valid_until
  valid_until="$(sed -n 's/^Valid-Until: //p' "$WORK/Release")"
  if [ -n "$valid_until" ] && [ "$(date -d "$valid_until" +%s)" -lt "$(date +%s)" ]; then
    die "InRelease expired on $valid_until"
  fi
}

# Print "version filename sha256 size" for every claude-desktop stanza in the
# hash-verified Packages index for $1.
index() {
  local arch="$1" rel="main/binary-$1/Packages" want_sha want_size
  fetch_release
  read -r want_sha want_size < <(awk -v p="$rel" '
    /^SHA256:/ {f=1; next} /^[^ ]/ {f=0} f && $3 == p {print $1, $2; exit}' "$WORK/Release")
  [ -n "${want_sha:-}" ] || die "Packages index for $arch not listed in signed Release"
  get "$REPO_URL/dists/stable/$rel" "$WORK/Packages.$arch"
  [ "$(stat -c %s "$WORK/Packages.$arch")" = "$want_size" ] || die "Packages ($arch) size mismatch"
  [ "$(sha256sum "$WORK/Packages.$arch" | cut -d' ' -f1)" = "$want_sha" ] ||
    die "Packages ($arch) sha256 does not match signed Release"
  awk -v RS= -F'\n' '
    {
      pkg = ver = file = sha = size = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^Package: /)  pkg  = substr($i, 10)
        if ($i ~ /^Version: /)  ver  = substr($i, 10)
        if ($i ~ /^Filename: /) file = substr($i, 11)
        if ($i ~ /^SHA256: /)   sha  = substr($i, 9)
        if ($i ~ /^Size: /)     size = substr($i, 7)
      }
      if (pkg == "claude-desktop" && ver != "") print ver, file, sha, size
    }' "$WORK/Packages.$arch" | sort -V -k1,1
}

cmd="${1:-}"
case "$cmd" in
  versions)
    check_arch "${2:-}"
    index "$2" | cut -d' ' -f1
    ;;
  latest)
    check_arch "${2:-}"
    index "$2" | cut -d' ' -f1 | tail -n1
    ;;
  common)
    comm -12 <(index amd64 | cut -d' ' -f1 | sort) <(index arm64 | cut -d' ' -f1 | sort) |
      sort -V | tail -n1
    ;;
  fetch)
    check_arch "${2:-}"
    [ -n "${3:-}" ] || die "usage: upstream.sh fetch <arch> <outdir> [version]"
    arch="$2" outdir="$3" version="${4:-}"
    if [ -n "$version" ]; then
      line="$(index "$arch" | awk -v v="$version" '$1 == v {print; exit}')"
    else
      line="$(index "$arch" | tail -n1)"
    fi
    [ -n "$line" ] || die "version '${version:-latest}' not found for $arch"
    read -r ver file sha size <<<"$line"
    mkdir -p "$outdir"
    dest="$outdir/claude-desktop_${ver}_${arch}.deb"
    echo "Downloading $file ($size bytes)" >&2
    get "$REPO_URL/$file" "$dest.part"
    [ "$(stat -c %s "$dest.part")" = "$size" ] || die "deb size mismatch"
    [ "$(sha256sum "$dest.part" | cut -d' ' -f1)" = "$sha" ] || die "deb sha256 mismatch"
    mv "$dest.part" "$dest"
    echo "Verified $dest (sha256 $sha)" >&2
    echo "$dest"
    ;;
  *)
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
    ;;
esac

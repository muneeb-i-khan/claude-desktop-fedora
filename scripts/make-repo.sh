#!/usr/bin/env bash
# Assemble the static DNF repository site published on GitHub Pages.
#
# Usage: scripts/make-repo.sh <rpm-dir> <site-dir> <owner/repo>
#
# Layout:  <site>/rpm/<arch>/{*.rpm,repodata/}
#          <site>/claude-desktop.repo
#          <site>/RPM-GPG-KEY-claude-desktop-fedora   (only when signing)
#
# Signing is optional: set RPM_GPG_KEY_ID (key already in the gpg keyring) and
# the metadata is signed and the .repo file enables gpgcheck/repo_gpgcheck.
#
# Needs: createrepo_c, and gnupg2 when signing.
set -euo pipefail

RPM_DIR="${1:?usage: make-repo.sh <rpm-dir> <site-dir> <owner/repo>}"
SITE="${2:?}"
SLUG="${3:?}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OWNER="${SLUG%%/*}"
REPO="${SLUG##*/}"
BASEURL="https://${OWNER,,}.github.io/${REPO}/rpm/\$basearch"

rm -rf "$SITE"
mkdir -p "$SITE/rpm"

for arch in x86_64 aarch64; do
  shopt -s nullglob
  rpms=("$RPM_DIR"/*."$arch".rpm)
  shopt -u nullglob
  [ "${#rpms[@]}" -gt 0 ] || { echo "no $arch rpm found, skipping" >&2; continue; }
  mkdir -p "$SITE/rpm/$arch"
  cp "${rpms[@]}" "$SITE/rpm/$arch/"
  createrepo_c --quiet --general-compress-type zstd "$SITE/rpm/$arch"
  if [ -n "${RPM_GPG_KEY_ID:-}" ]; then
    gpg --batch --yes --armor --detach-sign -u "$RPM_GPG_KEY_ID" \
      -o "$SITE/rpm/$arch/repodata/repomd.xml.asc" "$SITE/rpm/$arch/repodata/repomd.xml"
  fi
done

if [ -n "${RPM_GPG_KEY_ID:-}" ]; then
  gpg --batch --yes --armor --export "$RPM_GPG_KEY_ID" >"$SITE/RPM-GPG-KEY-claude-desktop-fedora"
  GPGCHECK=1
  GPGKEY="gpgkey=https://${OWNER,,}.github.io/${REPO}/RPM-GPG-KEY-claude-desktop-fedora"
else
  GPGCHECK=0
  GPGKEY="# Packages are unsigned: integrity rests on HTTPS and on the checks run at build time."
fi

sed -e "s|@BASEURL@|$BASEURL|g" \
  -e "s|@GPGCHECK@|$GPGCHECK|g" \
  -e "s|@GPGKEY@|$GPGKEY|g" \
  "$ROOT/packaging/claude-desktop.repo.in" >"$SITE/claude-desktop.repo"

cat >"$SITE/index.html" <<EOF
<!doctype html>
<meta charset="utf-8">
<title>Claude Desktop for Fedora (unofficial)</title>
<h1>Claude Desktop for Fedora (unofficial)</h1>
<p>Unofficial RPM repository. Claude Desktop is proprietary software owned by Anthropic.</p>
<pre>sudo dnf config-manager addrepo --from-repofile=https://${OWNER,,}.github.io/${REPO}/claude-desktop.repo
sudo dnf install claude-desktop</pre>
<p><a href="https://github.com/${SLUG}">Project page</a></p>
EOF

echo "Repository written to $SITE"

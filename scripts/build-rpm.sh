#!/usr/bin/env bash
# Download + verify the upstream .deb and build the RPM for the current machine.
#
# Usage: scripts/build-rpm.sh [version]      (default: newest upstream version)
# Output: dist/claude-desktop-<version>-<release>.<arch>.rpm
#
# Needs: rpm-build binutils tar xz zstd desktop-file-utils gnupg2 curl gawk
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-}"

case "$(uname -m)" in
  x86_64) DEBARCH=amd64 ;;
  aarch64) DEBARCH=arm64 ;;
  *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

TOP="$ROOT/build/rpmbuild"
rm -rf "$TOP"
mkdir -p "$TOP"/{SOURCES,SPECS,BUILD,BUILDROOT,RPMS,SRPMS} "$ROOT/dist"

deb="$("$ROOT/scripts/upstream.sh" fetch "$DEBARCH" "$TOP/SOURCES" ${VERSION:+"$VERSION"})"
VERSION="$(basename "$deb" | sed -E 's/^claude-desktop_(.+)_(amd64|arm64)\.deb$/\1/')"
cp "$ROOT/packaging/claude-desktop-wrapper.sh" "$TOP/SOURCES/"

rpmbuild -bb "$ROOT/packaging/claude-desktop.spec" \
  --define "_topdir $TOP" \
  --define "upstream_version $VERSION" \
  ${PKG_RELEASE:+--define "pkg_release $PKG_RELEASE"}

find "$TOP/RPMS" -name '*.rpm' -exec cp -v {} "$ROOT/dist/" \;

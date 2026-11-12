#!/bin/bash
# Launcher for Claude Desktop (unofficial Fedora packaging).
#
# On a Wayland session this adds the Ozone/Wayland flags so Electron runs as a
# native Wayland client instead of going through XWayland.
#
# Overrides:
#   CLAUDE_USE_X11=1                       force X11/XWayland, add no flags
#   --ozone-platform[-hint]=...            any such flag you pass is respected
#   ${XDG_CONFIG_HOME:-~/.config}/claude-desktop-flags.conf
#                                          extra flags, one or more per line,
#                                          '#' starts a comment
set -u

APP=/usr/lib/claude-desktop/claude-desktop

flags=()

# Extra user flags (kept simple: whitespace-separated, no shell expansion).
conf="${XDG_CONFIG_HOME:-$HOME/.config}/claude-desktop-flags.conf"
if [ -r "$conf" ]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    # shellcheck disable=SC2206 # word splitting is intended
    [ -n "${line//[[:space:]]/}" ] && flags+=($line)
  done <"$conf"
fi

user_set_ozone=0
user_set_features=0
for arg in "${flags[@]}" "$@"; do
  case "$arg" in
    --ozone-platform=* | --ozone-platform-hint=*) user_set_ozone=1 ;;
    --enable-features=*) user_set_features=1 ;;
    *) ;;
  esac
done

if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] \
  && [ "${CLAUDE_USE_X11:-0}" != "1" ] \
  && [ "$user_set_ozone" = "0" ]; then
  inject=(--ozone-platform=wayland)
  [ "$user_set_features" = "0" ] && inject+=(--enable-features=UseOzonePlatform)
  flags=("${inject[@]}" "${flags[@]}")
fi

exec "$APP" "${flags[@]}" "$@"

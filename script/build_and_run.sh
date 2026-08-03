#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="ParaDict"
BUNDLE_ID="com.hiq.ParaDict"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/build/codex-derived-data"
BUILD_APP="$DERIVED_DATA_DIR/Build/Products/Debug/$APP_NAME.app"
INSTALL_APP="/Applications/$APP_NAME.app"
INSTALL_BINARY="$INSTALL_APP/Contents/MacOS/$APP_NAME"

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify)
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$ROOT_DIR/ParaDict.xcodeproj" \
  -scheme ParaDict \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

rm -rf "$INSTALL_APP"
/usr/bin/ditto "$BUILD_APP" "$INSTALL_APP"

open_app() {
  /usr/bin/open -n "$INSTALL_APP"
}

verify_installed_process() {
  local running_path
  sleep 1
  running_path="$(
    pgrep -x "$APP_NAME" \
      | head -n 1 \
      | xargs -I '{}' sh -c 'lsof -p "$1" 2>/dev/null | awk '\''$4 == "txt" { print $9; exit }'\''' _ '{}'
  )"

  if [[ "$running_path" != "$INSTALL_BINARY" ]]; then
    echo "Expected $INSTALL_BINARY to be running, found: ${running_path:-nothing}" >&2
    exit 1
  fi
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$INSTALL_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    verify_installed_process
    ;;
esac

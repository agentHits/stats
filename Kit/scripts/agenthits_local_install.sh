#!/bin/bash
set -euo pipefail

SOURCE_APP=""
DESTINATION_APP="/Applications/Stats AgentHits.app"
BUNDLE_ID="eu.exelban.Stats.AgentHits"
BUNDLE_NAME="Stats AgentHits"
DRY_RUN=0
LAUNCH_APP=1

usage() {
  cat <<'EOF'
Usage:
  Kit/scripts/agenthits_local_install.sh --source /path/to/Stats.app [options]

Options:
  --source PATH        Built Stats.app bundle to install as Stats AgentHits.app.
  --destination PATH   Destination app bundle. Default: /Applications/Stats AgentHits.app.
  --bundle-id ID       Bundle identifier. Default: eu.exelban.Stats.AgentHits.
  --bundle-name NAME   Bundle name/display name. Default: Stats AgentHits.
  --no-launch          Install and sign without launching the app.
  --dry-run            Validate and print actions without copying, signing, defaults, or launch.
  --self-test          Run dry-run safety tests.
  -h, --help           Show this help.
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

plist_set_or_add() {
  local key="$1"
  local value="$2"
  local plist="$DESTINATION_APP/Contents/Info.plist"

  if /usr/libexec/PlistBuddy -c "Print :$key" "$plist" >/dev/null 2>&1; then
    run /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist"
  else
    run /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist"
  fi
}

make_fake_app() {
  local app="$1"
  mkdir -p "$app/Contents/MacOS"
  cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
EOF
  touch "$app/Contents/MacOS/Stats"
}

self_test() {
  local tmpdir
  tmpdir="$(mktemp -d /tmp/agenthits-local-install.XXXXXX)"
  trap "rm -rf '$tmpdir'" EXIT

  make_fake_app "$tmpdir/Stats.app"
  mkdir -p "$tmpdir/dest"

  "$0" --source "$tmpdir/Stats.app" --destination "$tmpdir/dest/Stats AgentHits.app" --dry-run --no-launch >/dev/null

  if "$0" --source "$tmpdir/Stats.app" --destination /Applications/Stats.app --dry-run --no-launch >/dev/null 2>&1; then
    die "self-test expected /Applications/Stats.app refusal"
  fi

  if "$0" --source "$tmpdir/Stats.app" --destination "$tmpdir/dest/Stats.app" --dry-run --no-launch >/dev/null 2>&1; then
    die "self-test expected Stats.app basename refusal"
  fi

  if "$0" --source "$tmpdir/Stats.app" --destination /Applications --dry-run --no-launch >/dev/null 2>&1; then
    die "self-test expected /Applications directory refusal"
  fi

  if "$0" --source "$tmpdir/Stats.app" --destination /Applications/ --dry-run --no-launch >/dev/null 2>&1; then
    die "self-test expected /Applications/ directory refusal"
  fi

  if "$0" --source "$tmpdir/Stats.app" --destination "$tmpdir/dest/not-an-app" --dry-run --no-launch >/dev/null 2>&1; then
    die "self-test expected non-.app destination refusal"
  fi

  if "$0" --source "$tmpdir/Stats.app" --destination "$tmpdir/dest/Personal Stats.app" --dry-run --no-launch >/dev/null 2>&1; then
    die "self-test expected non-AgentHits destination refusal"
  fi

  if "$0" --source "$tmpdir/Stats.app" --destination "$tmpdir/dest/Stats AgentHits.app" --bundle-id eu.exelban.Stats --dry-run --no-launch >/dev/null 2>&1; then
    die "self-test expected non-AgentHits bundle id refusal"
  fi

  "$0" --source "$tmpdir/Stats.app" --destination "$tmpdir/dest/Stats AgentHits.app" --no-launch >/dev/null
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$tmpdir/dest/Stats AgentHits.app/Contents/Info.plist")" == "eu.exelban.Stats.AgentHits" ]] || die "self-test expected AgentHits bundle id"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$tmpdir/dest/Stats AgentHits.app/Contents/Info.plist")" == "Stats AgentHits" ]] || die "self-test expected AgentHits bundle name"
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$tmpdir/dest/Stats AgentHits.app/Contents/Info.plist")" == "Stats AgentHits" ]] || die "self-test expected AgentHits display name"

  echo "AgentHits local install self-tests passed."
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE_APP="$2"
      shift
      ;;
    --destination)
      DESTINATION_APP="$2"
      shift
      ;;
    --bundle-id)
      BUNDLE_ID="$2"
      shift
      ;;
    --bundle-name)
      BUNDLE_NAME="$2"
      shift
      ;;
    --no-launch)
      LAUNCH_APP=0
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --self-test)
      self_test
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
  shift
done

[[ -n "$SOURCE_APP" ]] || die "--source is required"
[[ -d "$SOURCE_APP" ]] || die "source app does not exist: $SOURCE_APP"
[[ -f "$SOURCE_APP/Contents/Info.plist" ]] || die "source is not a macOS app bundle: $SOURCE_APP"
[[ -f "$SOURCE_APP/Contents/MacOS/Stats" ]] || die "source app has no Stats executable: $SOURCE_APP"

SOURCE_APP="$(cd "$(dirname "$SOURCE_APP")" && pwd)/$(basename "$SOURCE_APP")"
DEST_PARENT="$(dirname "$DESTINATION_APP")"
DEST_BASENAME="$(basename "$DESTINATION_APP")"
DEST_PARENT="$(cd "$DEST_PARENT" && pwd)"
DESTINATION_APP="$DEST_PARENT/$DEST_BASENAME"

[[ "$DESTINATION_APP" != "/Applications/Stats.app" ]] || die "refusing to overwrite official /Applications/Stats.app"
[[ "$DESTINATION_APP" != "/Applications" ]] || die "destination must be an AgentHits .app bundle, not /Applications"
[[ "$DEST_BASENAME" != "Stats.app" ]] || die "destination bundle must not be named Stats.app"
[[ "$DEST_BASENAME" == *.app ]] || die "destination must end with .app"
[[ "$DEST_BASENAME" == *"AgentHits"* ]] || die "destination bundle name must visibly contain AgentHits"
[[ "$SOURCE_APP" != "$DESTINATION_APP" ]] || die "source and destination must differ"
[[ "$BUNDLE_ID" == *".AgentHits" ]] || die "bundle id must be AgentHits-specific"
[[ "$BUNDLE_NAME" == *"AgentHits"* ]] || die "bundle name must visibly contain AgentHits"

if pgrep -f "$DESTINATION_APP/Contents/MacOS/Stats" >/dev/null 2>&1; then
  run pkill -f "$DESTINATION_APP/Contents/MacOS/Stats"
fi

run rm -rf "$DESTINATION_APP"
run ditto "$SOURCE_APP" "$DESTINATION_APP"

plist_set_or_add "CFBundleIdentifier" "$BUNDLE_ID"
plist_set_or_add "CFBundleName" "$BUNDLE_NAME"
plist_set_or_add "CFBundleDisplayName" "$BUNDLE_NAME"

run codesign --force --deep --sign - "$DESTINATION_APP"
run codesign --verify --deep --strict "$DESTINATION_APP"
run defaults write "$BUNDLE_ID" dockIcon -bool false

if [[ "$LAUNCH_APP" == "1" ]]; then
  run open "$DESTINATION_APP"
fi

echo "Stats AgentHits local install ready: $DESTINATION_APP"

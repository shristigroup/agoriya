#!/usr/bin/env bash
set -euo pipefail

# Build and (optionally) publish TrackFolks.
#
#   ./deploy.sh                       build iOS + Android, upload nothing
#   ./deploy.sh --upload              build both, upload iOS to App Store Connect
#                                     and Android to Google Play
#   ./deploy.sh --ios-only [--upload]       one platform only
#   ./deploy.sh --android-only [--upload]
#   --full-clean                      run `flutter clean` first
#   --rebuild                         ignore a previous build and build again
#
# Progress is tracked per platform in dist/.deploy_state (built / uploaded, keyed
# by version@commit). Re-running after a failed upload reuses the artifact that
# is already built and only uploads it. A build is reused only if it is the same
# version AND the same git commit with a clean working tree; otherwise it is
# rebuilt, so a stale binary can never be shipped.
#
# Android is an App Bundle (AAB) signed with the upload key — what Google Play
# takes. Uploads go to Play's internal testing track by default; any other track
# (PLAY_TRACK=production) is uploaded as a DRAFT so the rollout/review is still
# started by hand in Play Console. Credentials: see the checks below.

# ─── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Colour

info()    { echo -e "${BLUE}[deploy]${NC} $*"; }
success() { echo -e "${GREEN}[deploy]${NC} $*"; }
warn()    { echo -e "${YELLOW}[deploy]${NC} $*"; }
error()   { echo -e "${RED}[deploy]${NC} $*"; exit 1; }

# ─── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"
STATE_FILE="$DIST_DIR/.deploy_state"
TRACKING_ENV_FILE="$SCRIPT_DIR/functions/.env"

# ─── Tracking config (shared with Cloud Functions — see functions/.env.example) ──
# functions/.env is gitignored; fall back to the tracked example so a fresh
# clone can still build, and warn since that means defaults are in play.
if [[ ! -f "$TRACKING_ENV_FILE" ]]; then
  warn "functions/.env not found — using functions/.env.example defaults."
  warn "Copy functions/.env.example to functions/.env to customize tracking intervals."
  TRACKING_ENV_FILE="$SCRIPT_DIR/functions/.env.example"
fi

# ─── Read version from pubspec.yaml ───────────────────────────────────────────
PUBSPEC_VERSION=$(grep '^version:' "$SCRIPT_DIR/pubspec.yaml" \
  | awk '{print $2}' \
  | tr -d '[:space:]')

if [[ -z "$PUBSPEC_VERSION" ]]; then
  error "Could not read version from pubspec.yaml"
fi

info "Current version: $PUBSPEC_VERSION"
mkdir -p "$DIST_DIR"

# ─── Per-platform build/upload state ──────────────────────────────────────────
# dist/.deploy_state holds lines like:  android_built=2.1.0+12@a1b2c3d
state_get() {
  [[ -f "$STATE_FILE" ]] || return 0
  grep "^$1=" "$STATE_FILE" | tail -1 | cut -d= -f2- || true
}
state_set() {
  touch "$STATE_FILE"
  { grep -v "^$1=" "$STATE_FILE" || true; echo "$1=$2"; } > "$STATE_FILE.tmp"
  mv "$STATE_FILE.tmp" "$STATE_FILE"
}

# What a build is identified by: version + commit (+dirty if tracked files differ).
GIT_REV=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo "nogit")
TREE_DIRTY=false
if [[ "$GIT_REV" != "nogit" ]] && ! git -C "$SCRIPT_DIR" diff --quiet HEAD -- 2>/dev/null; then
  TREE_DIRTY=true
  GIT_REV="$GIT_REV-dirty"
fi
BUILD_ID="$PUBSPEC_VERSION@$GIT_REV"

# ─── Parse build args ─────────────────────────────────────────────────────────
BUILD_IOS=true
BUILD_ANDROID=true
UPLOAD=false
REBUILD=false
SKIP_CLEAN=true

for arg in "$@"; do
  case $arg in
    --ios-only)     BUILD_ANDROID=false ;;
    --android-only) BUILD_IOS=false ;;
    --upload)       UPLOAD=true ;;
    --full-clean)   SKIP_CLEAN=false ;;
    --rebuild)      REBUILD=true ;;
    *) error "Unknown option: $arg  (use --ios-only, --android-only, --upload, --full-clean, --rebuild)" ;;
  esac
done

# ─── Validate upload credentials early (only for the platforms being built) ───
if [[ "$UPLOAD" == true && "$BUILD_IOS" == true ]]; then
  # Set these in .env or your shell profile:
  #   export ASC_KEY_ID="XXXXXXXXXX"
  #   export ASC_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  #   export ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8"
  if [[ "$(uname)" != "Darwin" ]]; then
    error "Uploading the iOS build is only supported on macOS."
  fi
  if [[ -z "${ASC_KEY_ID:-}" ]]; then
    error "ASC_KEY_ID is not set. Export it in your shell profile.\n  export ASC_KEY_ID=\"YOUR_KEY_ID\""
  fi
  if [[ -z "${ASC_ISSUER_ID:-}" ]]; then
    error "ASC_ISSUER_ID is not set. Export it in your shell profile.\n  export ASC_ISSUER_ID=\"YOUR_ISSUER_ID\""
  fi
  if [[ -z "${ASC_KEY_PATH:-}" ]]; then
    error "ASC_KEY_PATH is not set. Export it in your shell profile.\n  export ASC_KEY_PATH=\"\$HOME/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8\""
  fi
  if [[ ! -f "$ASC_KEY_PATH" ]]; then
    error "ASC_KEY_PATH file not found: $ASC_KEY_PATH"
  fi
  info "App Store Connect credentials verified."
fi

if [[ "$UPLOAD" == true && "$BUILD_ANDROID" == true ]]; then
  # Set these in .env or your shell profile:
  #   export PLAY_SERVICE_ACCOUNT_JSON="$HOME/.play/service-account.json"   # outside the repo
  #   export PLAY_TRACK="internal"            # optional; internal (default) | production | ...
  #   export PLAY_RELEASE_NOTES="..."         # optional
  if [[ -z "${PLAY_SERVICE_ACCOUNT_JSON:-}" ]]; then
    error "PLAY_SERVICE_ACCOUNT_JSON is not set.\n  export PLAY_SERVICE_ACCOUNT_JSON=\"\$HOME/.play/service-account.json\""
  fi
  if [[ ! -f "$PLAY_SERVICE_ACCOUNT_JSON" ]]; then
    error "PLAY_SERVICE_ACCOUNT_JSON file not found: $PLAY_SERVICE_ACCOUNT_JSON"
  fi
  command -v python3 >/dev/null || error "python3 is required to upload to Google Play."
  info "Google Play credentials verified."
fi

# ─── Work out what is left to do, per platform ────────────────────────────────
AAB_DEST="$DIST_DIR/agoriya-$PUBSPEC_VERSION.aab"
IPA_DEST="$DIST_DIR/agoriya-$PUBSPEC_VERSION.ipa"

# reusable <platform> <artifact>: an existing build of exactly this version+commit
reusable() {
  [[ "$REBUILD" == false && "$TREE_DIRTY" == false \
     && "$(state_get "${1}_built")" == "$BUILD_ID" && -f "$2" ]]
}

ANDROID_NEEDS_BUILD=false; ANDROID_NEEDS_UPLOAD=false
IOS_NEEDS_BUILD=false;     IOS_NEEDS_UPLOAD=false
if [[ "$BUILD_ANDROID" == true ]]; then
  reusable android "$AAB_DEST" || ANDROID_NEEDS_BUILD=true
  if [[ "$UPLOAD" == true && "$(state_get android_uploaded)" != "$BUILD_ID" ]]; then
    ANDROID_NEEDS_UPLOAD=true
  fi
fi
if [[ "$BUILD_IOS" == true ]]; then
  if [[ "$(uname)" != "Darwin" ]]; then
    warn "iOS skipped — not running on macOS."
    BUILD_IOS=false
  else
    reusable ios "$IPA_DEST" || IOS_NEEDS_BUILD=true
    if [[ "$UPLOAD" == true && "$(state_get ios_uploaded)" != "$BUILD_ID" ]]; then
      IOS_NEEDS_UPLOAD=true
    fi
  fi
fi

[[ "$TREE_DIRTY" == true ]] && warn "Uncommitted changes in tracked files — builds from this tree are never reused."
if [[ "$BUILD_ANDROID" == true && "$ANDROID_NEEDS_BUILD" == false ]]; then
  info "Android: AAB for $BUILD_ID is already built — not rebuilding."
fi
if [[ "$BUILD_IOS" == true && "$IOS_NEEDS_BUILD" == false ]]; then
  info "iOS: IPA for $BUILD_ID is already built — not rebuilding."
fi

if [[ "$ANDROID_NEEDS_BUILD" == false && "$ANDROID_NEEDS_UPLOAD" == false \
   && "$IOS_NEEDS_BUILD" == false && "$IOS_NEEDS_UPLOAD" == false ]]; then
  success "Nothing to do for $BUILD_ID — everything requested is already done."
  success "(Bump the version for a new release, or use --rebuild to build again.)"
  exit 0
fi

# ─── Flutter clean & pub get (only if something is being built) ───────────────
if [[ "$ANDROID_NEEDS_BUILD" == true || "$IOS_NEEDS_BUILD" == true ]]; then
  if [[ "$SKIP_CLEAN" == true ]]; then
    warn "Skipping flutter clean (--no-clean). Using existing build cache."
  else
    info "Running flutter clean..."
    flutter clean
  fi

  info "Running flutter pub get..."
  flutter pub get
fi

# ─── Android — App Bundle (upload key) ────────────────────────────────────────
if [[ "$ANDROID_NEEDS_BUILD" == true ]]; then
  info "Building Android App Bundle (upload key)..."
  # env -u: a leftover TF_SIGN_WITH_DEBUG (the old website-APK switch) must
  # never sign the bundle Google Play receives.
  env -u TF_SIGN_WITH_DEBUG flutter build appbundle --release --dart-define-from-file="$TRACKING_ENV_FILE"

  AAB_SRC="$SCRIPT_DIR/build/app/outputs/bundle/release/app-release.aab"
  [[ -f "$AAB_SRC" ]] || error "AAB not found at $AAB_SRC"
  cp "$AAB_SRC" "$AAB_DEST"
  state_set android_built "$BUILD_ID"
  success "AAB → $AAB_DEST"
fi

if [[ "$ANDROID_NEEDS_UPLOAD" == true ]]; then
  PLAY_TRACK_USED="${PLAY_TRACK:-internal}"
  info "Uploading AAB to Google Play ($PLAY_TRACK_USED)..."
  python3 "$SCRIPT_DIR/scripts/play_upload.py" \
    --aab "$AAB_DEST" \
    --key "$PLAY_SERVICE_ACCOUNT_JSON" \
    --track "$PLAY_TRACK_USED" \
    --name "$PUBSPEC_VERSION" \
    --notes "${PLAY_RELEASE_NOTES:-Bug fixes and improvements.}"
  state_set android_uploaded "$BUILD_ID"
  success "Uploaded to Google Play ($PLAY_TRACK_USED)."
fi

# ─── iOS — release IPA ────────────────────────────────────────────────────────
if [[ "$IOS_NEEDS_BUILD" == true ]]; then
  info "Building iOS release IPA..."
  flutter build ipa --release --dart-define-from-file="$TRACKING_ENV_FILE"

  # flutter build ipa places the archive here
  IPA_SRC=$(find "$SCRIPT_DIR/build/ios/archive" -name "*.xcarchive" | head -1)

  if [[ -z "$IPA_SRC" ]]; then
    error "xcarchive not found. Ensure Xcode signing is configured."
  fi

  # Export the IPA from the archive
  EXPORT_DIR="$SCRIPT_DIR/build/ios/ipa"
  EXPORT_PLIST="$SCRIPT_DIR/ios/ExportOptions.plist"

  if [[ ! -f "$EXPORT_PLIST" ]]; then
    warn "ios/ExportOptions.plist not found — creating a default app-store plist."
    cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>uploadSymbols</key>
    <true/>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
PLIST
  fi

  xcodebuild -exportArchive \
    -archivePath "$IPA_SRC" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_PLIST" \
    -allowProvisioningUpdates \
    2>&1 | grep -E "(error:|warning:|IPA|Export)"

  IPA_FILE=$(find "$EXPORT_DIR" -name "*.ipa" | head -1)

  if [[ -z "$IPA_FILE" ]]; then
    error "IPA export failed. Check Xcode signing and ExportOptions.plist."
  fi

  cp "$IPA_FILE" "$IPA_DEST"
  state_set ios_built "$BUILD_ID"
  success "IPA → $IPA_DEST"
fi

# ─── Upload to App Store Connect ──────────────────────────────────────────────
if [[ "$IOS_NEEDS_UPLOAD" == true ]]; then
  [[ -f "$IPA_DEST" ]] || error "No IPA to upload at $IPA_DEST."

  # altool has no --private-key option: it looks for AuthKey_<ASC_KEY_ID>.p8 in
  # $API_PRIVATE_KEYS_DIR (or ./private_keys, ~/private_keys, ~/.private_keys,
  # ~/.appstoreconnect/private_keys). Point it at the key file's directory.
  if [[ "$(basename "$ASC_KEY_PATH")" != "AuthKey_${ASC_KEY_ID}.p8" ]]; then
    error "ASC_KEY_PATH must be named AuthKey_${ASC_KEY_ID}.p8 (altool looks the key up by that name). Got: $(basename "$ASC_KEY_PATH")"
  fi
  export API_PRIVATE_KEYS_DIR="$(dirname "$ASC_KEY_PATH")"

  info "Validating IPA before upload..."
  xcrun altool --validate-app \
    -f "$IPA_DEST" \
    -t ios \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID" \
    2>&1 | grep -v "^$" || true

  info "Uploading IPA to App Store Connect..."
  xcrun altool --upload-app \
    -f "$IPA_DEST" \
    -t ios \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID" \
    2>&1 | grep -v "^$"

  state_set ios_uploaded "$BUILD_ID"
  success "Upload complete — check TestFlight in App Store Connect for processing status."
fi

success "────────────────────────────────────────"
success "Done — $BUILD_ID"
if [[ "$BUILD_ANDROID" == true ]]; then
  note=""; [[ "$(state_get android_uploaded)" == "$BUILD_ID" ]] && note=" — uploaded to Google Play ✓"
  success "  Android: dist/agoriya-$PUBSPEC_VERSION.aab$note"
fi
if [[ "$BUILD_IOS" == true ]]; then
  note=""; [[ "$(state_get ios_uploaded)" == "$BUILD_ID" ]] && note=" — uploaded to TestFlight ✓"
  success "  iOS:     dist/agoriya-$PUBSPEC_VERSION.ipa$note"
fi
success "────────────────────────────────────────"

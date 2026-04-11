#!/usr/bin/env bash
set -euo pipefail

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
VERSION_FILE="$DIST_DIR/.last_version"

# ─── Read version from pubspec.yaml ───────────────────────────────────────────
PUBSPEC_VERSION=$(grep '^version:' "$SCRIPT_DIR/pubspec.yaml" \
  | awk '{print $2}' \
  | tr -d '[:space:]')

if [[ -z "$PUBSPEC_VERSION" ]]; then
  error "Could not read version from pubspec.yaml"
fi

info "Current version: $PUBSPEC_VERSION"

# ─── Compare with last built version ──────────────────────────────────────────
if [[ -f "$VERSION_FILE" ]]; then
  LAST_VERSION=$(cat "$VERSION_FILE")
  if [[ "$LAST_VERSION" == "$PUBSPEC_VERSION" ]]; then
    warn "Version $PUBSPEC_VERSION was already built. Bump the version in pubspec.yaml before deploying."
    warn "Example: version: 0.2.0+2"
    exit 1
  fi
fi

mkdir -p "$DIST_DIR"

# ─── Parse build args ─────────────────────────────────────────────────────────
BUILD_IOS=true
BUILD_ANDROID=true

for arg in "$@"; do
  case $arg in
    --ios-only)     BUILD_ANDROID=false ;;
    --android-only) BUILD_IOS=false ;;
  esac
done

# ─── Flutter clean & pub get ──────────────────────────────────────────────────
info "Running flutter clean..."
flutter clean

info "Running flutter pub get..."
flutter pub get

# ─── Android — release APK ───────────────────────────────────────────────────
if [[ "$BUILD_ANDROID" == true ]]; then
  info "Building Android release APK..."
  flutter build apk --release

  APK_SRC="$SCRIPT_DIR/build/app/outputs/flutter-apk/app-release.apk"
  APK_DEST="$DIST_DIR/agoriya-$PUBSPEC_VERSION.apk"

  if [[ ! -f "$APK_SRC" ]]; then
    error "APK not found at $APK_SRC"
  fi

  cp "$APK_SRC" "$APK_DEST"
  success "APK → $APK_DEST"
fi

# ─── iOS — release IPA ────────────────────────────────────────────────────────
if [[ "$BUILD_IOS" == true ]]; then
  if [[ "$(uname)" != "Darwin" ]]; then
    warn "iOS build skipped — not running on macOS."
  else
    info "Building iOS release IPA..."
    flutter build ipa --release

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

    IPA_DEST="$DIST_DIR/agoriya-$PUBSPEC_VERSION.ipa"
    cp "$IPA_FILE" "$IPA_DEST"
    success "IPA → $IPA_DEST"
  fi
fi

# ─── Record built version ─────────────────────────────────────────────────────
echo "$PUBSPEC_VERSION" > "$VERSION_FILE"

success "────────────────────────────────────────"
success "Build complete — version $PUBSPEC_VERSION"
[[ "$BUILD_ANDROID" == true ]] && success "  APK: dist/agoriya-$PUBSPEC_VERSION.apk"
[[ "$BUILD_IOS"     == true ]] && [[ "$(uname)" == "Darwin" ]] && success "  IPA: dist/agoriya-$PUBSPEC_VERSION.ipa"
success "────────────────────────────────────────"

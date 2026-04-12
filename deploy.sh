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
STORAGE_BUCKET="agoriya-app.firebasestorage.app"

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
UPLOAD_IOS=false

for arg in "$@"; do
  case $arg in
    --ios-only)     BUILD_ANDROID=false ;;
    --android-only) BUILD_IOS=false ;;
    --upload)       UPLOAD_IOS=true ;;
  esac
done

# ─── Validate upload credentials early ───────────────────────────────────────
# Set these in your shell profile (~/.zshrc or ~/.bash_profile):
#   export ASC_KEY_ID="XXXXXXXXXX"
#   export ASC_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
#   export ASC_KEY_PATH="$HOME/.appstoreconnect/AuthKey_XXXXXXXXXX.p8"
if [[ "$UPLOAD_IOS" == true ]]; then
  if [[ "$(uname)" != "Darwin" ]]; then
    error "--upload is only supported on macOS."
  fi
  if [[ -z "${ASC_KEY_ID:-}" ]]; then
    error "ASC_KEY_ID is not set. Export it in your shell profile.\n  export ASC_KEY_ID=\"YOUR_KEY_ID\""
  fi
  if [[ -z "${ASC_ISSUER_ID:-}" ]]; then
    error "ASC_ISSUER_ID is not set. Export it in your shell profile.\n  export ASC_ISSUER_ID=\"YOUR_ISSUER_ID\""
  fi
  if [[ -z "${ASC_KEY_PATH:-}" ]]; then
    error "ASC_KEY_PATH is not set. Export it in your shell profile.\n  export ASC_KEY_PATH=\"\$HOME/.appstoreconnect/AuthKey_XXXXXXXXXX.p8\""
  fi
  if [[ ! -f "$ASC_KEY_PATH" ]]; then
    error "ASC_KEY_PATH file not found: $ASC_KEY_PATH"
  fi
  info "Upload credentials verified."
fi

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

  # ── Upload APK to Firebase Storage ──────────────────────────────────────────
  if command -v gsutil &>/dev/null; then
    gcloud config set project agoriya-app

    info "Uploading APK to Firebase Storage..."

    gsutil cp "$APK_DEST" \
      "gs://$STORAGE_BUCKET/releases/agoriya-$PUBSPEC_VERSION.apk"
    gsutil cp "$APK_DEST" \
      "gs://$STORAGE_BUCKET/releases/latest.apk"

    # Make both files publicly readable.
    # Requires uniform bucket-level access to be OFF (fine-grained ACLs).
    # If your bucket uses uniform access, set a Storage Rule instead:
    #   match /releases/{file} { allow read; }
    gsutil acl ch -u AllUsers:R \
      "gs://$STORAGE_BUCKET/releases/agoriya-$PUBSPEC_VERSION.apk" 2>/dev/null \
      || warn "Could not set ACL — ensure Firebase Storage rules allow public reads for /releases/."
    gsutil acl ch -u AllUsers:R \
      "gs://$STORAGE_BUCKET/releases/latest.apk" 2>/dev/null \
      || warn "Could not set ACL on latest.apk — check Storage rules."

    success "APK uploaded → gs://$STORAGE_BUCKET/releases/latest.apk"
    success "Public URL: https://firebasestorage.googleapis.com/v0/b/$STORAGE_BUCKET/o/releases%2Flatest.apk?alt=media"
  else
    warn "gsutil not found — skipping Firebase Storage upload."
    warn "Install Google Cloud SDK: https://cloud.google.com/sdk"
    warn "Then run: gcloud auth login && gcloud config set project agoriya-app"
  fi
fi

# ─── iOS — release IPA ────────────────────────────────────────────────────────
IPA_DEST=""
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

# ─── Upload to App Store Connect ──────────────────────────────────────────────
if [[ "$UPLOAD_IOS" == true ]]; then
  if [[ -z "$IPA_DEST" || ! -f "$IPA_DEST" ]]; then
    error "No IPA to upload. Run with --upload alongside an iOS build (not --android-only)."
  fi

  info "Validating IPA before upload..."
  xcrun altool --validate-app \
    -f "$IPA_DEST" \
    -t ios \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID" \
    --private-key "$ASC_KEY_PATH" \
    2>&1 | grep -v "^$" || true

  info "Uploading IPA to App Store Connect..."
  xcrun altool --upload-app \
    -f "$IPA_DEST" \
    -t ios \
    --apiKey "$ASC_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID" \
    --private-key "$ASC_KEY_PATH" \
    2>&1 | grep -v "^$"

  success "Upload complete — check TestFlight in App Store Connect for processing status."
fi

# ─── Record built version ─────────────────────────────────────────────────────
echo "$PUBSPEC_VERSION" > "$VERSION_FILE"

success "────────────────────────────────────────"
success "Build complete — version $PUBSPEC_VERSION"
[[ "$BUILD_ANDROID" == true ]] && success "  APK: dist/agoriya-$PUBSPEC_VERSION.apk"
[[ "$BUILD_ANDROID" == true ]] && command -v gsutil &>/dev/null && success "  Storage: gs://$STORAGE_BUCKET/releases/latest.apk"
[[ "$BUILD_IOS"     == true ]] && [[ "$(uname)" == "Darwin" ]] && success "  IPA: dist/agoriya-$PUBSPEC_VERSION.ipa"
[[ "$UPLOAD_IOS"    == true ]] && success "  Uploaded to TestFlight ✓"
success "────────────────────────────────────────"

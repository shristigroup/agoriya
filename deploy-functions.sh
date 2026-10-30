#!/usr/bin/env bash
# Deploy Cloud Functions. Secrets (Stripe keys) are read from ./.secrets (gitignored) and pushed to
# Google Secret Manager only when their value changed since the last run, then the functions are deployed.
#
#   ./deploy-functions.sh                                   # push changed secrets, deploy all functions
#   ./deploy-functions.sh functions:createCheckoutSession,functions:stripeWebhook
#   ./deploy-functions.sh functions:stripeWebhook           # e.g. after changing STRIPE_WEBHOOK_SECRET
#   DRY_RUN=1 ./deploy-functions.sh                         # show what would run, without running firebase
#
# .secrets format (see .secrets.example):  KEY=value, one per line, # for comments. Values are never printed.
set -euo pipefail
cd "$(dirname "$0")"

PROJECT="${FIREBASE_PROJECT:-agoriya-app}"
SECRETS_FILE=".secrets"
STATE_FILE=".secrets.state"     # sha256 of each pushed KEY=value, so unchanged secrets are not re-pushed (gitignored)
TARGET="${1:-functions}"
shift || true

run() { if [[ -n "${DRY_RUN:-}" ]]; then echo "[dry run] $*"; else "$@"; fi; }

if [[ -f "$SECRETS_FILE" ]]; then
  # Refuse to continue if the secrets file could be committed.
  if ! git check-ignore -q "$SECRETS_FILE"; then
    echo "Refusing to run: $SECRETS_FILE is not gitignored. Add it to .gitignore first." >&2
    exit 1
  fi
  touch "$STATE_FILE"
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    key="${key//[[:space:]]/}"
    [[ -z "$key" || "$key" == \#* ]] && continue
    value="${value%$'\r'}"
    value="${value#\"}"; value="${value%\"}"; value="${value#\'}"; value="${value%\'}"
    if [[ ! "$key" =~ ^[A-Z][A-Z0-9_]*$ ]]; then echo "Skipping invalid key name in $SECRETS_FILE: $key" >&2; continue; fi
    if [[ -z "$value" ]]; then echo "Skipping $key: empty value" >&2; continue; fi
    hash="$(printf '%s=%s' "$key" "$value" | shasum -a 256 | cut -d' ' -f1)"
    if grep -q "^$key $hash\$" "$STATE_FILE"; then
      echo "Secret $key unchanged, skipping."
      continue
    fi
    echo "Pushing secret $key to Secret Manager..."
    if [[ -n "${DRY_RUN:-}" ]]; then
      echo "[dry run] firebase functions:secrets:set $key --data-file - --project $PROJECT --force   (value from $SECRETS_FILE)"
    else
      printf '%s' "$value" | firebase functions:secrets:set "$key" --data-file - --project "$PROJECT" --force
      grep -v "^$key " "$STATE_FILE" > "$STATE_FILE.tmp" || true
      echo "$key $hash" >> "$STATE_FILE.tmp"
      mv "$STATE_FILE.tmp" "$STATE_FILE"
    fi
  done < "$SECRETS_FILE"
else
  echo "No $SECRETS_FILE found: deploying without pushing any secrets."
fi

run firebase deploy --only "$TARGET" --project "$PROJECT" "$@"

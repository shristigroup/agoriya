#!/usr/bin/env python3
"""Upload an Android App Bundle to Google Play (Android Publisher API v3).

Authenticates with a service-account JSON key, creates an edit, uploads the
bundle, puts it in a release on the chosen track and commits. Python standard
library + `openssl` + `curl` only (the python.org build of Python lacks CA
certificates on macOS, so HTTPS goes through curl).

  internal track -> status "completed": available to internal testers at once
  other tracks   -> status "draft": appears as a draft release in Play Console
                    so the rollout/review is still started by hand there

Usage:
  play_upload.py --aab app.aab --key sa.json [--package com.agoriya.app]
                 [--track internal] [--name "2.1.0+12"] [--notes "..."]
                 [--status completed|draft] [--dry-run]
"""
import argparse, base64, json, os, subprocess, sys, tempfile, time

API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"
UPLOAD = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications"


def b64(b: bytes) -> bytes:
    return base64.urlsafe_b64encode(b).rstrip(b"=")


def access_token(sa: dict) -> str:
    """OAuth2 JWT-bearer flow: sign an RS256 assertion with the SA's key."""
    now = int(time.time())
    header = b64(json.dumps({"alg": "RS256", "typ": "JWT"}).encode())
    claims = b64(json.dumps({
        "iss": sa["client_email"],
        "scope": "https://www.googleapis.com/auth/androidpublisher",
        "aud": "https://oauth2.googleapis.com/token",
        "iat": now, "exp": now + 3000,
    }).encode())
    signing_input = header + b"." + claims
    with tempfile.NamedTemporaryFile("w", suffix=".pem", delete=False) as f:
        f.write(sa["private_key"])
        pem = f.name
    os.chmod(pem, 0o600)
    try:
        sig = subprocess.run(["openssl", "dgst", "-sha256", "-sign", pem],
                             input=signing_input, capture_output=True, check=True).stdout
    finally:
        os.unlink(pem)
    return (signing_input + b"." + b64(sig)).decode()


def curl(method, url, token=None, body=None, data_file=None, content_type=None, step=""):
    cmd = ["curl", "-sS", "-g", "-X", method, url]
    if token:
        cmd += ["-H", "Authorization: Bearer " + token]
    if body is not None:
        cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(body)]
    if data_file:
        cmd += ["-H", "Content-Type: " + (content_type or "application/octet-stream"),
                "--data-binary", "@" + data_file]
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"curl failed: {out.stderr.strip()}")
    try:
        data = json.loads(out.stdout) if out.stdout.strip() else {}
    except json.JSONDecodeError:
        sys.exit(f"Unexpected response from {url}: {out.stdout[:300]}")
    if isinstance(data, dict) and "error" in data:
        err = data["error"]
        where = f" while trying to {step}" if step else ""
        sys.exit(f"Google Play API error{where} ({err.get('code')}): {err.get('message')}")
    return data


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--aab", required=True)
    ap.add_argument("--key", required=True, help="service-account JSON key file")
    ap.add_argument("--package", default="com.agoriya.app")
    ap.add_argument("--track", default="internal")
    ap.add_argument("--name", default="", help="release name shown in Play Console")
    ap.add_argument("--notes", default="Bug fixes and improvements.")
    ap.add_argument("--status", choices=["completed", "draft"],
                    help='default: "completed" on internal, "draft" elsewhere')
    ap.add_argument("--dry-run", action="store_true", help="check inputs and sign a token, call nothing")
    a = ap.parse_args()

    if not os.path.isfile(a.aab):
        sys.exit(f"AAB not found: {a.aab}")
    if not os.path.isfile(a.key):
        sys.exit(f"Service-account key not found: {a.key}")
    sa = json.load(open(a.key))
    for k in ("client_email", "private_key"):
        if k not in sa:
            sys.exit(f"{a.key} is not a service-account key (missing {k})")
    status = a.status or ("completed" if a.track == "internal" else "draft")
    size_mb = os.path.getsize(a.aab) / 1048576

    print(f"[play] {a.package} | track={a.track} status={status} | "
          f"{os.path.basename(a.aab)} ({size_mb:.1f} MB) | as {sa['client_email']}")
    assertion = access_token(sa)
    if a.dry_run:
        print(f"[play] dry run OK (signed a {len(assertion)}-char assertion); nothing sent")
        return

    # token exchange is form-encoded, not JSON
    out = subprocess.run(["curl", "-sS", "-X", "POST", "https://oauth2.googleapis.com/token",
                          "-d", "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer",
                          "--data-urlencode", "assertion=" + assertion],
                         capture_output=True, text=True).stdout
    tok = json.loads(out).get("access_token")
    if not tok:
        sys.exit(f"Could not get an access token: {out[:300]}")

    edit = curl("POST", f"{API}/{a.package}/edits", tok, body={}, step="open an edit")["id"]
    print(f"[play] edit {edit} created; uploading bundle (this can take a minute)...")
    bundle = curl("POST", f"{UPLOAD}/{a.package}/edits/{edit}/bundles?uploadType=media",
                  tok, data_file=a.aab, step="upload the bundle")
    vc = bundle["versionCode"]
    print(f"[play] uploaded: versionCode {vc}")

    release = {"name": a.name or str(vc), "versionCodes": [str(vc)], "status": status,
               "releaseNotes": [{"language": "en-US", "text": a.notes}]}
    curl("PUT", f"{API}/{a.package}/edits/{edit}/tracks/{a.track}", tok,
         body={"track": a.track, "releases": [release]}, step=f"assign it to the '{a.track}' track")
    # Play checks release permissions when the edit is validated/committed, not
    # when it is staged, so a 403 here means the service account lacks them.
    curl("POST", f"{API}/{a.package}/edits/{edit}:validate", tok, body={},
         step="validate the release (the service account needs 'Release apps to "
              "testing tracks' / 'Release to production' in Play Console > Users and permissions)")
    curl("POST", f"{API}/{a.package}/edits/{edit}:commit", tok, body={}, step="commit the release")
    print(f"[play] committed: versionCode {vc} on '{a.track}' as {status}.")
    if status == "draft":
        print("[play] it is a DRAFT: open Play Console > Production (or the track) to roll it out.")


if __name__ == "__main__":
    main()

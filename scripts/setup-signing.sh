#!/usr/bin/env bash
#
# One-time setup for stable APK signing.
#
# Generates a signing keystore and uploads it, plus its credentials, to this
# repository's GitHub Actions secrets so every CI build is signed with the same
# key. Without this, each workflow run generates a throwaway debug key and the
# resulting APK cannot be installed over the previous one.
#
# Run this once, on a machine that has `keytool` (any JDK) and an authenticated
# `gh`. Re-running is refused while a keystore already exists -- see BACKUP below.
#
# Usage:
#   scripts/setup-signing.sh [-R owner/repo]
#
set -euo pipefail

ALIAS="smsgateway"
VALIDITY_DAYS=10000
DNAME="CN=SMS Gateway Local, OU=Local Build, O=Local Build, C=US"

REPO_ARG=()
while [ $# -gt 0 ]; do
    case "$1" in
        -R|--repo) REPO_ARG=(--repo "$2"); shift 2 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYSTORE="$REPO_ROOT/app/local-keystore.jks"

for tool in keytool gh base64 openssl; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "error: '$tool' not found in PATH" >&2
        exit 1
    }
done

if ! gh auth status >/dev/null 2>&1; then
    echo "error: gh is not authenticated -- run 'gh auth login' first" >&2
    exit 1
fi

# Refuse to clobber. Overwriting the keystore silently breaks in-place updates
# for every device that already has a build installed.
if [ -e "$KEYSTORE" ]; then
    cat >&2 <<EOF
error: $KEYSTORE already exists.

Generating a new key would change the app's signature, and Android would refuse
to install the next build over the one on your device. If you genuinely want to
start over, move the old keystore aside first and plan to uninstall the app.
EOF
    exit 1
fi

# 256 bits, hex so the value survives env vars, Gradle, and GitHub secrets
# without quoting hazards. Deliberately not `tr -dc ... </dev/urandom | head -c N`:
# head closes the pipe, tr dies with SIGPIPE, and pipefail plus set -e abort the
# script every time.
randpw() { openssl rand -hex 32; }

# One password for both store and key: PKCS12 does not support differing
# passwords, and keytool silently ignores -keypass when they differ. Uploading a
# distinct key password would produce a secret that cannot open the key, and
# signing would fail in CI. build.gradle still reads two variables, so both
# secrets are set to this same value.
PASSWORD="$(randpw)"

echo "Generating keystore at app/local-keystore.jks ..."
keytool -genkeypair \
    -keystore "$KEYSTORE" \
    -storetype PKCS12 \
    -storepass "$PASSWORD" \
    -keypass "$PASSWORD" \
    -alias "$ALIAS" \
    -keyalg RSA \
    -keysize 2048 \
    -validity "$VALIDITY_DAYS" \
    -dname "$DNAME" \
    >/dev/null

# -w0 is GNU-only; piping through tr keeps this working on macOS too.
KEYSTORE_B64="$(base64 <"$KEYSTORE" | tr -d '\n')"

echo "Uploading secrets to GitHub ..."
# Piped rather than passed via --body so the values never appear in argv.
printf '%s' "$KEYSTORE_B64" | gh secret set LOCAL_KEYSTORE_BASE64 "${REPO_ARG[@]}"
printf '%s' "$PASSWORD"     | gh secret set LOCAL_STORE_PASSWORD  "${REPO_ARG[@]}"
printf '%s' "$PASSWORD"     | gh secret set LOCAL_KEY_PASSWORD    "${REPO_ARG[@]}"
printf '%s' "$ALIAS"        | gh secret set LOCAL_KEY_ALIAS       "${REPO_ARG[@]}"

cat > secrets <<EOF

Password:  $PASSWORD   (opens both the store and the key)
Key alias: $ALIAS

Copy those into a password manager and keep a copy of app/local-keystore.jks
somewhere outside this repository. GitHub secrets are write-only, so you cannot
read them back later.

If you lose both the keystore and the secrets, you can never again update an
installed build in place -- you would have to uninstall the app, losing its
database, webhook registrations, and local-server credentials.

The keystore is matched by *.jks in .gitignore, so it will not be committed.
EOF

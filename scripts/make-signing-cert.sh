#!/bin/bash
# Creates "FocusNow Local Signing", a self-signed code-signing certificate, in
# your login keychain (or the keychain given). build-app.sh signs with it when
# it's there, so macOS keeps FocusNow's permissions, such as calendar access,
# across rebuilds. Run it once; macOS may ask for your login password.
# Usage: scripts/make-signing-cert.sh [keychain]
set -euo pipefail

NAME="FocusNow Local Signing"
KC="${1:-$HOME/Library/Keychains/login.keychain-db}"

if security find-identity -p codesigning "$KC" 2>/dev/null | grep -q "\"$NAME\""; then
    echo "\"$NAME\" is already in $KC"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
P12_PASS=$(uuidgen)
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/identity.p12" -passout pass:"$P12_PASS"
security import "$TMP/identity.p12" -k "$KC" -P "$P12_PASS" -T /usr/bin/codesign >/dev/null

# Let codesign use the key on every build without asking each time.
if [ -n "${FOCUSNOW_KEYCHAIN_PASSWORD:-}" ]; then
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -l "$NAME" \
        -k "$FOCUSNOW_KEYCHAIN_PASSWORD" "$KC" >/dev/null
else
    echo "Your login password lets builds sign without asking each time:"
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -l "$NAME" "$KC" >/dev/null
fi
echo "created \"$NAME\" in $KC"

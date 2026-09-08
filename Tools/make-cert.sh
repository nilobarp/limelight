#!/bin/sh
# Creates the self-signed code-signing identity Limelight signs itself with.
#
# Why bother: TCC pins an app's Accessibility grant to its code signature. An
# ad-hoc signature changes hash on every build, so macOS silently drops the
# permission each time you rebuild — while still showing the toggle as enabled.
# A stable identity makes the grant survive.
#
# Nothing here is sent anywhere. The certificate never leaves your keychain and
# is only trusted on this machine.
set -eu

IDENTITY="${1:-Limelight Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

OPENSSL=/usr/bin/openssl

if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "'$IDENTITY' already exists — nothing to do."
    echo "A second certificate with the same name would make codesign ambiguous."
    exit 0
fi

d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT

echo "Creating a self-signed code-signing certificate '$IDENTITY'…"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$d/key.pem" -out "$d/cert.pem" \
    -subj "/CN=$IDENTITY" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

# -name sets the PKCS#12 friendlyName, which becomes the label of the private
# key in Keychain Access. Without it macOS falls back to the archive's file
# name, so codesign ends up asking to access a key called something like "id".
"$OPENSSL" pkcs12 -export -out "$d/id.p12" -inkey "$d/key.pem" -in "$d/cert.pem" \
    -name "$IDENTITY" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
    -passout pass:limelight >/dev/null 2>&1

echo "Importing it into your login keychain…"
security import "$d/id.p12" -k "$KEYCHAIN" -P limelight -T /usr/bin/codesign -A >/dev/null

# A self-signed certificate is not a valid signing identity until it is trusted
# for that purpose. macOS may ask for your password here.
echo "Trusting it for code signing (macOS may ask for your password)…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$d/cert.pem"

# macOS gates key use on the partition list as well as the ACL, so the first
# codesign will pop a "wants to access key" password prompt unless codesign is
# added to it. Offer to do that now; the alternative is one click on
# "Always Allow" the first time it asks.
if [ -t 0 ]; then
    echo
    printf 'Let codesign use this key without prompting? [Y/n] '
    read -r reply || reply=""
    case "$reply" in
        [Nn]*)
            echo 'Fine — click "Always Allow" the first time codesign asks.'
            ;;
        *)
            printf 'login keychain password (not stored, passed only to security(1)): '
            stty -echo 2>/dev/null || true
            read -r pw || pw=""
            stty echo 2>/dev/null || true
            echo
            if security set-key-partition-list -S apple-tool:,apple:,codesign: \
                 -s -l "$IDENTITY" -k "$pw" "$KEYCHAIN" >/dev/null 2>&1; then
                echo "Done — codesign will not prompt."
            else
                echo 'Could not set that; click "Always Allow" when codesign asks.'
            fi
            unset pw
            ;;
    esac
fi

echo
if security find-identity -v -p codesigning | grep "$IDENTITY"; then
    echo
    echo "Done. Now run: make install"
else
    echo "Failed: '$IDENTITY' is not a valid signing identity." >&2
    echo "You can still 'make install' — it falls back to ad-hoc signing." >&2
    exit 1
fi

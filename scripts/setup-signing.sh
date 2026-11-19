#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/signing-config.sh"

KEYCHAIN="$SUPERFINDER_SIGNING_KEYCHAIN"
IDENTITY="$SUPERFINDER_SIGNING_IDENTITY"
PASSWORD_FILE="$SUPERFINDER_SIGNING_PASSWORD_FILE"
SUPPORT_DIR="$(dirname "$PASSWORD_FILE")"

if [[ -e "$KEYCHAIN" ]]; then
  if /usr/bin/security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -qF "$IDENTITY"; then
    if [[ ! -f "$PASSWORD_FILE" ]]; then
      echo "错误：签名身份存在，但钥匙串密码文件缺失：" >&2
      echo "  $PASSWORD_FILE" >&2
      echo "请恢复该文件；如果无法恢复，请删除钥匙串后重新运行本脚本（会导致一次重新授权）。" >&2
      exit 1
    fi
    echo "稳定签名身份已存在：$IDENTITY"
    echo "钥匙串：$KEYCHAIN"
    exit 0
  fi
  echo "错误：钥匙串已存在，但没有找到「$IDENTITY」身份：" >&2
  echo "  $KEYCHAIN" >&2
  echo "为避免破坏已有签名，本脚本不会覆盖它。请先检查或手动移除后重试。" >&2
  exit 1
fi

umask 077
mkdir -p "$SUPPORT_DIR"
chmod 700 "$SUPPORT_DIR"
if [[ ! -f "$PASSWORD_FILE" ]]; then
  /usr/bin/openssl rand -hex 24 > "$PASSWORD_FILE"
  chmod 600 "$PASSWORD_FILE"
fi
PASSWORD="$(cat "$PASSWORD_FILE")"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/superfinder-signing.XXXXXX")"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

CERT="$TMP_DIR/cert.pem"
KEY="$TMP_DIR/key.pem"
P12="$TMP_DIR/identity.p12"

/usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$KEY" -out "$CERT" \
  -subj "/CN=$IDENTITY/O=SuperFinder" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

/usr/bin/openssl pkcs12 -export \
  -inkey "$KEY" -in "$CERT" -out "$P12" \
  -passout pass:superfinder -name "$IDENTITY" >/dev/null 2>&1

/usr/bin/security create-keychain -p "$PASSWORD" "$KEYCHAIN"
/usr/bin/security set-keychain-settings -lut 21600 "$KEYCHAIN"
/usr/bin/security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
/usr/bin/security import "$P12" -k "$KEYCHAIN" -P superfinder \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null
/usr/bin/security set-key-partition-list \
  -S apple-tool:,apple:,codesign: -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null
/usr/bin/security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$CERT"

if ! /usr/bin/security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -qF "$IDENTITY"; then
  echo "错误：签名身份创建后仍不可用。" >&2
  exit 1
fi

echo "已创建稳定签名身份：$IDENTITY"
echo "钥匙串：$KEYCHAIN"
echo "证书有效期：10 年"
echo
echo "现在运行 ./scripts/build.sh。以后重新构建会沿用同一签名，"
echo "Screen Recording（以及可选辅助功能）授权不需要每次重新确认。"

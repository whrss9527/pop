#!/usr/bin/env bash
# 给 Pop.app 签名。
#   不设 CODESIGN_IDENTITY：本地签名（ad-hoc），不开 Hardened Runtime。每次构建的签名都不一样，
#     macOS 会把新版本当成另一个程序，更新后要重新授权辅助功能。
#   CODESIGN_IDENTITY=证书名字或 SHA-1：用证书签名，开 Hardened Runtime、带安全时间戳；
#     CODESIGN_KEYCHAIN 可以指定证书所在的钥匙串。证书不变，签名的「身份」就不变，更新后授权不会丢。
#
# 用法：scripts/sign-app.sh <Pop.app>
set -euo pipefail

APP="${1:?用法: scripts/sign-app.sh <Pop.app>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS="$ROOT/Pop/Resources/Pop-NoCloud.entitlements"

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  args=(--force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" --entitlements "$ENTITLEMENTS")
  if [ -n "${CODESIGN_KEYCHAIN:-}" ]; then
    args+=(--keychain "$CODESIGN_KEYCHAIN")
  fi
else
  args=(--force --sign - --entitlements "$ENTITLEMENTS")
fi

codesign "${args[@]}" "$APP"
codesign --verify --deep --strict "$APP"

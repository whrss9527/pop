#!/usr/bin/env bash
# 公开发行和签名 dry-run 共用的门禁；本地构建、ad-hoc 与自签名 CI 不调用它。
# credentials 只检查凭据是否完整；identity 检查导入的身份；archive 检查公证后最终安装包。
set -euo pipefail

fail() { echo "::error::$*" >&2; exit 1; }

check_identity() {
  [[ "${CODESIGN_IDENTITY:-}" =~ ^[0-9a-fA-F]{40}$ ]] || fail "公开发行需要有效的证书签名身份"
  [[ "${CODESIGN_NAME:-}" == 'Developer ID Application: '* ]] || fail "公开发行需要 Developer ID Application 证书"
}

case "${1:-}" in
  credentials)
    [ -n "${CERTIFICATE_P12_BASE64:-}" ] || fail "公开发行缺少 MACOS_CERTIFICATE_P12"
    [ -n "${CERTIFICATE_PASSWORD:-}" ] || fail "公开发行缺少 MACOS_CERTIFICATE_PASSWORD"
    # 与 notarize.sh 的选择顺序一致：个人 API 密钥不要求 Issuer ID。
    if [ -n "${NOTARY_KEY_P8:-}" ]; then
      [ -n "${NOTARY_KEY_ID:-}" ] || fail "公证 API 密钥缺少 NOTARY_KEY_ID"
    else
      [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ] \
        || fail "公开发行需要完整的公证 API 密钥或 Apple ID 凭据"
    fi
    ;;
  identity)
    check_identity
    ;;
  archive)
    check_identity
    [ "${NOTARIZED:-}" = "1" ] || fail "安装包尚未通过苹果公证"
    archive="${2:?用法：check-public-signing.sh archive Pop-版本.zip}"
    [ -f "$archive" ] || fail "找不到最终安装包"
    work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pop-public-signing.XXXXXX")"
    trap 'rm -rf "$work"' EXIT
    ditto -x -k "$archive" "$work"
    app="$work/Pop.app"
    [ -d "$app" ] || fail "最终安装包不包含 Pop.app"
    codesign --verify --deep --strict --all-architectures "$app"
    codesign --display --verbose=4 "$app" > "$work/signature.txt" 2>&1
    grep -Fxq "Authority=${CODESIGN_NAME}" "$work/signature.txt" || fail "最终安装包的 Developer ID 与导入的证书不一致"
    # 再解压最终 zip 验证票据，避免把压回 zip 前的检查当成安装包验收。
    for attempt in 1 2 3; do
      if xcrun stapler validate "$app"; then break; else result=$?; fi
      [ "$result" -eq 68 ] && [ "$attempt" -lt 3 ] || exit "$result"
      echo "最终安装包票据网络查询未完成，5 秒后重试（${attempt}/3）"
      sleep 5
    done
    if ! spctl --assess --type execute --verbose=2 "$app" > "$work/assessment.txt" 2>&1; then
      cat "$work/assessment.txt"
      fail "最终安装包未通过 Gatekeeper"
    fi
    cat "$work/assessment.txt"
    grep -Fxq 'source=Notarized Developer ID' "$work/assessment.txt" || fail "Gatekeeper 未明确认可公证后的 Developer ID"
    ;;
  *) fail "用法：check-public-signing.sh credentials | identity | archive Pop-版本.zip" ;;
esac

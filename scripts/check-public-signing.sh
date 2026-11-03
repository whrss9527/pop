#!/usr/bin/env bash
# 公开发行和签名 dry-run 共用的检查；本地构建、ad-hoc 与自签名 CI 不调用它。
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
    archive="${2:?用法：check-public-signing.sh archive Pop-版本.zip或.dmg [对应ZIP]}"
    [ -f "$archive" ] || fail "找不到最终安装包"
    work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/pop-public-signing.XXXXXX")"
    mounted=""
    cleanup() {
      if [ -n "$mounted" ]; then hdiutil detach "$mounted" -force >/dev/null || true; fi
      rm -rf "$work"
    }
    trap cleanup EXIT
    targets=()
    case "$archive" in
      *.zip)
        ditto -x -k "$archive" "$work"
        app="$work/Pop.app"
        ;;
      *.dmg)
        reference="${3:?DMG 验收需要对应的 ZIP}"
        hdiutil verify "$archive"
        mounted="$work/volume"
        hdiutil attach "$archive" -readonly -mountpoint "$mounted" -nobrowse -noautoopen
        xcrun swift -e 'import Foundation; let target = try URL(resolvingAliasFileAt: URL(fileURLWithPath: CommandLine.arguments[1]), options: [.withoutUI, .withoutMounting]); if target.path != "/Applications" { exit(1) }' "$mounted/Applications" || fail "DMG 的安装目标不是应用程序文件夹"
        [ -s "$mounted/.DS_Store" ] && [ -s "$mounted/.background/background.png" ] || fail "DMG 缺少安装布局"
        ditto -x -k "$reference" "$work/reference"
        app="$mounted/Pop.app"
        diff -qr "$work/reference/Pop.app" "$app" || fail "DMG 与 ZIP 里的 App 不一致"
        targets+=("$archive")
        ;;
      *) fail "不支持的安装包格式" ;;
    esac
    [ -d "$app" ] || fail "最终安装包不包含 Pop.app"
    targets+=("$app")
    if ! spctl --status > "$work/policy.txt" 2>&1; then
      cat "$work/policy.txt"
      fail "无法确认 Gatekeeper 策略状态"
    fi
    grep -Fxq 'assessments enabled' "$work/policy.txt" || fail "Gatekeeper 未启用或状态未知"
    if grep -Eiq 'override|security.*disabled|assessments.*disabled' "$work/policy.txt"; then
      fail "Gatekeeper 策略被覆盖或关闭"
    fi
    for target in "${targets[@]}"; do
      codesign --verify --deep --strict --all-architectures "$target"
      codesign --display --verbose=4 "$target" > "$work/signature.txt" 2>&1
      grep -Fxq "Authority=${CODESIGN_NAME}" "$work/signature.txt" || fail "最终安装包的 Developer ID 与导入的证书不一致"
      for attempt in 1 2 3; do
        if xcrun stapler validate "$target"; then break; else result=$?; fi
        [ "$result" -eq 68 ] && [ "$attempt" -lt 3 ] || exit "$result"
        echo "最终安装包票据网络查询未完成，5 秒后重试（${attempt}/3）"
        sleep 5
      done
      assessment=(--type execute)
      if [[ "$target" == *.dmg ]]; then assessment=(--type open --context context:primary-signature); fi
      if ! spctl --assess "${assessment[@]}" --verbose=2 "$target" > "$work/assessment.txt" 2>&1; then
        cat "$work/assessment.txt"
        fail "最终安装包未通过 Gatekeeper"
      fi
      cat "$work/assessment.txt"
      if grep -Eiq 'override|security.*disabled|assessments.*disabled' "$work/assessment.txt"; then
        fail "Gatekeeper 验收包含覆盖或关闭状态"
      fi
      grep -Fxq 'source=Notarized Developer ID' "$work/assessment.txt" || fail "Gatekeeper 未明确认可公证后的 Developer ID"
    done
    ;;
  *) fail "用法：check-public-signing.sh credentials | identity | archive Pop-版本.zip或.dmg [对应ZIP]" ;;
esac

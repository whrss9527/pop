#!/usr/bin/env bash
# 只构建，不启动；独立身份、无网络权限的沙盒包，供本机手动验收生产视图。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/ui-fixture}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
cd "$ROOT"
xcodegen generate > "$OUT/generate.log" 2>&1
xcodebuild build -project Pop.xcodeproj -scheme PopUIFixture -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$OUT/DerivedData" \
  -clonedSourcePackagesDirPath "$ROOT/build/SourcePackages" -jobs 2 \
  CODE_SIGNING_ALLOWED=NO > "$OUT/build.log" 2>&1
APP="$OUT/PopUIFixture.app"
rm -rf "$APP"
ditto "$OUT/DerivedData/Build/Products/Debug/PopUIFixture.app" "$APP"
codesign --force --sign - --entitlements Config/PopUIFixture.entitlements "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"

#!/usr/bin/env bash
# 端到端测试一键更新：用本地 HTTP 服务器假装 GitHub 发布了 9.9.9，启动 Pop，让它自动检查、下载、校验、替换并重新启动。
# 依次测三种情况：
#   1. 校验和不对：拒绝安装，程序不变；
#   2. 当前版本用证书签名、新版本却是本地签名（设置了 CODESIGN_IDENTITY 时才测）：拒绝安装；
#   3. 正常的新版本：替换成 9.9.9 并重新启动。
# 新版本和发布流程一样用 scripts/sign-app.sh 签名（设置了 CODESIGN_IDENTITY 时用证书）。
#
# 用法：scripts/update-e2e.sh <Pop.app>（测试通过后它会变成 9.9.9，请传一份拷贝进来）
set -euo pipefail

APP="${1:?用法: scripts/update-e2e.sh <Pop.app>}"
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${POP_E2E_PORT:-8765}"
WORK="$(mktemp -d -t pop-update-e2e)"
FEED="$WORK/feed"
mkdir -p "$FEED"
SERVER_PID=""
START=""

cleanup() {
  pkill -x Pop 2>/dev/null || true
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

version_of() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist" 2>/dev/null || true
}

pop_log() {
  log show --start "$START" --style compact --predicate 'process == "Pop"' 2>/dev/null || true
}

fail() {
  echo "---- Pop 的日志 ----"
  pop_log | grep -E "Pop 更新|Pop 已启动" | tail -30 || true
  echo "❌ $1"
  exit 1
}

# 造一个 9.9.9：复制当前的包，改版本号，签名，打包，写好发布列表。$1：identity（和当前环境一致）或 adhoc
make_release() {
  local dir="$WORK/build-$1"
  rm -rf "$dir" && mkdir -p "$dir"
  ditto "$APP" "$dir/Pop.app"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 9.9.9" "$dir/Pop.app/Contents/Info.plist"
  if [ "$1" = "adhoc" ]; then
    CODESIGN_IDENTITY="" "$ROOT/scripts/sign-app.sh" "$dir/Pop.app"
  else
    "$ROOT/scripts/sign-app.sh" "$dir/Pop.app"
  fi
  rm -f "$FEED/Pop-9.9.9.zip"
  (cd "$dir" && ditto -c -k --keepParent Pop.app "$FEED/Pop-9.9.9.zip")
  (cd "$FEED" && shasum -a 256 Pop-9.9.9.zip > SHA256SUMS.txt)
  local size
  size="$(stat -f %z "$FEED/Pop-9.9.9.zip")"
  cat > "$FEED/releases.json" <<JSON
[{"tag_name": "v9.9.9", "name": "Pop 9.9.9（测试版）", "draft": false, "prerelease": true,
  "html_url": "http://127.0.0.1:${PORT}/releases.json", "published_at": "2026-01-01T00:00:00Z",
  "body": "### 新增\n\n- CI 用来测试一键更新的假版本",
  "assets": [
    {"name": "Pop-9.9.9.zip", "size": ${size}, "browser_download_url": "http://127.0.0.1:${PORT}/Pop-9.9.9.zip"},
    {"name": "SHA256SUMS.txt", "size": 80, "browser_download_url": "http://127.0.0.1:${PORT}/SHA256SUMS.txt"}]}]
JSON
}

# 启动 Pop：它会马上检查这个假的发布列表，发现新版本就自动安装
launch_pop() {
  pkill -x Pop 2>/dev/null || true
  sleep 1
  START="$(date '+%Y-%m-%d %H:%M:%S')"
  POP_UPDATE_URL="http://127.0.0.1:${PORT}/releases.json" POP_UPDATE_AUTO_INSTALL=1 \
    "$APP/Contents/MacOS/Pop" > /dev/null 2>&1 &
}

wait_for_log() {
  local pattern="$1" seconds="$2"
  for _ in $(seq 1 "$seconds"); do
    if pop_log | grep -q "$pattern"; then
      return 0
    fi
    sleep 1
  done
  return 1
}

ORIGINAL="$(version_of "$APP")"
echo "当前版本：${ORIGINAL}，签名：$(codesign -dvv "$APP" 2>&1 | awk -F= '/^Authority=/{print $2; exit}')"

(cd "$FEED" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 > /dev/null 2>&1) &
SERVER_PID=$!
make_release identity
for _ in $(seq 1 30); do
  curl -sf -o /dev/null "http://127.0.0.1:${PORT}/releases.json" && break
  sleep 0.5
done
curl -sSf -o /dev/null "http://127.0.0.1:${PORT}/releases.json" || fail "本地的假发布服务器没有起来"

echo "==> 1. 校验和不对"
echo "0000000000000000000000000000000000000000000000000000000000000000  Pop-9.9.9.zip" > "$FEED/SHA256SUMS.txt"
launch_pop
wait_for_log "Pop 更新：更新到 9.9.9 失败" 60 || fail "校验和不对时没有报错"
pop_log | grep -q "校验和不对" || fail "失败原因不是校验和"
[ "$(version_of "$APP")" = "$ORIGINAL" ] || fail "校验和不对却换掉了程序"
echo "✅ 拒绝了校验和不对的包"

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  echo "==> 2. 新版本不是同一个证书签名的"
  make_release adhoc
  launch_pop
  wait_for_log "Pop 更新：更新到 9.9.9 失败" 60 || fail "签名不一致时没有报错"
  pop_log | grep -q "同一个证书" || fail "失败原因不是签名不一致"
  [ "$(version_of "$APP")" = "$ORIGINAL" ] || fail "签名不一致却换掉了程序"
  echo "✅ 拒绝了别的证书签名的包"
fi

echo "==> 3. 正常更新"
make_release identity
launch_pop
for _ in $(seq 1 90); do
  if [ "$(version_of "$APP")" = "9.9.9" ] && pop_log | grep -q "Pop 已启动，版本 9.9.9"; then
    break
  fi
  sleep 1
done
pop_log | grep -E "Pop 更新|Pop 已启动" | tail -20 || true
[ "$(version_of "$APP")" = "9.9.9" ] || fail "程序没有被替换成 9.9.9"
pop_log | grep -q "Pop 已启动，版本 9.9.9" || fail "新版本没有重新启动"
pgrep -x Pop > /dev/null || fail "更新后 Pop 没有在运行"
codesign --verify --deep --strict "$APP" || fail "新程序的签名不完整"
if xattr "$APP" | grep -q com.apple.quarantine; then
  fail "新程序还带着隔离标记"
fi
echo "✅ 一键更新：下载、校验、替换、重新启动都正常"

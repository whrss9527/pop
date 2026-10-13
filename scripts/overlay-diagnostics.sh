#!/usr/bin/env bash
# 退出钩子也用于提前失败：保存已有原文，返回原始截图退出码。
save_overlay_diagnostics() {
  local status="$1"
  trap - EXIT
  if ! python3 "$SCRIPTS/overlay-diagnostics.py" preserve --work "$WORK" --output "$DIAGNOSTICS" --exit-status "$status"; then
    echo "保存浮窗诊断资料失败；截图退出码仍为 ${status}" >&2
  fi
  exit "$status"
}

#!/bin/bash
# 保留原门禁退出码；诊断写盘/采集失败不能把失败洗成通过或掩盖原错误。
preserve_startup_diagnostics() {
  local result=$?
  trap - EXIT
  {
    echo "$result" > "$DIAGNOSTICS/exit-status.txt"
    python3 "$ROOT/scripts/startup-diagnostics.py" collect --app "$APP" --output "$DIAGNOSTICS" \
      --start "$DIAGNOSTIC_START" --pids-file "$DIAGNOSTICS/launch-pids.txt"
  } || echo '::warning::启动诊断归档未完整生成' >&2
  exit "$result"
}

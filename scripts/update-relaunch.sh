#!/bin/sh
# 参数由更新器传入；只记录进程阶段和 open 的结果，不记录环境变量。
set -u
old_pid=$1
app=$2
opener=$3
max_wait=$4
shift 4
printf 'helper_started old_pid=%s\n' "$old_pid"
n=0
while /bin/kill -0 "$old_pid" 2>/dev/null; do
    if [ "$n" -ge "$max_wait" ]; then
        printf 'old_pid_timeout old_pid=%s\n' "$old_pid"
        exit 1
    fi
    /bin/sleep 0.2
    n=$((n + 1))
done
printf 'old_pid_exited old_pid=%s\n' "$old_pid"
# -n 避免 LaunchServices 把请求交给刚退出的旧实例。
"$opener" -n "$@" "$app"
result=$?
printf 'open_finished status=%s\n' "$result"
exit "$result"

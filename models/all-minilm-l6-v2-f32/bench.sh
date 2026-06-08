#!/usr/bin/env bash
# bench.sh - all-MiniLM-L6-v2 F32 embedding 速度基准测试
#
# 跑 4 个场景（单条 + 批量 10/50/100）× N 次（默认 3），输出 markdown 表格。
#
# 用法：
#   ./bench.sh                                  # 默认 http://localhost:8080, RUNS=3
#   ENDPOINT=http://1.2.3.4:8080 ./bench.sh     # 指定 endpoint
#   RUNS=5 ./bench.sh                           # 每场景跑 5 次

set -euo pipefail

ENDPOINT="${ENDPOINT:-http://localhost:8080}"
RUNS="${RUNS:-3}"

log()  { printf '[bench] %s\n' "$*"; }
die()  { printf '[bench] ERROR: %s\n' "$*" >&2; exit 1; }

command -v curl    >/dev/null || die "curl 未安装"
command -v python3 >/dev/null || die "python3 未安装"

curl -fsS "$ENDPOINT/health" >/dev/null \
    || die "server 不可达: $ENDPOINT/health （先 docker compose up -d）"

log "endpoint=$ENDPOINT  runs=$RUNS"

# 生成给定条数的文本列表
mk_texts() {
    local n="$1"
    local texts="["
    for i in $(seq 1 "$n"); do
        [ "$i" -gt 1 ] && texts="${texts},"
        local prompt="这是一段用于测试embedding模型的文本内容序号${i}"
        texts="${texts}$(python3 -c "import json; print(json.dumps('$prompt'))")"
    done
    texts="${texts}]"
    echo "$texts"
}

# 一次 embedding 请求，返回耗时（秒）
run_once() {
    local n="$1"
    local texts
    texts=$(mk_texts "$n")
    # 用 curl -w 捕获总耗时
    curl -sS -w '\n%{time_total}' -X POST "$ENDPOINT/v1/embeddings" \
        -H 'Content-Type: application/json' \
        -d "{\"input\": $texts}" \
    | tail -1
}

# 多次跑取平均，输出 "label|latency_ms|rps"
bench() {
    local label="$1" n="$2"
    local sum=0 t
    for _ in $(seq 1 "$RUNS"); do
        t=$(run_once "$n")
        sum=$(awk "BEGIN {print $sum+$t}")
    done
    local avg=$(awk "BEGIN {printf \"%.1f\", $sum/$RUNS}")
    local lat_ms=$(awk "BEGIN {printf \"%.1f\", ($avg/$n)*1000}")
    local rps=$(awk "BEGIN {printf \"%.1f\", $n/$avg}")
    echo "$label|$lat_ms|$rps"
}

# warm-up
log "warm-up..."
run_once 1 >/dev/null

log "running 4 scenarios × $RUNS runs..."

s1=$(bench "单条 (1)"  1)
s2=$(bench "小批 (10)" 10)
s3=$(bench "中批 (50)" 50)
s4=$(bench "大批 (100)" 100)

# 输出 markdown
cat <<EOF

## Embedding Bench Results

| 场景 | 每条延迟 (ms) | 吞吐 (text/s) |
|---|---:|---:|
EOF
for r in "$s1" "$s2" "$s3" "$s4"; do
    awk -F'|' '{printf "| %-8s | %12s | %11s |\n", $1, $2, $3}' <<<"$r"
done

echo
test_cmd="curl -sS -X POST $ENDPOINT/v1/embeddings \
    -H 'Content-Type: application/json' \
    -d '{\"input\": \"hello world\"}'"
echo "手动验证："
echo "  $test_cmd"

log "done."

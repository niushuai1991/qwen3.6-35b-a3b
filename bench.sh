#!/usr/bin/env bash
# bench.sh - Qwen3.6-35B-A3B 推理速度基准测试
#
# 跑 3 个场景（短/中/长 prompt）× N 次（默认 3），输出 markdown 表格 + VRAM 占用。
#
# 用法：
#   ./bench.sh                                    # 默认 http://localhost:8080, RUNS=3
#   ENDPOINT=http://1.2.3.4:8080 ./bench.sh       # 指定 endpoint
#   RUNS=5 ./bench.sh                             # 每场景跑 5 次
#   MODEL=xxx.gguf ./bench.sh                     # 指定模型名（与 /v1/models 一致）

set -euo pipefail

ENDPOINT="${ENDPOINT:-http://localhost:8080}"
MODEL="${MODEL:-Qwen3.6-35B-A3B-UD-IQ3_S.gguf}"
RUNS="${RUNS:-3}"

log()  { printf '[bench] %s\n' "$*"; }
die()  { printf '[bench] ERROR: %s\n' "$*" >&2; exit 1; }

command -v curl    >/dev/null || die "curl 未安装"
command -v python3 >/dev/null || die "python3 未安装"

curl -fsS "$ENDPOINT/health" >/dev/null \
    || die "server 不可达: $ENDPOINT/health （先 docker compose up -d）"

log "endpoint=$ENDPOINT  model=$MODEL  runs=$RUNS"

# 一次推理：打印 "prompt_tps predict_tps generated_tok"
run_once() {
    local prompt="$1" max="$2"
    local payload
    payload=$(python3 - "$prompt" "$max" "$MODEL" <<'PY'
import json, sys
prompt, max_tokens, model = sys.argv[1], int(sys.argv[2]), sys.argv[3]
print(json.dumps({
    "model": model,
    "messages": [{"role": "user", "content": prompt}],
    "max_tokens": max_tokens,
    "chat_template_kwargs": {"enable_thinking": False},
}))
PY
)
    curl -sS -X POST "$ENDPOINT/v1/chat/completions" \
        -H 'Content-Type: application/json' \
        -d "$payload" \
    | python3 -c "
import json, sys
d = json.load(sys.stdin)
ti = d['timings']
print(f\"{ti['prompt_per_second']:.1f} {ti['predicted_per_second']:.1f} {d['usage']['completion_tokens']}\")
"
}

# 多次跑取平均，输出 "label|prompt_tps|predict_tps|tok_per_run"
bench() {
    local label="$1" prompt="$2" max="$3"
    local p_sum=0 t_sum=0 n_sum=0 p t n
    for _ in $(seq 1 "$RUNS"); do
        IFS=' ' read -r p t n <<<"$(run_once "$prompt" "$max")"
        p_sum=$(awk "BEGIN {print $p_sum+$p}")
        t_sum=$(awk "BEGIN {print $t_sum+$t}")
        n_sum=$((n_sum+n))
    done
    local p_avg=$(awk "BEGIN {printf \"%.1f\", $p_sum/$RUNS}")
    local t_avg=$(awk "BEGIN {printf \"%.1f\", $t_sum/$RUNS}")
    local n_avg=$((n_sum/RUNS))
    echo "$label|$p_avg|$t_avg|$n_avg"
}

# warm-up（让 KV cache / CUDA graph 完成 lazy 初始化）
log "warm-up..."
run_once "hi" 4 >/dev/null

# 3 个场景
log "running 3 scenarios × $RUNS runs..."
long_pad="光合作用是植物利用光能将二氧化碳和水转化为有机物的过程，发生在叶绿体中。叶绿素吸收红光和蓝光，反射绿光，因此植物呈绿色。光合作用分两阶段：光反应产生 ATP 和 NADPH；暗反应固定碳合成葡萄糖。"
long_prompt="$long_pad$long_pad$long_pad 用一百字总结上述内容。"

short=$(bench "短 (10 / 64)"    "用一个汉字回答：天空是什么颜色" 64)
med=$(bench   "中 (20 / 256)"   "用一段话解释光合作用"            256)
long=$(bench  "长 (~200 / 512)" "$long_prompt"                    512)

# 输出 markdown
cat <<EOF

## Bench Results

| 场景 (in_tok / max_out) | prompt t/s | predict t/s | 实际 tok/run |
|---|---:|---:|---:|
EOF
for r in "$short" "$med" "$long"; do
    awk -F'|' '{printf "| %-22s | %10s | %10s | %10s |\n", $1, $2, $3, $4}' <<<"$r"
done

# 显存（仅当容器在跑）
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^qwen3\.6-35b-a3b$'; then
    echo
    echo "## VRAM"
    echo
    echo '```'
    docker exec qwen3.6-35b-a3b nvidia-smi \
        --query-gpu=name,memory.used,memory.total,utilization.gpu \
        --format=csv
    echo '```'
fi

log "done."

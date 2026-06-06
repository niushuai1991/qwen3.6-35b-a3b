#!/usr/bin/env bash
# research-model.sh - 拉取 HuggingFace 模型基础信息 + 搜索 GGUF 候选仓库 + 检查 llama.cpp 支持状态
#
# 用法：
#   ./research-model.sh <hf-repo-id> [llama.cpp-tag] [proxy]
#
# 例：
#   ./research-model.sh google/gemma-4-12B
#   ./research-model.sh google/gemma-4-12B b9847
#   ./research-model.sh google/gemma-4-12B b9847 http://localhost:7890
#   ./research-model.sh Qwen/Qwen3-30B-A3B master ""
#
# 输出三块：
#   1. Model Info        — arch / params / dtype / context / modalities
#   2. GGUF Sources      — HF 上候选仓库（official / full / partial）
#   3. llama.cpp Support — 指定 tag 是否包含目标 arch
#
# 退出码：
#   0  全部信息收集成功（不代表模型被 llama.cpp 支持）
#   1  参数错误 / HF 仓库不存在 / 严重网络错误

set -euo pipefail

die()  { printf '[research] ERROR: %s\n' "$*" >&2; exit 1; }
log()  { printf '[research] %s\n' "$*"; }
warn() { printf '[research] WARN: %s\n' "$*" >&2; }
hr()   { printf -- '---\n'; }

[ $# -ge 1 ] || die "用法: $0 <hf-repo-id> [llama.cpp-tag] [proxy]"

REPO="$1"
TAG="${2:-master}"
PROXY="${3:-${PROXY:-http://localhost:7890}}"
HF_BASE="https://huggingface.co"

#空字符串表示不走代理
CURL_PROXY=()
if [ -n "$PROXY" ]; then
    CURL_PROXY=(-x "$PROXY")
fi

curl_check() {
    curl -sS --max-time 20 "${CURL_PROXY[@]}" "$@" || {
        warn "请求失败: $*"
        return 1
    }
}

#####################################
# Phase 1: Model Info
#####################################
log "Phase 1: 拉取模型信息 (${REPO})"
hr

META_JSON=$(curl_check "${HF_BASE}/api/models/${REPO}") \
    || die "无法访问 HF API，检查仓库 ID 或代理设置"

# 拉模型 config.json 拿 dtype / context 等 API metadata 没暴露的字段
CONFIG_JSON=$(curl_check "${HF_BASE}/${REPO}/raw/main/config.json" 2>/dev/null || echo "{}")

export META_JSON CONFIG_JSON
python3 <<'PY'
import json, os
d = json.loads(os.environ["META_JSON"])
cfg = d.get("config", {}) or {}
try:
    cfg_file = json.loads(os.environ.get("CONFIG_JSON") or "{}")
except Exception:
    cfg_file = {}
archs = cfg.get("architectures") or cfg_file.get("architectures") or ["(未声明)"]
model_type = cfg.get("model_type") or cfg_file.get("model_type") or "(未声明)"
pipe_tag = d.get("pipeline_tag", "(未声明)")

total = 0
st = d.get("safetensors") or {}
for k, v in (st.get("parameters") or {}).items():
    total += v

text_cfg = (cfg_file.get("text_config") or {})
ctx = (
    cfg_file.get("max_position_embeddings")
    or text_cfg.get("max_position_embeddings")
    or cfg_file.get("seq_length")
    or 0
)
dtype = d.get("dtype") or cfg.get("dtype") or cfg_file.get("dtype") or text_cfg.get("dtype") or "(未声明)"

modalities = set()
mm_signals = (
    "image" in pipe_tag.lower()
    or "image" in model_type.lower()
    or "any-to-any" in pipe_tag.lower()
    or "multimodal" in model_type.lower()
    or "unified" in model_type.lower()
    or "vision_config" in cfg_file
    or "vision_config" in text_cfg
)
audio_signals = (
    "audio_config" in cfg_file
    or "audio_config" in text_cfg
    or "audio" in model_type.lower()
    or "any-to-any" in pipe_tag.lower()
)
if mm_signals:
    modalities.add("image")
if audio_signals:
    modalities.add("audio")
if not modalities:
    modalities.add("(仅文本)")

print(f"  ID:         {d.get('id')}")
print(f"  Arch:       {', '.join(archs)}")
print(f"  Model type: {model_type}")
print(f"  Pipeline:   {pipe_tag}")
if total:
    print(f"  Params:     {total/1e9:.2f}B")
else:
    print("  Params:     (未声明)")
print(f"  Dtype:      {dtype}")
if ctx:
    print(f"  Context:    {ctx}")
mods = ", ".join(sorted(modalities))
print(f"  Modalities: text -> text (+ {mods})")
print(f"  Created:    {d.get('createdAt', '?')}")
print(f"  Updated:    {d.get('lastModified', '?')}")
PY

#####################################
# Phase 2: GGUF Sources
#####################################
log ""
log "Phase 2: 搜索 GGUF 候选仓库"
hr

# 抽出 model 名（去掉组织前缀），用于搜索
MODEL_NAME=$(echo "$REPO" | awk -F/ '{print $NF}' | tr '[:upper:]' '[:lower:]')

# 用更宽的搜索词（model name + gguf）
SEARCH_QUERY="${MODEL_NAME}"

log "  搜索词: ${SEARCH_QUERY}"

SEARCH_JSON=$(curl_check "${HF_BASE}/api/models?search=${SEARCH_QUERY}&limit=50&full=true" 2>/dev/null || echo "[]")
export SEARCH_JSON
python3 <<'PY'
import json, os
try:
    data = json.loads(os.environ["SEARCH_JSON"])
except Exception:
    print("  (搜索失败或返回格式异常)")
    raise SystemExit(0)

def classify(repo_id, siblings):
    files = [s["rfilename"] for s in siblings if s.get("rfilename", "").endswith(".gguf")]
    has_mmproj = any("mmproj" in f.lower() for f in files)
    n_quant = len([f for f in files if "mmproj" not in f.lower()])

    if repo_id.startswith("ggml-org/"):
        kind = "official"
    elif n_quant >= 8:
        kind = "full"
    elif n_quant >= 1:
        kind = "partial"
    else:
        return None

    return (kind, n_quant, has_mmproj, files)

results = []
for m in data:
    sibs = m.get("siblings", [])
    info = classify(m["id"], sibs)
    if info:
        kind, n_q, has_mm, files = info
        results.append((m["id"], kind, n_q, has_mm, m.get("downloads", 0)))

priority = {"official": 0, "full": 1, "partial": 2}
results.sort(key=lambda x: (priority[x[1]], -x[4]))

if not results:
    print("  未找到 GGUF 仓库，可能需要本地 convert_hf_to_gguf.py 转换")
else:
    for rid, kind, n_q, has_mm, dl in results:
        tag = {"official": "[official]", "full": "[full]    ", "partial": "[partial] "}[kind]
        mm = "+mmproj" if has_mm else "       "
        print(f"  {tag} {mm} {rid:<50}  ({n_q} quants, dl={dl})")
PY

#####################################
# Phase 3: llama.cpp Support
#####################################
log ""
log "Phase 3: llama.cpp 支持检查 (tag: ${TAG})"
hr

ARCH_CPP_URL="https://raw.githubusercontent.com/ggml-org/llama.cpp/${TAG}/src/llama-arch.cpp"
CONVERSION_TREE_URL="https://github.com/ggml-org/llama.cpp/tree/${TAG}/conversion"

# 抓 arch.cpp
ARCH_CPP=$(curl_check "$ARCH_CPP_URL" 2>/dev/null || true)

if [ -z "$ARCH_CPP" ]; then
    warn "无法拉取 llama-arch.cpp (${ARCH_CPP_URL})"
    warn "可能 tag 不存在或网络问题。建议检查 https://github.com/ggml-org/llama.cpp/releases"
else
    log "  llama-arch.cpp 拉取成功 (length=$(printf '%s' "$ARCH_CPP" | wc -c))"

    # 推断 arch 名：从 model_type 推（如 gemma4_unified -> gemma4）
    MODEL_TYPE=$(echo "$META_JSON" | python3 -c '
import json, sys
d = json.load(sys.stdin)
cfg = d.get("config", {}) or {}
print(cfg.get("model_type", "").lower())
')

    # 从 model_type 推断可能的 LLM_ARCH_xxx 名字
    CANDIDATES=$(python3 -c '
import re, sys
mt = "'"$MODEL_TYPE"'"
# 把 _unified / _text / _audio / _vision 后缀去掉
base = re.sub(r"_(unified|text|audio|vision|causal)$", "", mt)
print(base)
# 也可能就是 mt 本身
if base != mt:
    print(mt)
')

    log "  目标 arch 候选词: $(echo "$CANDIDATES" | tr "\n" " ")"

    matched=""
    for cand in $CANDIDATES; do
        # 在 llama-arch.cpp 里搜类似 `LLM_ARCH_GEMMA4, "gemma4"` 的行
        if printf '%s' "$ARCH_CPP" | grep -qiE "LLM_ARCH_[A-Z0-9]+,\s+\"${cand}_?\"" 2>/dev/null; then
            matched="$cand"
            break
        fi
        # 大小写不敏感的子串匹配（如 gemma4_unified -> 搜 gemma4）
        if printf '%s' "$ARCH_CPP" | grep -qiE "\"${cand}\""; then
            matched="$cand"
            break
        fi
    done

    # 兜底：直接 grep model_type 的核心部分（小写）
    if [ -z "$matched" ]; then
        for cand in $CANDIDATES; do
            cand_upper=$(echo "$cand" | tr '[:lower:]' '[:upper:]')
            if echo "$ARCH_CPP" | grep -q "LLM_ARCH_${cand_upper}"; then
                matched="$cand"
                break
            fi
        done
    fi

    if [ -n "$matched" ]; then
        log "  ✅ Supported: 在 llama-arch.cpp 中找到 arch = \"${matched}\""
        log ""
        log "  对应行:"
        echo "$ARCH_CPP" | grep -iE "\"${matched}\"" | head -3 | sed 's/^/    /'

        # 进一步查 conversion 目录里相关 converter class
        log ""
        log "  检查 conversion 模块里的注册 class:"

        # 抓 conversion 目录列表
        # GitHub 不开 API（限流），直接试常见路径
        GEMMA_PY_URL="https://raw.githubusercontent.com/ggml-org/llama.cpp/${TAG}/conversion/gemma.py"
        CONV_GEMMA=$(curl_check "$GEMMA_PY_URL" 2>/dev/null || true)
        if [ -n "$CONV_GEMMA" ] && echo "$CONV_GEMMA" | grep -q "${matched^}"; then
            log "    conversion/gemma.py 里有 ${matched^} 相关 class:"
            echo "$CONV_GEMMA" | grep -E "class\s+${matched^}\w*|register\(\"${matched^}\w*\"" \
                | head -8 | sed 's/^/      /'
        else
            # 兜底：尝试 conversion/<base>.py
            BASE_CAND=$(echo "$matched" | sed -E 's/[0-9]+$//')
            OTHER_URL="https://raw.githubusercontent.com/ggml-org/llama.cpp/${TAG}/conversion/${BASE_CAND}.py"
            OTHER=$(curl_check "$OTHER_URL" 2>/dev/null || true)
            if [ -n "$OTHER" ]; then
                log "    conversion/${BASE_CAND}.py 里有相关 class:"
                echo "$OTHER" | grep -iE "class\s+\w*${matched^}\w*|register\(\".*${matched^}\w*\"" \
                    | head -8 | sed 's/^/      /'
            else
                warn "    无法自动定位 conversion 模块（可能要扫整个 conversion/ 目录）"
            fi
        fi
    else
        log "  ❌ Not supported (tag=${TAG})"
        log "  llama-arch.cpp 里未找到匹配 arch。可能："
        log "    1. 该 tag 早于模型 arch 合入；改 tag 参数试 master 或更新版本"
        log "    2. 模型还没适配；去 https://github.com/ggml-org/llama.cpp/issues 搜 model 名"
        log "    3. arch 命名特殊；手动看 ${ARCH_CPP_URL} 复核"
    fi
fi

log ""
log "Done."

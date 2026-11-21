#!/bin/sh
set -eu

model=/models/Qwen3-8B-Q4_K_M.gguf
if [ ! -r "$model" ]; then
    echo "Model is missing or unreadable: $model" >&2
    exit 1
fi

exec /opt/llama/bin/llama-server \
    --model "$model" \
    --alias qwen3-8b \
    --host 0.0.0.0 --port 8080 \
    --n-gpu-layers 0 \
    --threads "${QWEN_THREADS:-6}" \
    --threads-batch "${QWEN_THREADS_BATCH:-6}" \
    --ctx-size "${QWEN_CTX_SIZE:-4096}" \
    --parallel "${QWEN_PARALLEL:-1}" \
    --jinja --chat-template-kwargs '{"enable_thinking":false}' \
    --sleep-idle-seconds -1 \
    "$@"

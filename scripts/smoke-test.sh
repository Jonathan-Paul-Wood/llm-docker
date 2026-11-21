#!/usr/bin/env bash
set -euo pipefail
# Set these explicitly when you changed .env; this script does not execute .env.
base_url=${QWEN_BASE_URL:-http://127.0.0.1:8080}
base_url=${base_url%/}
headers=(-H 'Content-Type: application/json')
if [[ -n ${QWEN_API_KEY:-} ]]; then
    headers+=(-H "Authorization: Bearer $QWEN_API_KEY")
fi
curl --fail-with-body --silent --show-error --max-time 10 "$base_url/health"
printf '\n'
curl --fail-with-body --silent --show-error --max-time 300 \
    "$base_url/v1/chat/completions" "${headers[@]}" --data-binary @- <<'JSON'
{
  "model": "qwen3-8b",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant. Answer concisely."},
    {"role": "user", "content": "Explain what a Linux systemd service does in one sentence."}
  ],
  "temperature": 0.7,
  "top_p": 0.8,
  "top_k": 20,
  "min_p": 0,
  "presence_penalty": 1.5,
  "max_tokens": 128,
  "stream": false
}
JSON
printf '\n'

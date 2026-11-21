#!/bin/sh
set -eu

: "${MODEL_REVISION:?MODEL_REVISION must be set}"
: "${MODEL_SHA256:?MODEL_SHA256 must be set}"
cache_dir=${MODEL_CACHE_DIR:-/var/cache/qwen}
output_dir=${MODEL_OUTPUT_DIR:-/models}
attempts=${MODEL_DOWNLOAD_ATTEMPTS:-10}
retry_delay=${MODEL_RETRY_DELAY:-5}
case "$attempts" in
    ''|*[!0-9]*|0) echo 'MODEL_DOWNLOAD_ATTEMPTS must be positive.' >&2; exit 1 ;;
esac
mkdir -p "$cache_dir" "$output_dir"
cached="$cache_dir/$MODEL_SHA256.gguf"
partial="$cached.part"
url="https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/$MODEL_REVISION/Qwen3-8B-Q4_K_M.gguf"

verified() {
    [ -f "$1" ] && printf '%s  %s\n' "$MODEL_SHA256" "$1" | sha256sum --check --strict --status
}

if ! verified "$cached"; then
    # A bad completed cache entry must never be served or copied into the image.
    rm -f "$cached"
    attempt=1
    while :; do
        # Also handles a completed transfer interrupted before rename or checksum.
        if verified "$partial"; then
            mv "$partial" "$cached"
            break
        fi
        echo "Downloading model (attempt $attempt/$attempts; resuming cached partial file)..." >&2
        status=0
        # Separate invocations recompute the resume offset after every failure.
        # HTTP/1.1 avoids the HTTP/2 stream cancellation seen on large transfers.
        curl --http1.1 --fail --location --show-error \
            --connect-timeout 30 --speed-limit 1024 --speed-time 120 \
            --continue-at - --output "$partial" "$url" || status=$?
        if [ "$status" -eq 0 ]; then
            if ! verified "$partial"; then
                echo 'Model checksum mismatch; removing invalid partial file. Rebuild to download again.' >&2
                rm -f "$partial"
                exit 1
            fi
            mv "$partial" "$cached"
            break
        fi
        if [ "$status" -eq 33 ]; then
            echo 'Server refused download resumption; retrying from the beginning.' >&2
            rm -f "$partial"
        fi
        if [ "$attempt" -ge "$attempts" ]; then
            echo 'Download retries exhausted. Partial file remains in the BuildKit cache; rerun the build to resume.' >&2
            exit "$status"
        fi
        attempt=$((attempt + 1))
        sleep "$retry_delay"
    done
fi
cp "$cached" "$output_dir/Qwen3-8B-Q4_K_M.gguf"

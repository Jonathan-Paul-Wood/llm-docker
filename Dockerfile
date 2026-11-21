# syntax=docker/dockerfile:1
FROM ubuntu:24.04 AS download
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
ARG MODEL_REVISION=7c41481f57cb95916b40956ab2f0b139b296d974
ARG MODEL_SHA256=d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785
RUN mkdir -p /models && \
    curl --fail --location --retry 5 --retry-delay 5 \
      --output /models/Qwen3-8B-Q4_K_M.gguf.part \
      "https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/${MODEL_REVISION}/Qwen3-8B-Q4_K_M.gguf" && \
    echo "${MODEL_SHA256}  /models/Qwen3-8B-Q4_K_M.gguf.part" | sha256sum --check --strict && \
    mv /models/Qwen3-8B-Q4_K_M.gguf.part /models/Qwen3-8B-Q4_K_M.gguf && \
    curl --fail --location --retry 5 \
      --output /models/LICENSE \
      "https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/${MODEL_REVISION}/LICENSE" && \
    chmod 0644 /models/*

FROM ubuntu:24.04 AS build
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential cmake ninja-build git ca-certificates libssl-dev libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*
# llama.cpp v1.0.0. Keep an immutable source revision rather than tracking master.
ARG LLAMA_CPP_REF=2d8a32502909ca065c41c4cf5f2fb1c427c047fc
ARG BUILD_JOBS=6
WORKDIR /src
RUN git init llama.cpp && cd llama.cpp && \
    git remote add origin https://github.com/ggml-org/llama.cpp.git && \
    git fetch --depth 1 origin "${LLAMA_CPP_REF}" && git checkout --detach FETCH_HEAD && \
    git rev-parse HEAD > /src/llama.cpp.commit
# Runtime CPU dispatch avoids compiling only for the build machine's processor.
RUN cmake -S llama.cpp -B llama.cpp/build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON \
      -DGGML_NATIVE=OFF -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON \
      -DGGML_CUDA=OFF -DGGML_VULKAN=OFF \
      -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF \
      -DLLAMA_BUILD_UI=OFF -DLLAMA_USE_PREBUILT_UI=OFF && \
    cmake --build llama.cpp/build --target llama-server --parallel "${BUILD_JOBS}"

FROM ubuntu:24.04 AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl libcurl4t64 libssl3t64 libgomp1 libstdc++6 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 qwen \
    && useradd --uid 10001 --gid qwen --no-create-home --home-dir /nonexistent \
       --shell /usr/sbin/nologin qwen
WORKDIR /opt/qwen
# Include shared libraries and dynamically selected CPU backends beside the binary.
COPY --from=build /src/llama.cpp/build/bin/ /opt/llama/bin/
COPY --from=build /src/llama.cpp.commit /opt/qwen/llama.cpp.commit
COPY --from=build /src/llama.cpp/LICENSE /opt/qwen/licenses/llama.cpp.LICENSE
COPY --from=download /models/ /models/
COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/qwen-entrypoint
ENV LD_LIBRARY_PATH=/opt/llama/bin \
    HOME=/tmp \
    QWEN_THREADS=6 \
    QWEN_THREADS_BATCH=6 \
    QWEN_CTX_SIZE=4096 \
    QWEN_PARALLEL=1
USER 10001:10001
RUN /opt/llama/bin/llama-server --version
EXPOSE 8082
STOPSIGNAL SIGTERM
HEALTHCHECK --interval=10s --timeout=5s --start-period=300s --retries=6 \
    CMD curl --fail --silent --show-error http://127.0.0.1:8082/health || exit 1
ENTRYPOINT ["/usr/local/bin/qwen-entrypoint"]

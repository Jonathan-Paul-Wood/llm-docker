# Qwen3-8B Docker server

Build a self-contained CPU inference image, copy it to a Linux server, and expose an OpenAI-compatible API. The image includes llama.cpp and **Qwen3-8B-Q4_K_M.gguf** (5,027,783,488 bytes). Once the image is built or loaded, startup and inference require no internet connection, Python, GPU, or model volume.

This packages the supplied systemd setup. Docker runs llama-server as the main process and handles restarts; the host's Docker service handles startup after reboot. Do not run systemd inside the container.

## Defaults

| Setting | Value |
| --- | --- |
| Host endpoint | `http://127.0.0.1:8082/v1` |
| Model name | `qwen3-8b` |
| CPU threads / prompt threads | 6 / 6 |
| Context / simultaneous generation slots | 4096 tokens / 1 |
| Thinking | Disabled |
| Authentication | None; optional `QWEN_API_KEY` |
| Memory ceiling | 22,000,000,000 bytes, with swap disabled |
| Memory reservation | 18,000,000,000 bytes |
| Restart policy | `unless-stopped` |

The reservation is Docker's soft memory reservation, not systemd's `MemoryHigh` throttling control. The hard limit can cause an out-of-memory kill if exceeded. Docker will restart the process after a crash. An unhealthy status by itself does not trigger a Docker restart.

The image runs as UID/GID 10001 with a read-only root filesystem, a small temporary filesystem, and dropped Linux capabilities. Logs rotate automatically.

## Requirements

- Remote host: Ubuntu 22.04/24.04 or Debian 12+, Docker Engine with Compose v2 or newer, and sudo or Docker access.
- Plan for a 24 GB RAM host and at least 25 GB free disk during building/exporting/loading. Compilation and image caches need additional space. CPU inference performance depends on the processor and request length.
- Default architecture: Linux x86-64 (`linux/amd64`). For an ARM64 server, build for `linux/arm64` and set the same `QWEN_PLATFORM` in `.env`. Images must match the remote host's architecture.
- Building needs internet access to Ubuntu packages, GitHub, and Hugging Face. The model is checksum verified before being included. The first build downloads about 5 GB of model weights and compiles several CPU backends; allow time for both.

## Option A: Build and export on Windows, then copy to the server

Start Docker Desktop using Linux containers. In PowerShell, from this folder:

```powershell
.\scripts\build-image.ps1 -OutputArchive qwen3-8b-image.tar
```

This builds `open-llm-qwen3:1.0` and exports the complete image, including weights. If local PowerShell policy blocks the script, run it for this process:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-image.ps1 -OutputArchive qwen3-8b-image.tar
```

Replace `user@server` with your SSH destination:

```powershell
ssh user@server 'mkdir -p ~/llm-docker'
scp compose.yaml .env.example user@server:~/llm-docker/
scp -r scripts user@server:~/llm-docker/
scp qwen3-8b-image.tar user@server:~/llm-docker/
ssh user@server
```

On the remote Linux host:

```bash
cd ~/llm-docker
# Only needed if Docker Engine / Compose are not already installed:
sudo bash scripts/install-docker.sh

cp .env.example .env
chmod 600 .env
# Edit .env now if you want a different IP, port, thread count, or API key.
sudo bash scripts/deploy.sh --load qwen3-8b-image.tar
bash scripts/smoke-test.sh
```

The deploy script loads the image and starts Compose without building or pulling anything. It waits up to 600 seconds for a healthy server, then reports success. It prints logs if readiness fails. Relative archive paths are relative to the project folder. Docker installation needs network access; an already provisioned host can load and run this image offline.

## Option B: Build directly on the remote Linux server

Copy the entire project folder to the server, including `Dockerfile` and `docker/entrypoint.sh`. Then:

```bash
cd ~/llm-docker
sudo bash scripts/install-docker.sh
cp .env.example .env
chmod 600 .env
sudo bash scripts/deploy.sh --build
bash scripts/smoke-test.sh
```

Reduce `BUILD_JOBS` in `.env` if compilation uses too much memory. The build uses CPU dispatch rather than `-march=native`, so the resulting image selects an appropriate included CPU backend on the deployment machine.

## Option C: Distribute through a registry

Use an image name in a registry you control:

```powershell
.\scripts\build-image.ps1 -Image registry.example.com/team/qwen3-8b:1.0
docker push registry.example.com/team/qwen3-8b:1.0
```

On the server, set `QWEN_IMAGE=registry.example.com/team/qwen3-8b:1.0` in `.env`, authenticate to the registry if needed, and run:

```bash
sudo bash scripts/deploy.sh --pull
```

For custom image names built or loaded by other means, `.env` must name the exact image tag.

## Configuration and application access

Copy `.env.example` to `.env` and adjust settings there. The deploy script creates a private default `.env` if none exists. After editing, recreate the container:

```bash
sudo docker compose up -d --no-build --pull never --wait --wait-timeout 600
```

The server listens on `0.0.0.0:8082` **inside** its container so port forwarding works. Compose publishes it on host loopback by default.

- Applications on the host: base URL `http://127.0.0.1:8082/v1`, model `qwen3-8b`. Clients requiring a key field can use `local` when authentication is disabled.
- Other Compose services on the same Docker network: `http://qwen:8082/v1`. For a separate Compose project, attach the calling service to the existing `open-llm_default` external network. No published host port is needed for this path.
- A Linux container using host networking can use `http://127.0.0.1:8082/v1` directly.
- Your local workstation can use an SSH tunnel: `ssh -N -L 8082:127.0.0.1:8082 user@server`.
- For LAN access, set `QWEN_BIND_IP` to the server's private IP, set `QWEN_API_KEY`, and restrict access at the network firewall. Use a TLS reverse proxy for access across untrusted networks. Docker port publishing has its own firewall rules; do not assume UFW alone restricts it.

If authentication is enabled, send `Authorization: Bearer YOUR_KEY`. Keep `.env` private. For the smoke test, explicitly supply changes rather than sourcing `.env`:

```bash
QWEN_BASE_URL=http://127.0.0.1:8082 QWEN_API_KEY='your-key' bash scripts/smoke-test.sh
```

Requests need their own conversation history. The 4096-token context includes the prompt and generated output; increasing context or parallelism uses more memory. Allow generous CPU inference timeouts and queue requests in your application when necessary.

## Health, API test, and operation

```bash
curl --fail --show-error http://127.0.0.1:8082/health
bash scripts/smoke-test.sh

sudo docker compose ps
sudo docker compose logs -f --tail 100 qwen
sudo docker stats
sudo docker compose stop                 # Stop and release model RAM
sudo docker compose start                # Start an existing stopped container
sudo docker compose restart qwen
sudo docker compose down                # Remove containers/network; keep the image
```

`/health` returns 503 while loading and 200 when ready. The smoke test sends a short chat request using the sampling settings from the supplied notes and prints the JSON response; generated text is in `choices[0].message.content`.

Docker must start at boot. The installation script enables it with `systemctl enable --now docker`. On a host with Docker installed separately, enable that service using your host's service manager. The `unless-stopped` policy restarts the container after reboot unless you explicitly stopped it.

For troubleshooting, inspect `docker compose logs --tail 100 qwen`. Check for an occupied port, insufficient memory, or an image architecture mismatch. Initial model loading or CPU warmup can take time. A readiness timeout leaves the container available for diagnosis.

### Interrupted model downloads during builds

The downloader uses HTTP/1.1 and retries interrupted downloads up to ten times, resuming from the saved byte offset. A BuildKit cache mount retains partial files even if the build fails. Rerun `sudo bash scripts/deploy.sh --build` on the same Docker builder to resume. Keep the build cache; pruning it removes saved downloads. The final model must pass the pinned SHA-256 check before it enters the image.

If upgrading from the original Dockerfile after `curl: (92) HTTP/2 stream ... CANCEL`, copy the updated `Dockerfile`, `.dockerignore`, and `docker/download-model.sh` to the server, then rerun the build. The original failed layer did not have a cache mount, so its partial download cannot be resumed by this version. Other successful build layers can still be reused.

## Versions and upstream references

- llama.cpp source: `2d8a32502909ca065c41c4cf5f2fb1c427c047fc` (v1.0.0), recorded inside the image at `/opt/qwen/llama.cpp.commit`.
- Model repository revision: `7c41481f57cb95916b40956ab2f0b139b296d974`.
- Model SHA-256: `d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785`.
- Base image and Ubuntu package updates are resolved at build time; source/model pins do not make the whole OS image bit-for-bit reproducible.

Change source/model pins deliberately in `Dockerfile`, build with a new image tag, test it, then deploy. Keep the previous image tag for rollback by changing `QWEN_IMAGE` and recreating the container. Model and llama.cpp licenses are included in the image at `/models/LICENSE` and `/opt/qwen/licenses/llama.cpp.LICENSE`.

References: [official Qwen model and guidance](https://huggingface.co/Qwen/Qwen3-8B-GGUF), [model checksum](https://huggingface.co/Qwen/Qwen3-8B-GGUF/blob/main/Qwen3-8B-Q4_K_M.gguf), [pinned llama.cpp server documentation](https://github.com/ggml-org/llama.cpp/blob/2d8a32502909ca065c41c4cf5f2fb1c427c047fc/tools/server/README.md), [Docker on Ubuntu](https://docs.docker.com/engine/install/ubuntu/), [Docker on Debian](https://docs.docker.com/engine/install/debian/).

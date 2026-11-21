#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo 'Run with sudo: sudo bash scripts/install-docker.sh' >&2
    exit 1
fi
source /etc/os-release
case "$ID" in
    ubuntu|debian) ;;
    *) echo "Unsupported OS: $ID. Install Docker Engine and Compose manually." >&2; exit 1 ;;
esac

if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
    systemctl enable --now docker
    docker info >/dev/null
    echo 'Docker Engine and Compose are ready.'
    exit 0
fi
# Do not remove or replace conflicting packages on an existing host automatically.
for package in docker.io docker-compose docker-compose-v2 podman-docker containerd runc; do
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -qx 'install ok installed'; then
        echo "Existing package $package conflicts with Docker CE. Resolve it using Docker's installation documentation." >&2
        exit 1
    fi
done

apt-get update
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl --fail --silent --show-error --location --retry 5 \
    "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
codename=${UBUNTU_CODENAME:-$VERSION_CODENAME}
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/$ID
Suites: $codename
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
docker info >/dev/null
docker compose version
echo 'Docker is ready. Use sudo for Docker commands unless your account already has access.'

ARG CONTAINER_REGISTRY=docker.io
ARG GITHUB_HOST=github.com

FROM ${CONTAINER_REGISTRY}/jetbrains/teamcity-minimal-agent:2026.1.3-linux

ARG GITHUB_HOST

USER root

ARG APT_REPOSITORY
ARG APT_SECURITY_REPOSITORY
ARG PODMAN_VERSION=6.0.2
ARG PODMAN_SHA256=73ca9840cfa4d819e2def9274e4e1d16dc8396a230e19f7e362266312f31d4a4
ARG COMPOSE_VERSION=5.3.1
ARG COMPOSE_SHA256=f9ebc6ebdb19d769b793c245a736caaeb198c62587f13b25c660c13b4987f959

RUN <<APT_CONFIG
set -eu

. /etc/os-release
: "${APT_REPOSITORY:?APT_REPOSITORY is required}"
: "${APT_SECURITY_REPOSITORY:?APT_SECURITY_REPOSITORY is required}"
: "${VERSION_CODENAME:?The Ubuntu VERSION_CODENAME is required}"

rm --force \
    /etc/apt/sources.list \
    /etc/apt/sources.list.d/*.list \
    /etc/apt/sources.list.d/*.sources

cat > /etc/apt/sources.list.d/ubuntu.sources <<UBUNTU_SOURCES
Types: deb
URIs: ${APT_REPOSITORY}
Suites: ${VERSION_CODENAME} ${VERSION_CODENAME}-updates ${VERSION_CODENAME}-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: ${APT_SECURITY_REPOSITORY}
Suites: ${VERSION_CODENAME}-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
UBUNTU_SOURCES
APT_CONFIG

RUN <<INSTALL_TOOLS
set -eu

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
    ca-certificates \
    curl \
    git \
    tar

curl --fail --location --show-error \
    "https://${GITHUB_HOST}/podman-container-tools/podman/releases/download/v${PODMAN_VERSION}/podman-remote-static-linux_amd64.tar.gz" \
    --output /tmp/podman-remote.tar.gz
echo "${PODMAN_SHA256}  /tmp/podman-remote.tar.gz" | sha256sum --check --strict
tar --extract --gzip --file /tmp/podman-remote.tar.gz --directory /tmp
install --mode 0755 /tmp/bin/podman-remote-static-linux_amd64 /usr/local/bin/podman

curl --fail --location --show-error \
    "https://${GITHUB_HOST}/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
    --output /tmp/docker-compose
echo "${COMPOSE_SHA256}  /tmp/docker-compose" | sha256sum --check --strict
install --mode 0755 /tmp/docker-compose /usr/local/bin/docker-compose

rm --recursive --force /tmp/podman-remote.tar.gz /tmp/bin /tmp/docker-compose
rm --recursive --force /var/lib/apt/lists/*
INSTALL_TOOLS

COPY --chown=root:root podman-compose.sh /usr/local/bin/podman-compose
RUN chmod 0755 /usr/local/bin/podman-compose

ENV CONTAINER_HOST=unix:///run/user/1000/podman/podman.sock \
    DOCKER_HOST=unix:///run/user/1000/podman/podman.sock

USER buildagent

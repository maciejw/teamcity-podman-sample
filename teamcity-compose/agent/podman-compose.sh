#!/bin/sh
set -eu

if [ -n "${COMPOSE_PROJECT_NAME:-}" ]; then
    COMPOSE_PROJECT_NAME="$(printf '%s' "$COMPOSE_PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-')"
    export COMPOSE_PROJECT_NAME
fi

if [ "${1:-}" = "--version" ] && [ "$#" -eq 1 ]; then
    echo "podman-compose version 5.3.1"
    exit 0
fi

exec /usr/local/bin/docker-compose "$@"

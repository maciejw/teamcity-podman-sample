#!/bin/sh
set -eu

if [ "${1:-}" = "--version" ] && [ "$#" -eq 1 ]; then
    echo "podman-compose version 5.3.1"
    exit 0
fi

exec /usr/local/bin/docker-compose "$@"

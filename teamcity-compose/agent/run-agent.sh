#!/bin/bash

set -eu

AGENT_TEMPLATE=/opt/buildagent
if [ -n "${TEAMCITY_AGENT_HOME:-}" ]; then
  AGENT_DIST="$TEAMCITY_AGENT_HOME"
else
  AGENT_ROOT="${TEAMCITY_AGENT_ROOT:-/opt/teamcity-agents}"
  CONTAINER_ID="$(cat /etc/hostname)"
  CONTAINER_NAME="$(podman inspect --format '{{.Name}}' "$CONTAINER_ID")"
  CONTAINER_NAME="${CONTAINER_NAME#/}"

  case "$CONTAINER_NAME" in
    *[!A-Za-z0-9_.-]*|'')
      echo "Could not determine a safe container name: $CONTAINER_NAME" >&2
      exit 1
      ;;
  esac

  AGENT_DIST="$AGENT_ROOT/$CONTAINER_NAME"
  AGENT_NAME="${AGENT_NAME:-$CONTAINER_NAME}"
fi

CONFIG_FILE="${TEAMCITY_AGENT_CONFIG_FILE:-$AGENT_DIST/conf/buildAgent.properties}"
CONFIG_DIR="$(dirname "$CONFIG_FILE")"
LOG_DIR="$AGENT_DIST/logs"
export CONFIG_FILE LOG_DIR

case "$AGENT_DIST" in
  /*) ;;
  *)
    echo "TEAMCITY_AGENT_HOME must be an absolute path: $AGENT_DIST" >&2
    exit 1
    ;;
esac

if [ ! -x "$AGENT_DIST/bin/agent.sh" ]; then
  echo "Initializing TeamCity agent home at $AGENT_DIST"
  mkdir -p "$AGENT_DIST"
  cp -a "$AGENT_TEMPLATE/." "$AGENT_DIST/"
fi

mkdir -p "$CONFIG_DIR" "$LOG_DIR"
rm -f "$LOG_DIR"/*.pid

configure() {
  "$AGENT_DIST/bin/agent.sh" configure "$@"
}

reconfigure() {
  local -a options=()

  [ -n "${SERVER_URL:-}" ]  && options+=(--server-url "$SERVER_URL")
  [ -n "${AGENT_TOKEN:-}" ] && options+=(--auth-token "$AGENT_TOKEN")
  [ -n "${AGENT_NAME:-}" ]  && options+=(--name "$AGENT_NAME")
  [ -n "${OWN_ADDRESS:-}" ] && options+=(--ownAddress "$OWN_ADDRESS")
  [ -n "${OWN_PORT:-}" ]    && options+=(--ownPort "$OWN_PORT")

  if [ "${#options[@]}" -gt 0 ]; then
    configure "${options[@]}"
  fi
}

if [ ! -f "$CONFIG_FILE" ]; then
  if [ -z "${SERVER_URL:-}" ]; then
    echo "SERVER_URL is required to initialize the TeamCity agent." >&2
    exit 1
  fi

  cp -p "$AGENT_DIST"/conf/*.* "$CONFIG_DIR/"
  cp -p "$CONFIG_DIR/buildAgent.dist.properties" "$CONFIG_FILE"
  for agent_option in ${AGENT_OPTS:-}; do
    echo "$agent_option" >> "$CONFIG_FILE"
  done
fi

reconfigure

stop_agent() {
  "$AGENT_DIST/bin/agent.sh" stop force || true
}

trap stop_agent INT TERM HUP

"$AGENT_DIST/bin/agent.sh" start

while [ ! -f "$LOG_DIR/teamcity-agent.log" ]; do
  sleep 1
done

tail -qF "$LOG_DIR/teamcity-agent.log" &
wait $!

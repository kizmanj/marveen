#!/bin/bash
set -e

# Support PUID/PGID for Unraid and similar NAS systems
PUID=${PUID:-1000}
PGID=${PGID:-1000}

if [ "$(id -u)" = "0" ]; then
    echo "[marveen] Jogosultság beállítás: uid=$PUID gid=$PGID"
    groupmod -o -g "$PGID" node
    usermod -o -u "$PUID" node
    chown -R node:node /app/store /home/node 2>/dev/null || true
    exec gosu node "$0" "$@"
fi

# Ensure store directory exists
mkdir -p /app/store

# Load .env if present (make vars available to this script)
if [ -f /app/.env ]; then
    set -o allexport
    source /app/.env
    set +o allexport
elif [ -f /app/.env.example ]; then
    env > /app/.env
fi

# Install telegram plugin if missing (fresh deploy or empty ~/.claude mount)
PLUGIN_CACHE="${HOME}/.claude/plugins/cache/claude-plugins-official/telegram"
if [ ! -d "$PLUGIN_CACHE" ]; then
    echo "[marveen] Telegram plugin telepítése..."
    claude plugin marketplace add anthropics/claude-plugins-official 2>/dev/null || true
    claude plugin install telegram@claude-plugins-official --dangerously-skip-permissions 2>/dev/null && \
        echo "[marveen] Telegram plugin telepítve." || \
        echo "[marveen] WARN: Telegram plugin telepítés sikertelen."
fi

# Fix plugin installPath: replace host absolute paths with container paths
PLUGIN_JSON="${HOME}/.claude/plugins/installed_plugins.json"
if [ -f "$PLUGIN_JSON" ]; then
    sed -i "s|/[^\"']*/\.claude/plugins|${HOME}/.claude/plugins|g" "$PLUGIN_JSON"
    echo "[marveen] Plugin útvonalak javítva."
fi

# Start tmux server first (channels.sh and backend both need it)
echo "[marveen] tmux szerver indítása..."
export MCP_SERVER_CONNECTION_BATCH_SIZE=10
export MCP_CONNECTION_NONBLOCKING=1
export MCP_TIMEOUT=60000
tmux start-server

# Start backend in background
echo "[marveen] Backend indítása..."
node /app/dist/index.js &
BACKEND_PID=$!

# Wait for backend to initialize
sleep 3

echo "[marveen] Kész. Dashboard: http://localhost:3420"
echo "[marveen] Claude session: tmux attach -t marveen-channels"

# channels.sh supervisor loop -- replaces launchd/systemd KeepAlive in Docker.
# channels.sh creates the tmux session, monitors claude, and exits when it dies.
# This loop restarts it, mirroring the service-manager behavior on native installs.
FAIL_COUNT=0
while true; do
    echo "[marveen] channels.sh indítása (attempt $((FAIL_COUNT+1)))..."
    bash /app/scripts/channels.sh || true
    EXIT_CODE=$?

    # If backend died, exit the container so Docker can restart it
    if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
        echo "[marveen] Backend leállt, konténer újraindítása..."
        exit 1
    fi

    FAIL_COUNT=$((FAIL_COUNT + 1))
    if [ "$FAIL_COUNT" -ge 5 ]; then
        echo "[marveen] 5 egymást követő channels.sh hiba -- 300s várakozás..."
        sleep 300
        FAIL_COUNT=0
    else
        echo "[marveen] channels.sh leállt (exit $EXIT_CODE), újraindítás 5s múlva..."
        sleep 5
    fi
done

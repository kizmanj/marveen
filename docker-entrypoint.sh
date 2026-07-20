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
    # cp /app/.env.example /app/.env
    # echo "[marveen] .env létrehozva .env.example alapján -- szerkeszd meg!"
    env > /app/.env
fi

# Resolve channel plugin ID from CHANNEL_PROVIDER env (default: telegram)
PROVIDER="${CHANNEL_PROVIDER:-telegram}"
case "$PROVIDER" in
    telegram)  PLUGIN_ID="telegram@claude-plugins-official" ;;
    slack)     PLUGIN_ID="slack-channel@marveen-marketplace" ;;
    discord)   PLUGIN_ID="discord@claude-plugins-official" ;;
    *)         PLUGIN_ID="${PROVIDER}" ;;
esac

# Start tmux server FIRST so the backend can send tmux commands immediately
echo "[marveen] tmux szerver indítása..."
export MCP_SERVER_CONNECTION_BATCH_SIZE=10
export MCP_CONNECTION_NONBLOCKING=1
export MCP_TIMEOUT=60000
tmux new-session -d -s marveen-channels -c /app

# Start backend service in background (tmux server already running)
echo "[marveen] Backend indítása..."
node /app/dist/index.js &
BACKEND_PID=$!

# Wait for backend to start, then launch claude in the session
sleep 3
echo "[marveen] Claude Code session indítása (plugin: $PLUGIN_ID)..."
tmux send-keys -t marveen-channels \
    "claude --dangerously-skip-permissions --channels plugin:${PLUGIN_ID}" Enter

echo "[marveen] Kész. Dashboard: http://localhost:3420"
echo "[marveen] Claude session: tmux attach -t marveen-channels"

# Keep container alive, restart backend if it dies
wait $BACKEND_PID

FROM node:20-slim

RUN apt-get update && apt-get install -y \
    tmux \
    git \
    python3 \
    python3-pip \
    sqlite3 \
    curl \
    procps \
    bash \
    gosu \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Bun (telegram plugin runtime) + Claude Code CLI
RUN curl -fsSL https://bun.sh/install | bash \
    && ln -s /root/.bun/bin/bun /usr/local/bin/bun
RUN npm install -g @anthropic-ai/claude-code \
    && node /usr/local/lib/node_modules/@anthropic-ai/claude-code/install.cjs
#RUN git clone https://github.com/Szotasz/marveen.git /app
RUN git clone --branch docker_build --single-branch https://github.com/kizmanj/marveen.git /app

# System-level managed settings (Linux path, not overridden by ~/.claude volume)
# Required for: allowedChannelPlugins (plugin whitelist) + channelsEnabled (org policy gate)
RUN mkdir -p /etc/claude-code && cat > /etc/claude-code/managed-settings.json <<'EOF'
{
  "channelsEnabled": true,
  "allowedChannelPlugins": [
    {"plugin": "telegram", "marketplace": "claude-plugins-official"},
    {"plugin": "slack-channel", "marketplace": "marveen-marketplace"},
    {"plugin": "teams", "marketplace": "marveen-marketplace"}
  ]
}
EOF

# Non-root user: reuse the existing 'node' user (uid 1000) from node:20-slim
RUN mkdir -p /home/node/.claude /app/store \
    && chown -R node:node /home/node /app

WORKDIR /app

# Signal to channel-monitor that an external supervisor (entrypoint loop) manages
# channels.sh restarts -- prevents in-process spawn from racing the loop.
ENV MARVEEN_CHANNELS_SUPERVISED=1

# Build as node user
RUN gosu node npm ci --production=false && gosu node npm run build

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 3420

ENTRYPOINT ["/docker-entrypoint.sh"]
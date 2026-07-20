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
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI (as root, before user switch)
RUN npm install -g @anthropic-ai/claude-code
#RUN git clone https://github.com/Szotasz/marveen.git /app
RUN git clone https://github.com/kizmanj/marveen.git /app

# Non-root user: reuse the existing 'node' user (uid 1000) from node:20-slim
RUN mkdir -p /home/node/.claude /app/store \
    && chown -R node:node /home/node /app

WORKDIR /app

# Build as node user
RUN gosu node npm ci --production=false && gosu node npm run build

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

EXPOSE 3420

ENTRYPOINT ["/docker-entrypoint.sh"]
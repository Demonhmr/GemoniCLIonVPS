# =============================================================================
# Gemini CLI — Docker Image (v3.0)
# Entrypoint runs as root → fixes volume perms → drops to gemini via gosu
# =============================================================================

FROM node:20-slim

LABEL maintainer="GemoniCLIonVPS"
LABEL description="Gemini CLI — hardened container with tmux persistent sessions"

# ---------------------------------------------------------------------------
# System dependencies
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        tmux \
        git \
        curl \
        bash \
        jq \
        less \
        ca-certificates \
        libsecret-1-0 \
        gosu \
    && npm install -g @google/gemini-cli \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Unprivileged user with fixed UID=1001
# ---------------------------------------------------------------------------
RUN useradd -m -u 1001 -s /bin/bash gemini

# ---------------------------------------------------------------------------
# tmux config
# ---------------------------------------------------------------------------
COPY --chown=gemini:gemini .tmux.conf /home/gemini/.tmux.conf

# ---------------------------------------------------------------------------
# Pre-create directories so gosu can always chown them
# ---------------------------------------------------------------------------
RUN mkdir -p /home/gemini/.gemini /workspace \
    && chown -R gemini:gemini /home/gemini /workspace

# ---------------------------------------------------------------------------
# Telegram Bot setup
# ---------------------------------------------------------------------------
COPY --chown=gemini:gemini bot /bot
RUN cd /bot && npm install

# ---------------------------------------------------------------------------
# Entrypoint: runs as root, fixes volume perms, drops to gemini via gosu
# ---------------------------------------------------------------------------
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /workspace

# Container runs as root until entrypoint drops to gemini
ENTRYPOINT ["/entrypoint.sh"]
CMD ["sleep", "infinity"]

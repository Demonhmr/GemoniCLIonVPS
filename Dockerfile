# =============================================================================
# Gemini CLI — Docker Image (v2.0, security-hardened)
# Auth: OAuth via Google (gemini login on first run)
# User: unprivileged 'gemini', UID 1001 (not root)
# =============================================================================

FROM node:20-slim

LABEL maintainer="GemoniCLIonVPS"
LABEL description="Gemini CLI — hardened container with tmux persistent sessions"

# ---------------------------------------------------------------------------
# System dependencies — minimal set, no-install-recommends
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        tmux \
        git \
        curl \
        bash \
        jq \
        less \
        ca-certificates \
    && npm install -g @google/gemini-cli \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Unprivileged user with fixed UID=1001 (predictable, auditable)
# ---------------------------------------------------------------------------
RUN useradd -m -u 1001 -s /bin/bash gemini

# ---------------------------------------------------------------------------
# tmux config
# ---------------------------------------------------------------------------
COPY --chown=gemini:gemini .tmux.conf /home/gemini/.tmux.conf

# ---------------------------------------------------------------------------
# Working directory (mounted as named volume at runtime)
# ---------------------------------------------------------------------------
RUN mkdir -p /workspace && chown gemini:gemini /workspace

USER gemini
WORKDIR /workspace

# ---------------------------------------------------------------------------
# sleep infinity: keeps container alive with zero I/O (better than tail -f)
# ---------------------------------------------------------------------------
CMD ["sleep", "infinity"]

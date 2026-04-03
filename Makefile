.PHONY: up down attach shell gemini logs update status version help

# =============================================================================
# Default target
# =============================================================================
help:
	@echo ""
	@echo "  🤖 Gemini CLI on VPS — Makefile commands"
	@echo ""
	@echo "  make up       — Build image and start container (detached)"
	@echo "  make down     — Stop and remove container"
	@echo "  make attach   — Connect to persistent tmux session (main command)"
	@echo "  make shell    — Open bash inside container (diagnostics)"
	@echo "  make gemini   — Run Gemini CLI directly (no tmux)"
	@echo "  make logs     — Follow container logs"
	@echo "  make update   — Rebuild image and recreate container"
	@echo "  make status   — Show container status"
	@echo "  make version  — Print installed Gemini CLI version"
	@echo ""

# =============================================================================
# Lifecycle
# =============================================================================

# Build and start container in detached mode
up:
	docker compose up -d --build

# Stop and remove container (volumes are preserved!)
down:
	docker compose down

# Rebuild image and recreate container (use after gemini-cli update)
# NOTE: docker compose pull is intentionally omitted — image is built locally
update:
	docker compose up -d --build --force-recreate

# =============================================================================
# Access
# =============================================================================

# Connect to persistent tmux session — this is the main daily-use command.
# If the session doesn't exist yet, a new one named 'main' is created.
# Detach with: Ctrl+A, D  (session stays alive)
attach:
	@docker exec -it gemini-cli-service tmux attach -t main 2>/dev/null \
	  || docker exec -it gemini-cli-service tmux new-session -s main -n gemini

# Open bash shell inside container (useful for diagnostics)
shell:
	docker exec -it gemini-cli-service bash

# Run Gemini CLI interactively (TERM=xterm fixes SSH+Docker input issues)
gemini:
	docker exec -e TERM=xterm -it gemini-cli-service gemini

# Send a single prompt and get a response (most reliable on Windows SSH)
# Usage: make ask Q="your question here"
ask:
	@docker exec -it gemini-cli-service gemini -p "$(Q)"

# =============================================================================
# Monitoring
# =============================================================================

# Follow container stdout/stderr logs
logs:
	docker compose logs -f

# Show container running status and uptime
status:
	docker compose ps

# Print Gemini CLI version installed inside container
version:
	@docker exec gemini-cli-service gemini --version

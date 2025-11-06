#!/bin/bash

# Sync Project to VM
# Usage: ./sync-project.sh [dry-run]  # Add 'dry-run' arg to preview changes without syncing

set -euo pipefail  # Exit on errors, undefined vars, pipe failures

# Config (edit these as needed)
SOURCE_DIR="/mnt/c/Users/theon/Desktop/Home Lab Network Simulation/"
REMOTE_USER="yeah"
REMOTE_HOST="192.168.68.105"
REMOTE_PATH="/home/yeah/homelab/"
LOG_FILE="$HOME/sync-project-$(date +%Y%m%d-%H%M%S).log"

# Excludes
EXCLUDES=('.git' 'logs')

# Function for logging
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Check if dry-run
DRY_RUN=""
if [[ "${1:-}" == "dry-run" ]]; then
    DRY_RUN="--dry-run"
    log "Dry-run mode: Previewing changes only"
fi

# Build rsync command
RSYNC_CMD="rsync -avz ${DRY_RUN} "
for exclude in "${EXCLUDES[@]}"; do
    RSYNC_CMD+="--exclude '$exclude' "
done
RSYNC_CMD+="\"$SOURCE_DIR\" ${REMOTE_USER}@${REMOTE_HOST}:\"$REMOTE_PATH\""

log "Starting sync from: $SOURCE_DIR"
log "   To: $REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH"
log "   Excludes: ${EXCLUDES[*]}"

# Run rsync
if eval "$RSYNC_CMD" 2>&1 | tee -a "$LOG_FILE"; then
    log "Sync completed successfully!"
    log "   Full log: $LOG_FILE"
else
    log "Sync failed—check log: $LOG_FILE"
    exit 1
fi

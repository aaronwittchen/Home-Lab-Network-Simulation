#!/bin/bash
#
# Master Setup Script
# Purpose: Build entire home lab network with one command
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/homelab-setup-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] ✓ $*${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ✗ $*${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ⚠ $*${NC}" | tee -a "$LOG_FILE"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root"
   exit 1
fi

log "=========================================="
log "Home Lab Network Setup"
log "=========================================="
log "Log file: $LOG_FILE"
log ""

# Step 1: Create namespaces
log "Step 1/6: Creating network namespaces..."
if bash "$SCRIPT_DIR/01-create-namespaces.sh" >> "$LOG_FILE" 2>&1; then
    log_success "Namespaces created"
else
    log_error "Failed to create namespaces"
    exit 1
fi

# Step 2: Create veth pairs
log "Step 2/6: Creating virtual ethernet pairs..."
if bash "$SCRIPT_DIR/02-create-links.sh" >> "$LOG_FILE" 2>&1; then
    log_success "Virtual links created"
else
    log_error "Failed to create links"
    exit 1
fi

# Step 3: Configure IP addresses
log "Step 3/6: Configuring IP addresses..."
if bash "$SCRIPT_DIR/03-configure-ips.sh" >> "$LOG_FILE" 2>&1; then
    log_success "IP addresses configured"
else
    log_error "Failed to configure IPs"
    exit 1
fi

# Step 4: Configure firewall
log "Step 4/6: Configuring firewall rules..."
if bash "$SCRIPT_DIR/04-configure-firewall.sh" >> "$LOG_FILE" 2>&1; then
    log_success "Firewall configured"
else
    log_error "Failed to configure firewall"
    exit 1
fi

# Step 5: Start services
log "Step 5/6: Starting services..."
if bash "$SCRIPT_DIR/05-start-services.sh" >> "$LOG_FILE" 2>&1; then
    log_success "Services started"
else
    log_warning "Some services may have failed to start"
fi

# Step 6: Final status check
log "Step 6/6: Running status check..."
if [[ -f "$SCRIPT_DIR/status.sh" ]]; then
    bash "$SCRIPT_DIR/status.sh"
else
    log_warning "status.sh not found, skipping status check"
fi

log ""
log "=========================================="
log_success "Setup Complete!"
log "=========================================="
log ""
log "Next steps:"
log "  - Review status: sudo $SCRIPT_DIR/status.sh"
log "  - Test manually: sudo ip netns exec mgmt bash"
log "  - View logs: cat $LOG_FILE"
log "  - Tear down: sudo $SCRIPT_DIR/destroy-all.sh"
log ""
log "To access services:"
log "  - Web:      http://10.10.20.10:80"
log "  - App:      http://10.10.30.10:8080"
log "  - Database: http://10.10.40.10:3306"
log ""
log "To stop services: sudo pkill -f 'nginx.*homelab'; pkill -f 'python3.*8080'; pkill -f 'python3.*3306'"

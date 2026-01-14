#!/bin/bash
# ============================================
# install_fan_service.sh - Install Fan Performance Service
# Cài đặt systemd service để tự động chạy fan performance mode
# ============================================

# Don't use set -e - we handle errors manually

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/../data"
HOME_DIR="$HOME"
SERVICE_DIR="/etc/systemd/system"

# Files to install
FAN_SCRIPT="max_perf_v2.py"
MONITOR_SCRIPT="asus_fan_monitor.py"
SERVICE_FILE="asus-max-perf.service"

# ============================================
# Logging Functions
# ============================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $(date '+%H:%M:%S') - $1"
}

# ============================================
# Check Functions
# ============================================

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run with sudo!"
        log_info "Usage: sudo $0"
        exit 1
    fi
}

check_files_exist() {
    local missing=0
    
    log_debug "Checking required files..."
    
    # Check in data directory first (from backup)
    local fan_archive=$(ls -t "$DATA_DIR"/fan_setup_*.tar.gz 2>/dev/null | head -1)
    
    if [ -n "$fan_archive" ]; then
        log_info "Found fan backup: $(basename "$fan_archive")"
        return 0
    fi
    
    # Check in home directory
    if [ ! -f "$HOME_DIR/$FAN_SCRIPT" ]; then
        log_warning "Missing: $HOME_DIR/$FAN_SCRIPT"
        ((missing++))
    fi
    
    if [ ! -f "$HOME_DIR/$SERVICE_FILE" ]; then
        log_warning "Missing: $HOME_DIR/$SERVICE_FILE"
        ((missing++))
    fi
    
    if [ $missing -gt 0 ]; then
        log_error "Required files missing. Run pull_data.sh first or ensure files exist in $HOME_DIR"
        return 1
    fi
    
    return 0
}

# ============================================
# Installation Functions
# ============================================

extract_fan_files() {
    local fan_archive=$(ls -t "$DATA_DIR"/fan_setup_*.tar.gz 2>/dev/null | head -1)
    
    if [ -n "$fan_archive" ]; then
        log_info "Extracting fan files from backup..."
        log_debug "Archive: $fan_archive"
        
        tar -xzf "$fan_archive" -C "$HOME_DIR" 2>/dev/null
        
        # Set permissions
        chmod +x "$HOME_DIR"/*.py 2>/dev/null || true
        chmod +x "$HOME_DIR"/*.sh 2>/dev/null || true
        
        log_success "Fan files extracted to $HOME_DIR"
        return 0
    fi
    
    return 1
}

install_service() {
    local service_src="$HOME_DIR/$SERVICE_FILE"
    local service_dest="$SERVICE_DIR/$SERVICE_FILE"
    
    log_debug "Installing service..."
    log_debug "  Source: $service_src"
    log_debug "  Destination: $service_dest"
    
    if [ ! -f "$service_src" ]; then
        log_error "Service file not found: $service_src"
        return 1
    fi
    
    # Copy service file
    log_info "Copying service file to $SERVICE_DIR..."
    cp "$service_src" "$service_dest"
    
    # Set permissions
    chmod 644 "$service_dest"
    
    log_debug "Service file copied successfully"
    return 0
}

enable_service() {
    log_info "Reloading systemd daemon..."
    systemctl daemon-reload
    log_debug "Daemon reloaded"
    
    log_info "Enabling service to start on boot..."
    systemctl enable "$SERVICE_FILE"
    log_debug "Service enabled"
    
    log_info "Starting service..."
    systemctl start "$SERVICE_FILE"
    log_debug "Service started"
    
    # Check status
    sleep 1
    if systemctl is-active --quiet "$SERVICE_FILE"; then
        log_success "Service is running!"
    else
        log_warning "Service may not be running. Check with: systemctl status $SERVICE_FILE"
    fi
}

show_status() {
    echo ""
    echo "============================================"
    echo "  📊 Service Status"
    echo "============================================"
    echo ""
    
    systemctl status "$SERVICE_FILE" --no-pager || true
    
    echo ""
}

# ============================================
# Uninstall Function
# ============================================

uninstall_service() {
    echo ""
    echo "============================================"
    echo "  🗑️  Uninstalling Fan Service"
    echo "============================================"
    echo ""
    
    log_info "Stopping service..."
    systemctl stop "$SERVICE_FILE" 2>/dev/null || true
    
    log_info "Disabling service..."
    systemctl disable "$SERVICE_FILE" 2>/dev/null || true
    
    log_info "Removing service file..."
    rm -f "$SERVICE_DIR/$SERVICE_FILE"
    
    log_info "Reloading systemd daemon..."
    systemctl daemon-reload
    
    log_success "Service uninstalled!"
    echo ""
}

# ============================================
# Main
# ============================================

show_help() {
    echo "Usage: sudo $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  install      Install and enable fan performance service (default)"
    echo "  uninstall    Remove fan performance service"
    echo "  status       Show service status"
    echo "  -h, --help   Show this help"
    echo ""
}

main() {
    log_debug "Script started"
    log_debug "Args: $*"
    
    case "${1:-install}" in
        install)
            check_root
            
            echo ""
            echo "============================================"
            echo "  🔧 Installing Fan Performance Service"
            echo "============================================"
            echo ""
            
            # Try to extract from backup first
            extract_fan_files || true
            
            # Check if required files exist
            if [ ! -f "$HOME_DIR/$FAN_SCRIPT" ] && [ ! -f "$HOME_DIR/$SERVICE_FILE" ]; then
                log_error "Required files not found!"
                log_info "Make sure these files exist in $HOME_DIR:"
                log_info "  - $FAN_SCRIPT"
                log_info "  - $SERVICE_FILE"
                exit 1
            fi
            
            install_service
            enable_service
            show_status
            
            echo ""
            log_success "Installation complete!"
            echo ""
            log_info "Commands:"
            echo "  - Check status: systemctl status $SERVICE_FILE"
            echo "  - Stop service: sudo systemctl stop $SERVICE_FILE"
            echo "  - Restart service: sudo systemctl restart $SERVICE_FILE"
            echo "  - View logs: journalctl -u $SERVICE_FILE -f"
            echo ""
            ;;
        uninstall)
            check_root
            uninstall_service
            ;;
        status)
            show_status
            ;;
        -h|--help)
            show_help
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
    
    log_debug "Script completed"
}

main "$@"

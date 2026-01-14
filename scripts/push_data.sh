#!/bin/bash
# ============================================
# push_data.sh - Restore Config Script
# Restore HyDE, Hypr, Kitty configs và Fan/Performance scripts từ backup
# ============================================

# Don't use set -e - we want to continue even if some restores fail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/../data"
CONFIG_DIR="$HOME/.config"
HOME_DIR="$HOME"

# Global array for available backup folders
declare -a AVAILABLE_FOLDERS=()

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
# Utility Functions
# ============================================

list_backup_folders() {
    log_debug "Listing backup folders in: $DATA_DIR"
    
    if [ ! -d "$DATA_DIR" ]; then
        log_error "Data directory not found: $DATA_DIR"
        return 1
    fi
    
    # Only get folders matching timestamp pattern (YYYYMMDD_HHMMSS), exclude safety_backups
    local folders=()
    while IFS= read -r folder; do
        local name=$(basename "$folder")
        # Check if folder name matches timestamp pattern
        if [[ "$name" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
            folders+=("$folder")
        fi
    done < <(ls -dt "$DATA_DIR"/*/ 2>/dev/null)
    
    if [ ${#folders[@]} -eq 0 ]; then
        log_warning "No backup folders found"
        return 1
    fi
    
    echo ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}  Available backup folders:${NC}"
    echo -e "${CYAN}============================================${NC}"
    local i=1
    for folder in "${folders[@]}"; do
        local basename=$(basename "$folder")
        local file_count=$(ls -1 "$folder"/*.tar.gz 2>/dev/null | wc -l)
        local files=$(ls -1 "$folder"/*.tar.gz 2>/dev/null | xargs -I{} basename {} .tar.gz | tr '\n' ', ' | sed 's/,$//')
        echo "  $i) $basename ($file_count files: $files)"
        ((i++))
    done
    echo ""
    echo "  0) Hủy"
    echo ""
    
    # Store folders for later use
    AVAILABLE_FOLDERS=("${folders[@]}")
    return 0
}

get_latest_backup_folder() {
    # Get only timestamp folders
    for folder in $(ls -dt "$DATA_DIR"/*/ 2>/dev/null); do
        local name=$(basename "$folder")
        if [[ "$name" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
            echo "$folder"
            return
        fi
    done
}

select_backup_folder() {
    # Call list_backup_folders to populate AVAILABLE_FOLDERS and show menu
    if ! list_backup_folders; then
        return 1
    fi
    
    if [ ${#AVAILABLE_FOLDERS[@]} -eq 0 ]; then
        return 1
    fi
    
    read -p "Chọn số backup: " choice
    
    if [ "$choice" = "0" ] || [ -z "$choice" ]; then
        return 1
    fi
    
    if [ "$choice" -gt 0 ] 2>/dev/null && [ "$choice" -le ${#AVAILABLE_FOLDERS[@]} ]; then
        echo "${AVAILABLE_FOLDERS[$((choice-1))]}"
        return 0
    else
        log_warning "Lựa chọn không hợp lệ, dùng backup mới nhất"
        echo "${AVAILABLE_FOLDERS[0]}"
        return 0
    fi
}

# ============================================
# Restore Functions
# ============================================

backup_current() {
    local target_dir="$1"
    local name="$2"
    
    if [ -d "$target_dir" ]; then
        local backup_name="${name}_before_restore_$(date +%Y%m%d_%H%M%S).tar.gz"
        local backup_path="$DATA_DIR/safety_backups"
        mkdir -p "$backup_path"
        
        log_debug "Creating safety backup of current $name"
        tar -czf "$backup_path/$backup_name" -C "$(dirname "$target_dir")" "$(basename "$target_dir")" 2>/dev/null
        log_info "Safety backup created: $backup_name"
    fi
}

restore_config() {
    local backup_folder="$1"
    local name="$2"
    local target_parent="$3"
    local archive="$backup_folder/${name}.tar.gz"
    local is_chunked=false
    
    log_debug "Restoring $name"
    log_debug "  Backup folder: $backup_folder"
    log_debug "  Target parent: $target_parent"
    
    # Check if archive is chunked (split into parts)
    local chunk_count=$(ls -1 "${archive}.part_"* 2>/dev/null | wc -l)
    if [ "$chunk_count" -gt 0 ]; then
        log_info "📦 Found $chunk_count chunks, merging..."
        is_chunked=true
        
        # Merge chunks back into single file
        cat "${archive}.part_"* > "$archive"
        log_debug "Merged chunks into: $archive"
    fi
    
    if [ ! -f "$archive" ]; then
        log_warning "Archive not found: $archive - Skipping"
        return 1
    fi
    
    # Backup current before restore
    backup_current "$target_parent/$name" "$name"
    
    # Extract
    log_info "Restoring $name..."
    tar -xzf "$archive" -C "$target_parent" 2>/dev/null
    
    local result=$?
    
    # Cleanup merged file if it was chunked (keep original parts)
    if [ "$is_chunked" = true ]; then
        rm -f "$archive"
        log_debug "Removed temporary merged file"
    fi
    
    if [ $result -eq 0 ]; then
        log_success "$name restored successfully"
        return 0
    else
        log_error "Failed to restore $name"
        return 1
    fi
}

restore_fan_files() {
    local backup_folder="$1"
    local archive="$backup_folder/fan_setup.tar.gz"
    
    log_debug "Restoring fan files from: $archive"
    
    if [ ! -f "$archive" ]; then
        log_warning "Fan setup archive not found - Skipping"
        return 1
    fi
    
    log_info "Restoring fan/performance scripts to $HOME_DIR..."
    tar -xzf "$archive" -C "$HOME_DIR" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log_success "Fan/Performance scripts restored"
        
        # Make scripts executable
        log_debug "Setting executable permissions..."
        chmod +x "$HOME_DIR"/*.sh 2>/dev/null || true
        chmod +x "$HOME_DIR"/*.py 2>/dev/null || true
        
        return 0
    else
        log_error "Failed to restore fan/performance files"
        return 1
    fi
}

# ============================================
# Interactive Mode
# ============================================

restore_interactive() {
    echo ""
    echo "============================================"
    echo "  📥 Config Restore Script (Interactive)"
    echo "============================================"
    echo ""
    
    log_debug "Starting interactive restore"
    log_debug "Data directory: $DATA_DIR"
    
    if [ ! -d "$DATA_DIR" ]; then
        log_error "Data directory not found: $DATA_DIR"
        log_info "Run pull_data.sh first to create backups"
        exit 1
    fi
    
    # Select backup folder
    echo -e "${CYAN}=== Select Backup Folder ===${NC}"
    local backup_folder=$(select_backup_folder)
    
    if [ -z "$backup_folder" ]; then
        log_warning "No backup selected"
        exit 0
    fi
    
    log_info "Selected: $(basename "$backup_folder")"
    echo ""
    
    # Show available archives in folder
    echo -e "${CYAN}Available configs in this backup:${NC}"
    ls -1 "$backup_folder"/*.tar.gz 2>/dev/null | while read f; do
        echo "  - $(basename "$f" .tar.gz)"
    done
    echo ""
    
    # Ask what to restore
    echo "What to restore?"
    echo "  1) hyde"
    echo "  2) hypr"
    echo "  3) kitty"
    echo "  4) fan_setup"
    echo "  a) All"
    echo ""
    read -p "Select (space-separated, e.g. 1 2 3): " selections
    
    local success_count=0
    
    if [[ "$selections" == "a" || "$selections" == "A" ]]; then
        selections="1 2 3 4"
    fi
    
    for sel in $selections; do
        case $sel in
            1) restore_config "$backup_folder" "hyde" "$CONFIG_DIR" && ((success_count++)) ;;
            2) restore_config "$backup_folder" "hypr" "$CONFIG_DIR" && ((success_count++)) ;;
            3) restore_config "$backup_folder" "kitty" "$CONFIG_DIR" && ((success_count++)) ;;
            4) restore_fan_files "$backup_folder" && ((success_count++)) ;;
        esac
    done
    
    echo ""
    echo "============================================"
    echo "  ✅ Restore Complete!"
    echo "  Restored: $success_count items"
    echo "============================================"
    echo ""
}

# ============================================
# Quick Restore (Latest)
# ============================================

restore_latest() {
    echo ""
    echo "============================================"
    echo "  📥 Config Restore Script (Latest)"
    echo "============================================"
    echo ""
    
    log_debug "Starting restore from latest backup"
    
    local backup_folder=$(get_latest_backup_folder)
    
    if [ -z "$backup_folder" ]; then
        log_error "No backup folders found"
        log_info "Run pull_data.sh first to create backups"
        exit 1
    fi
    
    log_info "Using backup: $(basename "$backup_folder")"
    echo ""
    
    local success_count=0
    
    # Restore all available configs
    restore_config "$backup_folder" "hyde" "$CONFIG_DIR" && ((success_count++))
    restore_config "$backup_folder" "hypr" "$CONFIG_DIR" && ((success_count++))
    restore_config "$backup_folder" "kitty" "$CONFIG_DIR" && ((success_count++))
    restore_fan_files "$backup_folder" && ((success_count++))
    
    echo ""
    log_success "Restored $success_count items from latest backup"
    echo ""
}

# ============================================
# Main
# ============================================

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  (no args)            Interactive mode - chọn backup folder và items"
    echo "  -l, --latest         Restore tất cả từ backup mới nhất"
    echo "  --list               List all backup folders"
    echo "  -h, --help           Show this help"
    echo ""
}

main() {
    log_debug "Script started with args: $*"
    
    case "${1:-}" in
        -l|--latest)
            restore_latest
            ;;
        --list)
            echo ""
            list_backup_folders
            ;;
        -h|--help)
            show_help
            ;;
        "")
            # Default: interactive mode
            restore_interactive
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

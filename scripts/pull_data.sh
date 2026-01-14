#!/bin/bash
# ============================================
# pull_data.sh - Backup Config Script
# Backup HyDE, Hypr, Kitty configs và Fan/Performance scripts
# ============================================

# Don't use set -e - we want to continue even if some backups fail

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
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR=""

# Source directories
CONFIG_DIR="$HOME/.config"
HOME_DIR="$HOME"

# Config directories to backup
declare -A BACKUP_ITEMS=(
    ["hyde"]="$CONFIG_DIR/hyde"
    ["hypr"]="$CONFIG_DIR/hypr"
    ["kitty"]="$CONFIG_DIR/kitty"
    ["fan_setup"]="FAN_FILES"
)

# Fan/Performance files to backup (from ~/)
FAN_FILES=(
    "asus_fan_monitor.py"
    "asus-max-perf.service"
    "asus-max-performance.service"
    "max_perf.sh"
    "max_perf_v2.py"
    "max_performance.py"
    "setup_fan.sh"
    "debug_fan_state.py"
    "force_fan_loop.py"
    "force_max_fan.py"
    "restore_fan.py"
    "revive_fan_acpi.py"
    "test_fan_response.py"
)

# Selected items for backup
declare -a SELECTED_ITEMS=()

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

# Max chunk size in MB (for upload limits like GitHub 100MB)
CHUNK_SIZE_MB=90
CHUNK_SIZE_BYTES=$((CHUNK_SIZE_MB * 1024 * 1024))

create_backup_dir() {
    BACKUP_DIR="$DATA_DIR/$TIMESTAMP"
    log_debug "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    log_info "Backup folder: $TIMESTAMP"
}

get_archive_size() {
    local file="$1"
    if [ -f "$file" ]; then
        local size=$(du -h "$file" | cut -f1)
        echo "$size"
    else
        echo "0"
    fi
}

get_file_size_bytes() {
    local file="$1"
    if [ -f "$file" ]; then
        stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null
    else
        echo "0"
    fi
}

split_if_large() {
    local archive_path="$1"
    local name="$2"
    
    local file_size=$(get_file_size_bytes "$archive_path")
    log_debug "File size: $file_size bytes (limit: $CHUNK_SIZE_BYTES bytes = ${CHUNK_SIZE_MB}MB)"
    
    if [ "$file_size" -gt "$CHUNK_SIZE_BYTES" ]; then
        log_info "📦 File > ${CHUNK_SIZE_MB}MB, splitting into chunks..."
        
        # Split into chunks
        split -b ${CHUNK_SIZE_MB}m "$archive_path" "${archive_path}.part_"
        
        # Remove original, keep parts
        rm "$archive_path"
        
        # Count and log parts
        local part_count=$(ls -1 "${archive_path}.part_"* 2>/dev/null | wc -l)
        log_success "Split into $part_count chunks"
        
        # List parts
        for part in "${archive_path}.part_"*; do
            local part_size=$(get_archive_size "$part")
            log_debug "  - $(basename "$part") ($part_size)"
        done
    else
        log_debug "File size OK, no split needed"
    fi
}

# ============================================
# Selection Menu
# ============================================

show_selection_menu() {
    echo ""
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}  Chọn các config cần backup${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""
    echo "  1) hyde       - ~/.config/hyde"
    echo "  2) hypr       - ~/.config/hypr"
    echo "  3) kitty      - ~/.config/kitty"
    echo "  4) fan_setup  - Fan/Performance scripts"
    echo "  ---"
    echo "  a) Tất cả"
    echo "  q) Thoát"
    echo ""
    echo -e "${YELLOW}Nhập số (phân cách bằng dấu cách), ví dụ: 1 2 3${NC}"
    echo -e "${YELLOW}Hoặc nhập 'a' để backup tất cả:${NC}"
    echo ""
}

parse_selection() {
    local input="$1"
    SELECTED_ITEMS=()
    
    if [[ "$input" == "q" || "$input" == "Q" ]]; then
        log_info "Đã hủy backup"
        exit 0
    fi
    
    if [[ "$input" == "a" || "$input" == "A" || -z "$input" ]]; then
        SELECTED_ITEMS=("hyde" "hypr" "kitty" "fan_setup")
        return
    fi
    
    for num in $input; do
        case $num in
            1) SELECTED_ITEMS+=("hyde") ;;
            2) SELECTED_ITEMS+=("hypr") ;;
            3) SELECTED_ITEMS+=("kitty") ;;
            4) SELECTED_ITEMS+=("fan_setup") ;;
            *) log_warning "Lựa chọn không hợp lệ: $num" ;;
        esac
    done
}

# ============================================
# Backup Functions
# ============================================

backup_config_dir() {
    local src_dir="$1"
    local name="$2"
    local archive_name="${name}.tar.gz"
    local archive_path="$BACKUP_DIR/$archive_name"
    
    log_debug "Starting backup for: $name"
    log_debug "  Source: $src_dir"
    log_debug "  Destination: $archive_path"
    
    if [ ! -d "$src_dir" ]; then
        log_warning "Directory not found: $src_dir - Skipping"
        return 1
    fi
    
    log_info "Backing up $name..."
    
    # Create archive
    tar -czf "$archive_path" -C "$(dirname "$src_dir")" "$(basename "$src_dir")" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        local size=$(get_archive_size "$archive_path")
        log_success "$name backup complete: $archive_name ($size)"
        log_debug "Archive created successfully at: $archive_path"
        
        # Split if larger than CHUNK_SIZE_MB
        split_if_large "$archive_path" "$name"
        
        return 0
    else
        log_error "Failed to backup $name"
        return 1
    fi
}

backup_fan_files() {
    local archive_name="fan_setup.tar.gz"
    local archive_path="$BACKUP_DIR/$archive_name"
    local temp_dir=$(mktemp -d)
    local found_files=0
    
    log_debug "Starting fan/performance files backup"
    log_debug "  Temp directory: $temp_dir"
    log_debug "  Destination: $archive_path"
    
    log_info "Backing up fan/performance scripts..."
    
    # Copy existing files to temp directory
    for file in "${FAN_FILES[@]}"; do
        local src_path="$HOME_DIR/$file"
        if [ -f "$src_path" ]; then
            log_debug "  Found: $file"
            cp "$src_path" "$temp_dir/"
            ((found_files++))
        else
            log_debug "  Not found: $file (skipping)"
        fi
    done
    
    if [ $found_files -eq 0 ]; then
        log_warning "No fan/performance files found - Skipping"
        rm -rf "$temp_dir"
        return 1
    fi
    
    log_debug "Found $found_files files to backup"
    
    # Create archive
    tar -czf "$archive_path" -C "$temp_dir" . 2>/dev/null
    
    # Cleanup temp
    rm -rf "$temp_dir"
    
    if [ $? -eq 0 ]; then
        local size=$(get_archive_size "$archive_path")
        log_success "Fan/Performance backup complete: $archive_name ($size)"
        log_debug "Archive created with $found_files files"
        return 0
    else
        log_error "Failed to backup fan/performance files"
        return 1
    fi
}

# ============================================
# Main
# ============================================

main() {
    echo ""
    echo "============================================"
    echo "  📦 Config Backup Script"
    echo "  Timestamp: $TIMESTAMP"
    echo "============================================"
    echo ""
    
    log_debug "Script started"
    log_debug "Script directory: $SCRIPT_DIR"
    log_debug "Data directory: $DATA_DIR"
    log_debug "Home directory: $HOME_DIR"
    
    # Show selection menu
    show_selection_menu
    read -p "Lựa chọn: " user_input
    parse_selection "$user_input"
    
    if [ ${#SELECTED_ITEMS[@]} -eq 0 ]; then
        log_warning "Không có config nào được chọn"
        exit 0
    fi
    
    echo ""
    log_info "Đã chọn: ${SELECTED_ITEMS[*]}"
    echo ""
    
    create_backup_dir
    
    local success_count=0
    local total_count=${#SELECTED_ITEMS[@]}
    
    echo ""
    echo "--- Backing up selected configs ---"
    echo ""
    
    for item in "${SELECTED_ITEMS[@]}"; do
        case $item in
            "hyde")
                if backup_config_dir "$CONFIG_DIR/hyde" "hyde"; then
                    ((success_count++))
                fi
                ;;
            "hypr")
                if backup_config_dir "$CONFIG_DIR/hypr" "hypr"; then
                    ((success_count++))
                fi
                ;;
            "kitty")
                if backup_config_dir "$CONFIG_DIR/kitty" "kitty"; then
                    ((success_count++))
                fi
                ;;
            "fan_setup")
                if backup_fan_files; then
                    ((success_count++))
                fi
                ;;
        esac
    done
    
    echo ""
    echo "============================================"
    echo "  📊 Backup Summary"
    echo "============================================"
    echo ""
    log_info "Completed: $success_count/$total_count backups"
    log_info "Backup location: $BACKUP_DIR"
    echo ""
    
    # List created archives
    log_info "Created archives:"
    ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null | while read line; do
        echo "  $line"
    done
    
    log_debug "Script completed"
    echo ""
}

# Check for --all flag (skip menu)
if [[ "$1" == "--all" || "$1" == "-a" ]]; then
    SELECTED_ITEMS=("hyde" "hypr" "kitty" "fan_setup")
    
    echo ""
    echo "============================================"
    echo "  📦 Config Backup Script (All)"
    echo "  Timestamp: $TIMESTAMP"
    echo "============================================"
    echo ""
    
    log_debug "Script started with --all flag"
    create_backup_dir
    
    local success_count=0
    for item in "${SELECTED_ITEMS[@]}"; do
        case $item in
            "hyde") backup_config_dir "$CONFIG_DIR/hyde" "hyde" && ((success_count++)) ;;
            "hypr") backup_config_dir "$CONFIG_DIR/hypr" "hypr" && ((success_count++)) ;;
            "kitty") backup_config_dir "$CONFIG_DIR/kitty" "kitty" && ((success_count++)) ;;
            "fan_setup") backup_fan_files && ((success_count++)) ;;
        esac
    done
    
    echo ""
    log_info "Completed: $success_count/4 backups"
    log_info "Backup location: $BACKUP_DIR"
    echo ""
else
    main "$@"
fi

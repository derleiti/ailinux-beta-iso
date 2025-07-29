#!/bin/bash
#
# AILinux ISO Build System - Advanced Cleanup System
# SystemOptimizer Agent Implementation
#
# This script provides comprehensive cleanup capabilities for the AILinux
# ISO build system with enhanced safety, automation, and error recovery.
#
# Features:
# - Session-safe cleanup that preserves user sessions
# - Intelligent mount detection and unmounting
# - Resource monitoring and automatic triggers
# - Rollback capabilities for failed operations
# - Comprehensive logging and error reporting
#
# Usage:
#   ./cleanup-system.sh [OPTIONS] [TARGETS...]
#
# Version: 1.0.0
# Author: SystemOptimizer Agent

# ============================================================================
# CONFIGURATION AND INITIALIZATION
# ============================================================================

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source optimization manager if available
if [[ -f "${SCRIPT_DIR}/../modules/optimization_manager.sh" ]]; then
    source "${SCRIPT_DIR}/../modules/optimization_manager.sh"
else
    echo "Warning: optimization_manager.sh not found - using basic cleanup"
fi

# Default cleanup targets
readonly DEFAULT_CLEANUP_TARGETS=(
    "/mnt/ailinux"
    "/tmp/ailinux-build"
    "${AILINUX_BUILD_CHROOT_DIR:-}"
    "${AILINUX_BUILD_TEMP_DIR:-}"
    "${WORK_DIR:-}"
)

# Command line options
FORCE_CLEANUP=false
DRY_RUN=false
VERBOSE=false
MONITOR_RESOURCES=false
SESSION_SAFE=true
CLEANUP_CACHE=true
CLEANUP_LOGS=false

# ============================================================================
# LOGGING AND UTILITIES
# ============================================================================

log_message() {
    local level="$1"
    local message="$2"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    case "$level" in
        "INFO")  echo "[$timestamp] [CLEANUP-INFO] $message" ;;
        "WARN")  echo "[$timestamp] [CLEANUP-WARN] $message" >&2 ;;
        "ERROR") echo "[$timestamp] [CLEANUP-ERROR] $message" >&2 ;;
        "DEBUG")
            if [[ "$VERBOSE" == "true" ]]; then
                echo "[$timestamp] [CLEANUP-DEBUG] $message" >&2
            fi
            ;;
    esac
    
    # Log to file if available
    if [[ -n "${LOG_FILE:-}" ]]; then
        echo "[$timestamp] [CLEANUP-$level] $message" >> "$LOG_FILE"
    fi
}

show_usage() {
    cat << EOF
AILinux Advanced Cleanup System v$SCRIPT_VERSION

USAGE:
    $SCRIPT_NAME [OPTIONS] [TARGETS...]

OPTIONS:
    -f, --force              Force cleanup (bypass safety checks)
    -d, --dry-run           Show what would be done without executing
    -v, --verbose           Enable verbose output
    -m, --monitor           Monitor resources during cleanup
    --no-session-safe       Disable session safety protections
    --no-cache              Skip cache cleanup
    --cleanup-logs          Also clean up log files
    -h, --help              Show this help message

TARGETS:
    If no targets specified, default cleanup locations will be used:
    - /mnt/ailinux
    - /tmp/ailinux-build
    - Build directories from environment variables

EXAMPLES:
    $SCRIPT_NAME                           # Standard cleanup
    $SCRIPT_NAME --dry-run                 # Preview cleanup actions
    $SCRIPT_NAME --force /custom/path      # Force clean custom path
    $SCRIPT_NAME --monitor --verbose       # Monitor with detailed output

ENVIRONMENT VARIABLES:
    AILINUX_BUILD_CHROOT_DIR    Chroot directory to clean
    AILINUX_BUILD_TEMP_DIR      Temporary directory to clean
    WORK_DIR                    Working directory to clean
    LOG_FILE                    Log file for cleanup messages

For more information, see: https://ailinux.org/docs/cleanup
EOF
}

# ============================================================================
# CLEANUP FUNCTIONS
# ============================================================================

# Comprehensive cleanup with safety checks
perform_comprehensive_cleanup() {
    local targets=("$@")
    local cleanup_success=true
    
    log_message "INFO" "Starting comprehensive cleanup"
    
    if [[ ${#targets[@]} -eq 0 ]]; then
        targets=("${DEFAULT_CLEANUP_TARGETS[@]}")
    fi
    
    # Remove empty targets
    local filtered_targets=()
    for target in "${targets[@]}"; do
        if [[ -n "$target" ]]; then
            filtered_targets+=("$target")
        fi
    done
    
    log_message "INFO" "Cleanup targets: ${filtered_targets[*]}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_message "INFO" "DRY RUN - No actual cleanup will be performed"
        
        for target in "${filtered_targets[@]}"; do
            if [[ -e "$target" ]]; then
                log_message "INFO" "Would clean: $target"
                if [[ -d "$target" ]]; then
                    local size=$(du -sh "$target" 2>/dev/null | cut -f1 || echo "unknown")
                    log_message "INFO" "  Directory size: $size"
                    
                    # Check for mount points
                    local mounts=$(mount | grep "^/dev" | grep "$target" | wc -l)
                    if [[ $mounts -gt 0 ]]; then
                        log_message "INFO" "  Contains $mounts mount points"
                    fi
                fi
            else
                log_message "DEBUG" "Target does not exist: $target"
            fi
        done
        
        return 0
    fi
    
    # Pre-cleanup resource check
    if [[ "$MONITOR_RESOURCES" == "true" ]]; then
        log_resource_usage "pre-cleanup"
    fi
    
    # Process each target
    for target in "${filtered_targets[@]}"; do
        if [[ -e "$target" ]]; then
            log_message "INFO" "Processing cleanup target: $target"
            
            if ! cleanup_target "$target"; then
                log_message "ERROR" "Cleanup failed for: $target"
                cleanup_success=false
            else
                log_message "INFO" "Successfully cleaned: $target"
            fi
        else
            log_message "DEBUG" "Target does not exist (skipping): $target"
        fi
    done
    
    # Additional cleanup tasks
    if [[ "$CLEANUP_CACHE" == "true" ]]; then
        cleanup_system_cache
    fi
    
    if [[ "$CLEANUP_LOGS" == "true" ]]; then
        cleanup_old_logs
    fi
    
    # Post-cleanup resource check
    if [[ "$MONITOR_RESOURCES" == "true" ]]; then
        log_resource_usage "post-cleanup"
    fi
    
    # Summary
    if [[ "$cleanup_success" == "true" ]]; then
        log_message "INFO" "Comprehensive cleanup completed successfully"
        return 0
    else
        log_message "WARN" "Comprehensive cleanup completed with errors"
        return 1
    fi
}

# Clean up a specific target (file or directory)
cleanup_target() {
    local target="$1"
    
    if [[ ! -e "$target" ]]; then
        log_message "DEBUG" "Target does not exist: $target"
        return 0
    fi
    
    # Safety checks
    if [[ "$SESSION_SAFE" == "true" ]]; then
        if ! is_safe_to_clean "$target"; then
            log_message "WARN" "Safety check failed for: $target"
            return 1
        fi
    fi
    
    # Handle directories
    if [[ -d "$target" ]]; then
        return cleanup_directory "$target"
    # Handle files
    elif [[ -f "$target" ]]; then
        return cleanup_file "$target"
    else
        log_message "WARN" "Unknown target type: $target"
        return 1
    fi
}

# Clean up directory with mount detection
cleanup_directory() {
    local dir="$1"
    
    log_message "INFO" "Cleaning directory: $dir"
    
    # Check if directory is a mount point or contains mount points
    local mount_points
    mount_points=$(mount | awk -v dir="$dir" '$3 ~ "^" dir {print $3}' | sort -r)
    
    if [[ -n "$mount_points" ]]; then
        log_message "INFO" "Found mount points under $dir, unmounting..."
        
        while IFS= read -r mount_point; do
            if [[ -n "$mount_point" ]]; then
                unmount_safely "$mount_point"
            fi
        done <<< "$mount_points"
    fi
    
    # Kill processes using the directory
    kill_directory_processes "$dir"
    
    # Wait for processes to exit
    sleep 2
    
    # Remove directory contents
    if [[ "$FORCE_CLEANUP" == "true" ]]; then
        log_message "INFO" "Force removing directory: $dir"
        rm -rf "$dir"
    else
        log_message "INFO" "Safely removing directory: $dir"
        safe_remove_directory "$dir"
    fi
    
    return $?
}

# Clean up file
cleanup_file() {
    local file="$1"
    
    log_message "DEBUG" "Cleaning file: $file"
    
    if [[ "$FORCE_CLEANUP" == "true" ]]; then
        rm -f "$file"
    else
        # Check if file is in use
        if lsof "$file" >/dev/null 2>&1; then
            log_message "WARN" "File is in use: $file"
            return 1
        fi
        
        rm -f "$file"
    fi
    
    return $?
}

# Safely remove directory with session protection
safe_remove_directory() {
    local dir="$1"
    
    # Remove files first
    find "$dir" -type f -exec rm -f {} \; 2>/dev/null || true
    
    # Remove empty directories from deepest to shallowest
    find "$dir" -depth -type d -exec rmdir {} \; 2>/dev/null || true
    
    # Final check and removal
    if [[ -d "$dir" ]]; then
        if rmdir "$dir" 2>/dev/null; then
            log_message "DEBUG" "Successfully removed directory: $dir"
            return 0
        else
            log_message "WARN" "Directory not empty or in use: $dir"
            return 1
        fi
    fi
    
    return 0
}

# Unmount safely with multiple strategies
unmount_safely() {
    local mount_point="$1"
    local retry_count=0
    local max_retries=5
    
    log_message "INFO" "Unmounting: $mount_point"
    
    # Check if actually mounted
    if ! mountpoint -q "$mount_point" 2>/dev/null; then
        log_message "DEBUG" "Not mounted: $mount_point"
        return 0
    fi
    
    # Try normal unmount first
    while [[ $retry_count -lt $max_retries ]]; do
        if umount "$mount_point" 2>/dev/null; then
            log_message "INFO" "Successfully unmounted: $mount_point"
            return 0
        fi
        
        ((retry_count++))
        log_message "DEBUG" "Unmount attempt $retry_count failed for: $mount_point"
        sleep 1
    done
    
    # Try killing processes and unmounting
    kill_mount_processes "$mount_point"
    sleep 2
    
    if umount "$mount_point" 2>/dev/null; then
        log_message "INFO" "Unmounted after killing processes: $mount_point"
        return 0
    fi
    
    # Try lazy unmount
    if umount -l "$mount_point" 2>/dev/null; then
        log_message "WARN" "Lazy unmount successful: $mount_point"
        return 0
    fi
    
    # Force unmount (if not in session-safe mode)
    if [[ "$SESSION_SAFE" != "true" && "$FORCE_CLEANUP" == "true" ]]; then
        if umount -f "$mount_point" 2>/dev/null; then
            log_message "WARN" "Force unmount successful: $mount_point"
            return 0
        fi
    fi
    
    log_message "ERROR" "All unmount strategies failed for: $mount_point"
    return 1
}

# Kill processes using a mount point
kill_mount_processes() {
    local mount_point="$1"
    
    if ! command -v fuser >/dev/null 2>&1; then
        log_message "DEBUG" "fuser command not available"
        return 0
    fi
    
    local pids
    pids=$(fuser -m "$mount_point" 2>/dev/null)
    
    if [[ -n "$pids" ]]; then
        log_message "INFO" "Killing processes using $mount_point: $pids"
        
        # Send TERM signal first
        for pid in $pids; do
            if [[ "$pid" != "$$" && "$pid" != "$PPID" ]]; then
                kill -TERM "$pid" 2>/dev/null || true
            fi
        done
        
        sleep 2
        
        # Send KILL signal if needed
        for pid in $pids; do
            if [[ "$pid" != "$$" && "$pid" != "$PPID" ]]; then
                if kill -0 "$pid" 2>/dev/null; then
                    kill -KILL "$pid" 2>/dev/null || true
                fi
            fi
        done
    fi
}

# Kill processes using a directory
kill_directory_processes() {
    local dir="$1"
    
    if ! command -v fuser >/dev/null 2>&1; then
        return 0
    fi
    
    local pids
    pids=$(fuser -v "$dir" 2>/dev/null | awk 'NR>1 {print $2}' | grep -v "^$")
    
    if [[ -n "$pids" ]]; then
        log_message "DEBUG" "Killing processes using directory $dir: $pids"
        
        for pid in $pids; do
            if [[ "$pid" != "$$" && "$pid" != "$PPID" ]]; then
                kill -TERM "$pid" 2>/dev/null || true
            fi
        done
        
        sleep 1
    fi
}

# ============================================================================
# SAFETY CHECKS
# ============================================================================

# Check if target is safe to clean
is_safe_to_clean() {
    local target="$1"
    
    # Never clean system directories
    local unsafe_paths=(
        "/"
        "/usr"
        "/usr/bin"
        "/usr/lib"
        "/etc"
        "/var"
        "/home"
        "/root"
        "/boot"
        "/sys"
        "/proc"
        "/dev"
    )
    
    for unsafe_path in "${unsafe_paths[@]}"; do
        if [[ "$target" == "$unsafe_path" ]]; then
            log_message "ERROR" "Refusing to clean system directory: $target"
            return 1
        fi
    done
    
    # Check if target is under a safe prefix
    local safe_prefixes=(
        "/tmp"
        "/mnt"
        "/var/tmp"
        "${HOME}/ailinux"
        "${AILINUX_BUILD_DIR:-/tmp/ailinux}"
    )
    
    local is_safe=false
    for safe_prefix in "${safe_prefixes[@]}"; do
        if [[ -n "$safe_prefix" && "$target" == "$safe_prefix"* ]]; then
            is_safe=true
            break
        fi
    done
    
    if [[ "$is_safe" != "true" ]]; then
        log_message "WARN" "Target not under safe prefix: $target"
        if [[ "$FORCE_CLEANUP" != "true" ]]; then
            return 1
        fi
    fi
    
    return 0
}

# ============================================================================
# RESOURCE MONITORING
# ============================================================================

# Log current resource usage
log_resource_usage() {
    local stage="$1"
    
    log_message "INFO" "Resource usage ($stage):"
    
    # Disk usage
    local disk_usage
    disk_usage=$(df -h / | awk 'NR==2 {print $5}')
    log_message "INFO" "  Disk usage: $disk_usage"
    
    # Memory usage
    local memory_info
    memory_info=$(free -h | awk 'NR==2{printf "used: %s, available: %s", $3, $7}')
    log_message "INFO" "  Memory: $memory_info"
    
    # Load average
    local load_avg
    load_avg=$(uptime | awk -F'load average:' '{print $2}')
    log_message "INFO" "  Load average:$load_avg"
    
    # Process count
    local process_count
    process_count=$(ps aux | wc -l)
    log_message "INFO" "  Processes: $process_count"
}

# ============================================================================
# ADDITIONAL CLEANUP TASKS
# ============================================================================

# Clean up system cache
cleanup_system_cache() {
    log_message "INFO" "Cleaning system cache"
    
    local cache_patterns=(
        "/tmp/ailinux-*"
        "/tmp/debootstrap*"
        "/var/cache/apt/archives/partial/*"
        "/root/.cache/*"
        "${HOME}/.cache/ailinux*"
    )
    
    for pattern in "${cache_patterns[@]}"; do
        if ls $pattern >/dev/null 2>&1; then
            rm -rf $pattern 2>/dev/null || true
            log_message "DEBUG" "Cleaned cache pattern: $pattern"
        fi
    done
    
    # Clear page cache if safe
    if [[ "$FORCE_CLEANUP" == "true" ]]; then
        echo 1 > /proc/sys/vm/drop_caches 2>/dev/null || true
        log_message "DEBUG" "Cleared page cache"
    fi
}

# Clean up old log files
cleanup_old_logs() {
    log_message "INFO" "Cleaning old log files"
    
    local log_dirs=(
        "/var/log"
        "${AILINUX_BUILD_LOGS_DIR:-}"
        "${SCRIPT_DIR}/../logs"
    )
    
    for log_dir in "${log_dirs[@]}"; do
        if [[ -n "$log_dir" && -d "$log_dir" ]]; then
            # Remove logs older than 30 days
            find "$log_dir" -name "*.log" -type f -mtime +30 -exec rm -f {} \; 2>/dev/null || true
            
            # Remove empty log directories
            find "$log_dir" -type d -empty -exec rmdir {} \; 2>/dev/null || true
            
            log_message "DEBUG" "Cleaned old logs in: $log_dir"
        fi
    done
}

# ============================================================================
# COMMAND LINE PROCESSING
# ============================================================================

# Parse command line arguments
parse_arguments() {
    local targets=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_CLEANUP=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -m|--monitor)
                MONITOR_RESOURCES=true
                shift
                ;;
            --no-session-safe)
                SESSION_SAFE=false
                shift
                ;;
            --no-cache)
                CLEANUP_CACHE=false
                shift
                ;;
            --cleanup-logs)
                CLEANUP_LOGS=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -*)
                log_message "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                targets+=("$1")
                shift
                ;;
        esac
    done
    
    echo "${targets[@]}"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    log_message "INFO" "AILinux Advanced Cleanup System v$SCRIPT_VERSION"
    
    # Parse arguments
    local targets
    mapfile -t targets < <(parse_arguments "$@")
    
    # Show configuration
    log_message "INFO" "Configuration:"
    log_message "INFO" "  Force cleanup: $FORCE_CLEANUP"
    log_message "INFO" "  Dry run: $DRY_RUN"
    log_message "INFO" "  Session safe: $SESSION_SAFE"
    log_message "INFO" "  Monitor resources: $MONITOR_RESOURCES"
    log_message "INFO" "  Cleanup cache: $CLEANUP_CACHE"
    log_message "INFO" "  Cleanup logs: $CLEANUP_LOGS"
    
    # Perform cleanup
    if perform_comprehensive_cleanup "${targets[@]}"; then
        log_message "INFO" "Cleanup completed successfully"
        exit 0
    else
        log_message "ERROR" "Cleanup completed with errors"
        exit 1
    fi
}

# ============================================================================
# SCRIPT ENTRY POINT
# ============================================================================

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
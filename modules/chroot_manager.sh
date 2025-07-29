#!/bin/bash
#
# Chroot Management Module for AILinux Build Script
# Provides isolated chroot environment handling with session safety
#
# This module ensures that chroot operations don't interfere with the user's
# session by implementing proper isolation and cleanup mechanisms.
#

# Global chroot management configuration
declare -g CHROOT_ISOLATION_MODE="namespace"  # Options: namespace, traditional, hybrid
declare -g CHROOT_MOUNT_TRACKING=()
declare -g CHROOT_PROCESS_TRACKING=()
declare -g CHROOT_BACKUP_DIR=""
declare -g CHROOT_ACTIVE_SESSIONS=()

# Initialize chroot management system
init_chroot_management() {
    log_info "🏗️  Initializing isolated chroot management system..."
    
    # Set up chroot isolation
    setup_chroot_isolation
    
    # Create chroot backup directory
    create_chroot_backup_directory
    
    # Initialize mount tracking
    init_mount_tracking
    
    # Set up process isolation
    setup_process_isolation
    
    # Configure cleanup mechanisms
    configure_chroot_cleanup
    
    log_success "Chroot management system initialized with $CHROOT_ISOLATION_MODE isolation"
}

# Set up chroot isolation mechanisms
setup_chroot_isolation() {
    # Choose isolation mode based on capabilities and session type
    if command -v unshare >/dev/null 2>&1 && [ "$AILINUX_BUILD_SESSION_TYPE" != "unknown" ]; then
        CHROOT_ISOLATION_MODE="namespace"
        log_info "Using namespace isolation for chroot operations"
    elif [ -f /proc/sys/kernel/unprivileged_userns_clone ] && [ "$(cat /proc/sys/kernel/unprivileged_userns_clone)" = "1" ]; then
        CHROOT_ISOLATION_MODE="hybrid"
        log_info "Using hybrid isolation for chroot operations"
    else
        CHROOT_ISOLATION_MODE="traditional"
        log_info "Using traditional isolation for chroot operations"
    fi
    
    # Set environment variables for isolation
    export AILINUX_CHROOT_ISOLATION="$CHROOT_ISOLATION_MODE"
    export AILINUX_CHROOT_SESSION="chroot_session_$$"
}

# Create backup directory for chroot state
create_chroot_backup_directory() {
    CHROOT_BACKUP_DIR="/tmp/ailinux_chroot_backup_$$"
    mkdir -p "$CHROOT_BACKUP_DIR"
    
    # Create subdirectories
    mkdir -p "$CHROOT_BACKUP_DIR/mounts"
    mkdir -p "$CHROOT_BACKUP_DIR/processes"
    mkdir -p "$CHROOT_BACKUP_DIR/sessions"
    mkdir -p "$CHROOT_BACKUP_DIR/namespaces"
    
    export AILINUX_CHROOT_BACKUP_DIR="$CHROOT_BACKUP_DIR"
    log_info "Chroot backup directory: $CHROOT_BACKUP_DIR"
}

# Initialize mount tracking system
init_mount_tracking() {
    CHROOT_MOUNT_TRACKING=()
    
    # Create mount tracking file
    echo "# AILinux Chroot Mount Tracking" > "$CHROOT_BACKUP_DIR/mount_tracking.log"
    echo "# Started: $(date)" >> "$CHROOT_BACKUP_DIR/mount_tracking.log"
    echo "# Session: $AILINUX_CHROOT_SESSION" >> "$CHROOT_BACKUP_DIR/mount_tracking.log"
    
    export AILINUX_CHROOT_MOUNT_LOG="$CHROOT_BACKUP_DIR/mount_tracking.log"
}

# Set up process isolation mechanisms
setup_process_isolation() {
    CHROOT_PROCESS_TRACKING=()
    
    # Create process tracking file
    echo "# AILinux Chroot Process Tracking" > "$CHROOT_BACKUP_DIR/process_tracking.log"
    echo "# Started: $(date)" >> "$CHROOT_BACKUP_DIR/process_tracking.log"
    echo "# Parent PID: $$" >> "$CHROOT_BACKUP_DIR/process_tracking.log"
    
    export AILINUX_CHROOT_PROCESS_LOG="$CHROOT_BACKUP_DIR/process_tracking.log"
}

# Configure chroot cleanup mechanisms
configure_chroot_cleanup() {
    # Set up cleanup trap for chroot operations
    trap 'cleanup_chroot_on_exit' EXIT
    trap 'cleanup_chroot_on_signal' INT TERM
    
    # Create cleanup script for emergency situations
    create_emergency_cleanup_script
}

# Create emergency cleanup script
create_emergency_cleanup_script() {
    local emergency_script="$CHROOT_BACKUP_DIR/emergency_cleanup.sh"
    
    cat > "$emergency_script" << 'EOF'
#!/bin/bash
# Emergency chroot cleanup script
# This script can be run independently to clean up stuck chroot operations

CHROOT_DIR="$AILINUX_BUILD_CHROOT_DIR"
BACKUP_DIR="$AILINUX_CHROOT_BACKUP_DIR"

echo "Starting emergency chroot cleanup..."

# Kill chroot processes
if [ -f "$BACKUP_DIR/process_tracking.log" ]; then
    grep "^PID:" "$BACKUP_DIR/process_tracking.log" | while read -r line; do
        local pid=$(echo "$line" | cut -d: -f2 | tr -d ' ')
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "Killing chroot process: $pid"
            kill -TERM "$pid" 2>/dev/null || true
            sleep 2
            kill -KILL "$pid" 2>/dev/null || true
        fi
    done
fi

# Unmount filesystems
if [ -f "$BACKUP_DIR/mount_tracking.log" ]; then
    grep "^MOUNT:" "$BACKUP_DIR/mount_tracking.log" | tac | while read -r line; do
        local mount_point=$(echo "$line" | cut -d: -f2 | tr -d ' ')
        if [ -n "$mount_point" ] && mountpoint -q "$mount_point" 2>/dev/null; then
            echo "Unmounting: $mount_point"
            umount -l "$mount_point" 2>/dev/null || true
        fi
    done
fi

# Clean up namespace files
find "$BACKUP_DIR/namespaces" -type f -exec rm -f {} \; 2>/dev/null || true

echo "Emergency chroot cleanup completed"
EOF
    
    chmod +x "$emergency_script"
    export AILINUX_CHROOT_EMERGENCY_CLEANUP="$emergency_script"
}

# Safely enter chroot environment
enter_chroot_safely() {
    local chroot_dir="$1"
    local command="$2"
    local isolation_override="${3:-}"
    
    # Use override isolation mode if specified
    local isolation_mode="${isolation_override:-$CHROOT_ISOLATION_MODE}"
    
    log_info "🔒 Entering chroot environment safely (mode: $isolation_mode)"
    log_info "   Chroot: $chroot_dir"
    log_info "   Command: $command"
    
    # Validate chroot directory
    if ! validate_chroot_directory "$chroot_dir"; then
        log_error "❌ Chroot directory validation failed: $chroot_dir"
        return 1
    fi
    
    # Set up essential mounts
    if ! setup_essential_mounts "$chroot_dir"; then
        log_error "❌ Failed to set up essential mounts"
        cleanup_chroot_mounts "$chroot_dir"
        return 1
    fi
    
    # Execute command based on isolation mode
    case "$isolation_mode" in
        "namespace")
            execute_chroot_with_namespaces "$chroot_dir" "$command"
            ;;
        "hybrid")
            execute_chroot_hybrid "$chroot_dir" "$command"
            ;;
        "traditional")
            execute_chroot_traditional "$chroot_dir" "$command"
            ;;
        *)
            log_error "❌ Unknown isolation mode: $isolation_mode"
            return 1
            ;;
    esac
    
    local exit_code=$?
    
    # Clean up mounts
    cleanup_chroot_mounts "$chroot_dir"
    
    return $exit_code
}

# Validate chroot directory before use
validate_chroot_directory() {
    local chroot_dir="$1"
    
    # Check if directory exists
    if [ ! -d "$chroot_dir" ]; then
        log_error "Chroot directory does not exist: $chroot_dir"
        return 1
    fi
    
    # Check if it looks like a valid chroot
    local required_dirs=("usr" "etc" "bin" "sbin" "var" "tmp")
    local missing_dirs=()
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$chroot_dir/$dir" ]; then
            missing_dirs+=("$dir")
        fi
    done
    
    if [ ${#missing_dirs[@]} -gt 2 ]; then
        log_warn "⚠️  Chroot directory missing essential directories: ${missing_dirs[*]}"
        log_warn "This may not be a properly configured chroot environment"
    fi
    
    # Check permissions
    if [ ! -r "$chroot_dir" ] || [ ! -x "$chroot_dir" ]; then
        log_error "Insufficient permissions for chroot directory: $chroot_dir"
        return 1
    fi
    
    # Check if any mount points are already active
    if mount | grep -q "$chroot_dir"; then
        log_warn "⚠️  Existing mounts detected in chroot directory"
        log_info "Current mounts in $chroot_dir:"
        mount | grep "$chroot_dir" | while read -r mount_line; do
            log_info "   $mount_line"
        done
    fi
    
    log_info "✅ Chroot directory validation passed"
    return 0
}

# Set up essential filesystem mounts for chroot
setup_essential_mounts() {
    local chroot_dir="$1"
    
    log_info "🗂️  Setting up essential mounts for chroot..."
    
    # Essential mount points
    local mount_points=(
        "proc:proc:/proc:proc"
        "sysfs:sysfs:/sys:sysfs"
        "devtmpfs:udev:/dev:devtmpfs"
        "devpts:devpts:/dev/pts:devpts,gid=5,mode=620"
        "tmpfs:tmpfs:/run:tmpfs,mode=755,nodev,nosuid,strictatime"
    )
    
    for mount_spec in "${mount_points[@]}"; do
        IFS=':' read -r fs_type device mount_point options <<< "$mount_spec"
        local target="$chroot_dir$mount_point"
        
        # Create mount point if it doesn't exist
        if [ ! -d "$target" ]; then
            sudo mkdir -p "$target" || {
                log_error "Failed to create mount point: $target"
                return 1
            }
        fi
        
        # Skip if already mounted
        if mountpoint -q "$target" 2>/dev/null; then
            log_info "   $mount_point already mounted, skipping"
            continue
        fi
        
        # Mount filesystem
        log_info "   Mounting $mount_point ($fs_type)"
        if sudo mount -t "$fs_type" "$device" "$target" -o "$options" 2>/dev/null; then
            # Track mount for cleanup
            track_chroot_mount "$target" "$fs_type"
            log_info "   ✅ $mount_point mounted successfully"
        else
            log_warn "   ⚠️  Failed to mount $mount_point, continuing..."
        fi
    done
    
    log_success "Essential mounts setup completed"
    return 0
}

# Track chroot mounts for cleanup
track_chroot_mount() {
    local mount_point="$1"
    local fs_type="${2:-unknown}"
    
    # Add to tracking array
    CHROOT_MOUNT_TRACKING+=("$mount_point")
    
    # Log to tracking file
    echo "MOUNT:$mount_point:$fs_type:$(date)" >> "$AILINUX_CHROOT_MOUNT_LOG"
    
    log_info "📊 Tracking mount: $mount_point ($fs_type)"
}

# Execute chroot command with namespace isolation
execute_chroot_with_namespaces() {
    local chroot_dir="$1"
    local command="$2"
    
    log_info "🔒 Executing chroot with namespace isolation..."
    
    # Create namespace session file
    local namespace_file="$CHROOT_BACKUP_DIR/namespaces/session_$$"
    echo "$(date): Starting namespace session" > "$namespace_file"
    
    # Track the namespace session
    CHROOT_ACTIVE_SESSIONS+=("$$")
    
    # Execute with namespace isolation
    local chroot_result=0
    if ! sudo unshare --pid --fork --mount-proc \
        chroot "$chroot_dir" /usr/bin/env -i \
        HOME=/root \
        TERM="$TERM" \
        PS1='(ailinux-chroot) \u:\w\$ ' \
        PATH=/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin \
        DEBIAN_FRONTEND=noninteractive \
        LANG=en_US.UTF-8 \
        LC_ALL=en_US.UTF-8 \
        AILINUX_CHROOT_SESSION="$AILINUX_CHROOT_SESSION" \
        /bin/bash --login +h -c "$command"; then
        chroot_result=$?
        log_error "❌ Chroot command failed with namespace isolation (exit code: $chroot_result)"
    else
        log_success "✅ Chroot command completed successfully with namespace isolation"
    fi
    
    # Clean up namespace session
    echo "$(date): Namespace session completed with exit code $chroot_result" >> "$namespace_file"
    
    return $chroot_result
}

# Execute chroot command with hybrid isolation
execute_chroot_hybrid() {
    local chroot_dir="$1"
    local command="$2"
    
    log_info "🔒 Executing chroot with hybrid isolation..."
    
    # Try namespace isolation first, fall back to traditional
    if execute_chroot_with_namespaces "$chroot_dir" "$command" 2>/dev/null; then
        return 0
    else
        log_warn "⚠️  Namespace isolation failed, falling back to traditional chroot"
        execute_chroot_traditional "$chroot_dir" "$command"
    fi
}

# Execute chroot command with traditional isolation
execute_chroot_traditional() {
    local chroot_dir="$1"
    local command="$2"
    
    log_info "🔒 Executing chroot with traditional isolation..."
    
    # Create process tracking entry
    local process_start=$(date)
    echo "START:$$:$process_start" >> "$AILINUX_CHROOT_PROCESS_LOG"
    
    # Track this process
    CHROOT_PROCESS_TRACKING+=("$$")
    
    # Execute traditional chroot
    local chroot_result=0
    if ! sudo chroot "$chroot_dir" /usr/bin/env -i \
        HOME=/root \
        TERM="$TERM" \
        PS1='(ailinux-chroot) \u:\w\$ ' \
        PATH=/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin \
        DEBIAN_FRONTEND=noninteractive \
        LANG=en_US.UTF-8 \
        LC_ALL=en_US.UTF-8 \
        AILINUX_CHROOT_SESSION="$AILINUX_CHROOT_SESSION" \
        /bin/bash --login +h -c "$command"; then
        chroot_result=$?
        log_error "❌ Chroot command failed with traditional isolation (exit code: $chroot_result)"
    else
        log_success "✅ Chroot command completed successfully with traditional isolation"
    fi
    
    # Log process completion
    local process_end=$(date)
    echo "END:$$:$process_end:$chroot_result" >> "$AILINUX_CHROOT_PROCESS_LOG"
    
    return $chroot_result
}

# Safely exit chroot environment
exit_chroot_cleanly() {
    local chroot_dir="$1"
    
    log_info "🚪 Exiting chroot environment cleanly..."
    
    # Kill any remaining chroot processes
    cleanup_chroot_processes "$chroot_dir"
    
    # Unmount filesystems
    cleanup_chroot_mounts "$chroot_dir"
    
    # Clean up tracking data
    cleanup_chroot_tracking
    
    log_success "Chroot environment exited cleanly"
}

# Clean up chroot processes
cleanup_chroot_processes() {
    local chroot_dir="$1"
    
    log_info "🔄 Cleaning up chroot processes..."
    
    # Find processes using the chroot directory
    local chroot_pids=()
    
    # Use fuser to find processes
    if command -v fuser >/dev/null 2>&1; then
        local fuser_output
        if fuser_output=$(sudo fuser -v "$chroot_dir" 2>/dev/null); then
            # Parse fuser output to get PIDs
            echo "$fuser_output" | awk 'NR>1 {print $2}' | while read -r pid; do
                if [ -n "$pid" ] && [ "$pid" != "PID" ]; then
                    chroot_pids+=("$pid")
                fi
            done
        fi
    fi
    
    # Also check tracked processes
    for tracked_pid in "${CHROOT_PROCESS_TRACKING[@]}"; do
        if kill -0 "$tracked_pid" 2>/dev/null; then
            chroot_pids+=("$tracked_pid")
        fi
    done
    
    # Kill processes gracefully
    for pid in "${chroot_pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            log_info "   Terminating chroot process: $pid"
            
            # Try SIGTERM first
            kill -TERM "$pid" 2>/dev/null || true
            sleep 2
            
            # Use SIGKILL if still running
            if kill -0 "$pid" 2>/dev/null; then
                kill -KILL "$pid" 2>/dev/null || true
                log_warn "   ⚠️  Force-killed stubborn process: $pid"
            fi
        fi
    done
    
    # Wait for processes to exit
    sleep 2
    
    log_info "Chroot process cleanup completed"
}

# Clean up chroot mounts
cleanup_chroot_mounts() {
    local chroot_dir="$1"
    
    log_info "🗂️  Cleaning up chroot mounts..."
    
    # Unmount in reverse order (LIFO)
    local mounts_to_unmount=()
    
    # Get all mounts in chroot directory, sorted by depth (deepest first)
    while IFS= read -r mount_line; do
        local mount_point=$(echo "$mount_line" | awk '{print $2}')
        if [[ "$mount_point" == "$chroot_dir"* ]]; then
            mounts_to_unmount+=("$mount_point")
        fi
    done < <(mount | sort -k2 -r)
    
    # Also include tracked mounts
    for tracked_mount in "${CHROOT_MOUNT_TRACKING[@]}"; do
        if mountpoint -q "$tracked_mount" 2>/dev/null; then
            mounts_to_unmount+=("$tracked_mount")
        fi
    done
    
    # Remove duplicates and sort by depth (deepest first)
    local unique_mounts=($(printf '%s\n' "${mounts_to_unmount[@]}" | sort -u | sort -r))
    
    # Unmount each filesystem
    for mount_point in "${unique_mounts[@]}"; do
        if mountpoint -q "$mount_point" 2>/dev/null; then
            log_info "   Unmounting: $mount_point"
            
            # Try graceful unmount first
            if sudo umount "$mount_point" 2>/dev/null; then
                log_info "   ✅ Unmounted successfully: $mount_point"
            else
                # Try lazy unmount
                log_warn "   ⚠️  Graceful unmount failed, trying lazy unmount: $mount_point"
                if sudo umount -l "$mount_point" 2>/dev/null; then
                    log_info "   ✅ Lazy unmount successful: $mount_point"
                else
                    log_error "   ❌ Failed to unmount: $mount_point"
                fi
            fi
            
            # Update tracking log
            echo "UNMOUNT:$mount_point:$(date)" >> "$AILINUX_CHROOT_MOUNT_LOG"
        fi
    done
    
    # Verify no mounts remain
    if mount | grep -q "$chroot_dir"; then
        log_warn "⚠️  Some mounts still active in chroot directory:"
        mount | grep "$chroot_dir" | while read -r remaining_mount; do
            log_warn "   $remaining_mount"
        done
    else
        log_success "✅ All chroot mounts cleaned up successfully"
    fi
}

# Clean up chroot tracking data
cleanup_chroot_tracking() {
    log_info "📊 Cleaning up chroot tracking data..."
    
    # Clear tracking arrays
    CHROOT_MOUNT_TRACKING=()
    CHROOT_PROCESS_TRACKING=()
    CHROOT_ACTIVE_SESSIONS=()
    
    # Archive tracking logs
    if [ -n "$CHROOT_BACKUP_DIR" ] && [ -d "$CHROOT_BACKUP_DIR" ]; then
        local archive_dir="$CHROOT_BACKUP_DIR/archive_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$archive_dir"
        
        # Move logs to archive
        find "$CHROOT_BACKUP_DIR" -name "*.log" -exec mv {} "$archive_dir/" \; 2>/dev/null || true
        
        log_info "Tracking data archived to: $archive_dir"
    fi
}

# Handle chroot cleanup on script exit
cleanup_chroot_on_exit() {
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_warn "🧹 Performing chroot cleanup on script exit (code: $exit_code)"
    fi
    
    # Clean up any active chroot sessions
    for session in "${CHROOT_ACTIVE_SESSIONS[@]}"; do
        if [ -n "$session" ]; then
            cleanup_chroot_session "$session"
        fi
    done
    
    # Clean up backup directory
    if [ -n "$CHROOT_BACKUP_DIR" ] && [ -d "$CHROOT_BACKUP_DIR" ]; then
        # Keep emergency cleanup script but remove other files
        find "$CHROOT_BACKUP_DIR" -type f -not -name "emergency_cleanup.sh" -delete 2>/dev/null || true
    fi
}

# Handle chroot cleanup on signal
cleanup_chroot_on_signal() {
    log_warn "🛑 Chroot cleanup triggered by signal"
    
    # Emergency cleanup for all tracked resources
    cleanup_chroot_on_exit
    
    # Run emergency cleanup script if available
    if [ -n "$AILINUX_CHROOT_EMERGENCY_CLEANUP" ] && [ -f "$AILINUX_CHROOT_EMERGENCY_CLEANUP" ]; then
        log_info "Running emergency chroot cleanup script..."
        bash "$AILINUX_CHROOT_EMERGENCY_CLEANUP"
    fi
}

# Clean up specific chroot session
cleanup_chroot_session() {
    local session_id="$1"
    
    log_info "🧹 Cleaning up chroot session: $session_id"
    
    # Find and kill session processes
    if [ -f "$CHROOT_BACKUP_DIR/process_tracking.log" ]; then
        grep "START:$session_id:" "$CHROOT_BACKUP_DIR/process_tracking.log" | while read -r line; do
            local pid=$(echo "$line" | cut -d: -f2)
            if kill -0 "$pid" 2>/dev/null; then
                kill -TERM "$pid" 2>/dev/null || true
            fi
        done
    fi
    
    # Clean up session namespace file
    local namespace_file="$CHROOT_BACKUP_DIR/namespaces/session_$session_id"
    if [ -f "$namespace_file" ]; then
        echo "$(date): Session cleanup completed" >> "$namespace_file"
    fi
}

# Export functions for use in other modules
export -f init_chroot_management
export -f enter_chroot_safely
export -f exit_chroot_cleanly
export -f validate_chroot_directory
export -f setup_essential_mounts
export -f cleanup_chroot_mounts
export -f cleanup_chroot_processes
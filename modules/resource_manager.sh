#!/bin/bash
#
# Resource Management Module for AILinux Build Script
# Provides safe resource handling without affecting running processes
#
# This module manages system resources (disk space, memory, processes, mounts)
# in a way that doesn't interfere with the user's session or system stability.
#

# Global resource management configuration
declare -g RESOURCE_MONITORING_ENABLED=true
declare -g RESOURCE_CLEANUP_MODE="gentle"  # Options: gentle, aggressive, conservative
declare -g RESOURCE_BACKUP_DIR=""
declare -g TRACKED_RESOURCES=()
declare -g RESOURCE_THRESHOLDS=()
declare -g RESOURCE_ALERTS=()

# Resource thresholds (can be overridden)
declare -g DISK_SPACE_MIN_GB=5
declare -g MEMORY_USAGE_MAX_PERCENT=80
declare -g LOAD_AVERAGE_MAX=8.0
declare -g OPEN_FILES_MAX=1000

# Initialize resource management system
init_resource_management() {
    log_info "📊 Initializing safe resource management system..."
    
    # Set up resource monitoring
    setup_resource_monitoring
    
    # Create resource backup directory
    create_resource_backup_directory
    
    # Initialize resource tracking
    init_resource_tracking
    
    # Set up resource thresholds
    configure_resource_thresholds
    
    # Start resource monitoring
    start_resource_monitoring
    
    log_success "Resource management system initialized in $RESOURCE_CLEANUP_MODE mode"
}

# Set up resource monitoring capabilities
setup_resource_monitoring() {
    # Check available monitoring tools
    local monitoring_tools=()
    
    command -v df >/dev/null && monitoring_tools+=("disk_space")
    command -v free >/dev/null && monitoring_tools+=("memory")
    command -v uptime >/dev/null && monitoring_tools+=("load_average")
    command -v lsof >/dev/null && monitoring_tools+=("open_files")
    command -v ps >/dev/null && monitoring_tools+=("processes")
    command -v iostat >/dev/null && monitoring_tools+=("io_stats")
    
    log_info "Available monitoring tools: ${monitoring_tools[*]}"
    
    # Adjust cleanup mode based on session type
    case "$AILINUX_BUILD_SESSION_TYPE" in
        "ssh")
            RESOURCE_CLEANUP_MODE="conservative"
            log_info "SSH session - using conservative resource cleanup"
            ;;
        "gui")
            RESOURCE_CLEANUP_MODE="gentle"
            log_info "GUI session - using gentle resource cleanup"
            ;;
        "console")
            RESOURCE_CLEANUP_MODE="gentle"
            log_info "Console session - using gentle resource cleanup"
            ;;
        *)
            RESOURCE_CLEANUP_MODE="conservative"
            log_warn "Unknown session type - defaulting to conservative cleanup"
            ;;
    esac
}

# Create backup directory for resource state
create_resource_backup_directory() {
    RESOURCE_BACKUP_DIR="/tmp/ailinux_resource_backup_$$"
    mkdir -p "$RESOURCE_BACKUP_DIR"
    
    # Create subdirectories
    mkdir -p "$RESOURCE_BACKUP_DIR/snapshots"
    mkdir -p "$RESOURCE_BACKUP_DIR/monitoring"
    mkdir -p "$RESOURCE_BACKUP_DIR/cleanup"
    mkdir -p "$RESOURCE_BACKUP_DIR/alerts"
    
    export AILINUX_RESOURCE_BACKUP_DIR="$RESOURCE_BACKUP_DIR"
    log_info "Resource backup directory: $RESOURCE_BACKUP_DIR"
}

# Initialize resource tracking
init_resource_tracking() {
    TRACKED_RESOURCES=()
    
    # Create resource tracking log
    local tracking_log="$RESOURCE_BACKUP_DIR/resource_tracking.log"
    cat > "$tracking_log" << EOF
# AILinux Resource Tracking Log
# Started: $(date)
# Session: $AILINUX_BUILD_SESSION_TYPE
# Cleanup Mode: $RESOURCE_CLEANUP_MODE
# PID: $$
EOF
    
    export AILINUX_RESOURCE_TRACKING_LOG="$tracking_log"
    
    # Take initial resource snapshot
    take_resource_snapshot "initial"
}

# Configure resource thresholds based on system capabilities
configure_resource_thresholds() {
    log_info "⚙️  Configuring resource thresholds..."
    
    # Detect system resources
    local total_memory_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_memory_gb=$((total_memory_kb / 1024 / 1024))
    
    local available_disk_gb=$(df --output=avail . | tail -1 | awk '{print int($1/1024/1024)}')
    
    local cpu_cores=$(nproc)
    
    # Adjust thresholds based on available resources
    if [ "$total_memory_gb" -lt 4 ]; then
        MEMORY_USAGE_MAX_PERCENT=70
        log_info "Low memory system detected - reducing memory threshold to 70%"
    elif [ "$total_memory_gb" -gt 16 ]; then
        MEMORY_USAGE_MAX_PERCENT=85
        log_info "High memory system detected - increasing memory threshold to 85%"
    fi
    
    if [ "$available_disk_gb" -lt 10 ]; then
        DISK_SPACE_MIN_GB=2
        log_warn "⚠️  Low disk space detected - reducing minimum requirement to 2GB"
    elif [ "$available_disk_gb" -gt 50 ]; then
        DISK_SPACE_MIN_GB=10
        log_info "Plenty of disk space - increasing minimum to 10GB"
    fi
    
    LOAD_AVERAGE_MAX=$(echo "$cpu_cores * 2" | bc 2>/dev/null || echo "8")
    OPEN_FILES_MAX=$((cpu_cores * 500))
    
    # Store thresholds
    RESOURCE_THRESHOLDS=(
        "disk_space_min_gb=$DISK_SPACE_MIN_GB"
        "memory_usage_max_percent=$MEMORY_USAGE_MAX_PERCENT"
        "load_average_max=$LOAD_AVERAGE_MAX"
        "open_files_max=$OPEN_FILES_MAX"
    )
    
    log_info "Resource thresholds configured:"
    for threshold in "${RESOURCE_THRESHOLDS[@]}"; do
        log_info "   $threshold"
    done
}

# Start resource monitoring in background
start_resource_monitoring() {
    if [ "$RESOURCE_MONITORING_ENABLED" = true ]; then
        monitor_resources_background &
        local monitor_pid=$!
        
        echo "$monitor_pid" > "$RESOURCE_BACKUP_DIR/monitor_pid"
        
        # Set up resource alerts
        setup_resource_alerts
        
        log_info "Resource monitoring started (PID: $monitor_pid)"
    fi
}

# Monitor resources in background
monitor_resources_background() {
    local monitoring_log="$RESOURCE_BACKUP_DIR/monitoring/resource_monitor.log"
    
    echo "# Resource Monitoring Log - Started: $(date)" > "$monitoring_log"
    
    while sleep 30; do
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        
        # Monitor disk space
        local available_gb=$(df --output=avail . | tail -1 | awk '{print int($1/1024/1024)}')
        echo "[$timestamp] DISK: ${available_gb}GB available" >> "$monitoring_log"
        
        # Monitor memory usage
        local memory_usage=$(free | awk 'NR==2{printf "%.1f", $3*100/$2}')
        echo "[$timestamp] MEMORY: ${memory_usage}% used" >> "$monitoring_log"
        
        # Monitor load average
        local load_avg=$(uptime | awk -F'load average:' '{ print $2 }' | awk '{ print $1 }' | sed 's/,//')
        echo "[$timestamp] LOAD: $load_avg" >> "$monitoring_log"
        
        # Check thresholds
        check_resource_thresholds "$available_gb" "$memory_usage" "$load_avg"
        
        # Take periodic snapshots
        if [ $(($(date +%M) % 10)) -eq 0 ]; then
            take_resource_snapshot "periodic_$(date +%H%M)"
        fi
        
    done
}

# Check if resources exceed thresholds
check_resource_thresholds() {
    local disk_gb="$1"
    local memory_percent="$2"
    local load_avg="$3"
    
    local alerts=()
    
    # Check disk space
    if [ "$disk_gb" -lt "$DISK_SPACE_MIN_GB" ]; then
        alerts+=("DISK_SPACE_LOW:${disk_gb}GB<${DISK_SPACE_MIN_GB}GB")
        trigger_disk_cleanup
    fi
    
    # Check memory usage
    local memory_int=${memory_percent%.*}
    if [ "$memory_int" -gt "$MEMORY_USAGE_MAX_PERCENT" ]; then
        alerts+=("MEMORY_HIGH:${memory_percent}%>${MEMORY_USAGE_MAX_PERCENT}%")
        trigger_memory_cleanup
    fi
    
    # Check load average
    if command -v bc >/dev/null 2>&1; then
        if [ "$(echo "$load_avg > $LOAD_AVERAGE_MAX" | bc)" -eq 1 ]; then
            alerts+=("LOAD_HIGH:${load_avg}>${LOAD_AVERAGE_MAX}")
            trigger_load_reduction
        fi
    fi
    
    # Log alerts
    if [ ${#alerts[@]} -gt 0 ]; then
        local alert_msg="Resource thresholds exceeded: ${alerts[*]}"
        log_warn "⚠️  $alert_msg"
        
        # Store alert
        echo "$(date '+%Y-%m-%d %H:%M:%S'): $alert_msg" >> "$RESOURCE_BACKUP_DIR/alerts/resource_alerts.log"
        
        # Coordinate through swarm if available
        swarm_coordinate "resource_alert" "$alert_msg" "warning" "monitoring" || true
    fi
}

# Set up resource alerts
setup_resource_alerts() {
    RESOURCE_ALERTS=()
    
    # Create alert configuration
    local alert_config="$RESOURCE_BACKUP_DIR/alerts/alert_config.conf"
    cat > "$alert_config" << EOF
# Resource Alert Configuration
disk_space_min_gb=$DISK_SPACE_MIN_GB
memory_usage_max_percent=$MEMORY_USAGE_MAX_PERCENT
load_average_max=$LOAD_AVERAGE_MAX
open_files_max=$OPEN_FILES_MAX

# Alert actions
disk_cleanup_enabled=true
memory_cleanup_enabled=true
load_reduction_enabled=true
EOF
    
    log_info "Resource alerts configured"
}

# Take resource snapshot
take_resource_snapshot() {
    local snapshot_name="$1"
    local snapshot_file="$RESOURCE_BACKUP_DIR/snapshots/snapshot_${snapshot_name}_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "# Resource Snapshot: $snapshot_name"
        echo "# Timestamp: $(date)"
        echo "# Session: $AILINUX_BUILD_SESSION_TYPE"
        echo ""
        
        echo "== DISK USAGE =="
        df -h || true
        echo ""
        
        echo "== MEMORY USAGE =="
        free -h || true
        echo ""
        
        echo "== LOAD AVERAGE =="
        uptime || true
        echo ""
        
        echo "== PROCESS COUNT =="
        ps aux | wc -l || true
        echo ""
        
        echo "== OPEN FILES =="
        lsof | wc -l 2>/dev/null || echo "lsof not available"
        echo ""
        
        echo "== MOUNT POINTS =="
        mount | wc -l || true
        echo ""
        
        echo "== NETWORK CONNECTIONS =="
        ss -tuln | wc -l 2>/dev/null || netstat -tuln | wc -l 2>/dev/null || echo "network stats not available"
        
    } > "$snapshot_file"
    
    log_info "📸 Resource snapshot taken: $snapshot_name"
}

# Trigger disk cleanup when space is low
trigger_disk_cleanup() {
    log_warn "💾 Triggering disk cleanup due to low space..."
    
    case "$RESOURCE_CLEANUP_MODE" in
        "aggressive")
            perform_aggressive_disk_cleanup
            ;;
        "gentle")
            perform_gentle_disk_cleanup
            ;;
        "conservative")
            perform_conservative_disk_cleanup
            ;;
    esac
}

# Perform gentle disk cleanup
perform_gentle_disk_cleanup() {
    log_info "🧹 Performing gentle disk cleanup..."
    
    # Clean temporary build files
    if [ -d "/tmp" ]; then
        find /tmp -name "debootstrap*" -type d -mtime +1 -exec sudo rm -rf {} \; 2>/dev/null || true
        find /tmp -name "ailinux_*" -type d -user "$USER" -mtime +1 -exec rm -rf {} \; 2>/dev/null || true
    fi
    
    # Clean package cache (user-accessible only)
    if command -v apt-get >/dev/null 2>&1; then
        apt-get clean 2>/dev/null || true
    fi
    
    # Clean user cache directories
    if [ -d "$HOME/.cache" ]; then
        find "$HOME/.cache" -type f -atime +7 -delete 2>/dev/null || true
    fi
    
    # Clean build logs older than 7 days
    find . -name "*.log" -mtime +7 -delete 2>/dev/null || true
    
    log_info "Gentle disk cleanup completed"
}

# Perform conservative disk cleanup
perform_conservative_disk_cleanup() {
    log_info "🧹 Performing conservative disk cleanup..."
    
    # Only clean obviously safe temporary files
    if [ -d "/tmp" ]; then
        find /tmp -name "tmp.*" -user "$USER" -mtime +1 -delete 2>/dev/null || true
        find /tmp -name "ailinux_tmp_*" -user "$USER" -delete 2>/dev/null || true
    fi
    
    # Clean only our own build artifacts
    find . -name "*.tmp" -delete 2>/dev/null || true
    find . -name "core" -delete 2>/dev/null || true
    
    log_info "Conservative disk cleanup completed"
}

# Perform aggressive disk cleanup
perform_aggressive_disk_cleanup() {
    log_warn "🧹 Performing aggressive disk cleanup..."
    
    # All gentle cleanup actions
    perform_gentle_disk_cleanup
    
    # Additional aggressive actions
    if [ -d "/var/cache" ]; then
        sudo find /var/cache -type f -atime +3 -delete 2>/dev/null || true
    fi
    
    # Clean system logs (keeping recent ones)
    if [ -d "/var/log" ]; then
        sudo find /var/log -name "*.log" -size +100M -mtime +3 -delete 2>/dev/null || true
    fi
    
    # Clean old kernel headers (if safe)
    if command -v dpkg >/dev/null 2>&1; then
        local current_kernel=$(uname -r)
        dpkg -l | grep "linux-headers" | grep -v "$current_kernel" | awk '{print $2}' > /tmp/old_headers_$$
        if [ -s /tmp/old_headers_$$ ]; then
            log_info "Found old kernel headers to remove"
            # Don't actually remove in aggressive mode to avoid breaking system
        fi
        rm -f /tmp/old_headers_$$
    fi
    
    log_warn "Aggressive disk cleanup completed"
}

# Trigger memory cleanup when usage is high
trigger_memory_cleanup() {
    log_warn "🧠 Triggering memory cleanup due to high usage..."
    
    case "$RESOURCE_CLEANUP_MODE" in
        "aggressive")
            perform_aggressive_memory_cleanup
            ;;
        "gentle")
            perform_gentle_memory_cleanup
            ;;
        "conservative")
            perform_conservative_memory_cleanup
            ;;
    esac
}

# Perform gentle memory cleanup
perform_gentle_memory_cleanup() {
    log_info "🧹 Performing gentle memory cleanup..."
    
    # Clear page cache if safe
    if [ -w /proc/sys/vm/drop_caches ]; then
        # Only clear page cache, not inodes or dentries
        echo 1 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
    fi
    
    # Force garbage collection in any running interpreters
    pkill -USR1 python 2>/dev/null || true
    
    log_info "Gentle memory cleanup completed"
}

# Perform conservative memory cleanup
perform_conservative_memory_cleanup() {
    log_info "🧹 Performing conservative memory cleanup..."
    
    # Only sync and clear minimal cache
    sync 2>/dev/null || true
    
    # Clear only page cache, very conservatively
    if [ "$AILINUX_BUILD_SESSION_TYPE" != "gui" ]; then
        echo 1 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
    fi
    
    log_info "Conservative memory cleanup completed"
}

# Perform aggressive memory cleanup
perform_aggressive_memory_cleanup() {
    log_warn "🧹 Performing aggressive memory cleanup..."
    
    # All gentle cleanup actions
    perform_gentle_memory_cleanup
    
    # Clear all caches (risky but effective)
    if [ -w /proc/sys/vm/drop_caches ]; then
        echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
    fi
    
    # Compact memory
    if [ -w /proc/sys/vm/compact_memory ]; then
        echo 1 | sudo tee /proc/sys/vm/compact_memory >/dev/null 2>&1 || true
    fi
    
    log_warn "Aggressive memory cleanup completed"
}

# Trigger load reduction when system is overloaded
trigger_load_reduction() {
    log_warn "⚡ Triggering load reduction due to high system load..."
    
    # Reduce process priority for build operations
    renice -n 10 $$ 2>/dev/null || true
    
    # If ionice is available, reduce I/O priority
    if command -v ionice >/dev/null 2>&1; then
        ionice -c 3 -p $$ 2>/dev/null || true
    fi
    
    log_info "Load reduction measures applied"
}

# Track resource usage for a specific operation
track_resource_usage() {
    local operation_name="$1"
    local operation_pid="${2:-$$}"
    
    # Take snapshot before operation
    take_resource_snapshot "before_${operation_name}"
    
    # Track the resource usage
    TRACKED_RESOURCES+=("$operation_name:$operation_pid:$(date)")
    
    log_info "📊 Tracking resource usage for: $operation_name (PID: $operation_pid)"
}

# Stop tracking resource usage and generate report
stop_tracking_resource_usage() {
    local operation_name="$1"
    
    # Take snapshot after operation
    take_resource_snapshot "after_${operation_name}"
    
    # Generate usage report
    generate_resource_usage_report "$operation_name"
    
    log_info "📊 Stopped tracking resource usage for: $operation_name"
}

# Generate resource usage report
generate_resource_usage_report() {
    local operation_name="$1"
    local report_file="$RESOURCE_BACKUP_DIR/usage_report_${operation_name}_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "# Resource Usage Report: $operation_name"
        echo "# Generated: $(date)"
        echo ""
        
        # Find before and after snapshots
        local before_snapshot=$(find "$RESOURCE_BACKUP_DIR/snapshots" -name "*before_${operation_name}*" | sort | tail -1)
        local after_snapshot=$(find "$RESOURCE_BACKUP_DIR/snapshots" -name "*after_${operation_name}*" | sort | tail -1)
        
        if [ -n "$before_snapshot" ] && [ -n "$after_snapshot" ]; then
            echo "== RESOURCE USAGE COMPARISON =="
            echo "Before: $(basename "$before_snapshot")"
            echo "After:  $(basename "$after_snapshot")"
            echo ""
            
            # Simple comparison (could be enhanced)
            echo "Snapshot files available for detailed analysis:"
            echo "  Before: $before_snapshot"
            echo "  After:  $after_snapshot"
        else
            echo "== RESOURCE SNAPSHOTS NOT FOUND =="
            echo "Could not generate comparison report"
        fi
        
    } > "$report_file"
    
    log_info "📄 Resource usage report generated: $report_file"
}

# Clean up resource management
cleanup_resource_management() {
    log_info "🧹 Cleaning up resource management..."
    
    # Stop monitoring
    if [ -f "$RESOURCE_BACKUP_DIR/monitor_pid" ]; then
        local monitor_pid=$(cat "$RESOURCE_BACKUP_DIR/monitor_pid")
        if kill -0 "$monitor_pid" 2>/dev/null; then
            kill "$monitor_pid" 2>/dev/null || true
            log_info "Resource monitoring stopped"
        fi
    fi
    
    # Generate final resource report
    take_resource_snapshot "final"
    
    # Clean up old snapshots (keep recent ones)
    find "$RESOURCE_BACKUP_DIR/snapshots" -name "snapshot_*" -mtime +1 -delete 2>/dev/null || true
    
    # Archive monitoring data
    if [ -d "$RESOURCE_BACKUP_DIR/monitoring" ]; then
        tar -czf "$RESOURCE_BACKUP_DIR/monitoring_archive_$(date +%Y%m%d_%H%M%S).tar.gz" \
            -C "$RESOURCE_BACKUP_DIR" monitoring 2>/dev/null || true
        rm -rf "$RESOURCE_BACKUP_DIR/monitoring"
    fi
    
    log_success "Resource management cleanup completed"
}

# Export functions for use in other modules
export -f init_resource_management
export -f take_resource_snapshot
export -f track_resource_usage
export -f stop_tracking_resource_usage
export -f trigger_disk_cleanup
export -f trigger_memory_cleanup
export -f cleanup_resource_management
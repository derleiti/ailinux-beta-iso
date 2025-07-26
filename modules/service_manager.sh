#!/bin/bash
#
# Service Management Module for AILinux Build Script
# Provides session-aware service operations that don't terminate user sessions
#
# This module handles service operations safely, ensuring that session-critical
# services are not disrupted during the build process.
#

# Global service management configuration
declare -g SERVICE_ISOLATION_MODE="strict"
declare -g SERVICE_BACKUP_DIR=""
declare -g MODIFIED_SERVICES=()
declare -g SERVICE_DEPENDENCIES=()
declare -g ORIGINAL_SERVICE_STATES=()

# Initialize service management system
init_service_management() {
    log_info "⚙️  Initializing session-aware service management..."
    
    # Set up service isolation
    setup_service_isolation
    
    # Create service backup directory
    create_service_backup_directory
    
    # Analyze current service state
    analyze_current_services
    
    # Set up service monitoring
    setup_service_monitoring
    
    log_success "Service management system initialized"
}

# Set up service isolation mechanisms
setup_service_isolation() {
    # Determine isolation mode based on session type
    case "$AILINUX_BUILD_SESSION_TYPE" in
        "ssh")
            SERVICE_ISOLATION_MODE="strict"
            log_info "SSH session - using strict service isolation"
            ;;
        "gui")
            SERVICE_ISOLATION_MODE="ultra_strict"
            log_info "GUI session - using ultra-strict service isolation"
            ;;
        "console")
            SERVICE_ISOLATION_MODE="moderate"
            log_info "Console session - using moderate service isolation"
            ;;
        *)
            SERVICE_ISOLATION_MODE="strict"
            log_warn "Unknown session type - defaulting to strict isolation"
            ;;
    esac
}

# Create backup directory for service configurations
create_service_backup_directory() {
    SERVICE_BACKUP_DIR="/tmp/ailinux_service_backup_$$"
    mkdir -p "$SERVICE_BACKUP_DIR"
    
    # Create subdirectories
    mkdir -p "$SERVICE_BACKUP_DIR/systemd"
    mkdir -p "$SERVICE_BACKUP_DIR/states"
    mkdir -p "$SERVICE_BACKUP_DIR/configs"
    
    export AILINUX_SERVICE_BACKUP_DIR="$SERVICE_BACKUP_DIR"
    log_info "Service backup directory: $SERVICE_BACKUP_DIR"
}

# Analyze current service state
analyze_current_services() {
    log_info "📊 Analyzing current service state..."
    
    # Capture current systemd service states
    systemctl list-units --type=service --all > "$SERVICE_BACKUP_DIR/states/initial_services.txt" 2>/dev/null || true
    systemctl --user list-units --type=service --all > "$SERVICE_BACKUP_DIR/states/initial_user_services.txt" 2>/dev/null || true
    
    # Identify session-critical services
    identify_session_critical_services
    
    # Map service dependencies
    map_service_dependencies
    
    # Store original states
    store_original_service_states
}

# Identify services that are critical to the current session
identify_session_critical_services() {
    local critical_file="$SERVICE_BACKUP_DIR/critical_services.txt"
    
    # Base critical services for all session types
    local base_critical=(
        "dbus"
        "systemd-logind"
        "NetworkManager"
        "systemd-resolved"
        "systemd-timesyncd"
    )
    
    # Add session-specific critical services
    case "$AILINUX_BUILD_SESSION_TYPE" in
        "ssh")
            base_critical+=(
                "ssh"
                "sshd"
                "systemd-networkd"
            )
            ;;
        "gui")
            base_critical+=(
                "display-manager"
                "gdm3"
                "lightdm"
                "sddm"
                "xorg"
                "wayland"
                "pulseaudio"
                "pipewire"
                "bluetooth"
            )
            ;;
        "console")
            base_critical+=(
                "getty"
                "serial-getty"
            )
            ;;
    esac
    
    # Write critical services to file
    printf '%s\n' "${base_critical[@]}" > "$critical_file"
    
    log_info "Identified ${#base_critical[@]} session-critical services"
}

# Map service dependencies to avoid cascading failures
map_service_dependencies() {
    log_info "🔗 Mapping service dependencies..."
    
    local deps_file="$SERVICE_BACKUP_DIR/service_dependencies.txt"
    
    # For each critical service, map its dependencies
    while read -r service; do
        if systemctl list-dependencies "$service" > "$SERVICE_BACKUP_DIR/deps_${service}.txt" 2>/dev/null; then
            log_info "Mapped dependencies for $service"
        fi
    done < "$SERVICE_BACKUP_DIR/critical_services.txt"
    
    # Create combined dependency map
    find "$SERVICE_BACKUP_DIR" -name "deps_*.txt" -exec cat {} \; > "$deps_file" 2>/dev/null || true
}

# Store original service states for rollback
store_original_service_states() {
    log_info "💾 Storing original service states..."
    
    local states_file="$SERVICE_BACKUP_DIR/original_states.json"
    
    # Create JSON structure for service states
    echo "{" > "$states_file"
    echo "  \"timestamp\": \"$(date -Iseconds)\"," >> "$states_file"
    echo "  \"session_type\": \"$AILINUX_BUILD_SESSION_TYPE\"," >> "$states_file"
    echo "  \"services\": {" >> "$states_file"
    
    local first=true
    while read -r service; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$states_file"
        fi
        
        local state="unknown"
        if systemctl is-active "$service" >/dev/null 2>&1; then
            state="active"
        elif systemctl is-enabled "$service" >/dev/null 2>&1; then
            state="enabled"
        elif systemctl is-failed "$service" >/dev/null 2>&1; then
            state="failed"
        else
            state="inactive"
        fi
        
        echo "    \"$service\": \"$state\"" >> "$states_file"
    done < "$SERVICE_BACKUP_DIR/critical_services.txt"
    
    echo "  }" >> "$states_file"
    echo "}" >> "$states_file"
    
    log_info "Service states stored for rollback"
}

# Set up service monitoring
setup_service_monitoring() {
    # Start background service monitor
    monitor_critical_services &
    local monitor_pid=$!
    
    echo "$monitor_pid" > "$SERVICE_BACKUP_DIR/monitor_pid"
    
    # Set up service change alerts
    setup_service_alerts
}

# Monitor critical services in background
monitor_critical_services() {
    while sleep 10; do
        # Check if any critical services have stopped
        while read -r service; do
            if ! systemctl is-active "$service" >/dev/null 2>&1; then
                # Check if it was supposed to be running
                if grep -q "\"$service\": \"active\"" "$SERVICE_BACKUP_DIR/original_states.json" 2>/dev/null; then
                    log_warn "⚠️  Critical service $service has stopped!"
                    
                    # Attempt to restart if safe
                    if is_safe_to_restart_service "$service"; then
                        log_info "🔄 Attempting to restart $service safely..."
                        safe_service_restart "$service"
                    fi
                fi
            fi
        done < "$SERVICE_BACKUP_DIR/critical_services.txt"
        
        # Check for unauthorized service changes
        detect_unauthorized_service_changes
        
    done
}

# Set up service change alerts
setup_service_alerts() {
    # Monitor systemd journal for service changes
    if command -v journalctl >/dev/null 2>&1; then
        journalctl -f -u "*.service" --since=now | while read -r line; do
            if echo "$line" | grep -q -E "(Started|Stopped|Failed)"; then
                local service=$(echo "$line" | grep -o '[a-zA-Z0-9_-]*.service' | head -1)
                if [ -n "$service" ] && is_session_critical_service "$service"; then
                    log_info "📢 Service alert: $service state changed"
                fi
            fi
        done &
        
        echo $! > "$SERVICE_BACKUP_DIR/journal_monitor_pid"
    fi
}

# Check if a service is critical to the current session
is_session_critical_service() {
    local service="$1"
    
    # Remove .service suffix if present
    service="${service%.service}"
    
    if grep -q "^$service$" "$SERVICE_BACKUP_DIR/critical_services.txt" 2>/dev/null; then
        return 0
    fi
    
    return 1
}

# Check if it's safe to restart a service
is_safe_to_restart_service() {
    local service="$1"
    
    case "$SERVICE_ISOLATION_MODE" in
        "ultra_strict")
            # In GUI sessions, be extremely careful
            local unsafe_gui_services=(
                "display-manager"
                "gdm3"
                "lightdm"
                "sddm"
                "xorg"
                "wayland"
            )
            
            for unsafe in "${unsafe_gui_services[@]}"; do
                if [[ "$service" == *"$unsafe"* ]]; then
                    return 1
                fi
            done
            ;;
        "strict")
            # In SSH sessions, avoid network and auth services
            local unsafe_ssh_services=(
                "sshd"
                "NetworkManager"
                "systemd-logind"
            )
            
            for unsafe in "${unsafe_ssh_services[@]}"; do
                if [[ "$service" == *"$unsafe"* ]]; then
                    return 1
                fi
            done
            ;;
        "moderate")
            # In console sessions, be less restrictive
            local unsafe_console_services=(
                "getty"
                "systemd-logind"
            )
            
            for unsafe in "${unsafe_console_services[@]}"; do
                if [[ "$service" == *"$unsafe"* ]]; then
                    return 1
                fi
            done
            ;;
    esac
    
    return 0
}

# Safely restart a service
safe_service_restart() {
    local service="$1"
    local restart_method="${2:-smart}"  # Options: smart, reload, restart, stop-start
    
    log_info "🔄 Safely restarting service: $service (method: $restart_method)"
    
    # Check if service is session-critical
    if is_session_critical_service "$service"; then
        log_warn "⚠️  Service $service is session-critical - using gentle restart"
        restart_method="reload"
    fi
    
    # Back up current service configuration
    backup_service_config "$service"
    
    # Track the service modification
    MODIFIED_SERVICES+=("$service")
    
    case "$restart_method" in
        "smart")
            # Try reload first, then restart if needed
            if systemctl reload "$service" 2>/dev/null; then
                log_success "✅ Service $service reloaded successfully"
            elif systemctl restart "$service" 2>/dev/null; then
                log_success "✅ Service $service restarted successfully"
            else
                log_error "❌ Failed to restart service $service"
                return 1
            fi
            ;;
        "reload")
            if systemctl reload "$service" 2>/dev/null; then
                log_success "✅ Service $service reloaded successfully"
            elif systemctl reload-or-restart "$service" 2>/dev/null; then
                log_success "✅ Service $service reloaded/restarted successfully"
            else
                log_error "❌ Failed to reload service $service"
                return 1
            fi
            ;;
        "restart")
            if systemctl restart "$service" 2>/dev/null; then
                log_success "✅ Service $service restarted successfully"
            else
                log_error "❌ Failed to restart service $service"
                return 1
            fi
            ;;
        "stop-start")
            if systemctl stop "$service" 2>/dev/null; then
                sleep 2
                if systemctl start "$service" 2>/dev/null; then
                    log_success "✅ Service $service stop-started successfully"
                else
                    log_error "❌ Failed to start service $service after stop"
                    return 1
                fi
            else
                log_error "❌ Failed to stop service $service"
                return 1
            fi
            ;;
    esac
    
    # Verify service is running correctly
    sleep 2
    if systemctl is-active "$service" >/dev/null 2>&1; then
        log_success "✅ Service $service is running correctly after restart"
        return 0
    else
        log_error "❌ Service $service failed to start properly"
        
        # Attempt rollback
        rollback_service_config "$service"
        return 1
    fi
}

# Backup service configuration
backup_service_config() {
    local service="$1"
    
    log_info "💾 Backing up configuration for service: $service"
    
    # Create service-specific backup directory
    local service_backup_dir="$SERVICE_BACKUP_DIR/configs/$service"
    mkdir -p "$service_backup_dir"
    
    # Backup systemd unit file
    local unit_file="/etc/systemd/system/${service}.service"
    if [ -f "$unit_file" ]; then
        cp "$unit_file" "$service_backup_dir/" 2>/dev/null || true
    fi
    
    # Backup service-specific configuration directories
    case "$service" in
        "NetworkManager")
            cp -r /etc/NetworkManager/ "$service_backup_dir/" 2>/dev/null || true
            ;;
        "gdm3"|"lightdm"|"sddm")
            cp -r /etc/$service/ "$service_backup_dir/" 2>/dev/null || true
            ;;
        "dbus")
            cp -r /etc/dbus-1/ "$service_backup_dir/" 2>/dev/null || true
            ;;
    esac
    
    # Store current service state
    systemctl show "$service" > "$service_backup_dir/service_properties.txt" 2>/dev/null || true
}

# Rollback service configuration
rollback_service_config() {
    local service="$1"
    
    log_info "🔄 Rolling back configuration for service: $service"
    
    local service_backup_dir="$SERVICE_BACKUP_DIR/configs/$service"
    
    if [ ! -d "$service_backup_dir" ]; then
        log_warn "⚠️  No backup found for service $service"
        return 1
    fi
    
    # Restore systemd unit file
    local unit_file="/etc/systemd/system/${service}.service"
    if [ -f "$service_backup_dir/${service}.service" ]; then
        sudo cp "$service_backup_dir/${service}.service" "$unit_file" 2>/dev/null || true
        sudo systemctl daemon-reload
    fi
    
    # Restore service-specific configurations
    case "$service" in
        "NetworkManager")
            if [ -d "$service_backup_dir/NetworkManager" ]; then
                sudo cp -r "$service_backup_dir/NetworkManager/"* /etc/NetworkManager/ 2>/dev/null || true
            fi
            ;;
        "gdm3"|"lightdm"|"sddm")
            if [ -d "$service_backup_dir/$service" ]; then
                sudo cp -r "$service_backup_dir/$service/"* "/etc/$service/" 2>/dev/null || true
            fi
            ;;
        "dbus")
            if [ -d "$service_backup_dir/dbus-1" ]; then
                sudo cp -r "$service_backup_dir/dbus-1/"* /etc/dbus-1/ 2>/dev/null || true
            fi
            ;;
    esac
    
    # Restart service with original configuration
    systemctl restart "$service" 2>/dev/null || true
    
    log_info "Service $service configuration rolled back"
}

# Detect unauthorized service changes
detect_unauthorized_service_changes() {
    # Compare current service states with original
    local current_states="/tmp/current_service_states_$$"
    
    systemctl list-units --type=service --all > "$current_states" 2>/dev/null || return
    
    # Check for significant differences
    if ! diff -q "$SERVICE_BACKUP_DIR/states/initial_services.txt" "$current_states" >/dev/null 2>&1; then
        local changes=$(diff "$SERVICE_BACKUP_DIR/states/initial_services.txt" "$current_states" | wc -l)
        
        if [ "$changes" -gt 10 ]; then
            log_warn "⚠️  Significant service state changes detected: $changes differences"
            
            # Log the differences
            diff "$SERVICE_BACKUP_DIR/states/initial_services.txt" "$current_states" > "$SERVICE_BACKUP_DIR/service_changes.diff" 2>/dev/null || true
        fi
    fi
    
    rm -f "$current_states"
}

# Stop all modified services safely
stop_modified_services() {
    log_info "🛑 Stopping modified services safely..."
    
    for service in "${MODIFIED_SERVICES[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            if is_safe_to_restart_service "$service"; then
                log_info "Stopping modified service: $service"
                systemctl stop "$service" 2>/dev/null || true
            else
                log_warn "⚠️  Skipping stop of critical service: $service"
            fi
        fi
    done
}

# Restore all original service states
restore_original_service_states() {
    log_info "🔄 Restoring original service states..."
    
    # Read original states from JSON file
    local states_file="$SERVICE_BACKUP_DIR/original_states.json"
    
    if [ ! -f "$states_file" ]; then
        log_warn "⚠️  No original service states file found"
        return 1
    fi
    
    # Parse JSON and restore states (simplified approach)
    while read -r service; do
        local original_state=$(grep "\"$service\":" "$states_file" 2>/dev/null | cut -d'"' -f4)
        
        if [ -n "$original_state" ]; then
            case "$original_state" in
                "active")
                    if ! systemctl is-active "$service" >/dev/null 2>&1; then
                        systemctl start "$service" 2>/dev/null || true
                    fi
                    ;;
                "inactive")
                    if systemctl is-active "$service" >/dev/null 2>&1; then
                        if is_safe_to_restart_service "$service"; then
                            systemctl stop "$service" 2>/dev/null || true
                        fi
                    fi
                    ;;
            esac
        fi
    done < "$SERVICE_BACKUP_DIR/critical_services.txt"
    
    log_info "Service state restoration completed"
}

# Clean up service management resources
cleanup_service_management() {
    log_info "🧹 Cleaning up service management resources..."
    
    # Stop monitoring processes
    if [ -f "$SERVICE_BACKUP_DIR/monitor_pid" ]; then
        local monitor_pid=$(cat "$SERVICE_BACKUP_DIR/monitor_pid")
        if kill -0 "$monitor_pid" 2>/dev/null; then
            kill "$monitor_pid" 2>/dev/null || true
        fi
    fi
    
    if [ -f "$SERVICE_BACKUP_DIR/journal_monitor_pid" ]; then
        local journal_pid=$(cat "$SERVICE_BACKUP_DIR/journal_monitor_pid")
        if kill -0 "$journal_pid" 2>/dev/null; then
            kill "$journal_pid" 2>/dev/null || true
        fi
    fi
    
    # Restore original service states if needed
    restore_original_service_states
    
    # Clean up backup directory
    if [ -n "$SERVICE_BACKUP_DIR" ] && [ -d "$SERVICE_BACKUP_DIR" ]; then
        rm -rf "$SERVICE_BACKUP_DIR"
    fi
    
    log_success "Service management cleanup completed"
}

# Export functions for use in other modules
export -f init_service_management
export -f is_session_critical_service
export -f safe_service_restart
export -f backup_service_config
export -f rollback_service_config
export -f restore_original_service_states
export -f cleanup_service_management
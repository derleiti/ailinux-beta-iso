# AILinux Build Script Architecture v2.0 - Session-Safe Design

## Executive Summary

This document outlines a comprehensive architectural redesign of the AILinux build script to eliminate session logout issues while maintaining robustness and reliability. The current script's aggressive error handling (`set -eo pipefail`) and service management operations are causing user session termination.

## 🚨 Critical Session Safety Issues Identified

### 1. Aggressive Error Handling
- **Issue**: `set -eo pipefail` causes immediate script termination on any error
- **Impact**: Process termination can cascade to parent shell, causing logout
- **Solution**: Replace with granular error handling per operation

### 2. Service Management Operations
- **Issue**: Service restarts and systemd operations can affect user session
- **Impact**: NetworkManager, display manager, or session services may restart
- **Solution**: Session-aware service handling with dependency checking

### 3. Mount/Unmount Operations
- **Issue**: Aggressive filesystem unmounting with `fuser -km` kills processes
- **Impact**: Can terminate user session if processes are using shared resources
- **Solution**: Gentle unmounting with process isolation

### 4. Process Cleanup
- **Issue**: `pkill` and `fuser -km` operations are too broad
- **Impact**: May kill user session processes
- **Solution**: Targeted process management with PID tracking

## 🏗️ Modular Architecture Design

### Core Modules

#### 1. Session Safety Module (`session_safety.sh`)
```bash
# Isolation patterns and session protection
check_session_safety()
ensure_process_isolation()
safe_service_operation()
verify_no_session_impact()
```

#### 2. Error Handling Module (`error_handler.sh`)
```bash
# Granular error handling without aggressive exits
set_error_mode()        # Configure error handling per phase
handle_error()          # Smart error recovery
log_error_context()     # Detailed error logging
attempt_recovery()      # Automated recovery procedures
```

#### 3. Service Management Module (`service_manager.sh`)
```bash
# Session-aware service operations
check_service_dependencies()
safe_service_restart()
monitor_session_services()
rollback_service_changes()
```

#### 4. Chroot Operations Module (`chroot_manager.sh`)
```bash
# Isolated chroot environment handling
enter_chroot_safely()
exit_chroot_cleanly()
manage_chroot_mounts()
isolate_chroot_processes()
```

#### 5. Resource Management Module (`resource_manager.sh`)
```bash
# Safe resource handling
track_mount_points()
safe_unmount_procedure()
cleanup_without_disruption()
monitor_resource_usage()
```

#### 6. Signal Handling Module (`signal_handler.sh`)
```bash
# Proper signal trapping and cleanup
setup_signal_handlers()
graceful_shutdown()
emergency_cleanup()
preserve_user_session()
```

## 🔒 Session Safety Principles

### 1. Process Isolation
- Use subshells for risky operations
- Implement process containment
- Track parent process hierarchy
- Avoid affecting user session processes

### 2. Service Dependency Awareness
- Check service dependencies before operations
- Identify session-critical services
- Use service isolation techniques
- Implement rollback for service changes

### 3. Graceful Error Handling
- Replace `set -eo pipefail` with targeted error checks
- Implement error recovery procedures
- Use logging instead of immediate exits
- Provide user feedback on recoverable errors

### 4. Resource Protection
- Implement gentle unmounting procedures
- Use process-specific cleanup
- Protect shared system resources
- Monitor resource usage impact

## 🎯 Implementation Strategy

### Phase 1: Error Handling Replacement
```bash
# Replace aggressive error handling
# OLD: set -eo pipefail
# NEW: Function-specific error handling

safe_execute() {
    local cmd="$1"
    local error_msg="$2"
    local recovery_action="$3"
    
    if ! eval "$cmd"; then
        log_error "$error_msg"
        if [ -n "$recovery_action" ]; then
            log_info "Attempting recovery: $recovery_action"
            eval "$recovery_action"
        fi
        return 1
    fi
    return 0
}
```

### Phase 2: Service Management Refactoring
```bash
# Session-safe service operations
safe_service_restart() {
    local service="$1"
    
    # Check if service affects user session
    if is_session_critical_service "$service"; then
        log_warn "Service $service is session-critical, using gentle restart"
        systemctl reload "$service" || systemctl restart "$service"
    else
        systemctl restart "$service"
    fi
}

is_session_critical_service() {
    local service="$1"
    local session_services="NetworkManager gdm3 lightdm sddm"
    
    for critical in $session_services; do
        if [[ "$service" == "$critical" ]]; then
            return 0
        fi
    done
    return 1
}
```

### Phase 3: Mount Safety Implementation
```bash
# Safe mount/unmount procedures
safe_unmount() {
    local mount_point="$1"
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ! mountpoint -q "$mount_point"; then
            return 0  # Already unmounted
        fi
        
        # Gentle unmount attempt
        if umount "$mount_point" 2>/dev/null; then
            return 0
        fi
        
        # If busy, wait and retry
        log_warn "Mount point $mount_point busy, attempt $attempt/$max_attempts"
        sleep 2
        ((attempt++))
    done
    
    # Last resort: lazy unmount (but avoid fuser -km)
    log_warn "Using lazy unmount for $mount_point"
    umount -l "$mount_point" 2>/dev/null || true
}
```

### Phase 4: Chroot Isolation
```bash
# Isolated chroot operations
enter_chroot_safely() {
    local chroot_dir="$1"
    
    # Set up isolated environment
    export CHROOT_PID_FILE="/tmp/chroot_$$.pid"
    echo $$ > "$CHROOT_PID_FILE"
    
    # Use unshare for better isolation
    unshare --pid --fork --mount-proc \
        chroot "$chroot_dir" /usr/bin/env -i \
        HOME=/root \
        TERM="$TERM" \
        PATH=/usr/bin:/usr/sbin:/bin:/sbin \
        DEBIAN_FRONTEND=noninteractive \
        /bin/bash --login +h -c "$2"
}
```

## 🛡️ Safety Checks and Validations

### Pre-execution Safety Checks
```bash
verify_session_safety() {
    # Check current session type
    if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
        log_info "SSH session detected - extra safety measures enabled"
        export SESSION_TYPE="ssh"
    elif [ "$XDG_SESSION_TYPE" = "x11" ] || [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        log_info "Graphical session detected - GUI protection enabled"
        export SESSION_TYPE="gui"
    fi
    
    # Verify no conflicting processes
    check_conflicting_processes
    
    # Ensure adequate permissions without sudo escalation issues
    verify_permissions
}

check_conflicting_processes() {
    local conflicts=()
    
    # Check for other build processes
    if pgrep -f "debootstrap" > /dev/null; then
        conflicts+=("debootstrap")
    fi
    
    if pgrep -f "mksquashfs" > /dev/null; then
        conflicts+=("mksquashfs")
    fi
    
    if [ ${#conflicts[@]} -gt 0 ]; then
        log_error "Conflicting processes detected: ${conflicts[*]}"
        return 1
    fi
}
```

## 📊 Monitoring and Logging

### Session Impact Monitoring
```bash
monitor_session_impact() {
    # Monitor session processes
    export INITIAL_SESSION_PROCS=$(pgrep -u "$USER" | wc -l)
    
    # Track session services
    track_session_services
    
    # Monitor system load
    track_system_resources
}

track_session_services() {
    # Get initial state of session-critical services
    systemctl --user status > /tmp/session_services_initial.log 2>/dev/null || true
    
    # If in GUI session, track display manager
    if [ "$SESSION_TYPE" = "gui" ]; then
        systemctl status display-manager > /tmp/display_manager_initial.log 2>/dev/null || true
    fi
}
```

## 🔄 Recovery and Rollback Mechanisms

### Automated Recovery Procedures
```bash
setup_recovery_mechanisms() {
    # Create recovery checkpoint
    create_recovery_checkpoint
    
    # Set up automatic rollback on critical failures
    trap 'emergency_recovery' ERR EXIT
    
    # Monitor for session disconnection
    setup_disconnection_detection
}

emergency_recovery() {
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        log_critical "Build failed with exit code $exit_code, initiating recovery"
        
        # Stop all build processes gently
        cleanup_build_processes
        
        # Restore system state
        restore_from_checkpoint
        
        # Verify session integrity
        verify_session_integrity
    fi
}
```

## 🎛️ Configuration and Customization

### Build Configuration
```bash
# Session safety configuration
ENABLE_SESSION_MONITORING=true
ENABLE_AGGRESSIVE_CLEANUP=false
ENABLE_SERVICE_ISOLATION=true
ENABLE_CHROOT_ISOLATION=true

# Error handling configuration
ERROR_HANDLING_MODE="graceful"  # Options: graceful, strict, permissive
RECOVERY_ATTEMPTS=3
ENABLE_AUTO_RECOVERY=true

# Resource management
MAX_MOUNT_WAIT_TIME=30
ENABLE_LAZY_UNMOUNT=true
TRACK_RESOURCE_USAGE=true
```

## 🧪 Testing Strategy

### Session Safety Testing
1. **SSH Session Tests**: Verify build doesn't terminate SSH connections
2. **GUI Session Tests**: Ensure desktop environment remains stable
3. **Service Impact Tests**: Monitor service restart effects
4. **Resource Usage Tests**: Track system resource impact

### Error Recovery Testing
1. **Simulated Failures**: Test recovery from various failure points
2. **Resource Exhaustion**: Test behavior under resource constraints
3. **Permission Issues**: Test sudo permission handling
4. **Network Interruption**: Test network failure recovery

## 📋 Implementation Checklist

- [ ] Replace `set -eo pipefail` with granular error handling
- [ ] Implement session safety checks
- [ ] Create service management safety layer
- [ ] Add chroot isolation mechanisms
- [ ] Implement safe mount/unmount procedures
- [ ] Add signal handling and cleanup
- [ ] Create recovery and rollback systems
- [ ] Add comprehensive logging without session interference
- [ ] Implement resource monitoring
- [ ] Add session integrity verification

## 📈 Expected Benefits

1. **Session Stability**: Eliminates user logout issues
2. **Improved Reliability**: Better error handling and recovery
3. **Enhanced Safety**: Process isolation and resource protection
4. **Better Monitoring**: Comprehensive logging and progress tracking
5. **Maintainability**: Modular architecture for easier updates

## 🔮 Future Enhancements

1. **Container Integration**: Consider using containers for better isolation
2. **Parallel Execution**: Safe parallelization of build steps
3. **Resource Optimization**: Dynamic resource allocation
4. **Advanced Recovery**: Machine learning-based error prediction
5. **Cross-Platform Support**: Extend safety mechanisms to other distributions

---

This architecture provides a robust foundation for a session-safe build script that maintains system stability while building reliable AILinux ISOs.
#!/bin/bash
#
# Checksum Validation Module for AILinux Build Script
# Provides MD5 checksum validation for all downloads and files
#
# This module ensures data integrity throughout the build process by
# validating checksums for downloads, generated files, and build artifacts.
#

# Global checksum validation configuration
declare -g CHECKSUM_VALIDATION_ENABLED=true
declare -g CHECKSUM_ALGORITHM="md5"  # Options: md5, sha256, sha1
declare -g CHECKSUM_CACHE_DIR=""
declare -g VALIDATION_FAILURES=()
declare -g VALIDATION_REPORTS=()

# Initialize checksum validation system
init_checksum_validation() {
    log_info "🔐 Initializing checksum validation system..."
    
    # Set up checksum cache directory
    setup_checksum_cache
    
    # Validate checksum tools availability
    validate_checksum_tools
    
    # Configure validation settings
    configure_validation_settings
    
    # Set up validation logging
    setup_validation_logging
    
    log_success "Checksum validation system initialized with $CHECKSUM_ALGORITHM"
}

# Set up checksum cache directory
setup_checksum_cache() {
    CHECKSUM_CACHE_DIR="/tmp/ailinux_checksums_$$"
    mkdir -p "$CHECKSUM_CACHE_DIR"
    
    # Create subdirectories
    mkdir -p "$CHECKSUM_CACHE_DIR/downloads"
    mkdir -p "$CHECKSUM_CACHE_DIR/generated"
    mkdir -p "$CHECKSUM_CACHE_DIR/packages"
    mkdir -p "$CHECKSUM_CACHE_DIR/reports"
    
    export AILINUX_CHECKSUM_CACHE_DIR="$CHECKSUM_CACHE_DIR"
    log_info "Checksum cache directory: $CHECKSUM_CACHE_DIR"
}

# Validate checksum tools availability
validate_checksum_tools() {
    local available_tools=()
    
    # Check for available checksum tools
    command -v md5sum >/dev/null && available_tools+=("md5sum")
    command -v sha256sum >/dev/null && available_tools+=("sha256sum")
    command -v sha1sum >/dev/null && available_tools+=("sha1sum")
    command -v openssl >/dev/null && available_tools+=("openssl")
    
    if [ ${#available_tools[@]} -eq 0 ]; then
        log_error "❌ No checksum validation tools found!"
        CHECKSUM_VALIDATION_ENABLED=false
        return 1
    fi
    
    log_info "Available checksum tools: ${available_tools[*]}"
    
    # Prefer md5sum for AILinux compatibility
    if command -v md5sum >/dev/null; then
        CHECKSUM_ALGORITHM="md5"
        log_info "Using MD5 checksum validation (md5sum)"
    elif command -v sha256sum >/dev/null; then
        CHECKSUM_ALGORITHM="sha256"
        log_info "Using SHA256 checksum validation (sha256sum)"
    else
        CHECKSUM_ALGORITHM="openssl_md5"
        log_info "Using OpenSSL MD5 checksum validation"
    fi
}

# Configure validation settings
configure_validation_settings() {
    # Create validation configuration
    local config_file="$CHECKSUM_CACHE_DIR/validation_config.conf"
    
    cat > "$config_file" << EOF
# AILinux Checksum Validation Configuration
algorithm=$CHECKSUM_ALGORITHM
cache_dir=$CHECKSUM_CACHE_DIR
validation_enabled=$CHECKSUM_VALIDATION_ENABLED
auto_download_checksums=true
strict_validation=true
generate_reports=true
EOF
    
    export AILINUX_CHECKSUM_CONFIG="$config_file"
}

# Set up validation logging
setup_validation_logging() {
    local log_file="$CHECKSUM_CACHE_DIR/validation.log"
    
    cat > "$log_file" << EOF
# AILinux Checksum Validation Log
# Started: $(date)
# Algorithm: $CHECKSUM_ALGORITHM
# Session: $AILINUX_BUILD_SESSION_TYPE
# PID: $$
EOF
    
    export AILINUX_CHECKSUM_LOG="$log_file"
}

# Calculate checksum for a file
calculate_checksum() {
    local file_path="$1"
    local algorithm="${2:-$CHECKSUM_ALGORITHM}"
    
    if [ ! -f "$file_path" ]; then
        log_error "File not found for checksum calculation: $file_path"
        return 1
    fi
    
    local checksum=""
    
    case "$algorithm" in
        "md5")
            if command -v md5sum >/dev/null; then
                checksum=$(md5sum "$file_path" | awk '{print $1}')
            elif command -v openssl >/dev/null; then
                checksum=$(openssl md5 "$file_path" | awk '{print $NF}')
            fi
            ;;
        "sha256")
            if command -v sha256sum >/dev/null; then
                checksum=$(sha256sum "$file_path" | awk '{print $1}')
            elif command -v openssl >/dev/null; then
                checksum=$(openssl sha256 "$file_path" | awk '{print $NF}')
            fi
            ;;
        "sha1")
            if command -v sha1sum >/dev/null; then
                checksum=$(sha1sum "$file_path" | awk '{print $1}')
            elif command -v openssl >/dev/null; then
                checksum=$(openssl sha1 "$file_path" | awk '{print $NF}')
            fi
            ;;
        "openssl_md5")
            checksum=$(openssl md5 "$file_path" | awk '{print $NF}')
            ;;
    esac
    
    if [ -n "$checksum" ]; then
        echo "$checksum"
        
        # Cache the checksum
        cache_checksum "$file_path" "$checksum" "$algorithm"
        
        return 0
    else
        log_error "Failed to calculate $algorithm checksum for: $file_path"
        return 1
    fi
}

# Cache checksum for future reference
cache_checksum() {
    local file_path="$1"
    local checksum="$2"
    local algorithm="$3"
    
    local cache_file="$CHECKSUM_CACHE_DIR/$(basename "$file_path").checksum"
    
    {
        echo "# Checksum cache for $(basename "$file_path")"
        echo "file_path=$file_path"
        echo "algorithm=$algorithm" 
        echo "checksum=$checksum"
        echo "timestamp=$(date -Iseconds)"
        echo "file_size=$(stat -c%s "$file_path" 2>/dev/null || echo "unknown")"
    } > "$cache_file"
    
    log_info "📝 Cached $algorithm checksum for $(basename "$file_path"): $checksum"
}

# Validate MD5 checksum against expected value
validate_md5() {
    local file_path="$1"
    local expected_md5="$2"
    local operation_name="${3:-file_validation}"
    
    if [ ! -f "$file_path" ]; then
        log_error "❌ File not found for MD5 validation: $file_path"
        VALIDATION_FAILURES+=("$operation_name:file_not_found:$file_path")
        return 1
    fi
    
    if [ -z "$expected_md5" ]; then
        log_warn "⚠️  No expected MD5 provided for: $(basename "$file_path")"
        # Calculate and store for future reference
        local calculated_md5=$(calculate_checksum "$file_path" "md5")
        log_info "📝 Calculated MD5 for future reference: $calculated_md5"
        return 0
    fi
    
    log_info "🔍 Validating MD5 checksum for: $(basename "$file_path")"
    
    local calculated_md5=$(calculate_checksum "$file_path" "md5")
    
    if [ -z "$calculated_md5" ]; then
        log_error "❌ Failed to calculate MD5 for: $file_path"
        VALIDATION_FAILURES+=("$operation_name:calculation_failed:$file_path")
        return 1
    fi
    
    if [ "$calculated_md5" = "$expected_md5" ]; then
        log_success "✅ MD5 validation passed for: $(basename "$file_path")"
        log_info "   Expected: $expected_md5"
        log_info "   Calculated: $calculated_md5"
        
        # Log successful validation
        echo "$(date -Iseconds): SUCCESS: $operation_name: $file_path: $calculated_md5" >> "$AILINUX_CHECKSUM_LOG"
        
        return 0
    else
        log_error "❌ MD5 validation failed for: $(basename "$file_path")"
        log_error "   Expected:   $expected_md5"
        log_error "   Calculated: $calculated_md5"
        
        # Log failed validation
        echo "$(date -Iseconds): FAILURE: $operation_name: $file_path: expected=$expected_md5 calculated=$calculated_md5" >> "$AILINUX_CHECKSUM_LOG"
        
        VALIDATION_FAILURES+=("$operation_name:checksum_mismatch:$file_path")
        return 1
    fi
}

# Generate checksums for multiple files
generate_checksums() {
    local target_dir="$1"
    local output_file="${2:-checksums.md5}"
    local algorithm="${3:-md5}"
    
    if [ ! -d "$target_dir" ]; then
        log_error "Target directory not found: $target_dir"
        return 1
    fi
    
    log_info "📝 Generating $algorithm checksums for directory: $target_dir"
    
    local checksum_file="$target_dir/$output_file"
    
    # Generate checksums for all files in directory
    find "$target_dir" -type f -not -name "$output_file" -not -path "*/.*" | sort | while read -r file; do
        local relative_path=$(realpath --relative-to="$target_dir" "$file")
        local checksum=$(calculate_checksum "$file" "$algorithm")
        
        if [ -n "$checksum" ]; then
            echo "$checksum  $relative_path" >> "$checksum_file"
            log_info "   ✅ $(basename "$file"): $checksum"
        else
            log_error "   ❌ Failed to generate checksum for: $(basename "$file")"
        fi
    done
    
    if [ -f "$checksum_file" ]; then
        log_success "📄 Checksum file generated: $checksum_file"
        local count=$(wc -l < "$checksum_file")
        log_info "   Generated checksums for $count files"
        return 0
    else
        log_error "❌ Failed to generate checksum file"
        return 1
    fi
}

# Verify download integrity with checksum
verify_download() {
    local download_url="$1"
    local local_file="$2"
    local expected_checksum="${3:-}"
    local checksum_url="${4:-}"
    
    if [ ! -f "$local_file" ]; then
        log_error "❌ Downloaded file not found: $local_file"
        return 1
    fi
    
    log_info "🔍 Verifying download integrity for: $(basename "$local_file")"
    
    # If expected checksum provided, use it
    if [ -n "$expected_checksum" ]; then
        validate_md5 "$local_file" "$expected_checksum" "download_verification"
        return $?
    fi
    
    # If checksum URL provided, download and verify
    if [ -n "$checksum_url" ]; then
        local checksum_file="/tmp/download_checksum_$$"
        
        if wget -q -O "$checksum_file" "$checksum_url" 2>/dev/null; then
            # Extract checksum (assume first word is the checksum)
            local remote_checksum=$(head -1 "$checksum_file" | awk '{print $1}')
            
            if [ -n "$remote_checksum" ]; then
                validate_md5 "$local_file" "$remote_checksum" "download_verification"
                local result=$?
                rm -f "$checksum_file"
                return $result
            fi
        fi
        
        rm -f "$checksum_file"
        log_warn "⚠️  Could not download checksum file from: $checksum_url"
    fi
    
    # No expected checksum available, just calculate and log
    local calculated_checksum=$(calculate_checksum "$local_file" "md5")
    log_info "📝 Download checksum (for future reference): $calculated_checksum"
    
    # Store in downloads cache
    cache_checksum "$local_file" "$calculated_checksum" "md5"
    
    return 0
}

# Create validation report
create_validation_report() {
    local report_name="${1:-validation_report}"
    local report_file="$CHECKSUM_CACHE_DIR/reports/${report_name}_$(date +%Y%m%d_%H%M%S).txt"
    
    log_info "📊 Creating validation report: $report_name"
    
    {
        echo "# AILinux Checksum Validation Report"
        echo "# Report: $report_name"
        echo "# Generated: $(date)"
        echo "# Session: $AILINUX_BUILD_SESSION_TYPE"
        echo ""
        
        echo "== VALIDATION SUMMARY =="
        echo "Total Failures: ${#VALIDATION_FAILURES[@]}"
        echo "Algorithm Used: $CHECKSUM_ALGORITHM"
        echo "Validation Enabled: $CHECKSUM_VALIDATION_ENABLED"
        echo ""
        
        if [ ${#VALIDATION_FAILURES[@]} -gt 0 ]; then
            echo "== VALIDATION FAILURES =="
            for failure in "${VALIDATION_FAILURES[@]}"; do
                echo "FAILURE: $failure"
            done
            echo ""
        fi
        
        echo "== CACHED CHECKSUMS =="
        if [ -d "$CHECKSUM_CACHE_DIR" ]; then
            find "$CHECKSUM_CACHE_DIR" -name "*.checksum" -exec basename {} .checksum \; | sort
        fi
        echo ""
        
        echo "== VALIDATION LOG =="
        if [ -f "$AILINUX_CHECKSUM_LOG" ]; then
            cat "$AILINUX_CHECKSUM_LOG"
        fi
        
    } > "$report_file"
    
    VALIDATION_REPORTS+=("$report_file")
    
    log_success "📄 Validation report created: $report_file"
    
    # Coordinate through swarm
    swarm_coordinate "validation_report" "Checksum validation report generated: $report_file" "info" "validation" || true
}

# Validate package integrity
validate_package() {
    local package_file="$1"
    local expected_checksum="${2:-}"
    
    if [ ! -f "$package_file" ]; then
        log_error "❌ Package file not found: $package_file"
        return 1
    fi
    
    log_info "📦 Validating package integrity: $(basename "$package_file")"
    
    # Check if it's a .deb package
    if [[ "$package_file" == *.deb ]]; then
        # Validate .deb package structure
        if dpkg --info "$package_file" >/dev/null 2>&1; then
            log_success "✅ Package structure is valid: $(basename "$package_file")"
        else
            log_error "❌ Invalid .deb package structure: $(basename "$package_file")"
            VALIDATION_FAILURES+=("package_validation:invalid_structure:$package_file")
            return 1
        fi
    fi
    
    # Validate checksum if provided
    if [ -n "$expected_checksum" ]; then
        validate_md5 "$package_file" "$expected_checksum" "package_validation"
        return $?
    else
        # Generate checksum for reference
        local checksum=$(calculate_checksum "$package_file" "md5")
        log_info "📝 Package checksum: $checksum"
        
        # Cache in packages directory
        local package_cache_file="$CHECKSUM_CACHE_DIR/packages/$(basename "$package_file").checksum"
        cache_checksum "$package_file" "$checksum" "md5"
        
        return 0
    fi
}

# Bulk validate files from checksum file
bulk_validate_from_file() {
    local checksum_file="$1"
    local base_directory="${2:-.}"
    
    if [ ! -f "$checksum_file" ]; then
        log_error "❌ Checksum file not found: $checksum_file"
        return 1
    fi
    
    log_info "🔍 Bulk validating files from: $(basename "$checksum_file")"
    
    local total_files=0
    local successful_validations=0
    local failed_validations=0
    
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Parse checksum and filename
        local checksum=$(echo "$line" | awk '{print $1}')
        local filename=$(echo "$line" | awk '{$1=""; print $0}' | sed 's/^ *//')
        
        if [ -n "$checksum" ] && [ -n "$filename" ]; then
            local full_path="$base_directory/$filename"
            
            ((total_files++))
            
            if validate_md5 "$full_path" "$checksum" "bulk_validation"; then
                ((successful_validations++))
            else
                ((failed_validations++))
            fi
        fi
        
    done < "$checksum_file"
    
    log_info "📊 Bulk validation completed:"
    log_info "   Total files: $total_files"
    log_info "   Successful: $successful_validations"
    log_info "   Failed: $failed_validations"
    
    if [ $failed_validations -eq 0 ]; then
        log_success "✅ All files passed bulk validation"
        return 0
    else
        log_error "❌ $failed_validations files failed bulk validation"
        return 1
    fi
}

# Clean up checksum validation resources
cleanup_checksum_validation() {
    log_info "🧹 Cleaning up checksum validation resources..."
    
    # Generate final validation report
    create_validation_report "final_validation"
    
    # Archive validation data
    if [ -d "$CHECKSUM_CACHE_DIR" ]; then
        local archive_file="/tmp/ailinux_checksum_archive_$(date +%Y%m%d_%H%M%S).tar.gz"
        
        tar -czf "$archive_file" -C "$(dirname "$CHECKSUM_CACHE_DIR")" "$(basename "$CHECKSUM_CACHE_DIR")" 2>/dev/null || true
        
        if [ -f "$archive_file" ]; then
            log_info "📦 Validation data archived: $archive_file"
        fi
        
        # Clean up cache directory
        rm -rf "$CHECKSUM_CACHE_DIR"
    fi
    
    log_success "Checksum validation cleanup completed"
}

# Export functions for use in other modules
export -f init_checksum_validation
export -f calculate_checksum
export -f validate_md5
export -f generate_checksums
export -f verify_download
export -f validate_package
export -f bulk_validate_from_file
export -f create_validation_report
export -f cleanup_checksum_validation
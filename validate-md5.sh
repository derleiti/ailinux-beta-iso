#!/bin/bash
#
# MD5 Validation Hook for AILinux Build Process
# Validates checksums of critical build artifacts
#
# Usage: ./validate-md5.sh [--create] [--verify] [file1 file2 ...]
#

set -u  # Only undefined variables cause issues, not command failures

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATION_LOG="${SCRIPT_DIR}/md5-validation.log"
MD5_DIR="${SCRIPT_DIR}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$VALIDATION_LOG"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "$VALIDATION_LOG"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "$VALIDATION_LOG"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$VALIDATION_LOG"
}

# Function to create MD5 checksum for a file
create_md5() {
    local file="$1"
    local md5_file="${file}.md5"
    
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi
    
    log_info "Creating MD5 checksum for: $file"
    if md5sum "$file" > "$md5_file"; then
        log_success "Created: $md5_file"
        return 0
    else
        log_error "Failed to create MD5 for: $file"
        return 1
    fi
}

# Function to verify MD5 checksum for a file
verify_md5() {
    local file="$1"
    local md5_file="${file}.md5"
    
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi
    
    if [[ ! -f "$md5_file" ]]; then
        log_warning "MD5 file not found: $md5_file"
        log_info "Creating new MD5 checksum..."
        create_md5 "$file"
        return $?
    fi
    
    log_info "Verifying MD5 checksum for: $file"
    if (cd "$(dirname "$file")" && md5sum -c "$(basename "$md5_file")" --quiet); then
        log_success "MD5 verification passed: $file"
        return 0
    else
        log_error "MD5 verification failed: $file"
        log_warning "Consider regenerating with: $0 --create $file"
        return 1
    fi
}

# Function to find and validate all relevant build artifacts
validate_all_artifacts() {
    local error_count=0
    local artifacts=(
        "build-optimized.sh"
        "ailinux-*.iso"
        "modules/*.sh"
        "casper/vmlinuz"
        "casper/initrd"
        "isolinux/isolinux.bin"
        "boot/grub/grub.cfg"
        "EFI/BOOT/bootx64.efi"
        "EFI/BOOT/grubx64.efi"
    )
    
    log_info "Starting comprehensive MD5 validation..."
    
    for pattern in "${artifacts[@]}"; do
        for file in $pattern; do
            if [[ -f "$file" ]]; then
                if ! verify_md5 "$file"; then
                    ((error_count++))
                fi
            fi
        done
    done
    
    if [[ $error_count -eq 0 ]]; then
        log_success "All MD5 validations passed!"
        return 0
    else
        log_error "MD5 validation failed for $error_count files"
        return 1
    fi
}

# Function to create checksums for all build artifacts
create_all_checksums() {
    local artifacts=(
        "build-optimized.sh"
        "modules/"*.sh
    )
    
    log_info "Creating MD5 checksums for all artifacts..."
    
    for file in "${artifacts[@]}"; do
        if [[ -f "$file" ]]; then
            create_md5 "$file"
        fi
    done
    
    # Find and create checksums for any ISO files
    for iso in ailinux-*.iso; do
        if [[ -f "$iso" ]]; then
            create_md5 "$iso"
        fi
    done
    
    log_success "Checksum creation completed"
}

# Function to show usage
show_help() {
    cat << EOF
MD5 Validation Hook for AILinux Build Process

Usage: $0 [OPTIONS] [FILES...]

OPTIONS:
    --create        Create MD5 checksums for specified files or all artifacts
    --verify        Verify MD5 checksums for specified files or all artifacts
    --all           Process all build artifacts automatically
    --help          Show this help message

EXAMPLES:
    $0 --verify build-optimized.sh
    $0 --create --all
    $0 --verify ailinux-26.01.iso
    $0 --all

FILES:
    If no files specified with --all, validates/creates for all build artifacts
    
EXIT CODES:
    0 = Success
    1 = Validation failed or file not found
    2 = Invalid arguments

This script integrates with the AILinux build process to ensure artifact integrity.
EOF
}

# Main execution logic
main() {
    local create_mode=false
    local verify_mode=false
    local all_mode=false
    local files=()
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --create)
                create_mode=true
                shift
                ;;
            --verify)
                verify_mode=true
                shift
                ;;
            --all)
                all_mode=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_help
                exit 2
                ;;
            *)
                files+=("$1")
                shift
                ;;
        esac
    done
    
    # Initialize log
    echo "MD5 Validation Hook - $(date)" > "$VALIDATION_LOG"
    log_info "Starting MD5 validation process..."
    
    # Default to verify mode if no mode specified
    if [[ "$create_mode" == false && "$verify_mode" == false ]]; then
        verify_mode=true
    fi
    
    # Process files or all artifacts
    if [[ "$all_mode" == true || ${#files[@]} -eq 0 ]]; then
        if [[ "$create_mode" == true ]]; then
            create_all_checksums
        else
            validate_all_artifacts
        fi
    else
        local error_count=0
        for file in "${files[@]}"; do
            if [[ "$create_mode" == true ]]; then
                if ! create_md5 "$file"; then
                    ((error_count++))
                fi
            else
                if ! verify_md5 "$file"; then
                    ((error_count++))
                fi
            fi
        done
        
        if [[ $error_count -gt 0 ]]; then
            log_error "Operation failed for $error_count files"
            exit 1
        fi
    fi
    
    log_success "MD5 validation hook completed successfully"
}

# Run main function with all arguments
main "$@"
#!/bin/bash
#
# AILinux MD5 Validation Script v1.0
# Comprehensive checksum validation for ISO builds
# Part of the AILinux ISO Build System
#

set -u  # Exit on undefined variables
set +e  # Don't exit on command failures - handle gracefully

# Configuration
SCRIPT_VERSION="1.0"
SCRIPT_NAME="validate-md5"
VALIDATION_LOG="${AILINUX_BUILD_LOGS_DIR:-/tmp}/md5_validation_$(date +%Y%m%d_%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_validation() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$VALIDATION_LOG")" 2>/dev/null
    
    # Write to log file
    echo "[$timestamp] [$level] [MD5-VALIDATOR] $message" >> "$VALIDATION_LOG" 2>/dev/null
    
    # Console output with colors
    case "$level" in
        "ERROR")
            echo -e "${RED}❌ [ERROR]${NC} $message" >&2
            ;;
        "SUCCESS")
            echo -e "${GREEN}✅ [SUCCESS]${NC} $message"
            ;;
        "WARN")
            echo -e "${YELLOW}⚠️  [WARN]${NC} $message"
            ;;
        "INFO")
            echo -e "${BLUE}ℹ️  [INFO]${NC} $message"
            ;;
        *)
            echo "[$level] $message"
            ;;
    esac
}

# ============================================================================
# MD5 GENERATION FUNCTIONS
# ============================================================================

# Generate MD5 checksum for a file
generate_md5() {
    local file_path="$1"
    local output_file="${2:-${file_path}.md5}"
    
    if [[ ! -f "$file_path" ]]; then
        log_validation "ERROR" "Cannot generate MD5 - file does not exist: $file_path"
        return 1
    fi
    
    log_validation "INFO" "Generating MD5 checksum for: $file_path"
    
    # Generate MD5 checksum
    if command -v md5sum >/dev/null 2>&1; then
        # Linux systems
        md5sum "$file_path" > "$output_file" 2>/dev/null
    elif command -v md5 >/dev/null 2>&1; then
        # macOS systems
        md5 -r "$file_path" > "$output_file" 2>/dev/null
    else
        log_validation "ERROR" "No MD5 utility found (tried md5sum, md5)"
        return 1
    fi
    
    if [[ $? -eq 0 ]] && [[ -f "$output_file" ]]; then
        log_validation "SUCCESS" "MD5 checksum generated: $output_file"
        return 0
    else
        log_validation "ERROR" "Failed to generate MD5 checksum for: $file_path"
        return 1
    fi
}

# Generate MD5 checksums for all files in a directory
generate_directory_md5() {
    local directory="$1"
    local recursive="${2:-false}"
    local pattern="${3:-*}"
    
    if [[ ! -d "$directory" ]]; then
        log_validation "ERROR" "Directory does not exist: $directory"
        return 1
    fi
    
    log_validation "INFO" "Generating MD5 checksums for directory: $directory"
    
    local file_count=0
    local success_count=0
    local fail_count=0
    
    # Find files based on recursive flag
    local find_cmd="find '$directory'"
    if [[ "$recursive" != "true" ]]; then
        find_cmd="$find_cmd -maxdepth 1"
    fi
    find_cmd="$find_cmd -type f -name '$pattern'"
    
    while IFS= read -r -d '' file; do
        ((file_count++))
        
        # Skip .md5 files themselves
        if [[ "$file" == *.md5 ]]; then
            continue
        fi
        
        if generate_md5 "$file"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
        
    done < <(eval "$find_cmd -print0" 2>/dev/null)
    
    log_validation "INFO" "MD5 generation complete - Total: $file_count, Success: $success_count, Failed: $fail_count"
    
    if [[ $fail_count -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# MD5 VALIDATION FUNCTIONS
# ============================================================================

# Validate MD5 checksum for a single file
validate_md5() {
    local file_path="$1"
    local md5_file="${2:-${file_path}.md5}"
    
    if [[ ! -f "$file_path" ]]; then
        log_validation "ERROR" "Cannot validate - file does not exist: $file_path"
        return 1
    fi
    
    if [[ ! -f "$md5_file" ]]; then
        log_validation "ERROR" "Cannot validate - MD5 file does not exist: $md5_file"
        return 1
    fi
    
    log_validation "INFO" "Validating MD5 checksum for: $file_path"
    
    # Read expected checksum from MD5 file
    local expected_md5
    if command -v md5sum >/dev/null 2>&1; then
        # Linux format: checksum filename
        expected_md5=$(cut -d' ' -f1 "$md5_file" 2>/dev/null)
    elif command -v md5 >/dev/null 2>&1; then
        # macOS format: MD5 (filename) = checksum
        expected_md5=$(cut -d'=' -f2 "$md5_file" 2>/dev/null | tr -d ' ')
    else
        log_validation "ERROR" "No MD5 utility found"
        return 1
    fi
    
    if [[ -z "$expected_md5" ]]; then
        log_validation "ERROR" "Could not read expected checksum from: $md5_file"
        return 1
    fi
    
    # Calculate actual checksum
    local actual_md5
    if command -v md5sum >/dev/null 2>&1; then
        actual_md5=$(md5sum "$file_path" 2>/dev/null | cut -d' ' -f1)
    elif command -v md5 >/dev/null 2>&1; then
        actual_md5=$(md5 -q "$file_path" 2>/dev/null)
    fi
    
    if [[ -z "$actual_md5" ]]; then
        log_validation "ERROR" "Could not calculate actual checksum for: $file_path"
        return 1
    fi
    
    # Compare checksums (case-insensitive)
    if [[ "${expected_md5,,}" == "${actual_md5,,}" ]]; then
        log_validation "SUCCESS" "MD5 checksum valid for: $file_path"
        return 0
    else
        log_validation "ERROR" "MD5 checksum mismatch for: $file_path"
        log_validation "ERROR" "Expected: $expected_md5"
        log_validation "ERROR" "Actual:   $actual_md5"
        return 1
    fi
}

# Validate all MD5 files in a directory
validate_directory_md5() {
    local directory="$1"
    local recursive="${2:-false}"
    
    if [[ ! -d "$directory" ]]; then
        log_validation "ERROR" "Directory does not exist: $directory"
        return 1
    fi
    
    log_validation "INFO" "Validating MD5 checksums in directory: $directory"
    
    local file_count=0
    local success_count=0
    local fail_count=0
    
    # Find .md5 files
    local find_cmd="find '$directory'"
    if [[ "$recursive" != "true" ]]; then
        find_cmd="$find_cmd -maxdepth 1"
    fi
    find_cmd="$find_cmd -type f -name '*.md5'"
    
    while IFS= read -r -d '' md5_file; do
        ((file_count++))
        
        # Determine the original file path
        local original_file="${md5_file%.md5}"
        
        if validate_md5 "$original_file" "$md5_file"; then
            ((success_count++))
        else
            ((fail_count++))
        fi
        
    done < <(eval "$find_cmd -print0" 2>/dev/null)
    
    if [[ $file_count -eq 0 ]]; then
        log_validation "WARN" "No MD5 files found in directory: $directory"
        return 1
    fi
    
    log_validation "INFO" "MD5 validation complete - Total: $file_count, Success: $success_count, Failed: $fail_count"
    
    if [[ $fail_count -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# SPECIALIZED VALIDATION FUNCTIONS
# ============================================================================

# Validate ISO file integrity
validate_iso_integrity() {
    local iso_file="$1"
    
    if [[ ! -f "$iso_file" ]]; then
        log_validation "ERROR" "ISO file does not exist: $iso_file"
        return 1
    fi
    
    log_validation "INFO" "Performing comprehensive ISO integrity check: $iso_file"
    
    # Check file size
    local file_size=$(stat -f%z "$iso_file" 2>/dev/null || stat -c%s "$iso_file" 2>/dev/null)
    if [[ -n "$file_size" ]] && [[ $file_size -gt 0 ]]; then
        log_validation "SUCCESS" "ISO file size: $(numfmt --to=iec-i --suffix=B $file_size)"
    else
        log_validation "ERROR" "Could not determine ISO file size or file is empty"
        return 1
    fi
    
    # Validate MD5 checksum if available
    if [[ -f "${iso_file}.md5" ]]; then
        if validate_md5 "$iso_file"; then
            log_validation "SUCCESS" "ISO MD5 checksum validation passed"
        else
            log_validation "ERROR" "ISO MD5 checksum validation failed"
            return 1
        fi
    else
        log_validation "WARN" "No MD5 file found for ISO - generating one"
        generate_md5 "$iso_file"
    fi
    
    # Check if file is actually an ISO
    if command -v file >/dev/null 2>&1; then
        local file_type=$(file "$iso_file" 2>/dev/null)
        if echo "$file_type" | grep -qi "iso\|cd.*image\|dvd"; then
            log_validation "SUCCESS" "File type validation passed: $file_type"
        else
            log_validation "WARN" "File may not be a valid ISO: $file_type"
        fi
    fi
    
    log_validation "SUCCESS" "ISO integrity check completed successfully"
    return 0
}

# Validate build artifacts
validate_build_artifacts() {
    local build_dir="$1"
    
    if [[ ! -d "$build_dir" ]]; then
        log_validation "ERROR" "Build directory does not exist: $build_dir"
        return 1
    fi
    
    log_validation "INFO" "Validating build artifacts in: $build_dir"
    
    local validation_errors=0
    
    # Check for common build artifacts
    local artifacts=(
        "*.iso"
        "*.img"
        "*.tar.gz"
        "*.deb"
        "*.rpm"
    )
    
    for pattern in "${artifacts[@]}"; do
        local files=$(find "$build_dir" -name "$pattern" -type f 2>/dev/null)
        if [[ -n "$files" ]]; then
            log_validation "INFO" "Found artifacts matching pattern: $pattern"
            
            # Generate or validate MD5 for each artifact
            while IFS= read -r file; do
                if [[ -f "${file}.md5" ]]; then
                    if ! validate_md5 "$file"; then
                        ((validation_errors++))
                    fi
                else
                    log_validation "INFO" "Generating MD5 for artifact: $file"
                    generate_md5 "$file"
                fi
            done <<< "$files"
        fi
    done
    
    if [[ $validation_errors -eq 0 ]]; then
        log_validation "SUCCESS" "All build artifacts validated successfully"
        return 0
    else
        log_validation "ERROR" "Build artifact validation failed with $validation_errors errors"
        return 1
    fi
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Show usage information
show_usage() {
    cat << EOF
AILinux MD5 Validation Script v$SCRIPT_VERSION

Usage: $0 [COMMAND] [OPTIONS]

Commands:
  generate <file>              Generate MD5 checksum for a single file
  generate-dir <directory>     Generate MD5 checksums for all files in directory
  validate <file>              Validate MD5 checksum for a single file
  validate-dir <directory>     Validate all MD5 checksums in directory
  validate-iso <iso-file>      Comprehensive ISO integrity validation
  validate-build <build-dir>   Validate all build artifacts
  test                         Run self-test

Options:
  -r, --recursive             Process directories recursively
  -p, --pattern <pattern>     File pattern for directory operations (default: *)
  -h, --help                  Show this help message
  -v, --version               Show version information

Examples:
  $0 generate /path/to/file.iso
  $0 generate-dir /build/output --recursive
  $0 validate /path/to/file.iso
  $0 validate-iso /build/output/ailinux.iso
  $0 validate-build /build/output

Log file: $VALIDATION_LOG
EOF
}

# Show version information
show_version() {
    echo "AILinux MD5 Validation Script v$SCRIPT_VERSION"
    echo "Part of the AILinux ISO Build System"
    echo "Enhanced with session-safe validation capabilities"
}

# Run self-test
run_self_test() {
    log_validation "INFO" "Starting MD5 validation self-test"
    
    # Create temporary test files
    local test_dir=$(mktemp -d)
    local test_file="$test_dir/test_file.txt"
    local test_content="AILinux MD5 Validation Test Content - $(date)"
    
    echo "$test_content" > "$test_file"
    
    # Test MD5 generation
    if generate_md5 "$test_file"; then
        log_validation "SUCCESS" "MD5 generation test passed"
    else
        log_validation "ERROR" "MD5 generation test failed"
        rm -rf "$test_dir"
        return 1
    fi
    
    # Test MD5 validation
    if validate_md5 "$test_file"; then
        log_validation "SUCCESS" "MD5 validation test passed"
    else
        log_validation "ERROR" "MD5 validation test failed"
        rm -rf "$test_dir"
        return 1
    fi
    
    # Test directory operations
    echo "Another test file" > "$test_dir/test_file2.txt"
    if generate_directory_md5 "$test_dir"; then
        log_validation "SUCCESS" "Directory MD5 generation test passed"
    else
        log_validation "ERROR" "Directory MD5 generation test failed"
        rm -rf "$test_dir"
        return 1
    fi
    
    if validate_directory_md5 "$test_dir"; then
        log_validation "SUCCESS" "Directory MD5 validation test passed"
    else
        log_validation "ERROR" "Directory MD5 validation test failed"
        rm -rf "$test_dir"
        return 1
    fi
    
    # Cleanup
    rm -rf "$test_dir"
    
    log_validation "SUCCESS" "All MD5 validation tests passed successfully"
    return 0
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    local command="$1"
    shift
    
    # Parse options
    local recursive=false
    local pattern="*"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -r|--recursive)
                recursive=true
                shift
                ;;
            -p|--pattern)
                pattern="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            *)
                break
                ;;
        esac
    done
    
    # Execute command
    case "$command" in
        generate)
            if [[ $# -lt 1 ]]; then
                log_validation "ERROR" "Missing file path for generate command"
                show_usage
                exit 1
            fi
            generate_md5 "$1" "${2:-}"
            ;;
        generate-dir)
            if [[ $# -lt 1 ]]; then
                log_validation "ERROR" "Missing directory path for generate-dir command"
                show_usage
                exit 1
            fi
            generate_directory_md5 "$1" "$recursive" "$pattern"
            ;;
        validate)
            if [[ $# -lt 1 ]]; then
                log_validation "ERROR" "Missing file path for validate command"
                show_usage
                exit 1
            fi
            validate_md5 "$1" "${2:-}"
            ;;
        validate-dir)
            if [[ $# -lt 1 ]]; then
                log_validation "ERROR" "Missing directory path for validate-dir command"
                show_usage
                exit 1
            fi
            validate_directory_md5 "$1" "$recursive"
            ;;
        validate-iso)
            if [[ $# -lt 1 ]]; then
                log_validation "ERROR" "Missing ISO file path for validate-iso command"
                show_usage
                exit 1
            fi
            validate_iso_integrity "$1"
            ;;
        validate-build)
            if [[ $# -lt 1 ]]; then
                log_validation "ERROR" "Missing build directory path for validate-build command"
                show_usage
                exit 1
            fi
            validate_build_artifacts "$1"
            ;;
        test)
            run_self_test
            ;;
        *)
            log_validation "ERROR" "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Auto-execute if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        show_usage
        exit 1
    fi
    
    main "$@"
    exit $?
fi

log_validation "SUCCESS" "MD5 validation module loaded successfully (v$SCRIPT_VERSION)"
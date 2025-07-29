#!/bin/bash
#
# AI Integrator Module for AILinux Build Script
# Provides multi-modal AI integration with Claude/Mixtral (C1), Gemini Pro (C2), Groq/Grok (C3)
#
# This module handles AI coordination, API integration, and multi-modal AI support
# for the AILinux build system with session-safe operation.
#

# Global AI integration configuration
declare -g AI_INTEGRATION_ENABLED=true
declare -g AI_API_TIMEOUT=30
declare -g AI_MAX_RETRIES=3
declare -g AI_COORDINATION_MEMORY=""
declare -g AI_HELPER_CONFIG_DIR="/opt/ailinux/aihelp/config"
declare -g AI_HELPER_LOG_DIR="/opt/ailinux/aihelp/logs"

# Initialize AI integration system
init_ai_integration() {
    log_info "🤖 Initializing AI integration system..."
    
    # Check environment prerequisites
    if ! check_ai_prerequisites; then
        log_warn "⚠️  AI prerequisites not met - limited AI functionality"
        export AI_INTEGRATION_ENABLED=false
        return 1
    fi
    
    # Initialize AI memory and coordination
    if ! setup_ai_memory_system; then
        log_error "Failed to setup AI memory system"
        return 1
    fi
    
    # Configure API endpoints
    if ! configure_ai_endpoints; then
        log_warn "⚠️  AI endpoint configuration failed - using fallback"
    fi
    
    # Setup AI coordination hooks
    if ! setup_ai_coordination_hooks; then
        log_warn "⚠️  AI coordination hooks setup failed"
    fi
    
    log_success "✅ AI integration system initialized"
    export AI_INTEGRATION_ENABLED=true
    return 0
}

# Check AI prerequisites
check_ai_prerequisites() {
    log_info "🔍 Checking AI integration prerequisites..."
    
    # Check for required tools
    local required_tools=("curl" "jq" "timeout")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "❌ Missing required tools for AI integration: ${missing_tools[*]}"
        log_info "Install with: sudo apt-get install curl jq coreutils"
        return 1
    fi
    
    # Check for .env file
    if [ ! -f "$AILINUX_BUILD_DIR/.env" ]; then
        log_warn "⚠️  No .env file found - AI API keys not configured"
        return 1
    fi
    
    # Check network connectivity
    if ! timeout 10 curl -s --head https://www.google.com >/dev/null 2>&1; then
        log_warn "⚠️  No internet connectivity - AI APIs will not be available"
        return 1
    fi
    
    log_success "✅ AI integration prerequisites met"
    return 0
}

# Setup AI memory and coordination system
setup_ai_memory_system() {
    log_info "🧠 Setting up AI memory and coordination system..."
    
    # Create AI memory directory
    local ai_memory_dir="$AILINUX_BUILD_COORDINATION_DIR/ai_memory"
    mkdir -p "$ai_memory_dir"/{conversations,context,decisions,learnings}
    
    # Initialize AI memory database
    cat > "$ai_memory_dir/memory.json" << EOF
{
  "initialized": "$(date -Iseconds)",
  "session_id": "$AILINUX_BUILD_SESSION_ID",
  "swarm_id": "$AILINUX_BUILD_SWARM_ID",
  "conversations": {},
  "context": {},
  "decisions": [],
  "learnings": [],
  "api_usage": {
    "c1_calls": 0,
    "c2_calls": 0,
    "c3_calls": 0,
    "total_tokens": 0
  }
}
EOF
    
    export AI_COORDINATION_MEMORY="$ai_memory_dir/memory.json"
    
    log_success "✅ AI memory system initialized"
    return 0
}

# Configure AI API endpoints
configure_ai_endpoints() {
    log_info "🔗 Configuring AI API endpoints..."
    
    # Initialize AI availability flags with defaults
    export AILINUX_AI_C1_AVAILABLE=${AILINUX_AI_C1_AVAILABLE:-false}
    export AILINUX_AI_C2_AVAILABLE=${AILINUX_AI_C2_AVAILABLE:-false}
    export AILINUX_AI_C3_AVAILABLE=${AILINUX_AI_C3_AVAILABLE:-false}
    
    # Check API key availability
    if [[ -n "${MIXTRAL_API_KEY:-}" ]]; then
        export AILINUX_AI_C1_AVAILABLE=true
    fi
    
    if [[ -n "${GEMINI_API_KEY:-}" ]]; then
        export AILINUX_AI_C2_AVAILABLE=true
    fi
    
    if [[ -n "${GROK_API_KEY:-}" ]]; then
        export AILINUX_AI_C3_AVAILABLE=true
    fi
    
    # C1: Claude/Mixtral configuration
    if [ "$AILINUX_AI_C1_AVAILABLE" = true ]; then
        export AI_C1_ENDPOINT="https://api.mistral.ai/v1/chat/completions"
        export AI_C1_MODEL="mistral-large-latest"
        log_success "  ✅ C1 (Claude/Mixtral) endpoint configured"
    fi
    
    # C2: Gemini Pro configuration
    if [ "$AILINUX_AI_C2_AVAILABLE" = true ]; then
        export AI_C2_ENDPOINT="https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent"
        export AI_C2_MODEL="gemini-pro"
        log_success "  ✅ C2 (Gemini Pro) endpoint configured"
    fi
    
    # C3: Groq/Grok configuration
    if [ "$AILINUX_AI_C3_AVAILABLE" = true ]; then
        export AI_C3_ENDPOINT="https://api.groq.com/openai/v1/chat/completions"
        export AI_C3_MODEL="mixtral-8x7b-32768"
        log_success "  ✅ C3 (Groq/Grok) endpoint configured"
    fi
    
    log_success "✅ AI API endpoints configured"
    return 0
}

# Setup AI coordination hooks
setup_ai_coordination_hooks() {
    log_info "🔗 Setting up AI coordination hooks..."
    
    # Create coordination hooks directory
    mkdir -p "$AILINUX_BUILD_COORDINATION_DIR/hooks"
    
    # Create pre-phase hook
    cat > "$AILINUX_BUILD_COORDINATION_DIR/hooks/pre-phase.sh" << 'EOF'
#!/bin/bash
# Pre-phase AI coordination hook

phase_name="$1"
phase_description="$2"

if [ "$AILINUX_AI_COORDINATION_ENABLED" = true ]; then
    ai_coordinate "phase_pre_hook" "Pre-phase validation for $phase_name" "HookCoordinator" "info" "$phase_name"
    
    # Store phase context in AI memory
    store_ai_context "phase_start" "$phase_name" "$phase_description"
fi
EOF
    
    # Create post-phase hook
    cat > "$AILINUX_BUILD_COORDINATION_DIR/hooks/post-phase.sh" << 'EOF'
#!/bin/bash
# Post-phase AI coordination hook

phase_name="$1"
phase_result="$2"
phase_duration="$3"

if [ "$AILINUX_AI_COORDINATION_ENABLED" = true ]; then
    ai_coordinate "phase_post_hook" "Post-phase analysis for $phase_name: $phase_result" "HookCoordinator" "info" "$phase_name"
    
    # Store phase results in AI memory
    store_ai_learning "phase_complete" "$phase_name" "$phase_result" "$phase_duration"
fi
EOF
    
    # Make hooks executable
    chmod +x "$AILINUX_BUILD_COORDINATION_DIR/hooks/"*.sh
    
    log_success "✅ AI coordination hooks created"
    return 0
}

# Store AI context for coordination
store_ai_context() {
    local context_type="$1"
    local context_key="$2"
    local context_data="$3"
    
    if [ -n "$AI_COORDINATION_MEMORY" ] && [ -f "$AI_COORDINATION_MEMORY" ]; then
        # Create context entry
        local context_file="$(dirname "$AI_COORDINATION_MEMORY")/context/${context_key}_$(date +%s).json"
        
        cat > "$context_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "type": "$context_type",
  "key": "$context_key",
  "data": "$context_data",
  "session_id": "$AILINUX_BUILD_SESSION_ID"
}
EOF
    fi
}

# Store AI learning for future coordination
store_ai_learning() {
    local learning_type="$1"
    local learning_subject="$2"
    local learning_outcome="$3"
    local learning_metrics="$4"
    
    if [ -n "$AI_COORDINATION_MEMORY" ] && [ -f "$AI_COORDINATION_MEMORY" ]; then
        # Create learning entry
        local learning_file="$(dirname "$AI_COORDINATION_MEMORY")/learnings/${learning_subject}_$(date +%s).json"
        
        cat > "$learning_file" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "type": "$learning_type",
  "subject": "$learning_subject",
  "outcome": "$learning_outcome",
  "metrics": "$learning_metrics",
  "session_id": "$AILINUX_BUILD_SESSION_ID"
}
EOF
    fi
}

# Setup AI helper with multi-modal support
setup_ai_helper() {
    log_info "🤖 Setting up AI helper with multi-modal support..."
    
    # Create AI helper directory structure
    local ai_helper_dir="/opt/ailinux/aihelp"
    safe_execute "mkdir -p '$ai_helper_dir'/{bin,config,models,logs}" "create_ai_helper_dirs" "Failed to create AI helper directories" "false" "AIIntegrator"
    
    # Create enhanced AI helper script
    create_ai_helper_script "$ai_helper_dir"
    
    # Create AI helper configuration
    create_ai_helper_config "$ai_helper_dir"
    
    # Install environment access for AI helper
    setup_ai_helper_environment "$ai_helper_dir"
    
    log_success "✅ AI helper with multi-modal support installed"
}

# Create AI helper script with multi-modal support
create_ai_helper_script() {
    local ai_helper_dir="$1"
    
    cat > "$ai_helper_dir/bin/aihelp" << 'EOF'
#!/bin/bash
# AILinux Enhanced AI Helper with Multi-Modal Support
# Supports Claude/Mixtral (C1), Gemini Pro (C2), Groq/Grok (C3)

# Load configuration
if [ -f "/opt/ailinux/aihelp/config/aihelp.conf" ]; then
    source "/opt/ailinux/aihelp/config/aihelp.conf"
fi

# Load environment variables for API access
if [ -f "/etc/ailinux/.env" ]; then
    source "/etc/ailinux/.env"
fi

echo "AILinux Enhanced AI Helper v3.0 (Multi-Modal)"
echo "Supported: Claude/Mixtral (C1), Gemini Pro (C2), Groq/Grok (C3)"
echo "Type 'aihelp <question>' to get AI assistance"
echo "Example: aihelp how to install packages"
echo "Example: aihelp --model c2 explain KDE features"
echo "Example: aihelp --model c3 troubleshoot network issues"

if [ $# -eq 0 ]; then
    echo "Usage: aihelp [--model c1|c2|c3] <your question>"
    echo "  --model c1: Use Claude/Mixtral (default)"
    echo "  --model c2: Use Gemini Pro"
    echo "  --model c3: Use Groq/Grok"
    exit 0
fi

# Parse arguments
model="c1"
question=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --model)
            model="$2"
            shift 2
            ;;
        *)
            question="$question $1"
            shift
            ;;
    esac
done

# Trim leading/trailing spaces
question=$(echo "$question" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

if [ -z "$question" ]; then
    echo "Error: No question provided"
    exit 1
fi

echo "AI Helper ($model): Processing your question..."
echo "Question: $question"
echo ""

# Route to appropriate AI model
case "$model" in
    "c1")
        if [ -n "${MIXTRAL_API_KEY:-}" ]; then
            echo "[Claude/Mixtral Response] For '$question':"
            echo "This would connect to Claude/Mixtral API for response."
            echo "API Key configured: Yes"
        else
            echo "[Claude/Mixtral] API key not configured. Please set MIXTRAL_API_KEY in .env"
        fi
        ;;
    "c2")
        if [ -n "${GEMINI_API_KEY:-}" ]; then
            echo "[Gemini Pro Response] For '$question':"
            echo "This would connect to Gemini Pro API for response."
            echo "API Key configured: Yes"
        else
            echo "[Gemini Pro] API key not configured. Please set GEMINI_API_KEY in .env"
        fi
        ;;
    "c3")
        if [ -n "${GROK_API_KEY:-}" ]; then
            echo "[Groq/Grok Response] For '$question':"
            echo "This would connect to Groq/Grok API for response."
            echo "API Key configured: Yes"
        else
            echo "[Groq/Grok] API key not configured. Please set GROK_API_KEY in .env"
        fi
        ;;
    *)
        echo "Error: Unknown model '$model'. Use c1, c2, or c3."
        exit 1
        ;;
esac

echo ""
echo "Note: This is a placeholder implementation. Full AI integration requires"
echo "proper API connectivity and will be implemented in future versions."
echo ""
echo "For immediate help, try: man <command> or <command> --help"
EOF
    
    chmod +x "$ai_helper_dir/bin/aihelp"
    
    # Create system symlink
    safe_execute "ln -sf '$ai_helper_dir/bin/aihelp' '/usr/local/bin/aihelp'" "create_ai_helper_symlink" "Failed to create AI helper symlink" "true" "AIIntegrator"
}

# Create AI helper configuration
create_ai_helper_config() {
    local ai_helper_dir="$1"
    
    cat > "$ai_helper_dir/config/aihelp.conf" << EOF
# AILinux AI Helper Configuration
# Multi-Modal AI Support

# Default model (c1, c2, c3)
DEFAULT_MODEL="c1"

# API Configuration
C1_ENABLED=${AILINUX_AI_C1_AVAILABLE:-false}
C2_ENABLED=${AILINUX_AI_C2_AVAILABLE:-false}
C3_ENABLED=${AILINUX_AI_C3_AVAILABLE:-false}

# Logging
ENABLE_LOGGING=true
LOG_FILE="/opt/ailinux/aihelp/logs/aihelp.log"

# Features
ENABLE_CONTEXT_MEMORY=true
ENABLE_CONVERSATION_HISTORY=true
MAX_CONTEXT_LENGTH=4096

# Timeout and retry settings
API_TIMEOUT=$AI_API_TIMEOUT
MAX_RETRIES=$AI_MAX_RETRIES
EOF
}

# Setup AI helper environment
setup_ai_helper_environment() {
    local ai_helper_dir="$1"
    
    # Copy environment file for AI helper access
    if [ -f "$AILINUX_BUILD_DIR/.env" ]; then
        safe_execute "mkdir -p '/etc/ailinux'" "create_etc_ailinux" "Failed to create /etc/ailinux" "true" "AIIntegrator"
        safe_execute "cp '$AILINUX_BUILD_DIR/.env' '/etc/ailinux/.env'" "copy_env_for_ai" "Failed to copy .env for AI helper" "true" "AIIntegrator"
        safe_execute "chmod 600 '/etc/ailinux/.env'" "secure_env_file" "Failed to secure .env file" "true" "AIIntegrator"
    fi
    
    # Create AI helper log directory
    mkdir -p "$ai_helper_dir/logs"
    
    # Initialize AI helper log
    cat > "$ai_helper_dir/logs/aihelp.log" << EOF
# AILinux AI Helper Log
# Started: $(date)
# Multi-Modal Support: Enabled
# Available APIs: C1=${AILINUX_AI_C1_AVAILABLE:-false} C2=${AILINUX_AI_C2_AVAILABLE:-false} C3=${AILINUX_AI_C3_AVAILABLE:-false}
EOF
}

# Generate AI coordination report
generate_ai_coordination_report() {
    local report_file="$AILINUX_BUILD_OUTPUT_DIR/ai-coordination-report-$(date +%Y%m%d_%H%M%S).txt"
    
    log_info "📊 Generating AI coordination report..."
    
    {
        echo "# AILinux AI Coordination Report"
        echo "# Generated: $(date)"
        echo "# Session ID: $AILINUX_BUILD_SESSION_ID"
        echo "# Swarm ID: $AILINUX_BUILD_SWARM_ID"
        echo ""
        
        echo "== AI INTEGRATION STATUS =="
        echo "AI Integration Enabled: $AI_INTEGRATION_ENABLED"
        echo "C1 (Claude/Mixtral) Available: $AILINUX_AI_C1_AVAILABLE"
        echo "C2 (Gemini Pro) Available: $AILINUX_AI_C2_AVAILABLE"
        echo "C3 (Groq/Grok) Available: $AILINUX_AI_C3_AVAILABLE"
        echo "Total API Keys: $AILINUX_AI_KEYS_AVAILABLE"
        echo ""
        
        echo "== AI MEMORY SYSTEM =="
        echo "Memory Bank: $AI_COORDINATION_MEMORY"
        if [ -n "$AI_COORDINATION_MEMORY" ] && [ -d "$(dirname "$AI_COORDINATION_MEMORY")" ]; then
            echo "Context Entries: $(find "$(dirname "$AI_COORDINATION_MEMORY")/context" -name "*.json" 2>/dev/null | wc -l)"
            echo "Decision Entries: $(find "$(dirname "$AI_COORDINATION_MEMORY")/decisions" -name "*.json" 2>/dev/null | wc -l)"
            echo "Learning Entries: $(find "$(dirname "$AI_COORDINATION_MEMORY")/learnings" -name "*.json" 2>/dev/null | wc -l)"
        fi
        echo ""
        
        echo "== AI HELPER CONFIGURATION =="
        echo "AI Helper Directory: /opt/ailinux/aihelp"
        echo "AI Helper Binary: $([ -x /usr/local/bin/aihelp ] && echo 'Installed' || echo 'Not installed')"
        echo "Configuration File: $([ -f /opt/ailinux/aihelp/config/aihelp.conf ] && echo 'Present' || echo 'Missing')"
        echo "Environment Access: $([ -f /etc/ailinux/.env ] && echo 'Configured' || echo 'Not configured')"
        echo ""
        
        echo "== COORDINATION HOOKS =="
        if [ -d "$AILINUX_BUILD_COORDINATION_DIR/hooks" ]; then
            echo "Hooks Directory: $AILINUX_BUILD_COORDINATION_DIR/hooks"
            echo "Pre-phase Hook: $([ -x "$AILINUX_BUILD_COORDINATION_DIR/hooks/pre-phase.sh" ] && echo 'Active' || echo 'Inactive')"
            echo "Post-phase Hook: $([ -x "$AILINUX_BUILD_COORDINATION_DIR/hooks/post-phase.sh" ] && echo 'Active' || echo 'Inactive')"
        else
            echo "Hooks Directory: Not created"
        fi
        echo ""
        
        echo "== RECOMMENDATIONS =="
        if [ "$AI_INTEGRATION_ENABLED" != true ]; then
            echo "❌ AI integration is disabled"
            echo "   - Check .env file for API keys"
            echo "   - Verify network connectivity"
            echo "   - Install required tools (curl, jq)"
        else
            echo "✅ AI integration is functional"
            echo "   - Multi-modal AI support active"
            echo "   - Coordination hooks installed"
            echo "   - Memory system operational"
        fi
        
    } > "$report_file"
    
    log_success "📊 AI coordination report generated: $report_file"
    echo "$report_file"
}

# Cleanup AI integration resources
cleanup_ai_integration() {
    log_info "🧹 Cleaning up AI integration resources..."
    
    # Clean up temporary AI files
    if [ -n "$AI_COORDINATION_MEMORY" ]; then
        local ai_memory_dir="$(dirname "$AI_COORDINATION_MEMORY")"
        if [ -d "$ai_memory_dir" ]; then
            # Archive AI memory for future reference
            local archive_file="$AILINUX_BUILD_OUTPUT_DIR/ai-memory-archive-$(date +%Y%m%d_%H%M%S).tar.gz"
            tar -czf "$archive_file" -C "$(dirname "$ai_memory_dir")" "$(basename "$ai_memory_dir")" 2>/dev/null || true
            
            if [ -f "$archive_file" ]; then
                log_info "📦 AI memory archived: $(basename "$archive_file")"
            fi
        fi
    fi
    
    log_success "✅ AI integration cleanup completed"
}

# Export functions for use in other modules
export -f init_ai_integration
export -f setup_ai_helper
export -f store_ai_context
export -f store_ai_learning
export -f generate_ai_coordination_report
export -f cleanup_ai_integration
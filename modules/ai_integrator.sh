#!/bin/bash
#
# AI Integration Module for AILinux Build Script
# Provides AI helper integration and configuration
#
# This module handles the installation and configuration of AILinux's
# AI helper system located at /opt/ailinux/aihelp
#

# Global AI integration configuration
declare -g AI_HELPER_VERSION="1.0"
declare -g AI_HELPER_PATH="/opt/ailinux/aihelp"
declare -g AI_CONFIG_DIR="/etc/ailinux"
declare -g AI_DATA_DIR="/var/lib/ailinux"
declare -g AI_INSTALLED_COMPONENTS=()
declare -g AI_CONFIG_FILES=()

# Initialize AI integration system
init_ai_integration() {
    log_info "🤖 Initializing AI helper integration system..."
    
    # Set up AI directories
    setup_ai_directories
    
    # Configure AI services
    configure_ai_services
    
    # Set up AI helper paths
    setup_ai_paths
    
    # Configure AI integration
    configure_ai_integration
    
    log_success "AI helper integration system initialized"
}

# Set up AI directories and structure
setup_ai_directories() {
    local chroot_dir="${AILINUX_BUILD_CHROOT_DIR:-/tmp/ailinux_chroot}"
    
    log_info "📁 Setting up AI helper directories..."
    
    # Essential AI directories
    local ai_dirs=(
        "$chroot_dir$AI_HELPER_PATH"
        "$chroot_dir$AI_HELPER_PATH/bin"
        "$chroot_dir$AI_HELPER_PATH/lib"
        "$chroot_dir$AI_HELPER_PATH/share"
        "$chroot_dir$AI_HELPER_PATH/config"
        "$chroot_dir$AI_CONFIG_DIR"
        "$chroot_dir$AI_DATA_DIR"
        "$chroot_dir/usr/local/bin"
        "$chroot_dir/usr/share/applications"
        "$chroot_dir/etc/systemd/system"
    )
    
    for dir in "${ai_dirs[@]}"; do
        if ! safe_execute "mkdir -p '$dir'" "create_ai_dir" "Failed to create AI directory: $dir"; then
            return 1
        fi
    done
    
    log_success "✅ AI helper directories created"
}

# Install AI helper components
install_ai_helper() {
    local chroot_dir="${1:-$AILINUX_BUILD_CHROOT_DIR}"
    
    if [ ! -d "$chroot_dir" ]; then
        log_error "❌ Chroot directory not found: $chroot_dir"
        return 1
    fi
    
    log_info "🤖 Installing AI helper components..."
    
    # Install required Python packages for AI functionality
    local python_packages="python3 python3-pip python3-venv python3-setuptools"
    local ai_dependencies="curl wget jq sqlite3 git"
    
    local install_cmd="DEBIAN_FRONTEND=noninteractive apt-get install -y $python_packages $ai_dependencies"
    
    if ! enter_chroot_safely "$chroot_dir" "$install_cmd"; then
        log_error "❌ Failed to install AI helper dependencies"
        return 1
    fi
    
    log_success "✅ AI helper dependencies installed"
    
    # Install AI helper core components
    create_ai_helper_core "$chroot_dir"
    
    # Install AI helper CLI
    create_ai_helper_cli "$chroot_dir"
    
    # Install AI service daemon
    create_ai_service_daemon "$chroot_dir"
    
    # Install AI desktop integration
    create_ai_desktop_integration "$chroot_dir"
    
    log_success "🤖 AI helper components installed successfully"
}

# Create AI helper core system
create_ai_helper_core() {
    local chroot_dir="$1"
    
    log_info "🧠 Creating AI helper core system..."
    
    # Create main AI helper script
    local aihelp_main="$chroot_dir$AI_HELPER_PATH/bin/aihelp"
    
    cat > "$aihelp_main" << 'EOF'
#!/usr/bin/env python3
"""
AILinux AI Helper - Main Entry Point
Provides intelligent assistance for system tasks and user queries
"""

import sys
import os
import json
import argparse
import subprocess
from pathlib import Path

# Add AI helper lib to path
sys.path.insert(0, '/opt/ailinux/aihelp/lib')

class AIHelper:
    def __init__(self):
        self.config_dir = Path('/etc/ailinux')
        self.data_dir = Path('/var/lib/ailinux')
        self.cache_dir = Path('/tmp/ailinux')
        
        # Ensure directories exist
        self.config_dir.mkdir(parents=True, exist_ok=True)
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        
        self.load_config()
    
    def load_config(self):
        """Load AI helper configuration"""
        config_file = self.config_dir / 'aihelp.json'
        
        default_config = {
            'version': '1.0',
            'enabled': True,
            'log_level': 'INFO',
            'features': {
                'system_help': True,
                'command_suggestions': True,
                'troubleshooting': True,
                'package_assistance': True
            }
        }
        
        if config_file.exists():
            try:
                with open(config_file, 'r') as f:
                    self.config = json.load(f)
            except Exception as e:
                print(f"Warning: Could not load config: {e}")
                self.config = default_config
        else:
            self.config = default_config
            self.save_config()
    
    def save_config(self):
        """Save AI helper configuration"""
        config_file = self.config_dir / 'aihelp.json'
        try:
            with open(config_file, 'w') as f:
                json.dump(self.config, f, indent=2)
        except Exception as e:
            print(f"Warning: Could not save config: {e}")
    
    def help_command(self, query):
        """Provide help for system commands"""
        if not query:
            return "Please provide a command or query for help."
        
        # Simple command help mapping
        help_responses = {
            'ls': 'ls - List directory contents. Common options: -l (long format), -a (show hidden files)',
            'cd': 'cd - Change directory. Usage: cd <directory>',
            'pwd': 'pwd - Print working directory (shows current location)',
            'mkdir': 'mkdir - Create directories. Usage: mkdir <directory_name>',
            'rmdir': 'rmdir - Remove empty directories. Usage: rmdir <directory_name>',
            'rm': 'rm - Remove files and directories. Options: -r (recursive), -f (force)',
            'cp': 'cp - Copy files and directories. Usage: cp <source> <destination>',
            'mv': 'mv - Move/rename files and directories. Usage: mv <source> <destination>',
            'find': 'find - Search for files and directories. Usage: find <path> -name <pattern>',
            'grep': 'grep - Search text patterns in files. Usage: grep <pattern> <file>',
            'apt': 'apt - Package manager. Common commands: install, remove, update, upgrade, search',
            'systemctl': 'systemctl - Control systemd services. Commands: start, stop, restart, enable, disable, status',
            'sudo': 'sudo - Execute commands as another user (usually root). Usage: sudo <command>',
        }
        
        query_lower = query.lower().strip()
        
        if query_lower in help_responses:
            return help_responses[query_lower]
        
        # Check if it's a complex query
        if len(query.split()) > 1:
            return self.complex_help(query)
        
        # Try to find man page
        try:
            result = subprocess.run(['man', '-f', query], capture_output=True, text=True)
            if result.returncode == 0:
                return f"Manual page available for '{query}'. Run 'man {query}' for detailed information."
        except:
            pass
        
        return f"No specific help found for '{query}'. Try 'man {query}' or search online for more information."
    
    def complex_help(self, query):
        """Handle complex queries"""
        query_lower = query.lower()
        
        if 'install' in query_lower and 'package' in query_lower:
            return "To install packages: sudo apt update && sudo apt install <package_name>"
        elif 'remove' in query_lower and 'package' in query_lower:
            return "To remove packages: sudo apt remove <package_name> or sudo apt purge <package_name>"
        elif 'update' in query_lower and 'system' in query_lower:
            return "To update system: sudo apt update && sudo apt upgrade"
        elif 'disk' in query_lower and 'space' in query_lower:
            return "Check disk space with: df -h (human readable) or du -sh <directory> (directory size)"
        elif 'process' in query_lower:
            return "List processes: ps aux or top. Kill process: kill <PID> or killall <process_name>"
        elif 'network' in query_lower:
            return "Network info: ip addr show, ping <host>, wget/curl for downloads"
        elif 'permission' in query_lower:
            return "Change permissions: chmod <mode> <file>. Common modes: 755 (rwxr-xr-x), 644 (rw-r--r--)"
        
        return f"Complex query detected: '{query}'. Consider breaking it down or using specific commands."
    
    def suggest_command(self, description):
        """Suggest commands based on description"""
        description_lower = description.lower()
        
        suggestions = []
        
        if 'list' in description_lower and 'file' in description_lower:
            suggestions.append('ls -la')
        elif 'copy' in description_lower:
            suggestions.append('cp <source> <destination>')
        elif 'move' in description_lower:
            suggestions.append('mv <source> <destination>')
        elif 'delete' in description_lower or 'remove' in description_lower:
            suggestions.append('rm <filename> or rmdir <directory>')
        elif 'search' in description_lower:
            suggestions.append('find <path> -name "<pattern>" or grep "<pattern>" <file>')
        elif 'install' in description_lower:
            suggestions.append('sudo apt install <package_name>')
        elif 'update' in description_lower:
            suggestions.append('sudo apt update && sudo apt upgrade')
        elif 'restart' in description_lower or 'service' in description_lower:
            suggestions.append('sudo systemctl restart <service_name>')
        
        if suggestions:
            return "Suggested commands:\n" + "\n".join(f"  {cmd}" for cmd in suggestions)
        else:
            return "No specific command suggestions for that description."
    
    def troubleshoot(self, problem):
        """Provide troubleshooting assistance"""
        problem_lower = problem.lower()
        
        if 'slow' in problem_lower:
            return """System running slowly? Try:
1. Check disk space: df -h
2. Check memory usage: free -h
3. Check running processes: top or htop
4. Check system load: uptime
5. Clean package cache: sudo apt clean"""
        
        elif 'network' in problem_lower or 'internet' in problem_lower:
            return """Network issues? Try:
1. Check connection: ping google.com
2. Check network interfaces: ip addr show
3. Restart network: sudo systemctl restart NetworkManager
4. Check DNS: nslookup google.com
5. Check firewall: sudo ufw status"""
        
        elif 'boot' in problem_lower or 'startup' in problem_lower:
            return """Boot/startup issues? Try:
1. Check system logs: journalctl -b
2. Check failed services: systemctl --failed
3. Check disk errors: sudo fsck /dev/sdXY
4. Boot in recovery mode
5. Check GRUB configuration"""
        
        elif 'package' in problem_lower:
            return """Package issues? Try:
1. Update package lists: sudo apt update
2. Fix broken packages: sudo apt --fix-broken install
3. Clean package cache: sudo apt clean && sudo apt autoclean
4. Reconfigure packages: sudo dpkg --configure -a
5. Check package status: dpkg -l | grep <package>"""
        
        else:
            return f"For '{problem}', try checking system logs with 'journalctl' or search online for specific solutions."
    
    def run(self, args):
        """Main entry point"""
        parser = argparse.ArgumentParser(description='AILinux AI Helper')
        parser.add_argument('command', nargs='?', help='Command to execute')
        parser.add_argument('query', nargs='*', help='Query or parameters')
        parser.add_argument('--version', action='version', version=f'AI Helper {self.config["version"]}')
        
        parsed_args = parser.parse_args(args)
        
        if not parsed_args.command:
            print("AILinux AI Helper - Intelligent system assistance")
            print("\nAvailable commands:")
            print("  help <command>     - Get help for a command")
            print("  suggest <task>     - Get command suggestions")
            print("  troubleshoot <issue> - Get troubleshooting help")
            print("  status             - Show AI helper status")
            return 0
        
        query_text = ' '.join(parsed_args.query) if parsed_args.query else ''
        
        if parsed_args.command == 'help':
            result = self.help_command(query_text)
        elif parsed_args.command == 'suggest':
            result = self.suggest_command(query_text)
        elif parsed_args.command == 'troubleshoot':
            result = self.troubleshoot(query_text)
        elif parsed_args.command == 'status':
            result = f"AI Helper v{self.config['version']} - Status: {'Enabled' if self.config['enabled'] else 'Disabled'}"
        else:
            result = f"Unknown command: {parsed_args.command}"
        
        print(result)
        return 0

if __name__ == '__main__':
    helper = AIHelper()
    sys.exit(helper.run(sys.argv[1:]))
EOF
    
    # Make executable
    chmod +x "$aihelp_main"
    
    AI_INSTALLED_COMPONENTS+=("aihelp_core")
    log_success "✅ AI helper core created"
}

# Create AI helper CLI tools
create_ai_helper_cli() {
    local chroot_dir="$1"
    
    log_info "💻 Creating AI helper CLI tools..."
    
    # Create symlink for system-wide access
    local system_link="$chroot_dir/usr/local/bin/aihelp"
    ln -sf "$AI_HELPER_PATH/bin/aihelp" "$system_link"
    
    # Create convenient aliases
    local aliases_file="$chroot_dir/etc/profile.d/ailinux-aliases.sh"
    
    cat > "$aliases_file" << EOF
#!/bin/bash
# AILinux AI Helper Aliases

# AI Helper shortcuts
alias ai='aihelp'
alias aihelp-suggest='aihelp suggest'
alias aihelp-troubleshoot='aihelp troubleshoot'

# Helpful AI-powered commands
aihelp-quick() {
    if [ -z "\$1" ]; then
        echo "Usage: aihelp-quick <command|description>"
        return 1
    fi
    
    # Try help first, then suggest
    aihelp help "\$*" 2>/dev/null || aihelp suggest "\$*"
}

# AI-powered man page helper
man-ai() {
    if [ -z "\$1" ]; then
        echo "Usage: man-ai <command>"
        return 1
    fi
    
    echo "=== AI Helper Information ==="
    aihelp help "\$1"
    echo ""
    echo "=== Manual Page ==="
    man "\$1" 2>/dev/null || echo "No manual page available for \$1"
}
EOF
    
    AI_INSTALLED_COMPONENTS+=("aihelp_cli")
    log_success "✅ AI helper CLI tools created"
}

# Create AI service daemon
create_ai_service_daemon() {
    local chroot_dir="$1"
    
    log_info "🔧 Creating AI service daemon..."
    
    # Create AI service script
    local service_script="$chroot_dir$AI_HELPER_PATH/bin/aihelp-daemon"
    
    cat > "$service_script" << 'EOF'
#!/usr/bin/env python3
"""
AILinux AI Helper Daemon
Provides background AI services and system monitoring
"""

import time
import json
import logging
import signal
import sys
from pathlib import Path
from datetime import datetime

class AIHelperDaemon:
    def __init__(self):
        self.config_dir = Path('/etc/ailinux')
        self.data_dir = Path('/var/lib/ailinux')
        self.pid_file = Path('/var/run/aihelp-daemon.pid')
        self.log_file = Path('/var/log/aihelp-daemon.log')
        
        self.running = False
        self.setup_logging()
        
    def setup_logging(self):
        """Set up logging configuration"""
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(self.log_file),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
    
    def load_config(self):
        """Load daemon configuration"""
        config_file = self.config_dir / 'aihelp.json'
        try:
            with open(config_file, 'r') as f:
                return json.load(f)
        except Exception as e:
            self.logger.warning(f"Could not load config: {e}")
            return {'enabled': True, 'monitoring_interval': 300}
    
    def signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        self.logger.info(f"Received signal {signum}, shutting down...")
        self.running = False
    
    def write_pid(self):
        """Write PID file"""
        try:
            with open(self.pid_file, 'w') as f:
                f.write(str(os.getpid()))
        except Exception as e:
            self.logger.error(f"Could not write PID file: {e}")
    
    def remove_pid(self):
        """Remove PID file"""
        try:
            self.pid_file.unlink(missing_ok=True)
        except Exception as e:
            self.logger.error(f"Could not remove PID file: {e}")
    
    def monitor_system(self):
        """Monitor system health and provide insights"""
        try:
            # Basic system monitoring placeholder
            import subprocess
            
            # Check disk space
            result = subprocess.run(['df', '-h'], capture_output=True, text=True)
            if result.returncode == 0:
                # Log disk space info periodically
                self.logger.debug("System monitoring: disk space checked")
            
            # Check memory usage
            result = subprocess.run(['free', '-m'], capture_output=True, text=True)
            if result.returncode == 0:
                self.logger.debug("System monitoring: memory usage checked")
            
        except Exception as e:
            self.logger.error(f"System monitoring error: {e}")
    
    def run(self):
        """Main daemon loop"""
        # Set up signal handlers
        signal.signal(signal.SIGTERM, self.signal_handler)
        signal.signal(signal.SIGINT, self.signal_handler)
        
        self.write_pid()
        self.running = True
        
        config = self.load_config()
        monitoring_interval = config.get('monitoring_interval', 300)
        
        self.logger.info("AI Helper Daemon started")
        
        try:
            while self.running:
                if config.get('enabled', True):
                    self.monitor_system()
                
                # Sleep for monitoring interval
                time.sleep(monitoring_interval)
                
                # Reload config periodically
                config = self.load_config()
                
        except Exception as e:
            self.logger.error(f"Daemon error: {e}")
        finally:
            self.remove_pid()
            self.logger.info("AI Helper Daemon stopped")

if __name__ == '__main__':
    import os
    daemon = AIHelperDaemon()
    daemon.run()
EOF
    
    chmod +x "$service_script"
    
    # Create systemd service file
    local service_file="$chroot_dir/etc/systemd/system/aihelp-daemon.service"
    
    cat > "$service_file" << EOF
[Unit]
Description=AILinux AI Helper Daemon
After=multi-user.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
ExecStart=$AI_HELPER_PATH/bin/aihelp-daemon
Restart=always
RestartSec=5
PIDFile=/var/run/aihelp-daemon.pid

[Install]
WantedBy=multi-user.target
EOF
    
    AI_INSTALLED_COMPONENTS+=("aihelp_daemon")
    AI_CONFIG_FILES+=("$service_file")
    log_success "✅ AI service daemon created"
}

# Create AI desktop integration
create_ai_desktop_integration() {
    local chroot_dir="$1"
    
    log_info "🖥️  Creating AI desktop integration..."
    
    # Create desktop application entry
    local desktop_file="$chroot_dir/usr/share/applications/ailinux-helper.desktop"
    
    cat > "$desktop_file" << EOF
[Desktop Entry]
Name=AILinux Helper
Comment=AI-powered system assistance
Exec=gnome-terminal -- aihelp
Icon=dialog-information
Terminal=false
Type=Application
Categories=System;Utility;
Keywords=ai;help;assistant;support;
StartupNotify=true
EOF
    
    # Create KDE service menu integration
    local kde_service_dir="$chroot_dir/usr/share/kde4/services/ServiceMenus"
    mkdir -p "$kde_service_dir"
    
    local kde_service_file="$kde_service_dir/ailinux-helper.desktop"
    
    cat > "$kde_service_file" << EOF
[Desktop Entry]
Type=Service
ServiceTypes=KonqPopupMenu/Plugin
MimeType=all/all;
Actions=aihelp
X-KDE-Priority=TopLevel

[Desktop Action aihelp]
Name=Ask AI Helper
Icon=dialog-information
Exec=konsole -e aihelp suggest %f
EOF
    
    AI_INSTALLED_COMPONENTS+=("aihelp_desktop")
    log_success "✅ AI desktop integration created"
}

# Configure AI services
configure_ai_services() {
    local chroot_dir="${AILINUX_BUILD_CHROOT_DIR:-/tmp/ailinux_chroot}"
    
    log_info "⚙️  Configuring AI services..."
    
    # Create main AI configuration
    create_ai_main_config "$chroot_dir"
    
    # Set up AI logging
    setup_ai_logging "$chroot_dir"
    
    # Configure AI permissions
    configure_ai_permissions "$chroot_dir"
    
    log_success "✅ AI services configured"
}

# Create main AI configuration
create_ai_main_config() {
    local chroot_dir="$1"
    local config_file="$chroot_dir$AI_CONFIG_DIR/aihelp.json"
    
    cat > "$config_file" << EOF
{
  "version": "$AI_HELPER_VERSION",
  "enabled": true,
  "log_level": "INFO",
  "log_file": "/var/log/aihelp.log",
  "data_directory": "$AI_DATA_DIR",
  "cache_directory": "/tmp/ailinux",
  "features": {
    "system_help": true,
    "command_suggestions": true,
    "troubleshooting": true,
    "package_assistance": true,
    "system_monitoring": false,
    "auto_updates": false
  },
  "daemon": {
    "enabled": false,
    "monitoring_interval": 300,
    "auto_start": false
  },
  "ui": {
    "show_tips": true,
    "desktop_notifications": false,
    "integration_level": "basic"
  }
}
EOF
    
    AI_CONFIG_FILES+=("$config_file")
}

# Set up AI logging
setup_ai_logging() {
    local chroot_dir="$1"
    
    # Create log directory
    mkdir -p "$chroot_dir/var/log"
    
    # Create logrotate configuration
    local logrotate_file="$chroot_dir/etc/logrotate.d/ailinux-helper"
    
    cat > "$logrotate_file" << EOF
/var/log/aihelp.log {
    weekly
    missingok
    rotate 4
    compress
    delaycompress
    notifempty
    create 644 root root
}

/var/log/aihelp-daemon.log {
    weekly
    missingok
    rotate 4
    compress
    delaycompress
    notifempty
    create 644 root root
}
EOF
    
    AI_CONFIG_FILES+=("$logrotate_file")
}

# Configure AI permissions
configure_ai_permissions() {
    local chroot_dir="$1"
    
    # Set proper permissions for AI helper directory
    chmod -R 755 "$chroot_dir$AI_HELPER_PATH"
    chmod -R 644 "$chroot_dir$AI_CONFIG_DIR"/*
    
    # Make scripts executable
    find "$chroot_dir$AI_HELPER_PATH/bin" -type f -name "aihelp*" -exec chmod +x {} \;
}

# Setup AI paths
setup_ai_paths() {
    local chroot_dir="${AILINUX_BUILD_CHROOT_DIR:-/tmp/ailinux_chroot}"
    
    log_info "🛤️  Setting up AI helper paths..."
    
    # Add AI helper to system PATH
    local path_file="$chroot_dir/etc/environment"
    
    if [ -f "$path_file" ]; then
        # Update existing PATH
        sed -i 's|PATH="\(.*\)"|PATH="\1:/opt/ailinux/aihelp/bin"|' "$path_file"
    else
        # Create new environment file
        echo 'PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/ailinux/aihelp/bin"' > "$path_file"
    fi
    
    # Create shell initialization
    local bash_completion="$chroot_dir/etc/bash_completion.d/ailinux-helper"
    
    cat > "$bash_completion" << 'EOF'
# AILinux Helper Bash Completion

_aihelp_completions() {
    local cur prev commands
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    commands="help suggest troubleshoot status"
    
    if [[ ${COMP_CWORD} == 1 ]]; then
        COMPREPLY=($(compgen -W "${commands}" -- ${cur}))
        return 0
    fi
    
    case "${prev}" in
        help)
            local help_topics="ls cd pwd mkdir rm cp mv find grep apt systemctl sudo"
            COMPREPLY=($(compgen -W "${help_topics}" -- ${cur}))
            ;;
        suggest)
            local suggest_topics="install remove copy move list search"
            COMPREPLY=($(compgen -W "${suggest_topics}" -- ${cur}))
            ;;
        troubleshoot)
            local trouble_topics="slow network boot package"
            COMPREPLY=($(compgen -W "${trouble_topics}" -- ${cur}))
            ;;
    esac
}

complete -F _aihelp_completions aihelp
complete -F _aihelp_completions ai
EOF
    
    AI_CONFIG_FILES+=("$path_file" "$bash_completion")
    log_success "✅ AI helper paths configured"
}

# Validate AI integration
validate_ai_integration() {
    local chroot_dir="${1:-$AILINUX_BUILD_CHROOT_DIR}"
    
    log_info "🔍 Validating AI integration..."
    
    local validation_errors=0
    
    # Check if AI helper executable exists
    if [ ! -f "$chroot_dir$AI_HELPER_PATH/bin/aihelp" ]; then
        log_error "❌ AI helper executable not found"
        ((validation_errors++))
    fi
    
    # Check if AI helper is executable
    if [ ! -x "$chroot_dir$AI_HELPER_PATH/bin/aihelp" ]; then
        log_error "❌ AI helper is not executable"
        ((validation_errors++))
    fi
    
    # Check if system symlink exists
    if [ ! -L "$chroot_dir/usr/local/bin/aihelp" ]; then
        log_error "❌ AI helper system symlink missing"
        ((validation_errors++))
    fi
    
    # Check configuration files
    if [ ! -f "$chroot_dir$AI_CONFIG_DIR/aihelp.json" ]; then
        log_error "❌ AI helper configuration missing"
        ((validation_errors++))
    fi
    
    # Test AI helper functionality (basic test)
    if enter_chroot_safely "$chroot_dir" "python3 $AI_HELPER_PATH/bin/aihelp --version" >/dev/null 2>&1; then
        log_success "✅ AI helper executable test passed"
    else
        log_error "❌ AI helper executable test failed"
        ((validation_errors++))
    fi
    
    if [ $validation_errors -eq 0 ]; then
        log_success "✅ AI integration validation passed"
        return 0
    else
        log_error "❌ AI integration validation failed with $validation_errors errors"
        return 1
    fi
}

# Clean up AI integration resources
cleanup_ai_integration() {
    log_info "🧹 Cleaning up AI integration resources..."
    
    # Generate AI integration report
    create_ai_integration_report
    
    log_success "AI integration cleanup completed"
}

# Create AI integration report
create_ai_integration_report() {
    local report_file="/tmp/ailinux_ai_integration_report_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "# AILinux AI Integration Report"
        echo "# Generated: $(date)"
        echo "# Version: $AI_HELPER_VERSION"
        echo ""
        
        echo "== INSTALLED COMPONENTS =="
        printf '%s\n' "${AI_INSTALLED_COMPONENTS[@]}"
        echo ""
        
        echo "== CONFIGURATION FILES =="
        printf '%s\n' "${AI_CONFIG_FILES[@]}"
        echo ""
        
        echo "== AI HELPER PATHS =="
        echo "Helper Path: $AI_HELPER_PATH"
        echo "Config Directory: $AI_CONFIG_DIR"
        echo "Data Directory: $AI_DATA_DIR"
        echo ""
        
    } > "$report_file"
    
    log_success "📄 AI integration report created: $report_file"
    
    # Coordinate through swarm
    swarm_coordinate "ai_integration" "AI helper integration completed successfully" "success" "installation" || true
}

# Export functions for use in other modules
export -f init_ai_integration
export -f install_ai_helper
export -f configure_ai_services
export -f setup_ai_paths
export -f validate_ai_integration
export -f cleanup_ai_integration
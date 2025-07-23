#!/bin/bash
#
# AILinux ISO Build Script v20.3 - Complete Production Version
# Creates a bootable Live ISO of AILinux based on Ubuntu 24.04 (Noble Numbat)
#
# Features:
# - Comprehensive logging to build.log
# - Robust chroot environment to avoid service errors
# - AI-powered self-debugging on failures
# - Complete KDE Plasma desktop with applications
# - Calamares installer with custom branding (FIXED)
# - UEFI + BIOS boot support with Secure Boot
# - AI helper integration via Mixtral API
# - AILinux mirror support for faster downloads
#
# License: MIT License
# Copyright (c) 2024 derleiti

set -eo pipefail

# --- Configuration ---
readonly DISTRO_NAME="AILinux"
readonly DISTRO_VERSION="24.04"
readonly DISTRO_EDITION="Premium"
readonly UBUNTU_CODENAME="noble"
readonly ARCHITECTURE="amd64"

readonly LIVE_USER="ailinux"
readonly LIVE_HOSTNAME="ailinux"

readonly BUILD_DIR="AILINUX_BUILD"
readonly CHROOT_DIR="${BUILD_DIR}/chroot"
readonly ISO_DIR="${BUILD_DIR}/iso"
readonly ISO_NAME="${DISTRO_NAME,,}-${DISTRO_VERSION}-${DISTRO_EDITION,,}-${ARCHITECTURE}.iso"
readonly LOG_FILE="$(pwd)/build.log"

# --- Color and Logging Functions ---
readonly COLOR_RESET='\033[0m'
readonly COLOR_INFO='\033[0;34m'
readonly COLOR_SUCCESS='\033[0;32m'
readonly COLOR_WARN='\033[0;33m'
readonly COLOR_ERROR='\033[0;31m'
readonly COLOR_STEP='\033[1;36m'
readonly COLOR_AI='\033[1;35m'

# Redirect all output to log file and terminal
exec > >(tee -a "${LOG_FILE}") 2>&1

log() {
    local level_color="$1"
    local level_text="$2"
    local message="$3"
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${level_color}[${level_text}]${COLOR_RESET} ${message}"
}

log_info() { log "${COLOR_INFO}" "INFO" "$1"; }
log_success() { log "${COLOR_SUCCESS}" "SUCCESS" "$1"; }
log_warn() { log "${COLOR_WARN}" "WARNING" "$1"; }
log_error() { log "${COLOR_ERROR}" "ERROR" "$1"; }
log_step() {
    echo
    log "${COLOR_STEP}" "STEP $1" "==================== $2 ===================="
}
log_ai() { log "${COLOR_AI}" "AI-DEBUG" "$1"; }

# --- AI Debugger Function ---
ai_debugger() {
    log_error "Build failed. Starting AI analysis..."
    log_ai "Sending build log to Mixtral AI for analysis..."
    
    local api_key
    if [ -f ".env" ]; then
        api_key=$(grep "MISTRALAPIKEY" .env | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
    fi

    if [ -z "$api_key" ] || [ "$api_key" = "your_mixtral_api_key_here" ]; then
        log_error "No valid API key found. Skipping AI analysis."
        return
    fi
    
    local system_prompt="You are an expert-level Linux distribution build-system debugger. A user's build script has failed. Analyze the complete build.log provided. Identify the exact point of failure and provide a clear, actionable solution. Structure your response in German as follows:\n\n### 🚨 Fehleranalyse\nPrecise description of which command failed and why.\n\n### ✅ Lösungsvorschlag\nConcrete, step-by-step plan to fix the problem. If code needs to be changed, provide the exact corrected code block."
    
    local log_content
    log_content=$(tail -n 200 "${LOG_FILE}" | jq -Rs . 2>/dev/null || echo '"Log analysis failed"')

    local json_payload
    json_payload=$(jq -n \
                   --arg sp "$system_prompt" \
                   --arg lc "$log_content" \
                   '{model: "mistral-large-latest", messages: [{"role": "system", "content": $sp}, {"role": "user", "content": $lc}]}' 2>/dev/null || echo '{}')

    log_ai "Performing analysis... This may take a moment."
    
    local ai_response
    ai_response=$(curl -s -X POST "https://api.mistral.ai/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $api_key" \
        -d "$json_payload" 2>/dev/null || echo '{"choices":[{"message":{"content":"Analysis failed"}}]}')

    local analysis
    analysis=$(echo "$ai_response" | jq -r '.choices[0].message.content // "Analysis failed"' 2>/dev/null || echo "Analysis failed")

    echo
    log_ai "AI Analysis Result:"
    echo -e "${COLOR_AI}----------------------------------------------------------------------${COLOR_RESET}"
    echo -e "$analysis"
    echo -e "${COLOR_AI}----------------------------------------------------------------------${COLOR_RESET}"
}

# Error trap: calls AI debugger before script exits
trap 'ai_debugger' ERR

# --- Helper Functions ---
check_not_root() {
    if [ "$(id -u)" -eq 0 ]; then
        log_error "This script must not be run as root. It uses 'sudo' when needed."
        exit 1
    fi
}

check_dependencies() {
    local dependencies=("debootstrap" "squashfs-tools" "xorriso" "grub-pc-bin" "grub-efi-amd64-bin" "mtools" "dosfstools" "isolinux" "syslinux-common" "shim-signed" "gnupg" "git" "curl" "jq" "python3" "python3-pip")
    local missing=()
    
    for dep in "${dependencies[@]}"; do
        if ! dpkg -l "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_warn "Missing dependencies: ${missing[*]}"
        log_info "Installing missing packages..."
        sudo apt-get update
        sudo apt-get install -y "${missing[@]}"
    fi
}

run_in_chroot() {
    sudo chroot "${CHROOT_DIR}" /usr/bin/env -i \
        HOME=/root \
        TERM="$TERM" \
        PS1='(ailinux-chroot) \u:\w\$ ' \
        PATH=/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin \
        DEBIAN_FRONTEND=noninteractive \
        LANG=en_US.UTF-8 \
        LC_ALL=en_US.UTF-8 \
        /bin/bash --login +h -c "$1"
}

cleanup_mounts() {
    log_info "Cleaning up mount points..."
    for mount_point in "/run" "/sys" "/proc" "/dev/pts" "/dev"; do
        if mountpoint -q "${CHROOT_DIR}${mount_point}" 2>/dev/null; then
            sudo umount -f -l "${CHROOT_DIR}${mount_point}" || true
        fi
    done
}

# --- Build Steps ---

step_01_setup() {
    log_step "1/10" "Environment Setup and Dependency Check"
    
    # Create .env.example if it doesn't exist
    if [ ! -f ".env.example" ]; then
        log_info "Creating .env.example template..."
        cat > .env.example << 'EOF'
# .env - API key for Mixtral AI access
# Copy this file to .env and add your API key
MISTRALAPIKEY=your_mixtral_api_key_here
EOF
    fi
    
    # Check for .env file
    if [ ! -f ".env" ]; then
        log_error "Please create a .env file from the template and add your API key."
        log_info "Run: cp .env.example .env && nano .env"
        exit 1
    fi

    check_dependencies
    
    # Clean previous build
    if [ -d "${BUILD_DIR}" ]; then
        log_warn "Previous build directory found. Cleaning up..."
        cleanup_mounts
        sudo rm -rf "${BUILD_DIR}"
    fi
    
    # Remove old ISO files
    if [ -f "${ISO_NAME}" ]; then
        log_warn "Removing existing ISO file: ${ISO_NAME}"
        rm -f "${ISO_NAME}" "${ISO_NAME}.sha256"
    fi

    mkdir -p "${CHROOT_DIR}" "${ISO_DIR}"
    log_success "Build environment successfully set up."
}

step_02_bootstrap_system() {
    log_step "2/10" "Bootstrap Base System and Configure Repositories"
    
    log_info "Running debootstrap to create base system..."
    sudo debootstrap --arch="${ARCHITECTURE}" --variant=minbase "${UBUNTU_CODENAME}" "${CHROOT_DIR}" http://archive.ubuntu.com/ubuntu/
    
    log_info "Configuring full APT sources for the new system..."
    sudo tee "${CHROOT_DIR}/etc/apt/sources.list" > /dev/null <<'EOF'
deb http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse
EOF

    # Setup mounts for chroot
    sudo mount --bind /dev "${CHROOT_DIR}/dev"
    sudo mount --bind /dev/pts "${CHROOT_DIR}/dev/pts"
    sudo mount -t proc proc "${CHROOT_DIR}/proc"
    sudo mount -t sysfs sysfs "${CHROOT_DIR}/sys"
    sudo mount --bind /run "${CHROOT_DIR}/run"
    sudo cp /etc/resolv.conf "${CHROOT_DIR}/etc/"

    # Create bootstrap script file to avoid complex heredoc
    cat > /tmp/bootstrap_repos.sh << 'BOOTSTRAP_EOF'
#!/bin/bash
set -e
echo 'ailinux' > /etc/hostname

# Configure basic locale and APT
apt-get update
apt-get install -y --no-install-recommends locales apt-utils dialog curl wget gnupg ca-certificates lsb-release software-properties-common

# Add AILinux repository and external sources (Wine, Chrome, KDE Neon)
echo 'Adding AILinux repository and external sources...'
curl -fssSL https://ailinux.me:8443/mirror/add-ailinux-repo.sh | bash
if [ $? -eq 0 ]; then
    echo 'AILinux repository and external sources added successfully.'
else
    echo 'Warning: AILinux repo script not available, continuing without it...'
fi

# Add Microsoft VS Code repository
echo 'Adding Microsoft VS Code repository...'
curl -sSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg
echo 'deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main' | tee /etc/apt/sources.list.d/vscode.list

# Setup locales
echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
echo 'de_DE.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

# Enable i386 architecture for Wine
dpkg --add-architecture i386

# Final update to fetch all package lists
apt-get update
BOOTSTRAP_EOF

    sudo cp /tmp/bootstrap_repos.sh "${CHROOT_DIR}/tmp/"
    sudo chmod +x "${CHROOT_DIR}/tmp/bootstrap_repos.sh"
    run_in_chroot "/tmp/bootstrap_repos.sh"
    sudo rm -f "${CHROOT_DIR}/tmp/bootstrap_repos.sh" /tmp/bootstrap_repos.sh || true
    
    log_success "Base system and repositories configured."
}

step_03_install_packages() {
    log_step "3/10" "Install Core Packages, Kernel, and Desktop Environment"
    
    # Create package installation script
    cat > /tmp/install_packages.sh << 'PACKAGES_EOF'
#!/bin/bash
set -e

# Install kernel and boot components
apt-get install -y \
    linux-image-generic linux-headers-generic \
    casper discover laptop-detect os-prober \
    network-manager resolvconf net-tools wireless-tools \
    plymouth-theme-spinner ubuntu-standard \
    keyboard-configuration console-setup \
    sudo systemd systemd-sysv dbus init rsyslog \
    systemd-coredump grub-efi-amd64 shim-signed \
    initramfs-tools live-boot

# Install complete KDE desktop
apt-get install -y \
    kde-full plasma-desktop sddm-theme-breeze \
    xorg xinit x11-xserver-utils xserver-xorg-video-all

# Install core applications and AILinux App dependencies
apt-get install -y \
    firefox thunderbird vlc gimp \
    libreoffice libreoffice-l10n-en-us \
    gparted htop neofetch konsole kate okular \
    gwenview ark dolphin \
    ubuntu-restricted-extras ffmpeg \
    pulseaudio pulseaudio-utils pavucontrol \
    git build-essential cmake \
    python3 python3-pip python3-venv python3-dev \
    python3-pyqt5 python3-pyqt5.qtwidgets python3-pyqt5.qtcore python3-pyqt5.qtgui \
    nodejs npm default-jdk \
    linux-firmware bluez bluetooth \
    wpasupplicant printer-driver-all cups \
    jq tree vim nano curl wget unzip zip \
    software-properties-common apt-transport-https \
    filezilla

# Install optional packages with simple error handling
echo 'Installing optional packages...'

# Google Chrome
echo 'Trying to install Google Chrome...'
if apt-get install -y google-chrome-stable; then
    echo 'Google Chrome installed successfully.'
else
    echo 'Google Chrome installation from repository failed, trying direct download...'
    if wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/chrome.deb; then
        if dpkg -i /tmp/chrome.deb; then
            echo 'Google Chrome installed from direct download.'
        else
            echo 'Fixing broken dependencies...'
            apt-get install -f -y
        fi
        rm -f /tmp/chrome.deb
    else
        echo 'Google Chrome download failed, skipping...'
    fi
fi

# Wine
echo 'Trying to install Wine...'
if apt-get install -y winehq-staging winetricks; then
    echo 'Wine staging installed successfully.'
else
    echo 'Wine staging failed, trying regular wine...'
    if apt-get install -y wine wine32 wine64 winetricks; then
        echo 'Regular Wine installed successfully.'
    else
        echo 'Wine installation completely failed, skipping...'
    fi
fi

# VS Code
echo 'Trying to install VS Code...'
if apt-get install -y code; then
    echo 'VS Code installed successfully.'
else
    echo 'VS Code installation from repository failed, trying direct download...'
    if wget -q https://packages.microsoft.com/repos/code/pool/main/c/code/code_1.96.4-1738329923_amd64.deb -O /tmp/vscode.deb; then
        if dpkg -i /tmp/vscode.deb; then
            echo 'VS Code installed from direct download.'
        else
            echo 'Fixing broken dependencies...'
            apt-get install -f -y
        fi
        rm -f /tmp/vscode.deb
    else
        echo 'VS Code download failed, skipping...'
    fi
fi

echo 'Package installation completed.'
PACKAGES_EOF

    sudo cp /tmp/install_packages.sh "${CHROOT_DIR}/tmp/"
    sudo chmod +x "${CHROOT_DIR}/tmp/install_packages.sh"
    run_in_chroot "/tmp/install_packages.sh"
    sudo rm -f "${CHROOT_DIR}/tmp/install_packages.sh" /tmp/install_packages.sh || true
    
    log_success "All core packages and desktop environment installed."
}

step_04_install_ai_components() {
    log_step "4/10" "Install AILinux AI Components"
    
    # Copy .env file to chroot if it exists
    if [ -f ".env" ]; then
        sudo cp .env "${CHROOT_DIR}/tmp/.env"
    fi
    
    # Create AI components installation script
    cat > /tmp/install_ai.sh << 'AI_EOF'
#!/bin/bash
set -e
python3 -m pip install --break-system-packages requests python-dotenv psutil

mkdir -p /opt/ailinux

# Create the AI helper script
cat > /opt/ailinux/ailinux-helper.py << 'AIHELPER'
#!/usr/bin/env python3
import os
import sys
import json
import requests
import argparse
import subprocess
from dotenv import load_dotenv

# Load environment variables
load_dotenv(dotenv_path='/opt/ailinux/.env')

class AILinuxHelper:
    def __init__(self):
        self.api_key = os.getenv('MISTRALAPIKEY')
        if not self.api_key or self.api_key == 'your_mixtral_api_key_here':
            print('Error: MISTRALAPIKEY not found or not configured properly.')
            print('Please edit /opt/ailinux/.env and add your Mixtral API key.')
            sys.exit(1)
        
        self.api_url = 'https://api.mistral.ai/v1/chat/completions'
        self.system_prompt = '''Du bist AILinux Helper – ein KI-gesteuerter Assistent, der in der Linux-Distribution „AILinux 24.04 Premium" eingebettet ist.

Diese Distribution basiert auf Ubuntu 24.04 (Codename: Noble) und wurde speziell für eine moderne, KI-integrierte Offline-Nutzung entwickelt.
Dein Interface ist das Kommandozeilentool aihelp.

## 🎯 Deine Aufgabe

Du wirst direkt über das Terminal vom Nutzer aufgerufen, um:

- Fehlermeldungen und Logs zu analysieren
- technische Probleme zu erklären
- Lösungen bereitzustellen, z. B. Shell-Befehle oder Systemhinweise
- Hilfe zur Nutzung und Konfiguration von AILinux zu leisten

## 📋 Antwortformat (immer verwenden)

### 🚨 Problem Summary
*Kurzbeschreibung des gemeldeten oder erkannten Problems.*

### ⚙ Likely Cause
*Technische Erklärung der wahrscheinlichen Ursache – inkl. Log-Analyse, Abhängigkeiten, Services etc.*

### ✅ Suggested Solution
*Konkrete Lösung als Shell-Befehl(e) oder Beschreibung.*

Falls zu wenig Informationen gegeben sind, antworte mit:
"Bitte gib mir mehr Details wie Logs, konkrete Fehlermeldungen oder betroffene Befehle."

AILinux enthält: kde-full, firefox, chrome, thunderbird, vlc, gimp, libreoffice, wine, vscode, python3, nodejs, und viele andere Pakete.'''

    def analyze_problem(self, user_input):
        headers = {
            'Authorization': f'Bearer {self.api_key}',
            'Content-Type': 'application/json'
        }
        
        data = {
            'model': 'mistral-large-latest',
            'messages': [
                {'role': 'system', 'content': self.system_prompt},
                {'role': 'user', 'content': user_input}
            ]
        }
        
        try:
            response = requests.post(self.api_url, headers=headers, json=data, timeout=90)
            response.raise_for_status()
            return response.json()['choices'][0]['message']['content']
        except Exception as e:
            return f'Error contacting AI service: {e}'

    def get_system_info(self):
        try:
            import psutil
            info = {
                'CPU Usage': f'{psutil.cpu_percent()}%',
                'Memory Usage': f'{psutil.virtual_memory().percent}%',
                'Disk Usage': f'{psutil.disk_usage("/").percent}%',
                'Load Average': os.getloadavg(),
                'Uptime': subprocess.check_output(['uptime'], text=True).strip()
            }
            return '\n'.join([f'{k}: {v}' for k, v in info.items()])
        except:
            return 'System info unavailable'

def main():
    parser = argparse.ArgumentParser(description='AILinux Helper - AI-powered system assistant')
    parser.add_argument('query', nargs='*', help='Problem description or question to analyze')
    parser.add_argument('--sysinfo', '-s', action='store_true', help='Show system information')
    parser.add_argument('--log', '-l', type=str, help='Analyze a specific log file')
    args = parser.parse_args()
    
    helper = AILinuxHelper()
    
    if args.sysinfo:
        print('### 🖥 System Information')
        print(helper.get_system_info())
        return
    
    if args.log:
        if os.path.exists(args.log):
            with open(args.log, 'r') as f:
                log_content = f.read()
            user_input = f'Please analyze this log file ({args.log}):\n\n{log_content}'
        else:
            print(f'Error: Log file {args.log} not found.')
            return
    else:
        if args.query:
            user_input = ' '.join(args.query)
        else:
            print('Enter your problem description (press Ctrl+D when finished):')
            user_input = sys.stdin.read()
    
    if user_input.strip():
        print('\nAnalyzing...')
        print(helper.analyze_problem(user_input))
    else:
        print('No input provided.')

if __name__ == '__main__':
    main()
AIHELPER
chmod +x /opt/ailinux/ailinux-helper.py

# Create the AILinux GUI Application
cat > /opt/ailinux/ailinux-app.py << 'AILINUX_APP'
#!/usr/bin/env python3
"""
AILinux App - GUI für den AI-gestützten Linux-Assistenten
Eine benutzerfreundliche grafische Oberfläche für AILinux Helper
"""

import sys
import os
import subprocess
import threading
from PyQt5.QtWidgets import (QApplication, QMainWindow, QVBoxLayout, QHBoxLayout, 
                             QWidget, QTextEdit, QLineEdit, QPushButton, QLabel, 
                             QTabWidget, QScrollArea, QFrame, QSplitter, QSystemTrayIcon, QMenu, QAction)
from PyQt5.QtCore import Qt, QThread, pyqtSignal, QTimer
from PyQt5.QtGui import QFont, QPalette, QColor, QIcon, QPixmap

# Import the AI helper
sys.path.append('/opt/ailinux')
try:
    from ailinux_helper import AILinuxHelper
except ImportError:
    AILinuxHelper = None

class AIWorkerThread(QThread):
    response_ready = pyqtSignal(str)
    
    def __init__(self, query):
        super().__init__()
        self.query = query
        
    def run(self):
        if AILinuxHelper:
            try:
                helper = AILinuxHelper()
                response = helper.analyze_problem(self.query)
                self.response_ready.emit(response)
            except Exception as e:
                self.response_ready.emit(f"Fehler bei der AI-Analyse: {str(e)}")
        else:
            self.response_ready.emit("AI Helper nicht verfügbar. Bitte konfigurieren Sie den API-Schlüssel.")

class SystemInfoWidget(QWidget):
    def __init__(self):
        super().__init__()
        self.init_ui()
        self.update_timer = QTimer()
        self.update_timer.timeout.connect(self.update_info)
        self.update_timer.start(5000)  # Update every 5 seconds
        
    def init_ui(self):
        layout = QVBoxLayout()
        
        self.info_text = QTextEdit()
        self.info_text.setReadOnly(True)
        self.info_text.setFont(QFont("Courier", 10))
        
        refresh_btn = QPushButton("🔄 Aktualisieren")
        refresh_btn.clicked.connect(self.update_info)
        
        layout.addWidget(QLabel("🖥️ System-Informationen"))
        layout.addWidget(self.info_text)
        layout.addWidget(refresh_btn)
        
        self.setLayout(layout)
        self.update_info()
        
    def update_info(self):
        try:
            if AILinuxHelper:
                helper = AILinuxHelper()
                info = helper.get_system_info()
                self.info_text.setPlainText(info)
            else:
                self.info_text.setPlainText("System-Info nicht verfügbar")
        except:
            self.info_text.setPlainText("Fehler beim Laden der System-Informationen")

class AILinuxMainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.init_ui()
        self.setup_tray()
        
    def init_ui(self):
        self.setWindowTitle("AILinux Assistant")
        self.setGeometry(100, 100, 1000, 700)
        
        # Dark theme
        self.setStyleSheet("""
            QMainWindow { background-color: #2b2b2b; color: #ffffff; }
            QTextEdit { background-color: #3c3c3c; color: #ffffff; border: 1px solid #555; }
            QLineEdit { background-color: #3c3c3c; color: #ffffff; border: 1px solid #555; padding: 5px; }
            QPushButton { background-color: #4CAF50; color: white; border: none; padding: 8px; border-radius: 4px; }
            QPushButton:hover { background-color: #45a049; }
            QLabel { color: #ffffff; }
            QTabWidget::pane { border: 1px solid #555; background-color: #2b2b2b; }
            QTabBar::tab { background-color: #3c3c3c; color: #ffffff; padding: 8px; }
            QTabBar::tab:selected { background-color: #4CAF50; }
        """)
        
        # Central widget with tabs
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        
        layout = QVBoxLayout()
        central_widget.setLayout(layout)
        
        # Header
        header = QLabel("🧠 AILinux Assistant - KI-gestützter System-Support")
        header.setFont(QFont("Arial", 16, QFont.Bold))
        header.setAlignment(Qt.AlignCenter)
        layout.addWidget(header)
        
        # Tab widget
        self.tabs = QTabWidget()
        layout.addWidget(self.tabs)
        
        # AI Chat Tab
        self.create_ai_chat_tab()
        
        # System Info Tab
        self.create_system_info_tab()
        
        # Quick Actions Tab
        self.create_quick_actions_tab()
        
    def create_ai_chat_tab(self):
        ai_widget = QWidget()
        layout = QVBoxLayout()
        
        # Chat area
        self.chat_area = QTextEdit()
        self.chat_area.setReadOnly(True)
        self.chat_area.append("🤖 AILinux Assistant bereit! Beschreiben Sie Ihr Problem...")
        
        # Input area
        input_layout = QHBoxLayout()
        self.input_field = QLineEdit()
        self.input_field.setPlaceholderText("Beschreiben Sie Ihr Problem hier...")
        self.input_field.returnPressed.connect(self.send_query)
        
        send_btn = QPushButton("📤 Senden")
        send_btn.clicked.connect(self.send_query)
        
        clear_btn = QPushButton("🗑️ Löschen")
        clear_btn.clicked.connect(self.clear_chat)
        
        input_layout.addWidget(self.input_field)
        input_layout.addWidget(send_btn)
        input_layout.addWidget(clear_btn)
        
        layout.addWidget(self.chat_area)
        layout.addLayout(input_layout)
        
        ai_widget.setLayout(layout)
        self.tabs.addTab(ai_widget, "🤖 AI-Chat")
        
    def create_system_info_tab(self):
        self.system_info_widget = SystemInfoWidget()
        self.tabs.addTab(self.system_info_widget, "🖥️ System-Info")
        
    def create_quick_actions_tab(self):
        actions_widget = QWidget()
        layout = QVBoxLayout()
        
        layout.addWidget(QLabel("⚡ Schnell-Aktionen"))
        
        # Quick action buttons
        actions = [
            ("🔧 System-Update durchführen", "sudo apt update && sudo apt upgrade"),
            ("🧹 System aufräumen", "sudo apt autoremove && sudo apt autoclean"),
            ("📊 Festplatten-Info anzeigen", "df -h"),
            ("🔍 Große Dateien finden", "sudo du -h / | sort -hr | head -20"),
            ("🌐 Netzwerk-Status prüfen", "ip addr show && ping -c 3 google.com"),
            ("🔒 Firewall-Status prüfen", "sudo ufw status"),
        ]
        
        for name, command in actions:
            btn = QPushButton(name)
            btn.clicked.connect(lambda checked, cmd=command: self.run_command(cmd))
            layout.addWidget(btn)
            
        actions_widget.setLayout(layout)
        self.tabs.addTab(actions_widget, "⚡ Aktionen")
        
    def setup_tray(self):
        if QSystemTrayIcon.isSystemTrayAvailable():
            self.tray_icon = QSystemTrayIcon(self)
            
            # Create tray menu
            tray_menu = QMenu()
            
            show_action = QAction("AILinux App anzeigen", self)
            show_action.triggered.connect(self.show)
            tray_menu.addAction(show_action)
            
            quit_action = QAction("Beenden", self)
            quit_action.triggered.connect(QApplication.quit)
            tray_menu.addAction(quit_action)
            
            self.tray_icon.setContextMenu(tray_menu)
            self.tray_icon.show()
            
    def send_query(self):
        query = self.input_field.text().strip()
        if not query:
            return
            
        self.chat_area.append(f"\n👤 Benutzer: {query}")
        self.input_field.clear()
        
        self.chat_area.append("🤖 Analysiere...")
        
        # Start AI worker thread
        self.worker = AIWorkerThread(query)
        self.worker.response_ready.connect(self.handle_ai_response)
        self.worker.start()
        
    def handle_ai_response(self, response):
        self.chat_area.append(f"\n🤖 AILinux Assistant:\n{response}")
        self.chat_area.verticalScrollBar().setValue(
            self.chat_area.verticalScrollBar().maximum()
        )
        
    def clear_chat(self):
        self.chat_area.clear()
        self.chat_area.append("🤖 AILinux Assistant bereit! Beschreiben Sie Ihr Problem...")
        
    def run_command(self, command):
        self.chat_area.append(f"\n⚡ Führe aus: {command}")
        try:
            result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=30)
            output = result.stdout if result.stdout else result.stderr
            self.chat_area.append(f"📝 Ausgabe:\n{output}")
        except subprocess.TimeoutExpired:
            self.chat_area.append("⏰ Befehl-Timeout")
        except Exception as e:
            self.chat_area.append(f"❌ Fehler: {str(e)}")

def main():
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)  # Keep running in tray
    
    window = AILinuxMainWindow()
    window.show()
    
    sys.exit(app.exec_())

if __name__ == '__main__':
    main()
AILINUX_APP
chmod +x /opt/ailinux/ailinux-app.py

# Create desktop entry for AILinux App
cat > /usr/share/applications/ailinux-app.desktop << 'DESKTOP_ENTRY'
[Desktop Entry]
Version=1.0
Type=Application
Name=AILinux App
Name[de]=AILinux Anwendung
Comment=AI-powered system assistant GUI
Comment[de]=KI-gestützter System-Assistent mit GUI
Icon=ailinux-app
Exec=/opt/ailinux/ailinux-app.py
Terminal=false
StartupNotify=true
Categories=System;Utility;
Keywords=AI;assistant;system;helper;
DESKTOP_ENTRY

# Create symlink for easy command line access
ln -sf /opt/ailinux/ailinux-helper.py /usr/local/bin/aihelp
ln -sf /opt/ailinux/ailinux-app.py /usr/local/bin/ailinux-app

# Move .env file to final location
if [ -f '/tmp/.env' ]; then
    mv /tmp/.env /opt/ailinux/.env
    chmod 600 /opt/ailinux/.env
fi

echo "AILinux AI components and GUI app installed successfully."
AI_EOF

    sudo cp /tmp/install_ai.sh "${CHROOT_DIR}/tmp/"
    sudo chmod +x "${CHROOT_DIR}/tmp/install_ai.sh"
    run_in_chroot "/tmp/install_ai.sh"
    sudo rm -f "${CHROOT_DIR}/tmp/install_ai.sh" /tmp/install_ai.sh || true
    
    log_success "AILinux AI components installed."
}

step_05_configure_calamares() {
    log_step "5/10" "Configure Calamares Installer"
    
    # Copy branding files if they exist
    if [ -d "branding" ]; then
        sudo mkdir -p "${CHROOT_DIR}/tmp/branding"
        sudo cp -r branding/* "${CHROOT_DIR}/tmp/branding/"
    fi
    
    # Create Calamares configuration script
    cat > /tmp/configure_calamares.sh << 'CALAMARES_EOF'
#!/bin/bash
set -e
# Install Calamares and dependencies (without ubuntu-specific settings)
echo 'Installing Calamares installer...'
if apt-get install -y calamares python3-pyqt5 python3-yaml python3-parted imagemagick; then
    echo 'Calamares installed successfully.'
else
    echo 'Some Calamares dependencies failed, trying minimal installation...'
    if apt-get install -y calamares; then
        echo 'Minimal Calamares installation successful.'
        # Install optional dependencies individually
        apt-get install -y python3-pyqt5 || echo 'PyQt5 not available'
        apt-get install -y python3-yaml || echo 'PyYAML not available'  
        apt-get install -y python3-parted || echo 'python3-parted not available'
        apt-get install -y imagemagick || echo 'ImageMagick not available'
    else
        echo 'Calamares installation failed completely. Continuing without installer...'
        exit 0
    fi
fi

# Create Calamares configuration
mkdir -p /etc/calamares/modules

# Main settings - WITH corrected bootloader module
cat > /etc/calamares/settings.conf << 'SETTINGS'
---
modules-search: [ local ]

instances:
- id:       rootfs
  module:   unpackfs
  config:   unpackfs.conf

sequence:
- show:
  - welcome
  - locale
  - keyboard
  - partition
  - users
  - summary
- exec:
  - partition
  - mount
  - unpackfs@rootfs
  - machineid
  - fstab
  - locale
  - keyboard
  - localecfg
  - users
  - displaymanager
  - networkcfg
  - hwclock
  - services-systemd
  - bootloader
  - umount
- show:
  - finished

branding: ailinux

prompt-install: false

dont-chroot: false

oem-setup: false

disable-cancel: false

disable-cancel-during-exec: false

quit-at-end: false
SETTINGS

# CORRECTED Branding configuration
mkdir -p /etc/calamares/branding/ailinux
cat > /etc/calamares/branding/ailinux/branding.desc << 'BRANDING'
---
componentName:  ailinux

strings:
    productName:         AILinux
    shortProductName:    AILinux
    version:             24.04 Premium
    shortVersion:        24.04
    versionedName:       AILinux 24.04 Premium
    shortVersionedName:  AILinux 24.04
    bootloaderEntryName: AILinux
    productUrl:          https://github.com/derleiti/ailinux-beta-iso
    supportUrl:          https://github.com/derleiti/ailinux-beta-iso/issues
    bugReportUrl:        https://github.com/derleiti/ailinux-beta-iso/issues
    releaseNotesUrl:     https://github.com/derleiti/ailinux-beta-iso/releases

images:
    productLogo:         "logo.png"
    productIcon:         "icon.png"
    productWelcome:      "welcome.png"

style:
   sidebarBackground:    "#2c3e50"
   sidebarText:          "#ffffff"
   sidebarTextSelect:    "#3498db"
   sidebarTextCurrent:   "#ffffff"

slideshow:               "show.qml"

slideshowAPI: 2

uploadServer:
    type:    "fiche"
    url:     "http://termbin.com:9999"
BRANDING

# Copy branding images if available
if [ -d '/tmp/branding' ]; then
    cp /tmp/branding/* /etc/calamares/branding/ailinux/ 2>/dev/null || true
fi

# Create default images if not provided
if [ ! -f '/etc/calamares/branding/ailinux/logo.png' ]; then
    convert -size 256x256 xc:'#3498db' -pointsize 24 -fill white -gravity center -annotate +0+0 'AILinux' /etc/calamares/branding/ailinux/logo.png
fi

# Copy missing images from logo if they don't exist
if [ ! -f '/etc/calamares/branding/ailinux/icon.png' ]; then
    cp /etc/calamares/branding/ailinux/logo.png /etc/calamares/branding/ailinux/icon.png
fi

if [ ! -f '/etc/calamares/branding/ailinux/welcome.png' ]; then
    cp /etc/calamares/branding/ailinux/logo.png /etc/calamares/branding/ailinux/welcome.png
fi

# Create CORRECTED slideshow QML file
cat > /etc/calamares/branding/ailinux/show.qml << 'SLIDESHOW'
import QtQuick 2.5
import calamares.slideshow 1.0

Presentation {
    id: presentation
    
    Slide {
        anchors.fill: parent
        
        Rectangle {
            anchors.fill: parent
            color: "#2c3e50"
        }
        
        Image {
            id: background
            source: "welcome.png"
            width: 200
            height: 200
            fillMode: Image.PreserveAspectFit
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 50
        }
        
        Text {
            anchors.centerIn: parent
            text: "Willkommen zu AILinux 24.04 Premium!"
            font.pixelSize: 28
            color: "white"
            font.weight: Font.Bold
        }
        
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 50
            text: "Ihre KI-gestützte Linux-Distribution"
            font.pixelSize: 18
            color: "#3498db"
        }
    }
    
    Slide {
        anchors.fill: parent
        
        Rectangle {
            anchors.fill: parent
            color: "#34495e"
        }
        
        Column {
            anchors.centerIn: parent
            spacing: 20
            
            Text {
                text: "🧠 KI-Integration"
                font.pixelSize: 24
                color: "#3498db"
                font.weight: Font.Bold
            }
            
            Text {
                width: 400
                text: "AILinux enthält einen AI-Assistant.\nVerwenden Sie 'aihelp' im Terminal für:\n\n• Systemdiagnose\n• Fehlerbehebung\n• Log-Analyse\n• Technischen Support"
                font.pixelSize: 16
                color: "white"
                horizontalAlignment: Text.AlignCenter
                wrapMode: Text.WordWrap
            }
        }
    }
    
    Slide {
        anchors.fill: parent
        
        Rectangle {
            anchors.fill: parent
            color: "#3498db"
        }
        
        Column {
            anchors.centerIn: parent
            spacing: 20
            
            Text {
                text: "⚙️ Vollständige Desktop-Umgebung"
                font.pixelSize: 24
                color: "white"
                font.weight: Font.Bold
            }
            
            Text {
                width: 500
                text: "• KDE Plasma Desktop\n• Firefox & Chrome\n• LibreOffice Suite\n• GIMP & VLC\n• Visual Studio Code\n• Wine für Windows-Apps\n• Entwickler-Tools"
                font.pixelSize: 16
                color: "white"
                horizontalAlignment: Text.AlignCenter
                wrapMode: Text.WordWrap
            }
        }
    }
    
    Slide {
        anchors.fill: parent
        
        Rectangle {
            anchors.fill: parent
            color: "#27ae60"
        }
        
        Column {
            anchors.centerIn: parent
            spacing: 20
            
            Text {
                text: "🚀 Installation läuft..."
                font.pixelSize: 28
                color: "white"
                font.weight: Font.Bold
            }
            
            Text {
                width: 400
                text: "AILinux wird auf Ihrem System installiert.\nDies kann einige Minuten dauern.\n\nNach der Installation steht Ihnen\nder aihelp-Befehl zur Verfügung."
                font.pixelSize: 16
                color: "white"
                horizontalAlignment: Text.AlignCenter
                wrapMode: Text.WordWrap
            }
        }
    }
}
SLIDESHOW

# Welcome module (increased storage requirement)
cat > /etc/calamares/modules/welcome.conf << 'WELCOME'
---
showSupportUrl:         true
showKnownIssuesUrl:     false
showReleaseNotesUrl:    true
showDonateUrl:          false

requirements:
    requiredStorage:    20.0
    requiredRam:        2.0
    internetCheckUrl:   http://google.com
    checkHasInternetConnection: false

geoip:
    style:    "none"
    url:      ""
    selector: ""

lnf:
    defaultLnF:     org.kde.breeze.desktop
    lnfPath:        /usr/share/plasma/look-and-feel/
    showAll:        false
WELCOME

# Users module configuration
cat > /etc/calamares/modules/users.conf << 'USERS'
---
defaultGroups:
    - name: cdrom
      must_exist: false
    - name: floppy  
      must_exist: false
    - name: sudo
      must_exist: true
    - name: audio
      must_exist: false
    - name: dip
      must_exist: false
    - name: video
      must_exist: false
    - name: plugdev
      must_exist: false
    - name: netdev
      must_exist: false
    - name: bluetooth
      must_exist: false
    - name: lpadmin
      must_exist: false

autologinGroup:  autologin
sudoersGroup:    sudo
setRootPassword: false
doReusePassword: true

passwordRequirements:
    minLength: 4
    maxLength: -1

allowWeakPasswords: true
allowWeakPasswordsDefault: true

userShell: /bin/bash

hostname:
    location: EtcFile
    writeHostsFile: true
    template: "ailinux-${cpu}"
USERS

# Unpackfs configuration
cat > /etc/calamares/modules/unpackfs.conf << 'UNPACKFS'
---
unpack:
    -   source: "/cdrom/casper/filesystem.squashfs"
        sourcefs: "squashfs"
        destination: ""
        
exclude: [ "dev/*", "proc/*", "sys/*", "tmp/*", "run/*", "mnt/*", "media/*", "lost+found", "cdrom/*", "swapfile" ]

excludeFile: false
UNPACKFS

# Finished module
cat > /etc/calamares/modules/finished.conf << 'FINISHED'
---
restartNowEnabled: true
restartNowChecked: false
notifyOnFinished: true
FINISHED

# Display manager configuration
cat > /etc/calamares/modules/displaymanager.conf << 'DISPLAYMGR'
---
displaymanagers:
  - sddm
  - lightdm
  - gdm

defaultDesktopEnvironment:
    executable: "startkde"
    desktopFile: "plasma"

basicSetup: false

sysconfigSetup: false
DISPLAYMGR

# Partition module configuration - WITH automatic EFI partition
cat > /etc/calamares/modules/partition.conf << 'PARTITION'
---
efiSystemPartition: "/boot/efi"
efiSystemPartitionSize: 1000MiB
efiSystemPartitionName: "EFI"

userSwapChoices:
    - none
    - small
    - suspend

swapPartitionName: "swap"

drawNestedPartitions: false

alwaysShowPartitionLabels: true

allowManualPartitioning: true

initialPartitioningChoice: erase
initialSwapChoice: small

defaultFileSystemType: "ext4"

availableFileSystemTypes:
    - "ext4"
    - "ext3"
    - "ext2"
    - "btrfs"
    - "xfs"

partitionLayout:
    - name: "efi"
      type: "efi"
      size: 1000MiB
      mountPoint: "/boot/efi"
      filesystem: "fat32"
      attributes: 64
    - name: "root"
      type: "primary"
      size: 100%
      mountPoint: "/"
      filesystem: "ext4"

requiredPartitionTableType:
    - "gpt"

armInstall: false
PARTITION

# Bootloader configuration - SIMPLIFIED and WORKING
cat > /etc/calamares/modules/bootloader.conf << 'BOOTLOADER'
---
efiBootloaderId: "ailinux"

kernel: "/vmlinuz"
img: "/initrd.img"

grubInstall: "grub-install"
grubMkconfig: "grub-mkconfig"
grubCfg: "/boot/grub/grub.cfg"
efiBootMgr: "efibootmgr"

installEFIFallback: true
timeout: 10

efiInstallParams: "--target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ailinux --removable"
biosInstallParams: "--target=i386-pc"
BOOTLOADER

# Mount module configuration - to properly handle EFI partition
cat > /etc/calamares/modules/mount.conf << 'MOUNT'
---
extraMounts:
    - device: proc
      fs: proc
      mountPoint: /proc
    - device: sys  
      fs: sysfs
      mountPoint: /sys
    - device: /dev
      mountPoint: /dev
      options: bind
    - device: tmpfs
      fs: tmpfs
      mountPoint: /run
    - device: /dev/pts
      fs: devpts
      mountPoint: /dev/pts
      options: "gid=5,mode=620"

extraMountsEfi:
    - device: efivarfs
      fs: efivarfs
      mountPoint: /sys/firmware/efi/efivars
MOUNT

# Fstab module configuration - to ensure proper fstab generation
cat > /etc/calamares/modules/fstab.conf << 'FSTAB'
---
mountOptions:
    default:
        - defaults
        - noatime
    efi:
        - defaults
        - umask=077
    btrfs:
        - defaults
        - noatime
        - space_cache
        - autodefrag

ssdExtraMountOptions:
    ext4:
        - discard
    jfs:
        - discard
    xfs:
        - discard

efiMountOptions:
    - defaults
    - umask=077

crypttabOptions:
    - luks
FSTAB
cat > /etc/calamares/modules/bootloader.conf << 'BOOTLOADER'
---
efiBootloaderId: "ailinux"

kernel: "/vmlinuz"
img: "/initrd.img"

grubInstall: "grub-install"
grubMkconfig: "grub-mkconfig"
grubCfg: "/boot/grub/grub.cfg"
efiBootMgr: "efibootmgr"

installEFIFallback: true
timeout: 10

# Simplified installation parameters
efiInstallParams: "--target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ailinux --removable"
biosInstallParams: "--target=i386-pc"
BOOTLOADER

echo "Calamares configuration with corrected bootloader completed successfully."
CALAMARES_EOF

    sudo cp /tmp/configure_calamares.sh "${CHROOT_DIR}/tmp/"
    sudo chmod +x "${CHROOT_DIR}/tmp/configure_calamares.sh"
    run_in_chroot "/tmp/configure_calamares.sh"
    sudo rm -f "${CHROOT_DIR}/tmp/configure_calamares.sh" /tmp/configure_calamares.sh || true
    
    log_success "Calamares installer configured with corrected branding.desc."
}

step_06_create_live_user() {
    log_step "6/10" "Create Live User and Configure Desktop"
    
    # Create live user configuration script
    cat > /tmp/create_user.sh << 'USER_EOF'
#!/bin/bash
set -e
# Create live user
useradd -s /bin/bash -d '/home/ailinux' -m -G adm,cdrom,sudo,dip,plugdev,lpadmin,audio,video,bluetooth,netdev 'ailinux'
passwd -d 'ailinux'
echo 'ailinux ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers

# Configure SDDM for autologin
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/autologin.conf << 'SDDM_EOF'
[Autologin]
User=ailinux
Session=plasma

[Theme]
Current=breeze

[X11]
ServerPath=/usr/bin/X
SessionCommand=/usr/share/sddm/scripts/Xsession
SessionDir=/usr/share/xsessions
SDDM_EOF

# Create desktop shortcut for installer
mkdir -p '/home/ailinux/Desktop'
cat > '/home/ailinux/Desktop/install-ailinux.desktop' << 'INSTALL_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=Install AILinux
Name[de]=AILinux installieren
Comment=Install AILinux to your computer
Comment[de]=AILinux auf Ihrem Computer installieren
Icon=calamares
Exec=pkexec calamares
Terminal=false
StartupNotify=true
Categories=System;
INSTALL_EOF
chmod +x '/home/ailinux/Desktop/install-ailinux.desktop'

# Create AI helper shortcut
cat > '/home/ailinux/Desktop/aihelp.desktop' << 'AIHELP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=AILinux Helper (Terminal)
Name[de]=AILinux Assistent (Terminal)
Comment=AI-powered system assistant
Comment[de]=KI-gestützter Systemassistent
Icon=dialog-information
Exec=konsole -e aihelp
Terminal=true
StartupNotify=true
Categories=System;Utility;
AIHELP_EOF
chmod +x '/home/ailinux/Desktop/aihelp.desktop'

# Create AILinux App shortcut
cat > '/home/ailinux/Desktop/ailinux-app.desktop' << 'APP_EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=AILinux App
Name[de]=AILinux Anwendung  
Comment=AI-powered system assistant GUI
Comment[de]=KI-gestützter System-Assistent mit GUI
Icon=applications-system
Exec=/opt/ailinux/ailinux-app.py
Terminal=false
StartupNotify=true
Categories=System;Utility;
APP_EOF
chmod +x '/home/ailinux/Desktop/ailinux-app.desktop'

# Configure .bashrc
cat >> '/home/ailinux/.bashrc' << 'BASHRC_EOF'

# AILinux Welcome
echo ''
echo '🧠 Willkommen bei AILinux 24.04 Premium!'
echo 'Verwenden Sie "aihelp" für KI-gestützte Systemhilfe.'
echo 'Oder starten Sie "ailinux-app" für die grafische Oberfläche.'
echo ''

# AILinux App alias
alias aiapp='ailinux-app'
alias ai='aihelp'
BASHRC_EOF

# Set ownership
chown -R 'ailinux:ailinux' '/home/ailinux'

# Create autostart entry for AILinux App (optional)
mkdir -p '/home/ailinux/.config/autostart'
cat > '/home/ailinux/.config/autostart/ailinux-app.desktop' << 'AUTOSTART_EOF'
[Desktop Entry]
Type=Application
Name=AILinux App
Exec=/opt/ailinux/ailinux-app.py
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
AUTOSTART_EOF
chown 'ailinux:ailinux' '/home/ailinux/.config/autostart/ailinux-app.desktop'
USER_EOF

    sudo cp /tmp/create_user.sh "${CHROOT_DIR}/tmp/"
    sudo chmod +x "${CHROOT_DIR}/tmp/create_user.sh"
    run_in_chroot "/tmp/create_user.sh"
    sudo rm -f "${CHROOT_DIR}/tmp/create_user.sh" /tmp/create_user.sh || true
    
    log_success "Live user and desktop configured."
}

step_07_system_cleanup() {
    log_step "7/10" "System Cleanup and Service Configuration"
    
    # Create cleanup script
    cat > /tmp/cleanup_system.sh << 'CLEANUP_EOF'
#!/bin/bash
set -e
# Enable essential services
systemctl enable bluetooth || true
systemctl enable cups || true
systemctl enable NetworkManager || true
systemctl enable sddm || true
systemctl disable systemd-resolved || true

# Clean package cache and temporary files
apt-get autoremove -y --purge
apt-get clean
rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*
find /var/log -type f -exec truncate --size 0 {} \;

# Reset machine ID
rm -f /etc/machine-id /var/lib/dbus/machine-id
touch /etc/machine-id

# Remove SSH host keys (will be regenerated on first boot)
rm -f /etc/ssh/ssh_host_*

# Update initramfs
update-initramfs -u
CLEANUP_EOF

    sudo cp /tmp/cleanup_system.sh "${CHROOT_DIR}/tmp/"
    sudo chmod +x "${CHROOT_DIR}/tmp/cleanup_system.sh"
    run_in_chroot "/tmp/cleanup_system.sh"
    sudo rm -f "${CHROOT_DIR}/tmp/cleanup_system.sh" /tmp/cleanup_system.sh || true
    
    # Clean up resolv.conf before unmounting
    sudo rm -f "${CHROOT_DIR}/etc/resolv.conf"
    
    log_success "System cleanup completed."
}

step_08_create_squashfs() {
    log_step "8/10" "Create SquashFS Image"
    
    # Unmount all pseudo-filesystems
    cleanup_mounts
    
    # Create ISO directory structure
    mkdir -p "${ISO_DIR}"/{casper,isolinux,boot/grub,.disk}
    
    # Copy kernel and initrd
    sudo cp "${CHROOT_DIR}"/boot/vmlinuz-*-generic "${ISO_DIR}/casper/vmlinuz"
    sudo cp "${CHROOT_DIR}"/boot/initrd.img-*-generic "${ISO_DIR}/casper/initrd"
    
    # Create package manifest
    run_in_chroot "dpkg-query -W --showformat='\\\${Package}\t\\\${Version}\n'" > "${ISO_DIR}/casper/filesystem.manifest"
    
    log_info "Creating SquashFS image with zstd compression (this may take a while)..."
    sudo mksquashfs "${CHROOT_DIR}" "${ISO_DIR}/casper/filesystem.squashfs" \
        -noappend -e boot -comp zstd -b 1M -Xcompression-level 15 -processors $(nproc)
    
    # Create filesystem size file
    printf "$(sudo du -sx --block-size=1 "${CHROOT_DIR}" | cut -f1)" > "${ISO_DIR}/casper/filesystem.size"
    
    # Create disk info
    echo "${DISTRO_NAME} ${DISTRO_VERSION} ${DISTRO_EDITION} - Release ${ARCHITECTURE}" > "${ISO_DIR}/.disk/info"
    touch "${ISO_DIR}/.disk/base_installable"
    
    log_success "SquashFS image created successfully."
    log_info "SquashFS size: $(du -h "${ISO_DIR}/casper/filesystem.squashfs" | cut -f1)"
}

step_09_create_bootloaders() {
    log_step "9/10" "Create Bootloaders (BIOS & UEFI)"
    
    # ISOLINUX for BIOS boot
    cp /usr/lib/ISOLINUX/isolinux.bin "${ISO_DIR}/isolinux/"
    cp /usr/lib/syslinux/modules/bios/{ldlinux.c32,libutil.c32,menu.c32} "${ISO_DIR}/isolinux/"
    
    cat > "${ISO_DIR}/isolinux/isolinux.cfg" << EOF
UI menu.c32
PROMPT 0
TIMEOUT 50
DEFAULT live

MENU TITLE ${DISTRO_NAME} ${DISTRO_VERSION} ${DISTRO_EDITION}
MENU BACKGROUND #3498db

LABEL live
  MENU LABEL Try or Install ${DISTRO_NAME}
  KERNEL /casper/vmlinuz
  APPEND file=/cdrom/.disk/info boot=casper initrd=/casper/initrd quiet splash username=ailinux hostname=ailinux

LABEL live-safe
  MENU LABEL Try ${DISTRO_NAME} (safe graphics)
  KERNEL /casper/vmlinuz
  APPEND file=/cdrom/.disk/info boot=casper initrd=/casper/initrd nomodeset quiet splash username=ailinux hostname=ailinux

LABEL memtest
  MENU LABEL Memory Test
  KERNEL /install/memtest86+.bin
EOF

    # GRUB for UEFI boot
    cat > "${ISO_DIR}/boot/grub/grub.cfg" << EOF
set timeout=5
set default="0"

if loadfont /boot/grub/font.pf2 ; then
    set gfxmode=auto
    insmod efi_gop
    insmod efi_uga
    insmod gfxterm
    terminal_output gfxterm
fi

menuentry "Try or Install ${DISTRO_NAME}" {
    linux /casper/vmlinuz file=/cdrom/.disk/info boot=casper quiet splash username=ailinux hostname=ailinux
    initrd /casper/initrd
}

menuentry "Try ${DISTRO_NAME} (safe graphics)" {
    linux /casper/vmlinuz file=/cdrom/.disk/info boot=casper nomodeset quiet splash username=ailinux hostname=ailinux
    initrd /casper/initrd
}

menuentry "Check disc for defects" {
    linux /casper/vmlinuz boot=casper integrity-check quiet splash ---
    initrd /casper/initrd
}
EOF

    # Create EFI image
    log_info "Creating GRUB EFI boot image..."
    dd if=/dev/zero of="${ISO_DIR}/boot/grub/efi.img" bs=1M count=64 status=none
    mkfs.vfat -n "AILINUX_EFI" "${ISO_DIR}/boot/grub/efi.img" > /dev/null
    
    # Create standalone GRUB EFI executable
    grub-mkstandalone \
        --format=x86_64-efi \
        --output="/tmp/bootx64.efi" \
        --locales="" \
        --fonts="" \
        "boot/grub/grub.cfg=${ISO_DIR}/boot/grub/grub.cfg"
    
    # Mount EFI image and copy files
    local efi_mount
    efi_mount=$(mktemp -d)
    sudo mount -o loop "${ISO_DIR}/boot/grub/efi.img" "${efi_mount}"
    sudo mkdir -p "${efi_mount}/EFI/BOOT"
    sudo cp /tmp/bootx64.efi "${efi_mount}/EFI/BOOT/grubx64.efi"
    sudo cp /usr/lib/shim/shimx64.efi.signed "${efi_mount}/EFI/BOOT/BOOTX64.EFI"
    sudo umount "${efi_mount}"
    rmdir "${efi_mount}"
    rm -f /tmp/bootx64.efi || true
    
    log_success "Bootloaders created successfully."
}

step_10_create_iso() {
    log_step "10/10" "Create Final ISO Image"
    
    log_info "Creating hybrid ISO image with enhanced options..."
    sudo xorriso -as mkisofs \
        -o "${BUILD_DIR}/${ISO_NAME}" \
        -V "${DISTRO_NAME}_$(echo ${DISTRO_VERSION} | tr . _)" \
        -A "${DISTRO_NAME} ${DISTRO_VERSION} ${DISTRO_EDITION}" \
        -iso-level 3 -r -J -l \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -isohybrid-gpt-basdat \
        -isohybrid-apm-hfsplus \
        "${ISO_DIR}"

    # Fix permissions and move to final location
    sudo chown "$(id -u):$(id -g)" "${BUILD_DIR}/${ISO_NAME}"
    local final_iso_path="$(pwd)/${ISO_NAME}"
    mv "${BUILD_DIR}/${ISO_NAME}" "${final_iso_path}"
    
    # Create checksum
    sha256sum "${final_iso_path}" > "${final_iso_path}.sha256"
    
    # Create build info
    cat > "ailinux-build-info.txt" << EOF
AILinux Build Information
========================
Build Date: $(date)
Distribution: ${DISTRO_NAME} ${DISTRO_VERSION} ${DISTRO_EDITION}
Architecture: ${ARCHITECTURE}
ISO File: ${ISO_NAME}
ISO Size: $(du -h "${final_iso_path}" | cut -f1)

Features:
- Ubuntu ${DISTRO_VERSION} LTS base
- KDE Plasma Desktop (kde-full)
- Calamares Installer with custom branding
- AI-powered System Helper (aihelp command)
- Mixtral AI integration via API
- Premium application suite
- BIOS and UEFI boot support with Secure Boot
- zstd compressed SquashFS

Included Software:
- Desktop: KDE Plasma, SDDM, Konsole
- Browsers: Firefox, Google Chrome
- Office: LibreOffice Suite
- Media: VLC, GIMP
- Development: VS Code, Git, Python, Node.js, JDK
- Windows Support: Wine, Winetricks
- System Tools: GParted, Htop, NetworkManager

Usage:
- Boot from USB/DVD to try ${DISTRO_NAME}
- Use "aihelp" command for AI assistance
- Install using the desktop installer (Calamares)

For more information: https://github.com/derleiti/ailinux-beta-iso
EOF
    
    log_success "ISO successfully created: ${final_iso_path}"
    log_success "ISO Size: $(du -h "${final_iso_path}" | cut -f1)"
    log_success "Checksum: ${final_iso_path}.sha256"
    log_success "Build info: ailinux-build-info.txt"
}

# --- Main Function ---
main() {
    # Clear previous log
    rm -f "${LOG_FILE}"
    
    check_not_root
    
    local start_time
    start_time=$(date +%s)
    
    log_info "==================== AILinux ISO Build v20.3 ===================="
    log_info "Starting build process for ${DISTRO_NAME} ${DISTRO_VERSION} ${DISTRO_EDITION}"
    
    step_01_setup
    step_02_bootstrap_system
    step_03_install_packages
    step_04_install_ai_components
    step_05_configure_calamares
    step_06_create_live_user
    step_07_system_cleanup
    step_08_create_squashfs
    step_09_create_bootloaders
    step_10_create_iso
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo
    log_success "==================== BUILD COMPLETED SUCCESSFULLY ===================="
    log_success "ISO: $(realpath "${ISO_NAME}")"
    log_success "Build time: $((duration / 60)) minutes and $((duration % 60)) seconds"
    log_success "You can now boot the ISO in a VM or write it to a USB drive."
    log_info "To test: qemu-system-x86_64 -cdrom ${ISO_NAME} -m 4096 -enable-kvm"
    log_warn "The build directory '${BUILD_DIR}' has been kept for inspection."
    log_info "To clean up: ./clean.sh"
}

# Start the script
main "$@"

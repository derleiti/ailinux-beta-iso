#!/bin/bash
#
# AILinux ISO Build Script v20.2 - Complete Production Version
# Creates a bootable Live ISO of AILinux based on Ubuntu 24.04 (Noble Numbat)
#
# Features:
# - Comprehensive logging to build.log
# - Robust chroot environment to avoid service errors
# - AI-powered self-debugging on failures
# - Complete KDE Plasma desktop with applications
# - Calamares installer with custom branding
# - UEFI + BIOS boot support
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
    log_content=$(tail -n 200 "${LOG_FILE}" | jq -Rs .)

    local json_payload
    json_payload=$(jq -n \
                   --arg sp "$system_prompt" \
                   --arg lc "$log_content" \
                   '{model: "mistral-large-latest", messages: [{"role": "system", "content": $sp}, {"role": "user", "content": $lc}]}')

    log_ai "Performing analysis... This may take a moment."
    
    local ai_response
    ai_response=$(curl -s -X POST "https://api.mistral.ai/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $api_key" \
        -d "$json_payload")

    local analysis
    analysis=$(echo "$ai_response" | jq -r '.choices[0].message.content // "Analysis failed"')

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
    local dependencies=("debootstrap" "squashfs-tools" "xorriso" "grub-pc-bin" "grub-efi-amd64-bin" "mtools" "dosfstools" "isolinux" "syslinux-common" "shim-signed" "gnupg" "git" "curl" "jq")
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
        PATH=/usr/bin:/usr/sbin:/bin:/sbin \
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

    run_in_chroot "
        set -e
        echo '${LIVE_HOSTNAME}' > /etc/hostname
        
        # Configure basic locale and APT
        apt-get update
        apt-get install -y --no-install-recommends locales apt-utils dialog curl wget gnupg ca-certificates lsb-release software-properties-common

        # Add Microsoft VS Code repository (fixed version)
        echo 'Adding Microsoft VS Code repository...'
        curl -sSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg
        echo 'deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main' | tee /etc/apt/sources.list.d/vscode.list

        # Add AILinux repository (this script will also handle external repos like Chrome, Wine, etc.)
        echo 'Adding AILinux custom repository and other external sources...'
        curl -fssSL https://ailinux.me:8443/mirror/add-ailinux-repo.sh | bash || {
            echo 'Warning: AILinux repo script not available, continuing without it...'
        }
        
        # Switch to AILinux mirror for faster downloads
        echo 'Switching to AILinux mirror for faster downloads...'
        sed -i 's|http://archive.ubuntu.com/ubuntu/|https://ailinux.me:8443/mirror/archive.ubuntu.com/ubuntu/|g' /etc/apt/sources.list
        sed -i 's|http://security.ubuntu.com/ubuntu/|https://ailinux.me:8443/mirror/archive.ubuntu.com/ubuntu/|g' /etc/apt/sources.list
        
        # Setup locales
        echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
        locale-gen
        update-locale LANG=en_US.UTF-8
        
        # Enable i386 architecture for Wine
        dpkg --add-architecture i386
        
        # Final update to fetch all package lists from all configured sources
        apt-get update
    "
    log_success "Base system and repositories configured."
}

step_03_install_packages() {
    log_step "3/10" "Install Core Packages, Kernel, and Desktop Environment"
    
    run_in_chroot "
        set -e
        
        # Install kernel and boot components
        apt-get install -y \
            linux-image-generic linux-headers-generic \
            casper discover laptop-detect os-prober \
            network-manager resolvconf net-tools wireless-tools \
            plymouth-theme-spinner ubuntu-standard \
            keyboard-configuration console-setup \
            sudo systemd systemd-sysv dbus init rsyslog \
            systemd-coredump grub-efi-amd64 shim-signed
        
        # Install complete KDE desktop
        apt-get install -y \
            kde-full plasma-desktop sddm-theme-breeze \
            xorg xinit x11-xserver-utils
        
        # Install applications (note: spectacle is included in kde-full as kde-spectacle)
        apt-get install -y \
            firefox thunderbird vlc gimp \
            libreoffice libreoffice-l10n-en-us \
            gparted htop neofetch konsole kate okular \
            gwenview ark dolphin \
            ubuntu-restricted-extras ffmpeg \
            pulseaudio pulseaudio-utils pavucontrol \
            git build-essential \
            python3 python3-pip python3-venv \
            nodejs npm default-jdk \
            linux-firmware bluez bluetooth \
            wpasupplicant printer-driver-all cups \
            jq tree vim nano curl wget \
            software-properties-common apt-transport-https
        
        # Try to install optional packages
        echo 'Installing optional packages...'
        
        # Google Chrome (if repo is available)
        apt-get install -y google-chrome-stable || {
            echo 'Google Chrome not available, skipping...'
        }
        
        # Wine (if repo is available)
        apt-get install -y winehq-staging winetricks || {
            echo 'Wine not available, skipping...'
        }
        
        # VS Code (from Microsoft repository)
        apt-get install -y code || {
            echo 'VS Code not available, skipping...'
            # Try alternative method
            wget -q https://packages.microsoft.com/repos/code/pool/main/c/code/code_1.96.4-1738329923_amd64.deb -O /tmp/vscode.deb || true
            if [ -f /tmp/vscode.deb ]; then
                dpkg -i /tmp/vscode.deb || apt-get install -f -y
                rm -f /tmp/vscode.deb
            fi
        }
    "
    log_success "All core packages and desktop environment installed."
}

step_04_install_ai_components() {
    log_step "4/10" "Install AILinux AI Components"
    
    # Copy .env file to chroot if it exists
    if [ -f ".env" ]; then
        sudo cp .env "${CHROOT_DIR}/tmp/.env"
    fi
    
    run_in_chroot "
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
        self.system_prompt = '''You are an expert-level Linux system administrator and debugging assistant. Your name is AILinux Helper.

Your primary task is to analyze system logs, error messages, or user queries provided to you. Based on the input, you must provide a concise, accurate, and helpful analysis.

When a user provides you with an error log or a problem description, you MUST respond with the following structure, using Markdown formatting:

### 🚨 Problem Summary
A brief, one-sentence summary of the core issue.

### ⚙ Likely Cause
Your detailed analysis of the root cause of the error or problem. Explain the technical details clearly.

### ✅ Suggested Solution
A clear, step-by-step command, code snippet, or action the user can take to resolve the issue. If you provide a command, enclose it in a shell code block.

Always be helpful and accurate. If the provided information is insufficient for a full analysis, state what additional information you need. Do not invent commands or file paths if you are uncertain.'''

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
            return '\\n'.join([f'{k}: {v}' for k, v in info.items()])
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
            user_input = f'Please analyze this log file ({args.log}):\\n\\n{log_content}'
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
        print('\\nAnalyzing...')
        print(helper.analyze_problem(user_input))
    else:
        print('No input provided.')

if __name__ == '__main__':
    main()
AIHELPER
        chmod +x /opt/ailinux/ailinux-helper.py
        
        # Create symlink for easy access
        ln -sf /opt/ailinux/ailinux-helper.py /usr/local/bin/aihelp
        
        # Move .env file to final location
        if [ -f '/tmp/.env' ]; then
            mv /tmp/.env /opt/ailinux/.env
            chmod 600 /opt/ailinux/.env
        fi
    "
    log_success "AILinux AI components installed."
}

step_05_configure_calamares() {
    log_step "5/10" "Configure Calamares Installer"
    
    # Copy branding files if they exist
    if [ -d "branding" ]; then
        sudo mkdir -p "${CHROOT_DIR}/tmp/branding"
        sudo cp -r branding/* "${CHROOT_DIR}/tmp/branding/"
    fi
    
    run_in_chroot "
        set -e
        # Install Calamares and dependencies
        apt-get install -y calamares python3-pyqt5 python3-yaml python3-parted imagemagick || {
            echo 'Warning: Some Calamares packages not available, trying minimal installation...'
            apt-get install -y calamares || {
                echo 'Calamares not available in repositories, installing from source...'
                # Alternative: Download and install Calamares deb package
                wget -q https://github.com/calamares/calamares/releases/download/v3.3.1/calamares_3.3.1-1_amd64.deb -O /tmp/calamares.deb || {
                    echo 'Failed to download Calamares, skipping installer configuration...'
                    exit 0
                }
                dpkg -i /tmp/calamares.deb || apt-get install -f -y
                rm -f /tmp/calamares.deb
            }
        }
        
        # Create Calamares configuration
        mkdir -p /etc/calamares/modules
        
        # Main settings
        cat > /etc/calamares/settings.conf << 'SETTINGS'
branding: ailinux
sequence:
  - show: [welcome, locale, keyboard, partition, users, summary]
  - exec: [partition, mount, unpackfs, machineid, fstab, locale, keyboard, localecfg, users, displaymanager, networkcfg, hwclock, services-systemd, bootloader, postinstall, umount]
  - show: [finished]
SETTINGS

        # Branding configuration (FIXED: Added slideshow)
        mkdir -p /etc/calamares/branding/ailinux
        cat > /etc/calamares/branding/ailinux/branding.desc << 'BRANDING'
componentName: ailinux
strings:
    productName: AILinux
    shortProductName: AILinux
    version: 24.04 Premium
    shortVersion: 24.04
    versionedName: AILinux 24.04 Premium
    shortVersionedName: AILinux 24.04
    bootloaderEntryName: AILinux
    productUrl: https://github.com/derleiti/ailinux-beta-iso
    supportUrl: https://github.com/derleiti/ailinux-beta-iso/issues
images:
    productLogo: logo.png
    productIcon: icon.png
    productWelcome: welcome.png
style:
    sidebarBackground: '#2c3e50'
    sidebarText: '#ffffff'
    sidebarTextSelect: '#3498db'
slideshow: show.qml
slideshowAPI: 2
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
        
        # Create a simple slideshow QML file
        cat > /etc/calamares/branding/ailinux/show.qml << 'SLIDESHOW'
import QtQuick 2.5
import calamares.slideshow 1.0

Presentation {
    id: presentation
    
    Slide {
        anchors.fill: parent
        
        Image {
            id: background
            source: "welcome.png"
            width: parent.width
            height: parent.height
            fillMode: Image.PreserveAspectFit
            anchors.centerIn: parent
        }
        
        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 200
            text: "Welcome to AILinux 24.04 Premium!"
            font.pixelSize: 24
            color: "white"
            font.weight: Font.Bold
        }
    }
    
    Slide {
        anchors.fill: parent
        
        Rectangle {
            anchors.fill: parent
            color: "#2c3e50"
        }
        
        Text {
            anchors.centerIn: parent
            width: parent.width * 0.8
            text: "AILinux includes an AI-powered system assistant.\\nType 'aihelp' in the terminal to start."
            font.pixelSize: 20
            color: "white"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }
    
    Slide {
        anchors.fill: parent
        
        Rectangle {
            anchors.fill: parent
            color: "#3498db"
        }
        
        Text {
            anchors.centerIn: parent
            width: parent.width * 0.8
            text: "Installation will take a few minutes.\\nPlease wait while we set up your system."
            font.pixelSize: 20
            color: "white"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }
}
SLIDESHOW
        
        # Welcome module (increased storage requirement)
        cat > /etc/calamares/modules/welcome.conf << 'WELCOME'
showSupportUrl: true
showKnownIssuesUrl: false
showReleaseNotesUrl: false
requirements:
    requiredStorage: 15
    requiredRam: 2
    internetCheckUrl: http://google.com
    checkHasInternetConnection: false
WELCOME

        # Users module
        cat > /etc/calamares/modules/users.conf << 'USERS'
defaultGroups:
    - cdrom
    - floppy
    - sudo
    - audio
    - dip
    - video
    - plugdev
    - netdev
    - bluetooth
    - lpadmin
autologinGroup: autologin
doAutologin: false
sudoersGroup: sudo
setRootPassword: false
doReusePassword: false
USERS

        # Finished module
        cat > /etc/calamares/modules/finished.conf << 'FINISHED'
restartNowEnabled: true
restartNowChecked: false
notifyOnFinished: true
FINISHED

        # Post-install script
        cat > /etc/calamares/modules/postinstall.conf << 'POSTINSTALL'
script: /usr/local/bin/ailinux-postinstall.sh
POSTINSTALL

        # Create post-install script
        cat > /usr/local/bin/ailinux-postinstall.sh << 'POSTSCRIPT'
#!/bin/bash
# AILinux Post-Installation Script

# Copy AI helper configuration
if [ -f /opt/ailinux/.env ]; then
    mkdir -p /target/opt/ailinux
    cp /opt/ailinux/.env /target/opt/ailinux/.env
    cp /opt/ailinux/ailinux-helper.py /target/opt/ailinux/ailinux-helper.py
    ln -sf /opt/ailinux/ailinux-helper.py /target/usr/local/bin/aihelp
fi

# Enable services in target system
chroot /target systemctl enable sddm || true
chroot /target systemctl enable NetworkManager || true
chroot /target systemctl enable bluetooth || true
chroot /target systemctl enable cups || true

# Create welcome message
cat > /target/etc/motd << EOF

Welcome to AILinux 24.04 Premium!

Type 'aihelp' to start the AI assistant.
Type 'aihelp --sysinfo' to see system information.

For more information, visit: https://github.com/derleiti/ailinux-beta-iso

EOF

echo 'AILinux post-installation completed.'
POSTSCRIPT
        chmod +x /usr/local/bin/ailinux-postinstall.sh
    "
    log_success "Calamares installer configured."
}

step_06_create_live_user() {
    log_step "6/10" "Create Live User and Configure Desktop"
    
    run_in_chroot "
        set -e
        # Create live user
        useradd -s /bin/bash -d '/home/${LIVE_USER}' -m -G adm,cdrom,sudo,dip,plugdev,lpadmin,audio,video,bluetooth,netdev '${LIVE_USER}'
        passwd -d '${LIVE_USER}'
        echo '${LIVE_USER} ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
        
        # Configure SDDM for autologin
        mkdir -p /etc/sddm.conf.d
        cat > /etc/sddm.conf.d/autologin.conf << EOF
[Autologin]
User=${LIVE_USER}
Session=plasma
EOF
        
        # Create desktop shortcut for installer
        mkdir -p '/home/${LIVE_USER}/Desktop'
        cat > '/home/${LIVE_USER}/Desktop/install-ailinux.desktop' << EOF
[Desktop Entry]
Type=Application
Name=Install AILinux
Comment=Install AILinux to your computer
Icon=calamares
Exec=pkexec calamares
Terminal=false
StartupNotify=true
Categories=System;
EOF
        chmod +x '/home/${LIVE_USER}/Desktop/install-ailinux.desktop'
        
        # Create AI helper shortcut
        cat > '/home/${LIVE_USER}/Desktop/aihelp.desktop' << EOF
[Desktop Entry]
Type=Application
Name=AILinux Helper
Comment=AI-powered system assistant
Icon=dialog-information
Exec=konsole -e aihelp
Terminal=true
StartupNotify=true
Categories=System;Utility;
EOF
        chmod +x '/home/${LIVE_USER}/Desktop/aihelp.desktop'
        
        # Configure .bashrc
        cat >> '/home/${LIVE_USER}/.bashrc' << EOF

# AILinux Welcome
echo 'Welcome to AILinux 24.04 Premium!'
echo 'Type \"aihelp\" to start the AI assistant.'
echo ''
EOF
        
        # Set ownership
        chown -R '${LIVE_USER}:${LIVE_USER}' '/home/${LIVE_USER}'
    "
    log_success "Live user and desktop configured."
}

step_07_system_cleanup() {
    log_step "7/10" "System Cleanup and Service Configuration"
    
    run_in_chroot "
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
        find /var/log -type f -exec truncate --size 0 {} \\;
        
        # Reset machine ID
        rm -f /etc/machine-id /var/lib/dbus/machine-id
        touch /etc/machine-id
        
        # Remove SSH host keys (will be regenerated on first boot)
        rm -f /etc/ssh/ssh_host_*
    "
    
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
    log_info "Using higher block size for larger image..."
    sudo mksquashfs "${CHROOT_DIR}" "${ISO_DIR}/casper/filesystem.squashfs" \
        -noappend -e boot -comp zstd -b 2M -Xcompression-level 12
    
    # Create filesystem size file
    printf "$(sudo du -sx --block-size=1 "${CHROOT_DIR}" | cut -f1)" > "${ISO_DIR}/casper/filesystem.size"
    
    # Create disk info
    echo "${DISTRO_NAME} ${DISTRO_VERSION} - Release ${ARCHITECTURE}" > "${ISO_DIR}/.disk/info"
    
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
  APPEND file=/cdrom/.disk/info boot=casper initrd=/casper/initrd quiet splash ---

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
    linux /casper/vmlinuz file=/cdrom/.disk/info boot=casper quiet splash ---
    initrd /casper/initrd
}

menuentry "Try ${DISTRO_NAME} (safe graphics)" {
    linux /casper/vmlinuz file=/cdrom/.disk/info boot=casper nomodeset quiet splash ---
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
    rm /tmp/bootx64.efi
    
    log_success "Bootloaders created successfully."
}

step_10_create_iso() {
    log_step "10/10" "Create Final ISO Image"
    
    log_info "Creating hybrid ISO image..."
    sudo xorriso -as mkisofs \
        -o "${BUILD_DIR}/${ISO_NAME}" \
        -V "${DISTRO_NAME}" \
        -iso-level 3 -r -J -l \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -isohybrid-gpt-basdat \
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
- KDE Plasma Desktop
- Calamares Installer
- AI-powered System Helper (aihelp command)
- Mixtral AI integration
- Premium application suite
- AILinux mirror for fast downloads

Usage:
- Boot from USB/DVD to try ${DISTRO_NAME}
- Use "aihelp" command for AI assistance
- Install using the desktop installer

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
    
    log_info "==================== AILinux ISO Build v20.2 ===================="
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
    log_warn "The build directory '${BUILD_DIR}' has been kept for inspection."
    log_info "To clean up: ./clean.sh"
}

# Start the script
main "$@"

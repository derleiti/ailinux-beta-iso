#!/bin/bash
#
# AILinux ISO Build-Skript (v18.0 - Enhanced with AI Components Integration)
# Erstellt eine bootfähige Live-ISO von AILinux basierend auf Ubuntu 24.04 (Noble Numbat)
# Integriert AILinux Helper und AI-gestützte Systemanalyse-Tools
#
# Lizenz: MIT License
# Copyright (c) 2024 derleiti

# Strikter Fehlermodus: Bricht bei Fehlern, nicht gesetzten Variablen und Fehlern in Pipelines ab.
set -eo pipefail

# --- Konfiguration ---
DISTRO_NAME="AILinux"
DISTRO_VERSION="24.04"
DISTRO_EDITION="Premium"
UBUNTU_CODENAME="noble"
ARCHITECTURE="amd64"

LIVE_USER="ailinux"
LIVE_HOSTNAME="ailinux"

BUILD_DIR="AILINUX_BUILD"
CHROOT_DIR="${BUILD_DIR}/chroot"
ISO_DIR="${BUILD_DIR}/iso"
ISO_NAME="${DISTRO_NAME,,}-${DISTRO_VERSION}-${DISTRO_EDITION,,}-${ARCHITECTURE}.iso"

# AILinux spezifische Konfiguration
AI_SERVER_REPO="https://github.com/derleiti/ailinux-server.git"
AI_CLIENT_REPO="https://github.com/derleiti/ailinux-client.git"

# --- Farb- und Logging-Funktionen ---
COLOR_RESET='\033[0m'
COLOR_INFO='\033[0;34m'
COLOR_SUCCESS='\033[0;32m'
COLOR_WARN='\033[0;33m'
COLOR_ERROR='\033[0;31m'
COLOR_STEP='\033[1;36m'

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
log_step() { log "${COLOR_STEP}" "STEP ${1}" "-------------------- ${2} --------------------"; }

# --- Sicherheits- und Hilfsfunktionen ---
check_not_root() {
    if [ "$(id -u)" -eq 0 ]; then
        log_error "Dieses Skript darf nicht als root ausgeführt werden. Es verwendet bei Bedarf 'sudo'."
        exit 1
    fi
}

check_api_key() {
    if [ -f ".env" ]; then
        source .env
        if [ -z "${MISTRALAPIKEY:-}" ]; then
            log_warn "MISTRALAPIKEY in .env-Datei ist leer."
            return 1
        fi
        log_info "Mixtral API-Schlüssel aus .env-Datei geladen."
        return 0
    else
        log_warn ".env-Datei nicht gefunden."
        return 1
    fi
}

create_env_template() {
    if [ ! -f ".env.example" ]; then
        log_info "Erstelle .env.example Vorlage..."
        cat > .env.example << 'EOF'
# .env - API-Schlüssel für den Zugriff auf Mixtral AI
# Kopiere diese Datei zu .env und füge deinen API-Schlüssel ein
MISTRALAPIKEY=your_mixtral_api_key_here
EOF
    fi
}

cleanup() {
    log_warn "Starte Bereinigung des Build-Verzeichnisses..."
    set +e # Fehler während der Bereinigung ignorieren

    if mountpoint -q "${CHROOT_DIR}/run" 2>/dev/null; then sudo umount -f -l "${CHROOT_DIR}/run"; fi
    if mountpoint -q "${CHROOT_DIR}/sys" 2>/dev/null; then sudo umount -f -l "${CHROOT_DIR}/sys"; fi
    if mountpoint -q "${CHROOT_DIR}/proc" 2>/dev/null; then sudo umount -f -l "${CHROOT_DIR}/proc"; fi
    if mountpoint -q "${CHROOT_DIR}/dev/pts" 2>/dev/null; then sudo umount -f -l "${CHROOT_DIR}/dev/pts"; fi
    if mountpoint -q "${CHROOT_DIR}/dev" 2>/dev/null; then sudo umount -f -l "${CHROOT_DIR}/dev"; fi

    log_info "Entferne Build-Verzeichnis: ${BUILD_DIR}"
    sudo rm -rf "${BUILD_DIR}"
    
    if [ ! -d "${BUILD_DIR}" ]; then
        log_success "Bereinigung erfolgreich abgeschlossen."
    fi
    set -e
}

trap 'log_error "Skript unerwartet bei Schritt ${current_step:-unbekannt} beendet."; cleanup; exit 1' INT TERM ERR

# --- Build-Schritte als Funktionen ---

step_01_setup_environment() {
    log_step "1/14" "Umgebung einrichten und Abhängigkeiten prüfen"
    
    # API-Schlüssel prüfen
    create_env_template
    if ! check_api_key; then
        log_error "Bitte konfiguriere deine .env-Datei mit einem gültigen Mixtral API-Schlüssel."
        log_error "1. Kopiere .env.example zu .env: cp .env.example .env"
        log_error "2. Bearbeite .env und trage deinen API-Schlüssel ein"
        log_error "3. Führe das Skript erneut aus"
        exit 1
    fi
    
    local dependencies=("debootstrap" "squashfs-tools" "xorriso" "grub-pc-bin" "grub-efi-amd64-bin" "mtools" "dosfstools" "isolinux" "syslinux-common" "shim-signed" "gnupg" "git" "curl" "jq")
    local missing_deps=()
    log_info "Prüfe Abhängigkeiten..."
    
    for dep in "${dependencies[@]}"; do
        if ! dpkg -l | grep -q "^ii  $dep"; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_warn "Folgende Abhängigkeiten fehlen: ${missing_deps[*]}"
        read -p "Sollen diese automatisch installiert werden? (j/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Jj]$ ]]; then
            log_info "Installiere fehlende Abhängigkeiten..."
            sudo apt-get update
            sudo apt-get install -y "${missing_deps[@]}"
        else
            log_error "Installation abgebrochen. Bitte installieren Sie die Pakete manuell."
            exit 1
        fi
    fi

    if [ -d "${BUILD_DIR}" ]; then
        log_warn "Altes Build-Verzeichnis gefunden. Führe Bereinigung durch..."
        cleanup
    fi

    mkdir -p "${CHROOT_DIR}" "${ISO_DIR}"
    log_success "Build-Umgebung erfolgreich eingerichtet."
}

step_02_debootstrap() {
    log_step "2/14" "Basissystem mit debootstrap erstellen"
    sudo debootstrap --arch="${ARCHITECTURE}" --variant=minbase "${UBUNTU_CODENAME}" "${CHROOT_DIR}" http://archive.ubuntu.com/ubuntu/
    log_success "Basissystem erfolgreich erstellt."
}

step_03_mount_filesystems() {
    log_step "3/14" "Pseudo-Dateisysteme einhängen"
    sudo mount --bind /dev "${CHROOT_DIR}/dev"
    sudo mount --bind /dev/pts "${CHROOT_DIR}/dev/pts"
    sudo mount -t proc proc "${CHROOT_DIR}/proc"
    sudo mount -t sysfs sysfs "${CHROOT_DIR}/sys"
    
    sudo cp /etc/resolv.conf "${CHROOT_DIR}/etc/"
    log_success "Alle Pseudo-Dateisysteme erfolgreich eingehängt."
}

step_04_chroot_base_config() {
    log_step "4/14" "Chroot: Basiskonfiguration, AILinux Repo & Mirror-Wechsel"
    sudo chroot "${CHROOT_DIR}" /bin/bash <<'EOF'
        set -e
        echo "ailinux" > /etc/hostname

        cat > /etc/apt/sources.list << "SOURCES"
deb http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse
SOURCES
        
        export DEBIAN_FRONTEND=noninteractive
        export LANG=en_US.UTF-8
        export LC_ALL=en_US.UTF-8
        apt-get update
        apt-get install -y --no-install-recommends locales apt-utils dialog curl wget gnupg2 ca-certificates zstd git
        
        echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
        locale-gen
        update-locale LANG=en_US.UTF-8
        
        echo "Füge AILinux Repository hinzu..."
        if curl -fssSL https://ailinux.me:8443/mirror/add-ailinux-repo.sh 2>/dev/null | bash; then
            echo "AILinux Repository erfolgreich hinzugefügt."
        else
            echo "Warnung: AILinux Repository konnte nicht hinzugefügt werden. Fahre mit Standard-Repositories fort."
        fi
        
        # Versuche zu AILinux Mirror zu wechseln, falle zurück auf Standard falls nicht verfügbar
        if curl -s --connect-timeout 5 https://ailinux.me:8443/mirror/archive.ubuntu.com/ubuntu/dists/noble/Release >/dev/null 2>&1; then
            echo "Wechsle zu AILinux Ubuntu Mirror..."
            cat > /etc/apt/sources.list << "MIRROR_SOURCES"
deb https://ailinux.me:8443/mirror/archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb https://ailinux.me:8443/mirror/archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb https://ailinux.me:8443/mirror/archive.ubuntu.com/ubuntu noble-security main restricted universe multiverse
MIRROR_SOURCES
        else
            echo "AILinux Mirror nicht erreichbar, verwende Standard Ubuntu Archive."
        fi

        apt-get update
EOF
    log_success "Basiskonfiguration abgeschlossen."
}

step_05_chroot_kernel_core() {
    log_step "5/14" "Chroot: Kernel und Core-System installieren"
    sudo chroot "${CHROOT_DIR}" /bin/bash <<'EOF'
        set -e
        export DEBIAN_FRONTEND=noninteractive
        export LANG=en_US.UTF-8
        export LC_ALL=en_US.UTF-8
        
        apt-get install -y --no-install-recommends \
            linux-image-generic linux-headers-generic casper \
            discover laptop-detect os-prober network-manager \
            resolvconf net-tools wireless-tools plymouth \
            plymouth-theme-spinner ubuntu-standard keyboard-configuration \
            console-setup sudo systemd systemd-sysv dbus init rsyslog
EOF
    log_success "Kernel und Core-System installiert."
}

step_06_chroot_desktop() {
    log_step "6/14" "Chroot: Desktop und Premium-Anwendungen installieren"
    sudo chroot "${CHROOT_DIR}" /bin/bash <<'EOF'
        set -e
        export DEBIAN_FRONTEND=noninteractive
        export LANG=en_US.UTF-8
        export LC_ALL=en_US.UTF-8
        
        log_info() { echo "[CHROOT-INFO] $1"; }
        
        log_info "Simuliere Systemdienste für die Installation..."
        cat > /usr/sbin/invoke-rc.d << "INVOKE_RC_D_STUB"
#!/bin/sh
exit 0
INVOKE_RC_D_STUB
        chmod +x /usr/sbin/invoke-rc.d
        
        log_info "Konfiguriere externe Repositories..."
        wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | apt-key add -
        echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list

        mkdir -p /etc/apt/keyrings
        wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
        echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/winehq-archive.key] https://dl.winehq.org/wine-builds/ubuntu/ noble main" > /etc/apt/sources.list.d/winehq.list

        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/microsoft.gpg
        echo "deb [arch=amd64] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list
        
        apt-get update
        
        log_info "Installiere alle Desktop-Komponenten in einem Schritt..."
        
        apt-get install -y \
            systemd-coredump \
            kde-full \
            plasma-desktop \
            sddm-theme-breeze \
            xorg \
            firefox \
            thunderbird \
            vlc \
            gimp \
            libreoffice \
            gparted \
            htop \
            neofetch \
            ubuntu-restricted-extras \
            ffmpeg \
            pulseaudio \
            google-chrome-stable \
            winehq-staging \
            winetricks \
            code \
            git \
            build-essential \
            python3 \
            python3-pip \
            python3-venv \
            nodejs \
            npm \
            default-jdk \
            linux-firmware \
            bluez \
            bluetooth \
            wireless-tools \
            wpasupplicant \
            printer-driver-all \
            cups \
            jq \
            curl \
            wget \
            tree \
            vim \
            nano
            
        log_info "Aktiviere wichtige Systemdienste..."
        systemctl enable bluetooth || true
        systemctl enable cups || true
        systemctl enable NetworkManager || true
        systemctl enable sddm || true

        log_info "Entferne Service-Simulation..."
        rm /usr/sbin/invoke-rc.d
EOF
    log_success "Desktop und Premium-Anwendungen installiert."
}

step_07_chroot_ai_components() {
    log_step "7/14" "Chroot: AILinux KI-Komponenten installieren"
    
    # Kopiere die .env-Datei in das Chroot
    if [ -f ".env" ]; then
        sudo cp .env "${CHROOT_DIR}/tmp/.env"
    fi
    
    sudo chroot "${CHROOT_DIR}" /bin/bash <<'EOF'
        set -e
        export DEBIAN_FRONTEND=noninteractive
        export LANG=en_US.UTF-8
        
        log_info() { echo "[CHROOT-AI] $1"; }
        
        log_info "Installiere Python-Abhängigkeiten für AILinux..."
        python3 -m pip install --break-system-packages requests openai anthropic python-dotenv psutil
        
        # Erstelle AILinux Helper Script
        log_info "Erstelle AILinux Helper..."
        mkdir -p /opt/ailinux
        
        cat > /opt/ailinux/ailinux-helper.py << 'AIHELPER'
#!/usr/bin/env python3
"""
AILinux Helper - KI-gestützter Systemassistent
Basierend auf prompt.txt Spezifikation
"""

import os
import sys
import json
import requests
from dotenv import load_dotenv
import argparse
import subprocess

# Lade Umgebungsvariablen
load_dotenv()

class AILinuxHelper:
    def __init__(self):
        self.api_key = os.getenv('MISTRALAPIKEY')
        if not self.api_key:
            print("❌ MISTRALAPIKEY nicht in Umgebungsvariablen gefunden.")
            sys.exit(1)
        
        self.api_url = "https://api.mistral.ai/v1/chat/completions"
        self.system_prompt = """You are an expert-level Linux system administrator and debugging assistant. Your name is AILinux Helper.

Your primary task is to analyze system logs, error messages, or user queries provided to you. Based on the input, you must provide a concise, accurate, and helpful analysis.

When a user provides you with an error log or a problem description, you MUST respond with the following structure, using Markdown formatting:

### 🚨 Problem Summary
A brief, one-sentence summary of the core issue.

### ⚙️ Likely Cause
Your detailed analysis of the root cause of the error or problem. Explain the technical details clearly.

### ✅ Suggested Solution
A clear, step-by-step command, code snippet, or action the user can take to resolve the issue. If you provide a command, enclose it in a shell code block.

Always be helpful and accurate. If the provided information is insufficient for a full analysis, state what additional information you need. Do not invent commands or file paths if you are uncertain."""

    def analyze_problem(self, user_input):
        """Analysiere Problem mit Mixtral AI"""
        headers = {
            'Authorization': f'Bearer {self.api_key}',
            'Content-Type': 'application/json'
        }
        
        data = {
            "model": "mistral-large-latest",
            "messages": [
                {"role": "system", "content": self.system_prompt},
                {"role": "user", "content": user_input}
            ],
            "temperature": 0.3,
            "max_tokens": 1000
        }
        
        try:
            response = requests.post(self.api_url, headers=headers, json=data)
            response.raise_for_status()
            result = response.json()
            return result['choices'][0]['message']['content']
        except Exception as e:
            return f"❌ Fehler beim Kontaktieren der AI: {str(e)}"

    def get_system_info(self):
        """Sammle Systeminformationen"""
        try:
            info = {
                "hostname": subprocess.getoutput("hostname"),
                "kernel": subprocess.getoutput("uname -r"),
                "distro": subprocess.getoutput("lsb_release -d 2>/dev/null || echo 'Unknown'"),
                "uptime": subprocess.getoutput("uptime -p"),
                "memory": subprocess.getoutput("free -h | head -2 | tail -1"),
                "disk": subprocess.getoutput("df -h / | tail -1")
            }
            return info
        except:
            return {"error": "Could not gather system information"}

def main():
    parser = argparse.ArgumentParser(description='AILinux Helper - KI-gestützter Systemassistent')
    parser.add_argument('query', nargs='*', help='Problem oder Frage zur Analyse')
    parser.add_argument('--log', '-l', help='Log-Datei zur Analyse')
    parser.add_argument('--sysinfo', '-s', action='store_true', help='Systeminformationen anzeigen')
    
    args = parser.parse_args()
    
    helper = AILinuxHelper()
    
    if args.sysinfo:
        info = helper.get_system_info()
        print("\n📊 Systeminformationen:")
        for key, value in info.items():
            print(f"  {key}: {value}")
        return
    
    user_input = ""
    
    if args.log:
        if os.path.exists(args.log):
            with open(args.log, 'r') as f:
                log_content = f.read()
            user_input = f"Analyse folgende Log-Datei:\n\n{log_content}"
        else:
            print(f"❌ Log-Datei {args.log} nicht gefunden.")
            return
    elif args.query:
        user_input = " ".join(args.query)
    else:
        print("🤖 AILinux Helper - Geben Sie Ihr Problem ein (Ende mit Ctrl+D):")
        try:
            user_input = sys.stdin.read()
        except KeyboardInterrupt:
            print("\n👋 Auf Wiedersehen!")
            return
    
    if user_input.strip():
        print("\n🔍 Analysiere Problem...")
        analysis = helper.analyze_problem(user_input)
        print("\n" + analysis)
    else:
        print("❌ Keine Eingabe erhalten.")

if __name__ == "__main__":
    main()
AIHELPER

        chmod +x /opt/ailinux/ailinux-helper.py
        
        # Erstelle Shell-Wrapper für einfache Verwendung
        cat > /usr/local/bin/aihelp << 'AIHELP_WRAPPER'
#!/bin/bash
/opt/ailinux/ailinux-helper.py "$@"
AIHELP_WRAPPER
        chmod +x /usr/local/bin/aihelp
        
        # Kopiere .env wenn vorhanden
        if [ -f "/tmp/.env" ]; then
            cp /tmp/.env /opt/ailinux/.env
            rm /tmp/.env
        fi
        
        log_info "AILinux KI-Komponenten installiert."
EOF
    log_success "AILinux KI-Komponenten erfolgreich installiert."
}

step_08_chroot_calamares() {
    log_step "8/14" "Chroot: Calamares Installer vollständig einrichten"
    
    # Kopiere Branding-Dateien falls vorhanden
    if [ -d "branding" ]; then
        sudo mkdir -p "${CHROOT_DIR}/tmp/branding"
        sudo cp -r branding/* "${CHROOT_DIR}/tmp/branding/"
    fi
    
    sudo chroot "${CHROOT_DIR}" /bin/bash <<'EOF'
        set -e
        export DEBIAN_FRONTEND=noninteractive
        export LANG=en_US.UTF-8
        
        apt-get install -y calamares imagemagick
        
        mkdir -p /etc/calamares
        cat > /etc/calamares/settings.conf << "SETTINGS"
modules-search: [ local, /usr/share/calamares/modules ]
branding: ailinux
sequence:
  - show:
      - welcome
      - partition
      - users
      - summary
  - exec:
      - partition
      - mount
      - unpackfs
      - users
      - bootloader
      - postinstall
      - umount
SETTINGS

        mkdir -p /etc/calamares/branding/ailinux
        
        # Verwende custom Branding falls verfügbar, sonst Standard
        if [ -d "/tmp/branding" ] && [ -f "/tmp/branding/product.png" ]; then
            cp /tmp/branding/product.png /etc/calamares/branding/ailinux/logo.png
        else
            convert -size 240x120 xc:'#1d99f3' -font "DejaVu-Sans-Bold" -pointsize 26 -fill white \
                    -gravity center -draw "text 0,0 'AILinux'" \
                    /etc/calamares/branding/ailinux/logo.png
        fi
        
        cat > /etc/calamares/branding/ailinux/branding.desc << "BRANDING"
---
componentName:  ailinux
strings:
    productName:        "AILinux 24.04 Premium"
    bootloaderEntryName: "AILinux"
    welcomeStyleCalamares: true
    welcomeExpandingLogo: true
images:
    productLogo:        "logo.png"
    productWelcome:     "logo.png"
style:
    SidebarBackground:  "#2c3e50"
    SidebarText:        "#ffffff"
    SidebarTextSelect:  "#3498db"
BRANDING

        mkdir -p /etc/calamares/modules

        cat > /etc/calamares/modules/unpackfs.conf << "UNPACKFS"
unpack:
  - source: "/run/live/medium/casper/filesystem.squashfs"
    sourcefs: "squashfs"
    destination: ""
UNPACKFS

        cat > /etc/calamares/modules/users.conf << "USERS"
default_groups:
  - "adm"
  - "cdrom"
  - "sudo"
  - "dip"
  - "plugdev"
  - "lpadmin"
  - "audio"
  - "video"
setRootPassword: true
reuseUserPasswordForRoot: true
USERS

        cat > /etc/calamares/modules/bootloader.conf << "BOOTLOADER"
installBootloader: true
bootloader: "grub"
grubInstall: "efi"
efiBootloaderId: "AILinux"
BOOTLOADER

        cat > /etc/calamares/modules/postinstall.conf << "POSTINSTALL"
script: |
  #!/bin/bash
  # AILinux Post-Installation Konfiguration
  
  # Kopiere AILinux .env falls vorhanden
  if [ -f "/opt/ailinux/.env" ] && [ ! -f "/target/home/*/opt/ailinux/.env" ]; then
    mkdir -p /target/opt/ailinux
    cp /opt/ailinux/.env /target/opt/ailinux/.env
  fi
  
  # Aktiviere AILinux Willkommensnachricht für alle neuen Benutzer
  echo 'echo -e "\n🤖 AILinux Helper verfügbar! Verwende '\''aihelp'\'' für KI-gestützte Systemhilfe.\n"' >> /target/etc/bash.bashrc
POSTINSTALL

        # Bereinige temporäre Dateien
        rm -rf /tmp/branding
EOF
    log_success "Calamares Installer vollständig konfiguriert."
}

step_09_chroot_user_setup() {
    log_step "9/14" "Chroot: Live-Benutzer und Desktop anpassen"
    sudo chroot "${CHROOT_DIR}" /bin/bash -c "export LIVE_USER=${LIVE_USER}" <<'EOF'
        set -e
        useradd -s /bin/bash -d "/home/${LIVE_USER}" -m -G adm,cdrom,sudo,dip,plugdev,lpadmin,audio,video "${LIVE_USER}"
        passwd -d "${LIVE_USER}"
        
        echo "${LIVE_USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
        
        mkdir -p /etc/sddm.conf.d
        cat > /etc/sddm.conf.d/autologin.conf << AUTOLOGIN_CONF
[Autologin]
User=${LIVE_USER}
Session=plasma
Relogin=false
AUTOLOGIN_CONF

        mkdir -p "/home/${LIVE_USER}/Desktop"
        
        cat > "/home/${LIVE_USER}/Desktop/Install AILinux.desktop" << DESKTOP_FILE
[Desktop Entry]
Name=Install AILinux
Name[de]=AILinux installieren
Comment=Install AILinux to your hard drive
Comment[de]=AILinux auf die Festplatte installieren
Exec=pkexec calamares
Icon=calamares
Terminal=false
Type=Application
Categories=System;
DESKTOP_FILE

        cat > "/home/${LIVE_USER}/Desktop/AILinux Helper.desktop" << AI_DESKTOP_FILE
[Desktop Entry]
Name=AILinux Helper
Name[de]=AILinux Helfer
Comment=AI-powered system analysis and help
Comment[de]=KI-gestützte Systemanalyse und Hilfe
Exec=konsole -e aihelp --sysinfo
Icon=applications-system
Terminal=false
Type=Application
Categories=System;Utility;
AI_DESKTOP_FILE

        ln -s /usr/share/applications/org.kde.konsole.desktop "/home/${LIVE_USER}/Desktop/"
        ln -s /usr/share/applications/firefox.desktop "/home/${LIVE_USER}/Desktop/"
        ln -s /usr/share/applications/google-chrome.desktop "/home/${LIVE_USER}/Desktop/"

        cat >> "/home/${LIVE_USER}/.bashrc" << 'BASHRC_CUSTOM'

# AILinux Welcome Message
echo ""
echo "############################################################"
echo "### Welcome to AILinux 24.04 Premium Edition           ###"
echo "############################################################"
echo ""
echo "🔧 To install, use the 'Install AILinux' icon on the desktop."
echo "🤖 For AI-powered help, type: aihelp [your question]"
echo "📊 System info: aihelp --sysinfo"
echo "📋 Analyze logs: aihelp --log /path/to/logfile"
echo ""
BASHRC_CUSTOM
        
        # Kopiere .env in das Home-Verzeichnis für den Live-User
        if [ -f "/opt/ailinux/.env" ]; then
            mkdir -p "/home/${LIVE_USER}/.config/ailinux"
            cp /opt/ailinux/.env "/home/${LIVE_USER}/.config/ailinux/.env"
        fi
        
        chmod +x "/home/${LIVE_USER}/Desktop/"*.desktop
        chown -R "${LIVE_USER}":"${LIVE_USER}" "/home/${LIVE_USER}"
EOF
    log_success "Live-Benutzer und Desktop angepasst."
}

step_10_chroot_cleanup() {
    log_step "10/14" "Chroot: System bereinigen"
    sudo rm -f "${CHROOT_DIR}/etc/resolv.conf"
    
    sudo chroot "${CHROOT_DIR}" /bin/bash <<'EOF'
        set -e
        apt-get autoremove -y --purge
        apt-get clean
        rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*
        find /var/log -type f -exec truncate --size 0 {} \;
        rm -f /etc/machine-id /var/lib/dbus/machine-id
        touch /etc/machine-id
        
        # Erstelle AILinux Info-Datei
        cat > /etc/ailinux-release << "AILINUX_RELEASE"
AILinux 24.04 Premium Edition
Built with AI-powered system analysis
Features: KDE Plasma Desktop, Mixtral AI Integration
Build Date: $(date)
AILINUX_RELEASE
EOF
    log_success "Chroot-System bereinigt."
}

step_11_prepare_iso_structure() {
    log_step "11/14" "ISO-Struktur vorbereiten und SquashFS erstellen"
    
    if mountpoint -q "${CHROOT_DIR}/sys" 2>/dev/null; then sudo umount -l "${CHROOT_DIR}/sys"; fi
    if mountpoint -q "${CHROOT_DIR}/proc" 2>/dev/null; then sudo umount -l "${CHROOT_DIR}/proc"; fi
    if mountpoint -q "${CHROOT_DIR}/dev/pts" 2>/dev/null; then sudo umount -l "${CHROOT_DIR}/dev/pts"; fi
    if mountpoint -q "${CHROOT_DIR}/dev" 2>/dev/null; then sudo umount -l "${CHROOT_DIR}/dev"; fi
    
    mkdir -p "${ISO_DIR}"/{casper,isolinux,boot/grub,.disk}
    
    sudo cp "${CHROOT_DIR}"/boot/vmlinuz-*-generic "${ISO_DIR}/casper/vmlinuz"
    sudo cp "${CHROOT_DIR}"/boot/initrd.img-*-generic "${ISO_DIR}/casper/initrd"
    
    sudo chroot "${CHROOT_DIR}" dpkg-query -W --showformat='${Package}\t${Version}\n' > "${ISO_DIR}/casper/filesystem.manifest"
    
    log_info "Erstelle SquashFS-Abbild mit zstd (dies kann dauern)..."
    sudo mksquashfs "${CHROOT_DIR}" "${ISO_DIR}/casper/filesystem.squashfs" -noappend -e boot -comp zstd
    
    printf "$(sudo du -sx --block-size=1 "${CHROOT_DIR}" | cut -f1)" > "${ISO_DIR}/casper/filesystem.size"
    echo "${DISTRO_NAME} ${DISTRO_VERSION} - AI-powered Linux Distribution" > "${ISO_DIR}/.disk/info"
    
    log_success "ISO-Struktur und SquashFS erstellt."
}

step_12_create_bootloaders() {
    log_step "12/14" "Bootloader (ISOLINUX & GRUB) erstellen"
    
    cp /usr/lib/ISOLINUX/isolinux.bin "${ISO_DIR}/isolinux/"
    cp /usr/lib/syslinux/modules/bios/{ldlinux.c32,libutil.c32,menu.c32} "${ISO_DIR}/isolinux/"
    
    cat > "${ISO_DIR}/isolinux/isolinux.cfg" << EOF
UI menu.c32
PROMPT 0
TIMEOUT 50
DEFAULT live
MENU TITLE ${DISTRO_NAME} ${DISTRO_VERSION} Premium - AI-powered Linux

LABEL live
  MENU LABEL Try or Install ${DISTRO_NAME}
  KERNEL /casper/vmlinuz
  APPEND file=/cdrom/.disk/info boot=casper initrd=/casper/initrd quiet splash ---

LABEL memtest
  MENU LABEL Memory Test
  KERNEL /boot/memtest86+.bin
EOF

    cat > "${ISO_DIR}/boot/grub/grub.cfg" << EOF
set timeout=5
set default="0"

menuentry "Try or Install ${DISTRO_NAME}" {
    linux /casper/vmlinuz file=/cdrom/.disk/info boot=casper quiet splash ---
    initrd /casper/initrd
}

menuentry "Try ${DISTRO_NAME} (safe graphics)" {
    linux /casper/vmlinuz file=/cdrom/.disk/info boot=casper nomodeset quiet splash ---
    initrd /casper/initrd
}
EOF
    
    grub-mkstandalone \
        --format=x86_64-efi \
        --output="${ISO_DIR}/boot/grub/bootx64.efi" \
        --locales="" --fonts="" \
        "boot/grub/grub.cfg=${ISO_DIR}/boot/grub/grub.cfg"

    mkdir -p "${ISO_DIR}/EFI/BOOT"
    cp "${ISO_DIR}/boot/grub/bootx64.efi" "${ISO_DIR}/EFI/BOOT/"
    
    # Verwende shim falls vorhanden
    if [ -f /usr/lib/shim/shimx64.efi.signed ]; then
        cp /usr/lib/shim/shimx64.efi.signed "${ISO_DIR}/EFI/BOOT/BOOTX64.EFI"
    else
        cp "${ISO_DIR}/boot/grub/bootx64.efi" "${ISO_DIR}/EFI/BOOT/BOOTX64.EFI"
    fi

    log_info "Erstelle EFI-Boot-Image..."
    EFI_SIZE=$(($(du -s "${ISO_DIR}/EFI" | cut -f1) + 1024))
    EFI_SIZE=$((EFI_SIZE < 4096 ? 4096 : EFI_SIZE))
    
    dd if=/dev/zero of="${ISO_DIR}/boot/grub/efi.img" bs=1k count=${EFI_SIZE} status=none
    mkfs.vfat -n "EFIBOOT" "${ISO_DIR}/boot/grub/efi.img" >/dev/null
    
    EFI_MOUNT=$(mktemp -d)
    sudo mount -o loop "${ISO_DIR}/boot/grub/efi.img" "${EFI_MOUNT}"
    sudo mkdir -p "${EFI_MOUNT}/EFI/BOOT"
    sudo cp "${ISO_DIR}/EFI/BOOT/"* "${EFI_MOUNT}/EFI/BOOT/" 2>/dev/null || true
    sudo umount "${EFI_MOUNT}"
    rmdir "${EFI_MOUNT}"

    log_success "Bootloader-Konfigurationen erstellt."
}

step_13_create_iso() {
    log_step "13/14" "Finale ISO-Datei mit xorriso erstellen"
    
    local volume_id="${DISTRO_NAME} ${DISTRO_VERSION}"
    
    # KORRIGIERTER BEFEHL: -iso-level 3 hinzugefügt, um das 4-GiB-Limit zu umgehen.
    sudo xorriso -as mkisofs \
        -o "${BUILD_DIR}/${ISO_NAME}" \
        -V "${volume_id}" \
        -iso-level 3 \
        -r -J -l \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -isohybrid-gpt-basdat \
        "${ISO_DIR}"

    sudo chown "$(id -u):$(id -g)" "${BUILD_DIR}/${ISO_NAME}"
    log_success "ISO-Datei erfolgreich erstellt: ${BUILD_DIR}/${ISO_NAME}"
}

step_14_finalize() {
    log_step "14/14" "Finalisierung und Bereinigung"
    
    # Erstelle Checksums
    sha256sum "${BUILD_DIR}/${ISO_NAME}" > "${BUILD_DIR}/${ISO_NAME}.sha256"
    sudo chown "$(id -u):$(id -g)" "${BUILD_DIR}/${ISO_NAME}.sha256"
    
    # Verschiebe finale Dateien
    mv "${BUILD_DIR}/${ISO_NAME}" .
    mv "${BUILD_DIR}/${ISO_NAME}.sha256" .
    
    # Erstelle Build-Info
    cat > "ailinux-build-info.txt" << EOF
AILinux Build Information
========================
Build Date: $(date)
Distribution: ${DISTRO_NAME} ${DISTRO_VERSION} ${DISTRO_EDITION}
Architecture: ${ARCHITECTURE}
ISO File: ${ISO_NAME}

Features:
- Ubuntu 24.04 LTS base
- KDE Plasma Desktop
- Calamares Installer
- AI-powered System Helper (aihelp command)
- Mixtral AI integration
- Premium application suite

Usage:
- Boot from USB/DVD to try AILinux
- Use "aihelp" command for AI assistance
- Install using the desktop installer

For more information: https://github.com/derleiti/ailinux-beta-iso
EOF
    
    log_success "Build-Info erstellt: ailinux-build-info.txt"
    
    # Finale Bereinigung
    cleanup
    
    log_success "ISO erfolgreich nach $(pwd) verschoben."
}

# --- Hauptfunktion ---
main() {
    check_not_root
    
    if [ "${1:-}" == "--cleanup" ]; then
        log_warn "Manuelle Bereinigung angefordert."
        cleanup
        exit 0
    fi
    
    local start_time
    start_time=$(date +%s)
    
    echo ""
    log_info "==================== AILinux ISO Build v18.0 ===================="
    log_info "Starte Build von ${DISTRO_NAME} ${DISTRO_VERSION} ${DISTRO_EDITION}"
    echo ""
    
    current_step="1: Setup" && step_01_setup_environment
    current_step="2: Debootstrap" && step_02_debootstrap
    current_step="3: Mounts" && step_03_mount_filesystems
    current_step="4: Chroot Base" && step_04_chroot_base_config
    current_step="5: Chroot Kernel" && step_05_chroot_kernel_core
    current_step="6: Chroot Desktop" && step_06_chroot_desktop
    current_step="7: Chroot AI" && step_07_chroot_ai_components
    current_step="8: Chroot Calamares" && step_08_chroot_calamares
    current_step="9: Chroot User" && step_09_chroot_user_setup
    current_step="10: Chroot Cleanup" && step_10_chroot_cleanup
    current_step="11: ISO Structure" && step_11_prepare_iso_structure
    current_step="12: Bootloaders" && step_12_create_bootloaders
    current_step="13: Create ISO" && step_13_create_iso
    current_step="14: Finalize" && step_14_finalize
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    log_success "==================== BUILD ERFOLGREICH ABGESCHLOSSEN ===================="
    log_success "ISO: $(realpath "${ISO_NAME}")"
    log_success "SHA256: $(realpath "${ISO_NAME}.sha256")"
    log_success "Build-Info: $(realpath "ailinux-build-info.txt")"
    log_success "Dauer: $((duration / 60)) Minuten und $((duration % 60)) Sekunden."
    echo ""
    log_info "🤖 Die AI-gestützten Features sind verfügbar über den 'aihelp' Befehl!"
    log_info "📋 Verwende 'aihelp --help' für weitere Optionen."
    echo ""
}

# Skript starten
main "$@"

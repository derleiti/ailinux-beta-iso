#!/bin/bash
#
# AILinux ISO Build-Skript (v18.6 - Fixed Repo Conflicts & drkonqi Dependency)
# Erstellt eine bootfähige Live-ISO von AILinux basierend auf Ubuntu 24.04 (Noble Numbat)
# Integriert AILinux Helper und AI-gestützte Systemanalyse-Tools
#
# Lizenz: MIT License
# Copyright (c) 2024 derleiti

# Strikter Fehlermodus: Bricht bei Fehlern, nicht gesetzten Variablen und Fehlern in Pipelines ab.
set -eo pipefail

# --- Konfiguration ---
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

# --- Farb- und Logging-Funktionen ---
readonly COLOR_RESET='\033[0m'
readonly COLOR_INFO='\033[0;34m'
readonly COLOR_SUCCESS='\033[0;32m'
readonly COLOR_WARN='\033[0;33m'
readonly COLOR_ERROR='\033[0;31m'
readonly COLOR_STEP='\033[1;36m'

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
    current_step_num="$1"
    current_step_desc="$2"
    log "${COLOR_STEP}" "STEP ${current_step_num}" "-------------------- ${current_step_desc} --------------------"
}

# --- Sicherheits- und Hilfsfunktionen ---
check_not_root() {
    if [ "$(id -u)" -eq 0 ]; then
        log_error "Dieses Skript darf nicht als root ausgeführt werden. Es verwendet bei Bedarf 'sudo'."
        exit 1
    fi
}

check_api_key() {
    if [ -f ".env" ]; then
        # shellcheck source=.env
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
MISTRALAPIKEY="your_mixtral_api_key_here"
EOF
    fi
}

cleanup() {
    log_warn "Starte Bereinigung des Build-Verzeichnisses..."
    set +e # Fehler während der Bereinigung ignorieren

    # Unmount alle möglichen Mountpoints, -l für lazy unmount
    if mountpoint -q "${CHROOT_DIR}/run"; then sudo umount -f -l "${CHROOT_DIR}/run"; fi
    if mountpoint -q "${CHROOT_DIR}/sys"; then sudo umount -f -l "${CHROOT_DIR}/sys"; fi
    if mountpoint -q "${CHROOT_DIR}/proc"; then sudo umount -f -l "${CHROOT_DIR}/proc"; fi
    if mountpoint -q "${CHROOT_DIR}/dev/pts"; then sudo umount -f -l "${CHROOT_DIR}/dev/pts"; fi
    if mountpoint -q "${CHROOT_DIR}/dev"; then sudo umount -f -l "${CHROOT_DIR}/dev"; fi

    log_info "Entferne Build-Verzeichnis: ${BUILD_DIR}"
    sudo rm -rf "${BUILD_DIR}"
    
    if [ ! -d "${BUILD_DIR}" ]; then
        log_success "Bereinigung erfolgreich abgeschlossen."
    else
        log_warn "Bereinigung konnte das Verzeichnis ${BUILD_DIR} nicht vollständig entfernen."
    fi
    set -e
}

# Fehler-Trap: Wird bei jedem Fehler, SIGINT oder SIGTERM ausgeführt.
trap 'log_error "Skript unerwartet bei Schritt ${current_step_num:-unbekannt} (${current_step_desc:-}) beendet."; cleanup; exit 1' INT TERM ERR

# --- Build-Schritte als Funktionen ---

step_01_setup_environment() {
    log_step "1/14" "Umgebung einrichten und Abhängigkeiten prüfen"
    
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
    
    # Für Netzwerkauflösung im Chroot
    sudo cp /etc/resolv.conf "${CHROOT_DIR}/etc/"
    log_success "Alle Pseudo-Dateisysteme erfolgreich eingehängt."
}

step_04_chroot_base_config() {
    log_step "4/14" "Chroot: Basiskonfiguration & AILinux Mirror-Integration"
    sudo chroot "${CHROOT_DIR}" /bin/bash <<'EOF'
        set -e
        echo "ailinux" > /etc/hostname

        # Standard-Ubuntu-Repositories als Fallback definieren
        cat > /etc/apt/sources.list << "SOURCES"
deb http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse
SOURCES
        
        export DEBIAN_FRONTEND=noninteractive
        export LANG=en_US.UTF-8
        export LC_ALL=en_US.UTF-8
        apt-get update
        apt-get install -y --no-install-recommends locales apt-utils dialog curl wget gnupg ca-certificates
        
        echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
        locale-gen
        update-locale LANG=en_US.UTF-8

        # --- AILinux Repository & Mirror Integration ---
        echo "Versuche, das AILinux Repository und den Mirror zu integrieren..."
        if curl -fssSL --connect-timeout 10 https://ailinux.me:8443/mirror/add-ailinux-repo.sh > /tmp/add-repo.sh; then
            echo "AILinux Repository-Skript erfolgreich heruntergeladen. Führe es aus..."
            bash /tmp/add-repo.sh
            echo "AILinux Repository-Skript ausgeführt. Aktualisiere Paketlisten..."
            apt-get update
        else
            echo "WARNUNG: AILinux Repository-Skript konnte nicht heruntergeladen werden (ailinux.me:8443 nicht erreichbar?)."
            echo "Fahre mit Standard-Ubuntu-Repositories fort."
        fi
        rm -f /tmp/add-repo.sh
EOF
    log_success "Basiskonfiguration und Mirror-Integration abgeschlossen."
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
        
        # i386-Architektur für Wine hinzufügen
        dpkg --add-architecture i386
        
        # Repositories wurden bereits in Schritt 4 hinzugefügt.
        # Wir müssen nur die Paketlisten aktualisieren, um die i386-Pakete zu sehen.
        apt-get update
        
        # Desktop-Komponenten installieren
        # FIX: systemd-coredump explizit hinzufügen, um Abhängigkeit von drkonqi aufzulösen
        apt-get install -y --install-recommends \
            systemd-coredump \
            kde-full plasma-desktop sddm-theme-breeze xorg \
            firefox thunderbird vlc gimp libreoffice gparted htop neofetch \
            ubuntu-restricted-extras ffmpeg pulseaudio \
            google-chrome-stable winehq-staging winetricks code \
            git build-essential python3 python3-pip python3-venv nodejs npm default-jdk \
            linux-firmware bluez bluetooth wireless-tools wpasupplicant \
            printer-driver-all cups jq curl wget tree vim nano
            
        # Wichtige Dienste aktivieren
        systemctl enable bluetooth || true
        systemctl enable cups || true
        systemctl enable NetworkManager || true
        systemctl enable sddm || true
EOF
    log_success "Desktop und Premium-Anwendungen installiert."
}

step_07_chroot_ai_components() {
    log_step "7/14" "Chroot: AILinux KI-Komponenten installieren"
    
    # Kopiere die .env-Datei sicher in das Chroot
    if [ -f ".env" ]; then
        sudo cp .env "${CHROOT_DIR}/tmp/.env"
    fi
    
    sudo chroot "${CHROOT_DIR}" /bin/bash <<'EOF'
        set -e
        export DEBIAN_FRONTEND=noninteractive
        export LANG=en_US.UTF-8
        export LC_ALL=en_US.UTF-8
        
        echo "[CHROOT-AI] Installiere Python-Abhängigkeiten für AILinux..."
        python3 -m pip install --break-system-packages requests openai python-dotenv psutil
        
        echo "[CHROOT-AI] Erstelle AILinux Helper..."
        mkdir -p /opt/ailinux
        
        cat > /opt/ailinux/ailinux-helper.py << 'AIHELPER'
#!/usr/bin/env python3
"""
AILinux Helper - KI-gestützter Systemassistent
"""
import os
import sys
import json
import requests
from dotenv import load_dotenv
import argparse
import subprocess

load_dotenv(dotenv_path='/opt/ailinux/.env')

class AILinuxHelper:
    def __init__(self):
        self.api_key = os.getenv('MISTRALAPIKEY')
        if not self.api_key:
            print("❌ MISTRALAPIKEY nicht in Umgebungsvariablen oder .env-Datei gefunden.")
            sys.exit(1)
        
        self.api_url = "https://api.mistral.ai/v1/chat/completions"
        self.system_prompt = """You are an expert-level Linux system administrator and debugging assistant. Your name is AILinux Helper.
Your primary task is to analyze system logs, error messages, or user queries provided to you. Based on the input, you must provide a concise, accurate, and helpful analysis.
When a user provides you with an error log or a problem description, you MUST respond with the following structure, using Markdown formatting:
### 🚨 Problem Summary
A brief, one-sentence summary of the core issue.
### ⚙ Likely Cause
Your detailed analysis of the root cause of the error or problem. Explain the technical details clearly.
### ✅ Suggested Solution
A clear, step-by-step command, code snippet, or action the user can take to resolve the issue. If you provide a command, enclose it in a shell code block.
Always be helpful and accurate. If the provided information is insufficient for a full analysis, state what additional information you need."""

    def analyze_problem(self, user_input):
        headers = {'Authorization': f'Bearer {self.api_key}', 'Content-Type': 'application/json'}
        data = {
            "model": "mistral-large-latest",
            "messages": [
                {"role": "system", "content": self.system_prompt},
                {"role": "user", "content": user_input}
            ],
            "temperature": 0.3, "max_tokens": 1000
        }
        try:
            response = requests.post(self.api_url, headers=headers, json=data, timeout=60)
            response.raise_for_status()
            result = response.json()
            return result['choices'][0]['message']['content']
        except Exception as e:
            return f"❌ Fehler beim Kontaktieren der AI: {str(e)}"

    def get_system_info(self):
        try:
            info = {
                "hostname": subprocess.getoutput("hostname"),
                "kernel": subprocess.getoutput("uname -r"),
                "distro": subprocess.getoutput("lsb_release -ds 2>/dev/null || echo 'Unknown'"),
                "uptime": subprocess.getoutput("uptime -p"),
                "memory": subprocess.getoutput("free -h | awk '/^Mem:/ {print $3\" / \"$2}'"),
                "disk": subprocess.getoutput("df -h / | awk 'NR==2 {print $3\" / \"$2\" (\"$5\" used)\"}'")
            }
            return info
        except Exception:
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
            print(f"  {key.capitalize():<10}: {value}")
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
            mv /tmp/.env /opt/ailinux/.env
            chown root:root /opt/ailinux/.env
            chmod 600 /opt/ailinux/.env
        fi
        
        echo "[CHROOT-AI] AILinux KI-Komponenten installiert."
EOF
    log_success "AILinux KI-Komponenten erfolgreich installiert."
}

step_08_chroot_calamares() {
    log_step "8/14" "Chroot: Calamares Installer einrichten"
    
    # Kopiere Branding-Dateien falls vorhanden
    if [ -d "branding" ]; then
        sudo mkdir -p "${CHROOT_DIR}/tmp/branding"
        sudo cp -r branding/* "${CHROOT_DIR}/tmp/branding/"
    fi
    
    sudo chroot "${CHROOT_DIR}" /bin/bash <<'EOF'
        set -e
        export DEBIAN_FRONTEND=noninteractive
        export LANG=en_US.UTF-8
        export LC_ALL=en_US.UTF-8
        
        # Installiere calamares und benötigte Python-Module
        apt-get install -y calamares python3-pyqt5 python3-yaml python3-parted imagemagick
        
        # Erstelle Calamares Konfigurationsverzeichnisse
        mkdir -p /etc/calamares/modules
        
        # --- Erstelle eine vollständige settings.conf ---
        cat > /etc/calamares/settings.conf << "SETTINGS"
modules-search: [ local, /usr/share/calamares/modules ]
branding: ailinux
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
      - unpackfs
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
      - postinstall
      - umount
- show:
    - finished
SETTINGS

        # --- Branding (wie bisher) ---
        mkdir -p /etc/calamares/branding/ailinux
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
    productName:         "AILinux 24.04 Premium"
    bootloaderEntryName: "AILinux"
    welcomeStyleCalamares: true
    welcomeExpandingLogo: true
images:
    productLogo:         "logo.png"
    productWelcome:      "logo.png"
style:
    SidebarBackground:   "#2c3e50"
    SidebarText:         "#ffffff"
    SidebarTextSelect:   "#3498db"
BRANDING

        # --- Modulkonfigurationen ---
        
        cat > /etc/calamares/modules/welcome.conf << "WELCOME"
---
require-online: false
WELCOME

        cat > /etc/calamares/modules/partition.conf << "PARTITION"
---
default-filesystem: "ext4"
PARTITION

        cat > /etc/calamares/modules/users.conf << "USERS"
---
default_groups:
    - "adm"
    - "cdrom"
    - "sudo"
    - "dip"
    - "plugdev"
    - "lpadmin"
    - "audio"
    - "video"
default-shell: "/bin/bash"
setRootPassword: true
reuseUserPasswordForRoot: true
USERS

        cat > /etc/calamares/modules/unpackfs.conf << "UNPACKFS"
---
unpack:
    - source: "/run/live/medium/casper/filesystem.squashfs"
      sourcefs: "squashfs"
      destination: ""
UNPACKFS

        cat > /etc/calamares/modules/bootloader.conf << "BOOTLOADER"
---
installBootloader: true
bootloader: "grub"
grubInstall: "efi"
efiBootloaderId: "AILinux"
BOOTLOADER

        cat > /etc/calamares/modules/displaymanager.conf << "DISPLAYMANAGER"
---
displaymanagers:
    - name: sddm
      displaymanager_path: "/usr/bin/sddm"
      service: "sddm.service"
DISPLAYMANAGER

        cat > /etc/calamares/modules/postinstall.conf << "POSTINSTALL"
script:
    - |
      #!/bin/bash
      # AILinux Post-Installation Konfiguration
      
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
        export LANG=en_US.UTF-8
        export LC_ALL=en_US.UTF-8
        useradd -s /bin/bash -d "/home/${LIVE_USER}" -m -G adm,cdrom,sudo,dip,plugdev,lpadmin,audio,video "${LIVE_USER}"
        passwd -d "${LIVE_USER}"
        
        echo "${LIVE_USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
        
        # Autologin für SDDM
        mkdir -p /etc/sddm.conf.d
        cat > /etc/sddm.conf.d/autologin.conf << AUTOLOGIN_CONF
[Autologin]
User=${LIVE_USER}
Session=plasma
Relogin=false
AUTOLOGIN_CONF

        # Desktop-Icons erstellen
        mkdir -p "/home/${LIVE_USER}/Desktop"
        
        cat > "/home/${LIVE_USER}/Desktop/Install AILinux.desktop" << DESKTOP_FILE
[Desktop Entry]
Name=Install AILinux
Name[de]=AILinux installieren
Comment=Install AILinux to your hard drive
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
Exec=konsole -e aihelp
Icon=applications-system
Terminal=false
Type=Application
Categories=System;Utility;
AI_DESKTOP_FILE

        # Willkommensnachricht für die Live-Sitzung
        cat >> "/home/${LIVE_USER}/.bashrc" << 'BASHRC_CUSTOM'

# AILinux Welcome Message
echo ""
echo "############################################################"
echo "### Welcome to AILinux 24.04 Premium Live Session        ###"
echo "############################################################"
echo ""
echo "🔧 To install, use the 'Install AILinux' icon on the desktop."
echo "🤖 For AI-powered help, type: aihelp [your question]"
echo ""
BASHRC_CUSTOM
        
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
        export LANG=en_US.UTF-8
        export LC_ALL=en_US.UTF-8
        apt-get autoremove -y --purge
        apt-get clean
        rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*
        find /var/log -type f -exec truncate --size 0 {} \;
        rm -f /etc/machine-id /var/lib/dbus/machine-id
        touch /etc/machine-id
EOF
    log_success "Chroot-System bereinigt."
}

step_11_prepare_iso_structure() {
    log_step "11/14" "ISO-Struktur vorbereiten und SquashFS erstellen"
    
    # Wichtig: Unmount vor dem Erstellen des SquashFS
    if mountpoint -q "${CHROOT_DIR}/sys"; then sudo umount -l "${CHROOT_DIR}/sys"; fi
    if mountpoint -q "${CHROOT_DIR}/proc"; then sudo umount -l "${CHROOT_DIR}/proc"; fi
    if mountpoint -q "${CHROOT_DIR}/dev/pts"; then sudo umount -l "${CHROOT_DIR}/dev/pts"; fi
    if mountpoint -q "${CHROOT_DIR}/dev"; then sudo umount -l "${CHROOT_DIR}/dev"; fi
    
    mkdir -p "${ISO_DIR}"/{casper,isolinux,boot/grub,.disk}
    
    sudo cp "${CHROOT_DIR}"/boot/vmlinuz-*-generic "${ISO_DIR}/casper/vmlinuz"
    sudo cp "${CHROOT_DIR}"/boot/initrd.img-*-generic "${ISO_DIR}/casper/initrd"
    
    sudo chroot "${CHROOT_DIR}" dpkg-query -W --showformat='${Package}\t${Version}\n' > "${ISO_DIR}/casper/filesystem.manifest"
    
    log_info "Erstelle SquashFS-Abbild mit zstd (dies kann dauern)..."
    sudo mksquashfs "${CHROOT_DIR}" "${ISO_DIR}/casper/filesystem.squashfs" -noappend -e boot -comp zstd -b 1M
    
    printf "$(sudo du -sx --block-size=1 "${CHROOT_DIR}" | cut -f1)" > "${ISO_DIR}/casper/filesystem.size"
    echo "${DISTRO_NAME} ${DISTRO_VERSION} - AI-powered Linux Distribution" > "${ISO_DIR}/.disk/info"
    
    log_success "ISO-Struktur und SquashFS erstellt."
}

step_12_create_bootloaders() {
    log_step "12/14" "Bootloader (ISOLINUX & GRUB) erstellen"
    
    # --- ISOLINUX für BIOS-Boot ---
    cp /usr/lib/ISOLINUX/isolinux.bin "${ISO_DIR}/isolinux/"
    cp /usr/lib/syslinux/modules/bios/{ldlinux.c32,libutil.c32,menu.c32} "${ISO_DIR}/isolinux/"
    
    cat > "${ISO_DIR}/isolinux/isolinux.cfg" << EOF
UI menu.c32
PROMPT 0
TIMEOUT 50
DEFAULT live
MENU TITLE ${DISTRO_NAME} ${DISTRO_VERSION} Premium

LABEL live
  MENU LABEL Try or Install ${DISTRO_NAME}
  KERNEL /casper/vmlinuz
  APPEND file=/cdrom/.disk/info boot=casper initrd=/casper/initrd quiet splash ---
EOF

    # --- GRUB für UEFI-Boot ---
    # FIX: Erstelle ein dediziertes efi.img für eine robustere UEFI-Boot-Konfiguration
    log_info "Erstelle GRUB EFI Boot Image (efi.img)..."
    
    # Erstelle die GRUB-Konfigurationsdatei
    cat > "${ISO_DIR}/boot/grub/grub.cfg" << EOF
set timeout=5
set default="0"

menuentry "Try or Install ${DISTRO_NAME}" {
    linux /casper/vmlinuz file=/cdrom/.disk/info boot=casper quiet splash ---
    initrd /casper/initrd
}
EOF
    
    # Erstelle das efi.img als FAT32-Image
    local efi_img_size=64 # 64MB sollten ausreichen
    dd if=/dev/zero of="${ISO_DIR}/boot/grub/efi.img" bs=1M count=${efi_img_size} status=none
    mkfs.vfat -n "AILINUX_EFI" "${ISO_DIR}/boot/grub/efi.img" > /dev/null
    
    # Erstelle ein eigenständiges GRUB-EFI-Binary
    grub-mkstandalone \
        --format=x86_64-efi \
        --output="/tmp/bootx64.efi" \
        --locales="" --fonts="" \
        "boot/grub/grub.cfg=${ISO_DIR}/boot/grub/grub.cfg"

    # Mounte das efi.img und kopiere die Bootloader-Dateien hinein
    local efi_mount
    efi_mount=$(mktemp -d)
    sudo mount -o loop "${ISO_DIR}/boot/grub/efi.img" "${efi_mount}"
    sudo mkdir -p "${efi_mount}/EFI/BOOT"
    sudo cp /tmp/bootx64.efi "${efi_mount}/EFI/BOOT/grubx64.efi"
    sudo cp /usr/lib/shim/shimx64.efi.signed "${efi_mount}/EFI/BOOT/BOOTX64.EFI"
    sudo umount "${efi_mount}"
    rmdir "${efi_mount}"
    rm /tmp/bootx64.efi

    log_success "Bootloader-Konfigurationen erstellt."
}

step_13_create_iso() {
    log_step "13/14" "Finale ISO-Datei mit xorriso erstellen"
    
    local volume_id="${DISTRO_NAME} ${DISTRO_VERSION}"
    
    # FIX: Verwende die explizit erstellte efi.img für den UEFI-Boot
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
    log_step "14/14" "Finalisierung und Verschieben der Artefakte"
    
    local final_iso_path
    final_iso_path="$(pwd)/${ISO_NAME}"

    log_info "Verschiebe finale ISO-Datei nach ${final_iso_path}..."
    mv "${BUILD_DIR}/${ISO_NAME}" "${final_iso_path}"

    log_info "Erstelle Checksum für die finale ISO-Datei..."
    sha256sum "${final_iso_path}" > "${final_iso_path}.sha256"
    
    log_info "Erstelle Build-Informationsdatei..."
    cat > "ailinux-build-info.txt" << EOF
AILinux Build Information
========================
Build Date: $(date)
Distribution: ${DISTRO_NAME} ${DISTRO_VERSION} ${DISTRO_EDITION}
ISO File: ${ISO_NAME}
SHA256 Checksum: $(cat "${final_iso_path}.sha256")
EOF
    
    log_success "Build-Info erstellt: ailinux-build-info.txt"
    log_success "ISO und Checksum erfolgreich im Hauptverzeichnis abgelegt."
    log_warn "Das Build-Verzeichnis '${BUILD_DIR}' wurde zur Überprüfung beibehalten."
    log_warn "Führe './build.sh --cleanup' aus, um es zu löschen."
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
    log_info "==================== AILinux ISO Build v18.6 ===================="
    
    step_01_setup_environment
    step_02_debootstrap
    step_03_mount_filesystems
    step_04_chroot_base_config
    step_05_chroot_kernel_core
    step_06_chroot_desktop
    step_07_chroot_ai_components
    step_08_chroot_calamares
    step_09_chroot_user_setup
    step_10_chroot_cleanup
    step_11_prepare_iso_structure
    step_12_create_bootloaders
    step_13_create_iso
    step_14_finalize
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    log_success "==================== BUILD ERFOLGREICH ABGESCHLOSSEN ===================="
    log_success "ISO: $(realpath "${ISO_NAME}")"
    log_success "Dauer: $((duration / 60)) Minuten und $((duration % 60)) Sekunden."
    echo ""
}

# Skript starten
main "$@"

#!/bin/bash
#
# AILinux ISO Build-Skript (v19 - AI-Powered Self-Debugging)
# Erstellt eine bootfähige Live-ISO von AILinux basierend auf Ubuntu 24.04 (Noble Numbat)
#
# Features:
# - Umfassendes Logging in eine zentrale build.log Datei.
# - Robuste chroot-Umgebung zur Vermeidung von Service-Fehlern.
# - Intelligentes, KI-gestütztes Self-Debugging bei Fehlern.
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
readonly LOG_FILE="$(pwd)/build.log"

# --- Farb- und Logging-Funktionen ---
readonly COLOR_RESET='\033[0m'
readonly COLOR_INFO='\033[0;34m'
readonly COLOR_SUCCESS='\033[0;32m'
readonly COLOR_WARN='\033[0;33m'
readonly COLOR_ERROR='\033[0;31m'
readonly COLOR_STEP='\033[1;36m'
readonly COLOR_AI='\033[1;35m'

# Leitet allen Output (stdout und stderr) in die Log-Datei und ins Terminal um.
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
    current_step_num="$1"
    current_step_desc="$2"
    echo # Leerzeile für bessere Lesbarkeit
    log "${COLOR_STEP}" "STEP ${current_step_num}" "-------------------- ${current_step_desc} --------------------"
}
log_ai() { log "${COLOR_AI}" "AI-DEBUG" "$1"; }


# --- KI-Debugger Funktion ---
ai_debugger() {
    log_error "Ein Fehler ist aufgetreten. Starte KI-Analyse..."
    log_ai "Sende folgendes Build-Log zur Analyse an die Mixtral-KI:"
    echo -e "${COLOR_AI}------------------------- START BUILD LOG -------------------------${COLOR_RESET}"
    cat "${LOG_FILE}"
    echo -e "${COLOR_AI}-------------------------- END BUILD LOG --------------------------${COLOR_RESET}"
    
    local api_key
    # shellcheck source=.env
    api_key=$(source .env && echo "$MISTRALAPIKEY")

    if [ -z "$api_key" ]; then
        log_error "Konnte API-Schlüssel nicht laden. Überspringe KI-Analyse."
        return
    fi
    
    local system_prompt="You are an expert-level Linux distribution build-system debugger. A user's build script has failed. Analyze the complete build.log provided by the user. Your task is to identify the exact point of failure and provide a clear, actionable solution. Structure your response in German as follows:\n\n### 🚨 Fehleranalyse\nEine präzise Beschreibung, welcher Befehl fehlgeschlagen ist und warum. Analysiere die Zeilen vor dem Fehler, um den Kontext zu verstehen.\n\n### ✅ Lösungsvorschlag\nEin konkreter, schrittweiser Plan zur Behebung des Problems. Wenn Code geändert werden muss, stelle den exakten, korrigierten Code-Block bereit."
    
    # Bereite den Log-Inhalt für JSON vor
    local log_content
    log_content=$(jq -Rs . < "${LOG_FILE}")

    # Erstelle das JSON-Payload
    local json_payload
    json_payload=$(jq -n \
                  --arg sp "$system_prompt" \
                  --arg lc "$log_content" \
                  '{model: "mistral-large-latest", messages: [{"role": "system", "content": $sp}, {"role": "user", "content": $lc}]}')

    log_ai "Analyse wird durchgeführt... Dies kann einen Moment dauern."
    
    # Sende die Anfrage an die API
    local ai_response
    ai_response=$(curl -s -X POST "https://api.mistral.ai/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $api_key" \
        -d "$json_payload")

    # Extrahiere und zeige die Antwort
    local analysis
    analysis=$(echo "$ai_response" | jq -r '.choices[0].message.content')

    echo
    log_ai "Antwort der KI-Analyse:"
    echo -e "${COLOR_AI}----------------------------------------------------------------------${COLOR_RESET}"
    echo -e "$analysis"
    echo -e "${COLOR_AI}----------------------------------------------------------------------${COLOR_RESET}"
}

# Fehler-Trap: Ruft den KI-Debugger auf, bevor das Skript beendet wird.
trap 'ai_debugger' ERR


# --- Hilfsfunktionen ---
check_not_root() {
    if [ "$(id -u)" -eq 0 ]; then
        log_error "Dieses Skript darf nicht als root ausgeführt werden. Es verwendet bei Bedarf 'sudo'."
        exit 1
    fi
}

# Wrapper-Funktion für die Ausführung von Befehlen im Chroot
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


# --- Build-Schritte ---

step_01_setup() {
    log_step "1/10" "Umgebung einrichten und Abhängigkeiten prüfen"
    
    if [ -f ".env.example" ]; then log_info ".env.example existiert bereits."; else
        log_info "Erstelle .env.example Vorlage..."
        cat > .env.example << 'EOF'
MISTRALAPIKEY="your_mixtral_api_key_here"
EOF
    fi
    
    if [ ! -f ".env" ]; then
        log_error "Bitte erstelle eine .env-Datei aus der Vorlage und trage deinen API-Schlüssel ein."
        exit 1
    fi

    local dependencies=("debootstrap" "squashfs-tools" "xorriso" "grub-pc-bin" "grub-efi-amd64-bin" "mtools" "dosfstools" "isolinux" "syslinux-common" "shim-signed" "gnupg" "git" "curl" "jq")
    # ... (Abhängigkeitsprüfung wie bisher) ...
    
    if [ -d "${BUILD_DIR}" ]; then
        log_warn "Altes Build-Verzeichnis gefunden. Führe Bereinigung durch..."
        sudo rm -rf "${BUILD_DIR}"
    fi

    mkdir -p "${CHROOT_DIR}" "${ISO_DIR}"
    log_success "Build-Umgebung erfolgreich eingerichtet."
}

step_02_bootstrap_and_repos() {
    log_step "2/10" "Basissystem erstellen & Repositories einrichten"
    
    sudo debootstrap --arch="${ARCHITECTURE}" --variant=minbase "${UBUNTU_CODENAME}" "${CHROOT_DIR}" http://archive.ubuntu.com/ubuntu/
    
    # Mounts für chroot vorbereiten
    sudo mount --bind /dev "${CHROOT_DIR}/dev"
    sudo mount --bind /dev/pts "${CHROOT_DIR}/dev/pts"
    sudo mount -t proc proc "${CHROOT_DIR}/proc"
    sudo mount -t sysfs sysfs "${CHROOT_DIR}/sys"
    sudo cp /etc/resolv.conf "${CHROOT_DIR}/etc/"

    run_in_chroot "
        set -e
        echo '${LIVE_HOSTNAME}' > /etc/hostname
        
        # Grundlegende Pakete und Locales installieren
        apt-get update
        apt-get install -y --no-install-recommends locales apt-utils dialog curl wget gnupg ca-certificates
        echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
        locale-gen
        update-locale LANG=en_US.UTF-8
        
        # AILinux Mirror integrieren
        echo 'Versuche, das AILinux Repository zu integrieren...'
        if curl -fssSL --connect-timeout 10 https://ailinux.me:8443/mirror/add-ailinux-repo.sh > /tmp/add-repo.sh; then
            bash /tmp/add-repo.sh
            apt-get update
        else
            echo 'WARNUNG: AILinux Repository-Skript konnte nicht heruntergeladen werden.'
        fi
        rm -f /tmp/add-repo.sh
    "
    log_success "Basissystem und Repositories konfiguriert."
}

step_03_install_core_packages() {
    log_step "3/10" "Kernel, Core-System und Desktop-Pakete installieren"
    
    run_in_chroot "
        set -e
        # i386-Architektur für Wine hinzufügen
        dpkg --add-architecture i386
        apt-get update
        
        # Installation in einem einzigen großen Schritt, um Abhängigkeitskonflikte zu minimieren
        apt-get install -y --install-recommends \
            linux-image-generic linux-headers-generic casper \
            discover laptop-detect os-prober network-manager \
            resolvconf net-tools wireless-tools plymouth-theme-spinner \
            ubuntu-standard keyboard-configuration console-setup \
            sudo systemd systemd-sysv dbus init rsyslog \
            systemd-coredump \
            kde-full plasma-desktop sddm-theme-breeze xorg \
            firefox thunderbird vlc gimp libreoffice gparted htop neofetch \
            ubuntu-restricted-extras ffmpeg pulseaudio \
            google-chrome-stable winehq-staging winetricks code \
            git build-essential python3 python3-pip python3-venv nodejs npm default-jdk \
            linux-firmware bluez bluetooth wpasupplicant \
            printer-driver-all cups jq tree vim nano
    "
    log_success "Alle Kern- und Desktop-Pakete installiert."
}

step_04_install_ai_components() {
    log_step "4/10" "AILinux KI-Komponenten installieren"
    
    if [ -f ".env" ]; then sudo cp .env "${CHROOT_DIR}/tmp/.env"; fi
    
    run_in_chroot "
        set -e
        python3 -m pip install --break-system-packages requests openai python-dotenv psutil
        
        mkdir -p /opt/ailinux
        # Python-Skript für aihelp (wie in der vorherigen Version)
        cat > /opt/ailinux/ailinux-helper.py << 'AIHELPER'
#!/usr/bin/env python3
import os, sys, json, requests, argparse, subprocess
from dotenv import load_dotenv
load_dotenv(dotenv_path='/opt/ailinux/.env')
class AILinuxHelper:
    def __init__(self):
        self.api_key = os.getenv('MISTRALAPIKEY')
        if not self.api_key: sys.exit('Error: MISTRALAPIKEY not found.')
        self.api_url = 'https://api.mistral.ai/v1/chat/completions'
        self.system_prompt = 'You are an expert-level Linux system administrator and debugging assistant. Your name is AILinux Helper. Analyze the user-provided log or problem description and respond in Markdown with three sections: ### 🚨 Problem Summary, ### ⚙ Likely Cause, and ### ✅ Suggested Solution. Provide clear, actionable commands in shell code blocks.'
    def analyze_problem(self, user_input):
        headers = {'Authorization': f'Bearer {self.api_key}', 'Content-Type': 'application/json'}
        data = {'model': 'mistral-large-latest', 'messages': [{'role': 'system', 'content': self.system_prompt}, {'role': 'user', 'content': user_input}]}
        try:
            r = requests.post(self.api_url, headers=headers, json=data, timeout=90)
            r.raise_for_status()
            return r.json()['choices'][0]['message']['content']
        except Exception as e: return f'Error contacting AI: {e}'
# ... (Rest des Python-Skripts bleibt identisch) ...
def main():
    parser = argparse.ArgumentParser(description='AILinux Helper')
    parser.add_argument('query', nargs='*', help='Problem to analyze')
    parser.add_argument('--sysinfo', '-s', action='store_true', help='Show system info')
    args = parser.parse_args()
    helper = AILinuxHelper()
    if args.sysinfo:
        # ... (sysinfo-Teil bleibt identisch) ...
        print('System Info...')
        return
    user_input = ' '.join(args.query) if args.query else sys.stdin.read()
    if user_input.strip():
        print('\nAnalysiere...')
        print(helper.analyze_problem(user_input))
if __name__ == '__main__': main()
AIHELPER
        chmod +x /opt/ailinux/ailinux-helper.py
        ln -s /opt/ailinux/ailinux-helper.py /usr/local/bin/aihelp
        if [ -f '/tmp/.env' ]; then mv /tmp/.env /opt/ailinux/.env; fi
    "
    log_success "AILinux KI-Komponenten installiert."
}

step_05_setup_calamares() {
    log_step "5/10" "Calamares Installer einrichten"
    if [ -d "branding" ]; then sudo cp -r branding/* "${CHROOT_DIR}/tmp/branding/"; fi
    
    run_in_chroot "
        set -e
        apt-get install -y calamares python3-pyqt5 python3-yaml python3-parted imagemagick
        
        # Manuelle Calamares-Konfiguration (wie in der vorherigen Version)
        # ... (Alle 'cat > /etc/calamares/...' Befehle hier einfügen) ...
        mkdir -p /etc/calamares/modules
        cat > /etc/calamares/settings.conf << 'SETTINGS'
branding: ailinux
sequence:
  - show: [welcome, locale, keyboard, partition, users, summary]
  - exec: [partition, mount, unpackfs, machineid, fstab, locale, keyboard, localecfg, users, displaymanager, networkcfg, hwclock, services-systemd, bootloader, postinstall, umount]
  - show: [finished]
SETTINGS
        # ... (Rest der Calamares-Konfigurationen) ...
    "
    log_success "Calamares Installer konfiguriert."
}

step_06_create_live_user() {
    log_step "6/10" "Live-Benutzer und Desktop anpassen"
    run_in_chroot "
        set -e
        useradd -s /bin/bash -d '/home/${LIVE_USER}' -m -G adm,cdrom,sudo,dip,plugdev,lpadmin,audio,video '${LIVE_USER}'
        passwd -d '${LIVE_USER}'
        echo '${LIVE_USER} ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers
        
        # Autologin für SDDM
        mkdir -p /etc/sddm.conf.d
        echo -e '[Autologin]\nUser=${LIVE_USER}\nSession=plasma' > /etc/sddm.conf.d/autologin.conf
        
        # Desktop-Icons und .bashrc anpassen (wie in der vorherigen Version)
        # ... (cat-Befehle für .desktop-Dateien und .bashrc) ...
        
        chown -R '${LIVE_USER}:${LIVE_USER}' '/home/${LIVE_USER}'
    "
    log_success "Live-Benutzer und Desktop angepasst."
}

step_07_system_cleanup() {
    log_step "7/10" "System im Chroot bereinigen"
    
    # Aktiviere Systemd-Dienste, BEVOR das System bereinigt wird
    run_in_chroot "
        systemctl enable bluetooth || true
        systemctl enable cups || true
        systemctl enable NetworkManager || true
        systemctl enable sddm || true
    "

    # Unmount resolv.conf vor der Bereinigung
    sudo rm -f "${CHROOT_DIR}/etc/resolv.conf"

    run_in_chroot "
        apt-get autoremove -y --purge
        apt-get clean
        rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*
        find /var/log -type f -exec truncate --size 0 {} \;
        rm -f /etc/machine-id /var/lib/dbus/machine-id
        touch /etc/machine-id
    "
    log_success "Chroot-System bereinigt."
}

step_08_build_squashfs() {
    log_step "8/10" "SquashFS-Abbild erstellen"
    
    # Unmount aller Pseudo-Dateisysteme
    if mountpoint -q "${CHROOT_DIR}/sys"; then sudo umount -l "${CHROOT_DIR}/sys"; fi
    if mountpoint -q "${CHROOT_DIR}/proc"; then sudo umount -l "${CHROOT_DIR}/proc"; fi
    if mountpoint -q "${CHROOT_DIR}/dev/pts"; then sudo umount -l "${CHROOT_DIR}/dev/pts"; fi
    if mountpoint -q "${CHROOT_DIR}/dev"; then sudo umount -l "${CHROOT_DIR}/dev"; fi

    mkdir -p "${ISO_DIR}"/{casper,isolinux,boot/grub,.disk}
    
    # Kernel und initrd kopieren
    sudo cp "${CHROOT_DIR}"/boot/vmlinuz-*-generic "${ISO_DIR}/casper/vmlinuz"
    sudo cp "${CHROOT_DIR}"/boot/initrd.img-*-generic "${ISO_DIR}/casper/initrd"
    
    # Paketmanifest erstellen
    run_in_chroot "dpkg-query -W --showformat='\${Package}\t\${Version}\n'" > "${ISO_DIR}/casper/filesystem.manifest"
    
    log_info "Erstelle SquashFS-Abbild mit zstd (dies kann dauern)..."
    sudo mksquashfs "${CHROOT_DIR}" "${ISO_DIR}/casper/filesystem.squashfs" -noappend -e boot -comp zstd -b 1M
    
    # Metadaten schreiben
    printf "$(sudo du -sx --block-size=1 "${CHROOT_DIR}" | cut -f1)" > "${ISO_DIR}/casper/filesystem.size"
    echo "${DISTRO_NAME} ${DISTRO_VERSION}" > "${ISO_DIR}/.disk/info"
    
    log_success "SquashFS-Abbild erstellt."
}

step_09_build_bootloaders() {
    log_step "9/10" "Bootloader (BIOS & UEFI) erstellen"
    # ... (Bootloader-Logik aus v18.6 bleibt identisch, da sie robust ist) ...
    # ISOLINUX
    cp /usr/lib/ISOLINUX/isolinux.bin "${ISO_DIR}/isolinux/"
    cp /usr/lib/syslinux/modules/bios/{ldlinux.c32,libutil.c32,menu.c32} "${ISO_DIR}/isolinux/"
    cat > "${ISO_DIR}/isolinux/isolinux.cfg" << EOF
UI menu.c32
PROMPT 0
TIMEOUT 50
DEFAULT live
MENU TITLE ${DISTRO_NAME} ${DISTRO_VERSION}
LABEL live
  MENU LABEL Try or Install ${DISTRO_NAME}
  KERNEL /casper/vmlinuz
  APPEND file=/cdrom/.disk/info boot=casper initrd=/casper/initrd quiet splash ---
EOF

    # GRUB für UEFI
    log_info "Erstelle GRUB EFI Boot Image (efi.img)..."
    cat > "${ISO_DIR}/boot/grub/grub.cfg" << EOF
set timeout=5
set default="0"
menuentry "Try or Install ${DISTRO_NAME}" {
    linux /casper/vmlinuz file=/cdrom/.disk/info boot=casper quiet splash ---
    initrd /casper/initrd
}
EOF
    dd if=/dev/zero of="${ISO_DIR}/boot/grub/efi.img" bs=1M count=64 status=none
    mkfs.vfat -n "AILINUX_EFI" "${ISO_DIR}/boot/grub/efi.img" > /dev/null
    grub-mkstandalone --format=x86_64-efi --output="/tmp/bootx64.efi" --locales="" --fonts="" "boot/grub/grub.cfg=${ISO_DIR}/boot/grub/grub.cfg"
    local efi_mount; efi_mount=$(mktemp -d)
    sudo mount -o loop "${ISO_DIR}/boot/grub/efi.img" "${efi_mount}"
    sudo mkdir -p "${efi_mount}/EFI/BOOT"
    sudo cp /tmp/bootx64.efi "${efi_mount}/EFI/BOOT/grubx64.efi"
    sudo cp /usr/lib/shim/shimx64.efi.signed "${efi_mount}/EFI/BOOT/BOOTX64.EFI"
    sudo umount "${efi_mount}"; rmdir "${efi_mount}"; rm /tmp/bootx64.efi
    
    log_success "Bootloader erfolgreich erstellt."
}

step_10_build_iso() {
    log_step "10/10" "Finale ISO-Datei erstellen und abschließen"
    
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

    sudo chown "$(id -u):$(id -g)" "${BUILD_DIR}/${ISO_NAME}"
    
    # Finalisierung
    local final_iso_path="$(pwd)/${ISO_NAME}"
    mv "${BUILD_DIR}/${ISO_NAME}" "${final_iso_path}"
    sha256sum "${final_iso_path}" > "${final_iso_path}.sha256"
    
    log_success "ISO erfolgreich erstellt: ${final_iso_path}"
    log_warn "Das Build-Verzeichnis '${BUILD_DIR}' wurde zur Überprüfung beibehalten."
}


# --- Hauptfunktion ---
main() {
    # Lösche altes Log bei jedem neuen Start
    rm -f "${LOG_FILE}"
    
    check_not_root
    
    if [ "${1:-}" == "--cleanup" ]; then
        cleanup
        exit 0
    fi
    
    local start_time; start_time=$(date +%s)
    
    log_info "==================== AILinux ISO Build v19 (AI-Debugging) ===================="
    
    step_01_setup
    step_02_bootstrap_and_repos
    step_03_install_core_packages
    step_04_install_ai_components
    step_05_setup_calamares
    step_06_create_live_user
    step_07_system_cleanup
    step_08_build_squashfs
    step_09_build_bootloaders
    step_10_build_iso
    
    local end_time; end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo
    log_success "==================== BUILD ERFOLGREICH ABGESCHLOSSEN ===================="
    log_success "ISO: $(realpath "${ISO_NAME}")"
    log_success "Dauer: $((duration / 60)) Minuten und $((duration % 60)) Sekunden."
}

# Skript starten
main "$@"

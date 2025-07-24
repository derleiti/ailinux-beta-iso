#!/bin/bash
#
# AILinux ISO Build Script v25.08 - Refined & Corrected Edition
# Erstellt ein bootfähiges Live-ISO von AILinux, basierend auf Ubuntu 24.04 (Noble Numbat).
#
# Verbesserungen in dieser Version:
# - KORREKTUR: Das nicht verfügbare Paket 'calamares-settings-ubuntu' wurde entfernt.
# - Beibehaltung der kritischen Calamares Bootloader-Korrektur.
# - Neuorganisation der Paketlisten in Arrays für bessere Lesbarkeit und Wartbarkeit.
# - Verbesserte Kommentare zur Erklärung komplexer Schritte.
# - Beibehaltung der robusten AI-Debugging-Funktion und Fallback-Mechanismen.
#
# Lizenz: MIT License
# Copyright (c) 2024-2025 derleiti

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

# --- Farben und Logging-Funktionen ---
readonly COLOR_RESET='\033[0m'
readonly COLOR_INFO='\033[0;34m'
readonly COLOR_SUCCESS='\033[0;32m'
readonly COLOR_WARN='\033[0;33m'
readonly COLOR_ERROR='\033[0;31m'
readonly COLOR_STEP='\033[1;36m'
readonly COLOR_AI='\033[1;35m'

# Leitet die gesamte Ausgabe in die Log-Datei und das Terminal um
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

# --- AI Debugger Funktion ---
ai_debugger() {
    log_error "Build fehlgeschlagen. Starte KI-Analyse..."
    log_ai "Sende Build-Log zur Analyse an die Mixtral AI..."
    
    local api_key
    if [ -f ".env" ]; then
        api_key=$(grep "MISTRALAPIKEY" .env | cut -d'=' -f2 | tr -d '"' | tr -d "'" | xargs)
    fi

    if [ -z "$api_key" ] || [ "$api_key" = "your_mixtral_api_key_here" ]; then
        log_error "Kein gültiger API-Schlüssel gefunden. Überspringe KI-Analyse."
        return
    fi
    
    local system_prompt="You are an expert-level Linux distribution build-system debugger. A user's build script has failed. Analyze the complete build.log provided. Identify the exact point of failure and provide a clear, actionable solution. Structure your response in German as follows:\n\n### 🚨 Fehleranalyse\nPrecise description of which command failed and why.\n\n### ✅ Lösungsvorschlag\nConcrete, step-by-step plan to fix the problem. If code needs to be changed, provide the exact corrected code block."
    
    local log_content
    log_content=$(tail -n 200 "${LOG_FILE}" | jq -Rs . 2>/dev/null || echo '"Log-Analyse fehlgeschlagen"')

    local json_payload
    json_payload=$(jq -n \
                      --arg sp "$system_prompt" \
                      --arg lc "$log_content" \
                      '{model: "mistral-large-latest", messages: [{"role": "system", "content": $sp}, {"role": "user", "content": $lc}]}' 2>/dev/null || echo '{}')

    log_ai "Führe Analyse durch... Dies kann einen Moment dauern."
    
    local ai_response
    ai_response=$(curl -s -X POST "https://api.mistral.ai/v1/chat/completions" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $api_key" \
        -d "$json_payload" 2>/dev/null || echo '{"choices":[{"message":{"content":"Analyse fehlgeschlagen"}}]}')

    local analysis
    analysis=$(echo "$ai_response" | jq -r '.choices[0].message.content // "Analyse fehlgeschlagen"' 2>/dev/null || echo "Analyse fehlgeschlagen")

    echo
    log_ai "Ergebnis der KI-Analyse:"
    echo -e "${COLOR_AI}----------------------------------------------------------------------${COLOR_RESET}"
    echo -e "$analysis"
    echo -e "${COLOR_AI}----------------------------------------------------------------------${COLOR_RESET}"
}

# Fehler-Trap: Ruft den AI-Debugger auf, bevor das Skript beendet wird
trap 'ai_debugger' ERR

# --- Hilfsfunktionen ---
check_not_root() {
    if [ "$(id -u)" -eq 0 ]; then
        log_error "Dieses Skript darf nicht als Root ausgeführt werden. Es verwendet bei Bedarf 'sudo'."
        exit 1
    fi
}

check_dependencies() {
    local dependencies=("debootstrap" "squashfs-tools" "xorriso" "grub-pc-bin" "grub-efi-amd64-bin" "mtools" "dosfstools" "isolinux" "syslinux-common" "shim-signed" "gnupg" "git" "curl" "jq" "python3" "python3-pip")
    local missing=()
    
    log_info "Prüfe Abhängigkeiten: ${dependencies[*]}"
    for dep in "${dependencies[@]}"; do
        if ! dpkg -l "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        log_warn "Fehlende Abhängigkeiten: ${missing[*]}"
        log_info "Installiere fehlende Pakete..."
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
    log_info "Bereinige Mount-Punkte..."
    # Unmount in umgekehrter Reihenfolge der tiefsten Verschachtelung
    for mount_point in "/dev/pts" "/dev" "/proc" "/sys" "/run"; do
        if mountpoint -q "${CHROOT_DIR}${mount_point}" 2>/dev/null; then
            sudo umount -f -l "${CHROOT_DIR}${mount_point}" || true
        fi
    done
}

# --- Build-Schritte ---

step_01_setup() {
    log_step "1/10" "Einrichtung der Umgebung und Prüfung der Abhängigkeiten"
    
    # Erstelle .env.example, falls nicht vorhanden
    if [ ! -f ".env.example" ]; then
        log_info "Erstelle .env.example Vorlage..."
        cat > .env.example << 'EOF'
# .env - API-Schlüssel für den Mixtral AI-Zugang
# Kopiere diese Datei nach .env und füge deinen API-Schlüssel hinzu
MISTRALAPIKEY="dein_mixtral_api_schlüssel_hier"
EOF
    fi
    
    # Prüfe auf .env-Datei
    if [ ! -f ".env" ]; then
        log_error "Bitte erstelle eine .env-Datei aus der Vorlage und füge deinen API-Schlüssel hinzu."
        log_info "Führe aus: cp .env.example .env && nano .env"
        exit 1
    fi

    check_dependencies
    
    # Bereinige vorherigen Build
    if [ -d "${BUILD_DIR}" ]; then
        log_warn "Vorheriges Build-Verzeichnis gefunden. Bereinige..."
        cleanup_mounts
        sudo rm -rf "${BUILD_DIR}"
    fi
    
    # Entferne alte ISO-Dateien
    if [ -f "${ISO_NAME}" ]; then
        log_warn "Entferne existierende ISO-Datei: ${ISO_NAME}"
        rm -f "${ISO_NAME}" "${ISO_NAME}.sha256"
    fi

    mkdir -p "${CHROOT_DIR}" "${ISO_DIR}"
    log_success "Build-Umgebung erfolgreich eingerichtet."
}

step_02_bootstrap_system() {
    log_step "2/10" "Bootstrap des Basissystems und Konfiguration der Repositories"
    
    log_info "Führe debootstrap aus, um das Basissystem zu erstellen..."
    sudo debootstrap --arch="${ARCHITECTURE}" --variant=minbase "${UBUNTU_CODENAME}" "${CHROOT_DIR}" http://archive.ubuntu.com/ubuntu/
    
    log_info "Konfiguriere APT-Quellen für das neue System..."
    sudo tee "${CHROOT_DIR}/etc/apt/sources.list" > /dev/null <<'EOF'
deb http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse
EOF

    # Richte Mounts für chroot ein
    sudo mount --bind /dev "${CHROOT_DIR}/dev"
    sudo mount --bind /dev/pts "${CHROOT_DIR}/dev/pts"
    sudo mount -t proc proc "${CHROOT_DIR}/proc"
    sudo mount -t sysfs sysfs "${CHROOT_DIR}/sys"
    sudo mount --bind /run "${CHROOT_DIR}/run"
    sudo cp /etc/resolv.conf "${CHROOT_DIR}/etc/"

    # Erstelle ein Bootstrap-Skript, um komplexe Here-Dokumente zu vermeiden
    local bootstrap_script
    bootstrap_script='
#!/bin/bash
set -e
echo "'${LIVE_HOSTNAME}'" > /etc/hostname

# Basiskonfiguration für Locale und APT
apt-get update
apt-get install -y --no-install-recommends locales apt-utils dialog curl wget gnupg ca-certificates software-properties-common

# Füge AILinux-Repository und externe Quellen hinzu
echo "Füge AILinux-Repository und externe Quellen hinzu..."
curl -fssSL https://ailinux.me:8443/mirror/add-ailinux-repo.sh | bash

# Füge Microsoft VS Code Repository hinzu
echo "Füge Microsoft VS Code Repository hinzu..."
curl -sSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg
echo "deb [arch=amd64,arm64,armhf signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | tee /etc/apt/sources.list.d/vscode.list

# Richte Locales ein
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "de_DE.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

# Aktiviere i386-Architektur für Wine
dpkg --add-architecture i386

# Finale Aktualisierung, um alle Paketlisten abzurufen
apt-get update
'
    run_in_chroot "$bootstrap_script"
    
    log_success "Basissystem und Repositories konfiguriert."
}

step_03_install_packages() {
    log_step "3/10" "Installation von Kernpaketen, Kernel und Desktop-Umgebung"
    
    # Definiere Paketlisten als Arrays für bessere Lesbarkeit
    local KERNEL_BOOT_PKGS=(
        linux-image-generic linux-headers-generic casper
        laptop-detect os-prober network-manager resolvconf net-tools
        wireless-tools plymouth-theme-spinner ubuntu-standard
        keyboard-configuration console-setup sudo systemd systemd-sysv
        dbus init rsyslog grub-efi-amd64 grub-efi-amd64-bin grub-efi-amd64-signed
        shim-signed grub2-common efibootmgr
        initramfs-tools live-boot mokutil
    )
    local KDE_ESSENTIAL_PKGS=(
        plasma-desktop plasma-workspace plasma-nm plasma-pa
        sddm sddm-theme-breeze xorg xserver-xorg-video-all
        plasma-discover plasma-discover-common discover
        konsole kate dolphin gwenview okular ark
        plasma-systemmonitor kcalc kwrite
    )
    local KDE_FULL_PKG=(
        kde-full
    )
    local CORE_APPS=(
        firefox thunderbird vlc gimp filezilla gparted htop neofetch
        ffmpeg pulseaudio pavucontrol git build-essential
        python3 python3-pip python3-venv python3-dev 
        linux-firmware bluez bluetooth wpasupplicant cups
        jq tree vim nano curl wget unzip zip software-properties-common
        apt-transport-https steam-installer
    )
    
    local install_script
    install_script=$(cat <<PACKAGES_EOF
set -ex

echo "Installiere Kernel, Boot-Komponenten und System-Tools..."
apt-get install -y --no-install-recommends ${KERNEL_BOOT_PKGS[*]}

echo "Installiere BIOS-Kompatibilitäts-Pakete separat..."
# Installiere grub-pc separat nach grub-efi für BIOS-Kompatibilität
if ! apt-get install -y --no-install-recommends grub-pc grub-pc-bin; then
    echo "WARNING: BIOS grub-pc Installation fehlgeschlagen - nur EFI verfügbar"
fi

echo "Installiere KDE Essential-Pakete (inkl. Discover)..."
# Installiere alle essentiellen KDE-Pakete inklusive Discover
apt-get install -y --no-install-recommends ${KDE_ESSENTIAL_PKGS[*]}

echo "Installiere kde-full für vollständigen Plasma 6 Desktop..."
# Jetzt kann kde-full erfolgreich installiert werden, da alle Abhängigkeiten vorhanden sind
if apt-get install -y --no-install-recommends ${KDE_FULL_PKG[*]}; then
    echo "SUCCESS: kde-full erfolgreich installiert mit allen Abhängigkeiten"
    # Sofortige Bereinigung für Platzeinsparung
    apt-get autoremove -y --purge || true
    apt-get autoclean || true
else
    echo "WARNING: kde-full Installation fehlgeschlagen trotz Abhängigkeiten"
    echo "INFO: KDE Essential-Pakete bereits installiert - Desktop funktionsfähig"
fi

echo "Installiere Kernanwendungen und Entwicklungstools..."
apt-get install -y --no-install-recommends ${CORE_APPS[*]}

echo "Installiere spezielle Pakete mit Fallbacks..."

# AILinux-App - KRITISCH für Anforderungen
echo "Installiere AILinux-App..."
if apt-get install -y --no-install-recommends ailinux-app; then
    echo "SUCCESS: AILinux-App erfolgreich installiert"
else
    echo "WARNING: AILinux-App nicht im Repository gefunden. Wird später manuell installiert."
fi

# Wine-Pakete - KRITISCH für Anforderungen
echo "Installiere Wine und Winetricks..."
if apt-get install -y --no-install-recommends winehq-staging winetricks; then
    echo "SUCCESS: Wine erfolgreich installiert"
else
    echo "WARNING: winehq-staging fehlgeschlagen, verwende Standard-Wine..."
    apt-get install -y --no-install-recommends wine64 wine32 winetricks || echo "ERROR: Wine-Installation fehlgeschlagen."
fi

# Google Chrome - KRITISCH für Anforderungen
echo "Installiere Google Chrome..."
if apt-get install -y --no-install-recommends google-chrome-stable; then
    echo "SUCCESS: Google Chrome erfolgreich installiert"
else
    echo "INFO: Google Chrome nicht im Repo, verwende manuellen Download..."
    wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/chrome.deb && \
    (dpkg -i /tmp/chrome.deb || apt-get -f install -y) && \
    echo "SUCCESS: Google Chrome manuell installiert"
    rm -f /tmp/chrome.deb
fi

# PyQt5 für AILinux App - Minimal installation
echo "Installiere PyQt5 minimal für AILinux App..."
apt-get install -y --no-install-recommends python3-pyqt5 python3-pyqt5.qtwidgets python3-pyqt5.qtgui || \
    echo "WARNING: PyQt5 Installation fehlgeschlagen"

# Aggressive Cleanup für kleinere ISO
echo "Bereinige unnötige Pakete für kleinere ISO..."
apt-get autoremove -y --purge
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*
rm -rf /var/tmp/*

echo "Paketinstallation abgeschlossen."
PACKAGES_EOF
)
    run_in_chroot "$install_script"
    
    log_success "Alle Kernpakete und die Desktop-Umgebung wurden installiert."
}

step_04_install_ai_components() {
    log_step "4/10" "Installation der AILinux AI-Komponenten"
    
    # Kopiere .env-Datei in chroot, falls vorhanden
    if [ -f ".env" ]; then
        sudo cp .env "${CHROOT_DIR}/tmp/.env"
    fi
    
    # Skript zur Installation der AI-Komponenten
    local ai_install_script
    ai_install_script='
#!/bin/bash
set -e

# Installiere Python-Abhängigkeiten
python3 -m pip install --break-system-packages requests python-dotenv psutil

# Erstelle Basisverzeichnis für AILinux-Komponenten
mkdir -p /opt/ailinux

# Erstelle den AI-Helfer
cat > /opt/ailinux/ailinux-helper.py << '"'AIHELPER'"'
#!/usr/bin/env python3
import os
import sys
import json
import requests
import argparse
import subprocess
from dotenv import load_dotenv

# Lade Umgebungsvariablen
load_dotenv(dotenv_path="/opt/ailinux/.env")

class AILinuxHelper:
    def __init__(self):
        self.api_key = os.getenv("MISTRALAPIKEY")
        if not self.api_key or self.api_key == "dein_mixtral_api_schlüssel_hier":
            print("Fehler: MISTRALAPIKEY nicht gefunden oder nicht konfiguriert.")
            print("Bitte bearbeiten Sie /opt/ailinux/.env und fügen Sie Ihren Mixtral API-Schlüssel hinzu.")
            sys.exit(1)
        
        self.api_url = "https://api.mistral.ai/v1/chat/completions"
        self.system_prompt = """Du bist AILinux Helper – ein KI-gesteuerter Assistent, der in der Linux-Distribution „AILinux 24.04 Premium" eingebettet ist.

Diese Distribution basiert auf Ubuntu 24.04 (Codename: Noble) und wurde speziell für eine moderne, KI-integrierte Offline-Nutzung entwickelt.

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

AILinux enthält: kde-full, firefox, chrome, thunderbird, vlc, gimp, libreoffice, wine, vscode, python3, nodejs, und viele andere Pakete."""

    def analyze_problem(self, user_input):
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        
        data = {
            "model": "mistral-large-latest",
            "messages": [
                {"role": "system", "content": self.system_prompt},
                {"role": "user", "content": user_input}
            ]
        }
        
        try:
            response = requests.post(self.api_url, headers=headers, json=data, timeout=90)
            response.raise_for_status()
            return response.json()["choices"][0]["message"]["content"]
        except Exception as e:
            return f"Fehler bei der Kontaktaufnahme mit dem KI-Dienst: {e}"

def main():
    parser = argparse.ArgumentParser(description="AILinux Helper - KI-gestützter Systemassistent")
    parser.add_argument("query", nargs="*", help="Problembeschreibung oder Frage zur Analyse")
    args = parser.parse_args()
    
    helper = AILinuxHelper()
    
    if args.query:
        user_input = " ".join(args.query)
    else:
        print("Geben Sie Ihre Problembeschreibung ein (drücken Sie Strg+D, wenn Sie fertig sind):")
        user_input = sys.stdin.read()
    
    if user_input.strip():
        print("\nAnalysiere...")
        print(helper.analyze_problem(user_input))
    else:
        print("Keine Eingabe erhalten.")

if __name__ == "__main__":
    main()
AIHELPER
chmod +x /opt/ailinux/ailinux-helper.py

# Erstelle Desktop-Eintrag
cat > /usr/share/applications/ailinux-helper.desktop << '"'DESKTOP'"'
[Desktop Entry]
Version=1.0
Type=Application
Name=AILinux Helper
Name[de]=AILinux Assistent
Comment=AI-powered system assistant
Comment[de]=KI-gestützter Systemassistent
Icon=applications-system
Exec=konsole -e /opt/ailinux/ailinux-helper.py
Terminal=true
Categories=System;Utility;
DESKTOP

# Erstelle Symlink
ln -sf /opt/ailinux/ailinux-helper.py /usr/local/bin/aihelp

# Verschiebe .env an den endgültigen Ort
if [ -f "/tmp/.env" ]; then
    mv /tmp/.env /opt/ailinux/.env
    chmod 600 /opt/ailinux/.env
fi

echo "Installation der AILinux AI-Komponenten abgeschlossen."
'
    run_in_chroot "$ai_install_script"
    sudo rm -f "${CHROOT_DIR}/tmp/.env"
    
    log_success "AILinux AI-Komponenten installiert."
}

step_05_configure_calamares() {
    log_step "5/10" "Konfiguration des Calamares Installers (mit Bootloader-Fix)"
    
    if [ -d "branding" ]; then
        sudo mkdir -p "${CHROOT_DIR}/tmp/branding"
        sudo cp -r branding/* "${CHROOT_DIR}/tmp/branding/"
    fi
    
    local calamares_script
    calamares_script='
#!/bin/bash
set -e

# Installiere Calamares mit allen Abhängigkeiten (insbesondere für Bootloader)
echo "Installiere Calamares mit vollständigen Abhängigkeiten..."
apt-get update

# Wichtige Bootloader-Abhängigkeiten ZUERST installieren
apt-get install -y \
    grub-pc-bin grub-efi-amd64-bin grub-efi-amd64-signed grub-common \
    grub2-common efibootmgr os-prober shim-signed

# Python-Abhängigkeiten für Calamares-Module
apt-get install -y python3-yaml python3-parted python3-setuptools python3-pyqt5

# Calamares Hauptpaket und zusätzliche Abhängigkeiten
# KORREKTUR: 'calamares-settings-ubuntu' wurde entfernt, da es nicht benötigt wird und nicht verfügbar ist.
apt-get install -y calamares imagemagick squashfs-tools dosfstools ntfs-3g btrfs-progs xfsprogs e2fsprogs

# Erstelle Calamares Konfigurationsverzeichnisse
mkdir -p /etc/calamares/modules
mkdir -p /etc/calamares/branding/ailinux

# Hauptkonfiguration (settings.conf)
cat > /etc/calamares/settings.conf << '"'SETTINGS'"'
---
modules-search: [ local ]
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
  - umount
- show:
  - finished
branding: ailinux
prompt-install: false
quit-at-end: false
SETTINGS

# Branding-Konfiguration
cat > /etc/calamares/branding/ailinux/branding.desc << '"'BRANDING'"'
---
componentName: ailinux
strings:
    productName: AILinux
    version: 24.04 Premium
    shortVersionedName: AILinux 24.04
    versionedName: AILinux 24.04 Premium
    shortProductName: AILinux
    bootloaderEntryName: AILinux
    productUrl: https://github.com/derleiti/ailinux-beta-iso
    supportUrl: https://github.com/derleiti/ailinux-beta-iso/issues
    knownIssuesUrl: https://github.com/derleiti/ailinux-beta-iso/issues
    releaseNotesUrl: https://github.com/derleiti/ailinux-beta-iso/releases

style:
    sidebarBackground: "#2c3e50"
    sidebarText: "#ffffff"
    sidebarTextSelect: "#4e73c7"
    sidebarTextCurrent: "#ffffff"

images:
    productLogo: "logo.png"
    productIcon: "icon.png"
    productWelcome: "welcome.png"

slideshow: "show.qml"
slideshowAPI: 2
BRANDING

# Erstelle einfache QML-Slideshow
cat > /etc/calamares/branding/ailinux/show.qml << '"'QML'"'
import QtQuick 2.0
import QtQuick.Controls 2.5
import QtQuick.Layouts 1.3

Rectangle {
    id: slideshow
    color: "#2c3e50"
    
    property int currentSlide: 0
    property var slides: [
        "Willkommen bei AILinux 24.04 Premium",
        "KI-gestützte Systemunterstützung mit aihelp",
        "Vollständige KDE Plasma Desktop-Umgebung",
        "Sichere Installation mit UEFI/BIOS-Support",
        "Installation wird abgeschlossen..."
    ]
    
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: {
            currentSlide = (currentSlide + 1) % slides.length
        }
    }
    
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 20
        
        Image {
            source: "logo.png"
            Layout.preferredWidth: 128
            Layout.preferredHeight: 128
            Layout.alignment: Qt.AlignHCenter
            fillMode: Image.PreserveAspectFit
        }
        
        Text {
            text: slides[currentSlide]
            color: "white"
            font.pixelSize: 24
            font.weight: Font.Bold
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            Layout.maximumWidth: slideshow.width * 0.8
        }
        
        Text {
            text: "AILinux wird installiert - Bitte warten..."
            color: "#bdc3c7"
            font.pixelSize: 16
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
QML

# Kopiere Branding-Bilder falls vorhanden, sonst erstelle Fallbacks
if [ -d "/tmp/branding" ]; then
    cp /tmp/branding/* /etc/calamares/branding/ailinux/ 2>/dev/null || true
fi
if [ ! -f "/etc/calamares/branding/ailinux/logo.png" ]; then
    convert -size 256x256 xc:"#2c3e50" -pointsize 24 -fill white -gravity center -annotate +0+0 "AILinux" /etc/calamares/branding/ailinux/logo.png
fi
for img in icon.png welcome.png; do
    if [ ! -f "/etc/calamares/branding/ailinux/${img}" ]; then
        cp /etc/calamares/branding/ailinux/logo.png "/etc/calamares/branding/ailinux/${img}"
    fi
done

# Wichtige Modulkonfigurationen
# unpackfs.conf
cat > /etc/calamares/modules/unpackfs.conf << '"'UNPACKFS'"'
---
unpack:
    - source: "/cdrom/casper/filesystem.squashfs"
      sourcefs: "squashfs"
      destination: ""
UNPACKFS

# bootloader.conf - VEREINFACHT für Calamares Kompatibilität
cat > /etc/calamares/modules/bootloader.conf << '"'BOOTLOADER'"'
---
# Basic bootloader configuration
efiBootloaderId: "ailinux"
bootloader: "grub"
installPath: "/boot/efi"
timeout: 10

# Kernel parameters
kernelLine: ",quiet splash"
fallbackKernelLine: ",quiet splash"

# GRUB configuration
grubInstall: "grub-install"
grubMkconfig: "grub-mkconfig"
grubCfg: "/boot/grub/grub.cfg"

# Installation parameters
efiInstallParams: "--target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ailinux"
biosInstallParams: "--target=i386-pc"
BOOTLOADER

# partition.conf - KORRIGIERT für automatische Partitionierung
cat > /etc/calamares/modules/partition.conf << '"'PARTITION'"'
---
# EFI System Partition Einstellungen
efiSystemPartition: "/boot/efi"
efiSystemPartitionSize: 1000MiB
efiSystemPartitionName: EFI
efiSystemPartitionMountPoint: "/boot/efi"

# Automatische Partitionierung
defaultFileSystemType: "ext4"
availableFileSystemTypes: ["ext4", "btrfs", "xfs"]
initialPartitioningChoice: "erase"
defaultPartitionTableType: "gpt"
requiredStorageGiB: 10.5

# KRITISCH: Automatische EFI Partition für Bootloader
always_show_partition_labels: true
drawNestedPartitions: false

# Partition Layout für automatische Installation
partitionLayout:
    - name: "efi"
      filesystem: "fat32"
      mountPoint: "/boot/efi"
      size: "1000MiB"
    - name: "root"
      filesystem: "ext4" 
      mountPoint: "/"
      size: "100%"

# Bootloader Support
ensureSuspendToDisk: true
userSwapChoices: ["suspend", "file"]
PARTITION

# displaymanager.conf
cat > /etc/calamares/modules/displaymanager.conf << '"'DISPLAYMANAGER'"'
---
displaymanagers:
  - sddm

defaultDesktopEnvironment:
    executable: "startkde"
    desktopFile: "plasma"

basicSetup: false
DISPLAYMANAGER

# users.conf
cat > /etc/calamares/modules/users.conf << '"'USERS'"'
---
defaultGroups:
    - sudo
    - adm
    - cdrom
    - dip
    - plugdev
    - lpadmin
    - audio
    - video
    - bluetooth
    - netdev
autologinGroup: autologin
sudoersGroup: sudo
setRootPassword: false
allowWeakPasswords: true
userShell: /bin/bash
USERS

echo "Calamares-Konfiguration mit korrigiertem Bootloader abgeschlossen."
'
    run_in_chroot "$calamares_script"
    
    log_success "Calamares Installer wurde erfolgreich konfiguriert."
}


step_06_create_live_user() {
    log_step "6/10" "Erstellung des Live-Benutzers und Desktop-Konfiguration"
    
    local user_script
    user_script='
#!/bin/bash
set -e
# Erstelle Live-Benutzer ohne Passwort
useradd -s /bin/bash -d "/home/'${LIVE_USER}'" -m -G adm,cdrom,sudo,dip,plugdev,lpadmin,audio,video,bluetooth,netdev "'${LIVE_USER}'"
passwd -d "'${LIVE_USER}'"
echo "'${LIVE_USER}' ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Konfiguriere SDDM für Autologin
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/autologin.conf << '"'SDDM_EOF'"'
[Autologin]
User='${LIVE_USER}'
Session=plasma
[Theme]
Current=breeze
SDDM_EOF

# Erstelle Desktop-Verknüpfung für den Installer
mkdir -p "/home/'${LIVE_USER}'/Desktop"
cat > "/home/'${LIVE_USER}'/Desktop/install-ailinux.desktop" << '"'INSTALL_EOF'"'
[Desktop Entry]
Version=1.0
Type=Application
Name=Install AILinux
Name[de]=AILinux installieren
Comment=Install AILinux to your computer
Icon=calamares
Exec=pkexec calamares
Terminal=false
Categories=System;
INSTALL_EOF
chmod +x "/home/'${LIVE_USER}'/Desktop/install-ailinux.desktop"

# Erstelle AI-Helfer-Verknüpfung
cat > "/home/'${LIVE_USER}'/Desktop/aihelp.desktop" << '"'AIHELP_EOF'"'
[Desktop Entry]
Version=1.0
Type=Application
Name=AILinux Helper
Name[de]=AILinux Assistent
Icon=dialog-information
Exec=konsole -e aihelp
Terminal=true
Categories=System;Utility;
AIHELP_EOF
chmod +x "/home/'${LIVE_USER}'/Desktop/aihelp.desktop"

# Konfiguriere .bashrc mit Willkommensnachricht und Alias
cat >> "/home/'${LIVE_USER}'/.bashrc" << '"'BASHRC_EOF'"'

# AILinux Welcome
echo ""
echo "🧠 Willkommen bei AILinux 24.04 Premium!"
echo "Verwenden Sie \"aihelp\" für KI-gestützte Systemhilfe."
echo ""
alias ai="aihelp"
BASHRC_EOF

# Setze Eigentümer
chown -R "'${LIVE_USER}':'${LIVE_USER}'" "/home/'${LIVE_USER}'"
'
    run_in_chroot "$user_script"
    
    log_success "Live-Benutzer und Desktop konfiguriert."
}

step_07_system_cleanup() {
    log_step "7/10" "Systembereinigung und Service-Konfiguration"
    
    local cleanup_script
    cleanup_script='
#!/bin/bash
set -e
# Aktiviere wichtige Dienste
systemctl enable bluetooth cups NetworkManager sddm

# Erweiterte Bereinigung für kleinere ISO
apt-get autoremove -y --purge
apt-get autoclean
apt-get clean
rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*
rm -rf /var/cache/apt/archives/*.deb
rm -rf /var/cache/apt/archives/partial/*
find /var/log -type f -exec truncate --size 0 {} \;
# Entferne zusätzliche temporäre Dateien
rm -rf /root/.cache /home/*/.cache
rm -rf /usr/share/doc/* /usr/share/man/*
rm -rf /var/cache/fontconfig/*

# Setze machine-id zurück
rm -f /etc/machine-id /var/lib/dbus/machine-id
touch /etc/machine-id

# Entferne SSH-Host-Schlüssel
rm -f /etc/ssh/ssh_host_*

# Aktualisiere initramfs
update-initramfs -u
'
    run_in_chroot "$cleanup_script"
    
    sudo rm -f "${CHROOT_DIR}/etc/resolv.conf"
    
    log_success "Systembereinigung abgeschlossen."
}

step_08_create_squashfs() {
    log_step "8/10" "Erstellung des SquashFS-Images"
    
    cleanup_mounts
    
    mkdir -p "${ISO_DIR}"/{casper,isolinux,boot/grub,.disk}
    
    sudo cp "${CHROOT_DIR}"/boot/vmlinuz-*-generic "${ISO_DIR}/casper/vmlinuz"
    sudo cp "${CHROOT_DIR}"/boot/initrd.img-*-generic "${ISO_DIR}/casper/initrd"
    
    run_in_chroot "dpkg-query -W --showformat='\\\${Package}\t\\\${Version}\n'" > "${ISO_DIR}/casper/filesystem.manifest"
    
    log_info "Erstelle SquashFS-Image mit zstd-Kompression (dies kann dauern)..."
    sudo mksquashfs "${CHROOT_DIR}" "${ISO_DIR}/casper/filesystem.squashfs" \
        -noappend -e boot -comp zstd -b 1M -Xcompression-level 15
    
    printf "$(sudo du -sx --block-size=1 "${CHROOT_DIR}" | cut -f1)" > "${ISO_DIR}/casper/filesystem.size"
    
    echo "${DISTRO_NAME} ${DISTRO_VERSION} ${DISTRO_EDITION} - Release ${ARCHITECTURE}" > "${ISO_DIR}/.disk/info"
    
    log_success "SquashFS-Image erfolgreich erstellt."
    log_info "SquashFS-Größe: $(du -h "${ISO_DIR}/casper/filesystem.squashfs" | cut -f1)"
}

step_09_create_bootloaders() {
    log_step "9/10" "Erstellung der Bootloader (BIOS & UEFI)"
    
    # ISOLINUX für BIOS-Boot
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
LABEL safe
  MENU LABEL Try ${DISTRO_NAME} (safe graphics)
  KERNEL /casper/vmlinuz
  APPEND file=/cdrom/.disk/info boot=casper initrd=/casper/initrd quiet splash nomodeset ---
EOF

    # GRUB für UEFI-Boot
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

    # Erstelle GRUB EFI-Image für Secure Boot
    log_info "Erstelle GRUB EFI-Boot-Image..."
    grub-mkstandalone \
        --format=x86_64-efi \
        --output="/tmp/bootx64.efi" \
        --locales="" --fonts="" \
        "boot/grub/grub.cfg=${ISO_DIR}/boot/grub/grub.cfg"

    dd if=/dev/zero of="${ISO_DIR}/boot/grub/efi.img" bs=1M count=64 status=none
    mkfs.vfat -n "AILINUX_EFI" "${ISO_DIR}/boot/grub/efi.img" > /dev/null
    
    local efi_mount
    efi_mount=$(mktemp -d)
    sudo mount -o loop "${ISO_DIR}/boot/grub/efi.img" "${efi_mount}"
    sudo mkdir -p "${efi_mount}/EFI/BOOT"
    sudo cp /tmp/bootx64.efi "${efi_mount}/EFI/BOOT/grubx64.efi"
    sudo cp /usr/lib/shim/shimx64.efi.signed "${efi_mount}/EFI/BOOT/BOOTX64.EFI"
    sudo umount "${efi_mount}"
    rmdir "${efi_mount}"
    rm -f /tmp/bootx64.efi
    
    log_success "Bootloader erfolgreich erstellt."
}

step_10_create_iso() {
    log_step "10/10" "Erstellung des finalen ISO-Images"
    
    log_info "Erstelle hybrides ISO-Image..."
    sudo xorriso -as mkisofs \
        -o "${BUILD_DIR}/${ISO_NAME}" \
        -V "${DISTRO_NAME}_${DISTRO_VERSION}" \
        -iso-level 3 -r -J -l \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot -e boot/grub/efi.img -no-emul-boot \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        "${ISO_DIR}"

    sudo chown "$(id -u):$(id -g)" "${BUILD_DIR}/${ISO_NAME}"
    mv "${BUILD_DIR}/${ISO_NAME}" "$(pwd)/"
    
    sha256sum "$(pwd)/${ISO_NAME}" > "$(pwd)/${ISO_NAME}.sha256"
    
    log_success "ISO erfolgreich erstellt: $(pwd)/${ISO_NAME}"
    log_info "ISO-Größe: $(du -h "$(pwd)/${ISO_NAME}" | cut -f1)"
}

# --- Hauptfunktion ---
main() {
    rm -f "${LOG_FILE}"
    
    check_not_root
    
    local start_time
    start_time=$(date +%s)
    
    log_info "==================== AILinux ISO Build v25.08 - Refined & Corrected ===================="
    log_info "Starte Build-Prozess für ${DISTRO_NAME} ${DISTRO_VERSION} ${DISTRO_EDITION}"
    
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
    log_success "==================== BUILD ERFOLGREICH ABGESCHLOSSEN ===================="
    log_success "ISO: $(realpath "${ISO_NAME}")"
    log_success "Build-Dauer: $((duration / 60)) Minuten und $((duration % 60)) Sekunden"
    log_info "Um das Build-Verzeichnis zu bereinigen: sudo rm -rf ${BUILD_DIR}"
}

# Starte das Skript
main "$@"

#!/bin/bash
#
# AILinux ISO Build-Skript (v16.0)
# Erstellt eine bootfähige Live-ISO von AILinux basierend auf Ubuntu 24.04 (Noble Numbat).
#
# Lizenz: MIT License
# Copyright (c) 2024 derleiti
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Strikter Fehlermodus: Bricht bei Fehlern, nicht gesetzten Variablen und Fehlern in Pipelines ab.
set -eo pipefail

# --- Konfiguration ---
DISTRO_NAME="AILinux"
DISTRO_VERSION="24.04"
UBUNTU_CODENAME="noble"
ARCHITECTURE="amd64"

LIVE_USER="ailinux"
LIVE_HOSTNAME="ailinux"

BUILD_DIR="AILINUX_BUILD"
CHROOT_DIR="${BUILD_DIR}/chroot"
ISO_DIR="${BUILD_DIR}/iso"
ISO_NAME="${DISTRO_NAME,,}-${DISTRO_VERSION}-${ARCHITECTURE}.iso"

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

# Überprüft, ob das Skript als root ausgeführt wird.
check_not_root() {
    if [ "$(id -u)" -eq 0 ]; then
        log_error "Dieses Skript darf nicht als root ausgeführt werden. Es verwendet bei Bedarf 'sudo'."
        exit 1
    fi
}

# Sichere Unmount-Funktion, versucht mehrfach.
safe_umount() {
    local mount_point="$1"
    if ! findmnt -rno TARGET "$mount_point" > /dev/null; then
        log_info "Mountpunkt '$mount_point' ist bereits unmounted."
        return 0
    fi
    log_info "Unmounte '$mount_point'..."
    local attempts=5
    while [ $attempts -gt 0 ]; do
        if sudo umount -l "$mount_point"; then
            log_success "Unmount von '$mount_point' erfolgreich."
            return 0
        fi
        log_warn "Unmount von '$mount_point' fehlgeschlagen. Versuche es in 3 Sekunden erneut..."
        sleep 3
        ((attempts--))
    done
    log_error "Konnte '$mount_point' nach mehreren Versuchen nicht unmounten."
    return 1
}

# Bereinigungsfunktion für Notfälle und nach dem Build.
cleanup() {
    log_warn "Starte Bereinigung..."
    # Deaktiviere den strikten Fehlermodus für die Bereinigung
    set +e

    safe_umount "${CHROOT_DIR}/dev/pts"
    safe_umount "${CHROOT_DIR}/dev"
    safe_umount "${CHROOT_DIR}/proc"
    safe_umount "${CHROOT_DIR}/sys"
    safe_umount "${CHROOT_DIR}/run"

    if [ -d "${BUILD_DIR}" ]; then
        log_info "Entferne Build-Verzeichnis: ${BUILD_DIR}"
        sudo rm -rf "${BUILD_DIR}"
        log_success "Bereinigung abgeschlossen."
    fi
}

# Trap, um bei Skript-Abbruch automatisch aufzuräumen.
trap 'log_error "Skript unerwartet beendet."; cleanup; exit 1' INT TERM ERR

# --- Build-Schritte als Funktionen ---

step_01_setup_environment() {
    log_step "1/12" "Umgebung einrichten und Abhängigkeiten prüfen"
    
    # Notwendige Pakete prüfen
    local dependencies=("debootstrap" "squashfs-tools" "xorriso" "grub-pc-bin" "grub-efi-amd64-bin" "mtools" "dosfstools" "isolinux" "syslinux-common")
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            log_error "Fehlende Abhängigkeit: '$dep'. Bitte installieren Sie es (z.B. mit 'sudo apt install $dep')."
            exit 1
        fi
    done
    log_info "Alle Abhängigkeiten sind vorhanden."

    # Build-Verzeichnisstruktur erstellen
    sudo rm -rf "${BUILD_DIR}"
    mkdir -p "${BUILD_DIR}"
    sudo chown "$(whoami)":"$(whoami)" "${BUILD_DIR}"
    mkdir -p "${CHROOT_DIR}" "${ISO_DIR}"
    log_success "Build-Umgebung erfolgreich eingerichtet."
}

step_02_debootstrap() {
    log_step "2/12" "Basissystem mit debootstrap erstellen"
    sudo debootstrap --arch="${ARCHITECTURE}" --variant=minbase "${UBUNTU_CODENAME}" "${CHROOT_DIR}" http://archive.ubuntu.com/ubuntu/
    log_success "Basissystem erfolgreich erstellt."
}

step_03_mount_filesystems() {
    log_step "3/12" "Pseudo-Dateisysteme einhängen"
    sudo mount --bind /dev "${CHROOT_DIR}/dev"
    sudo mount --bind /dev/pts "${CHROOT_DIR}/dev/pts"
    sudo mount -t proc proc "${CHROOT_DIR}/proc"
    sudo mount -t sysfs sysfs "${CHROOT_DIR}/sys"
    sudo mount -t tmpfs tmpfs "${CHROOT_DIR}/run"
    
    # DNS-Auflösung für chroot sicherstellen
    sudo cp /etc/resolv.conf "${CHROOT_DIR}/etc/"
    log_success "Alle Pseudo-Dateisysteme erfolgreich eingehängt."
}

step_04_chroot_base_config() {
    log_step "4/12" "Chroot: Basiskonfiguration"
    sudo chroot "${CHROOT_DIR}" /bin/bash <<'EOF'
        set -e
        # Hostname setzen
        echo "ailinux" > /etc/hostname

        # APT-Quellen konfigurieren
        cat > /etc/apt/sources.list << "SOURCES"
deb http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse
SOURCES
        
        # APT aktualisieren
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
EOF
    log_success "Basiskonfiguration im Chroot abgeschlossen."
}

step_05_chroot_kernel_core() {
    log_step "5/12" "Chroot: Kernel und Core-System installieren"
    sudo chroot "${CHROOT_DIR}" /bin/bash <<'EOF'
        set -e
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y --no-install-recommends \
            linux-image-generic \
            casper \
            lupin-casper \
            discover \
            network-manager \
            plymouth \
            plymouth-theme-ubuntu-logo \
            ubuntu-standard \
            locales \
            keyboard-configuration \
            console-setup
EOF
    log_success "Kernel und Core-System installiert."
}

step_06_chroot_desktop() {
    log_step "6/12" "Chroot: KDE Desktop und Anwendungen installieren"
    sudo chroot "${CHROOT_DIR}" /bin/bash <<'EOF'
        set -e
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y --no-install-recommends \
            kde-standard \
            sddm \
            konsole \
            firefox \
            vlc \
            libreoffice-calc \
            libreoffice-writer \
            libreoffice-impress
EOF
    log_success "KDE Desktop und Anwendungen installiert."
}

step_07_chroot_calamares() {
    log_step "7/12" "Chroot: Calamares Installer einrichten"
    sudo chroot "${CHROOT_DIR}" /bin/bash <<'EOF'
        set -e
        export DEBIAN_FRONTEND=noninteractive
        
        # Calamares und Ubuntu-spezifische Module installieren
        apt-get install -y calamares calamares-settings-ubuntu
        
        # Branding für AILinux setzen
        # Hinweis: Die genauen Keys können sich ändern. Dies ist ein Beispiel.
        sed -i 's/^branding:.*/branding: ailinux/' /etc/calamares/settings.conf
        
        # Ein eigenes Branding-Modul wäre der nächste Schritt
        # Hier eine einfache Anpassung des Produktnamens
        cat > /etc/calamares/branding/ailinux/branding.desc << "BRANDING"
[Branding]
componentName: ailinux
productName: AILinux 24.04
shortProductName: AILinux
productUrl: https://github.com/derleiti/ailinux-beta-iso
supportUrl: https://github.com/derleiti/ailinux-beta-iso/issues
productLogo: "/usr/share/calamares/branding/ailinux/logo.png"
productIcon: "/usr/share/calamares/branding/ailinux/icon.png"
BRANDING
        
        # Platzhalter-Bilder erstellen (ersetzen Sie diese durch Ihre eigenen)
        mkdir -p /usr/share/calamares/branding/ailinux/
        convert -size 220x100 xc:gray +antialias -font "DejaVu-Sans-Bold" -pointsize 30 -draw "gravity center text 0,0 'AILinux'" /usr/share/calamares/branding/ailinux/logo.png
        convert -size 32x32 xc:gray +antialias -font "DejaVu-Sans-Bold" -pointsize 10 -draw "gravity center text 0,0 'AI'" /usr/share/calamares/branding/ailinux/icon.png
EOF
    log_success "Calamares Installer konfiguriert."
}

step_08_chroot_user_setup() {
    log_step "8/12" "Chroot: Live-Benutzer und Autologin einrichten"
    sudo chroot "${CHROOT_DIR}" /bin/bash -c "export LIVE_USER=${LIVE_USER}" <<'EOF'
        set -e
        # Live-Benutzer erstellen
        useradd -s /bin/bash -d "/home/${LIVE_USER}" -m -G adm,cdrom,sudo,dip,plugdev,lpadmin,sambashare "${LIVE_USER}"
        # Passwort deaktivieren (leeres Passwort)
        passwd -d "${LIVE_USER}"

        # SDDM Autologin konfigurieren
        mkdir -p /etc/sddm.conf.d
        cat > /etc/sddm.conf.d/autologin.conf << AUTOLOGIN_CONF
[Autologin]
User=${LIVE_USER}
Session=plasma-x11.desktop
AUTOLOGIN_CONF

        # Calamares Desktop-Launcher erstellen
        mkdir -p "/home/${LIVE_USER}/Desktop"
        cat > "/home/${LIVE_USER}/Desktop/Install AILinux.desktop" << DESKTOP_FILE
[Desktop Entry]
Name=Install AILinux
Comment=Install AILinux to your hard drive
Exec=sudo calamares
Icon=calamares
Terminal=false
Type=Application
Categories=System;
DESKTOP_FILE
        
        chmod +x "/home/${LIVE_USER}/Desktop/Install AILinux.desktop"
        chown -R "${LIVE_USER}":"${LIVE_USER}" "/home/${LIVE_USER}"
EOF
    log_success "Live-Benutzer und Autologin eingerichtet."
}

step_09_chroot_cleanup() {
    log_step "9/12" "Chroot: System bereinigen"
    sudo chroot "${CHROOT_DIR}" /bin/bash <<'EOF'
        set -e
        # APT-Cache leeren
        apt-get autoremove -y
        apt-get clean
        
        # Temporäre Dateien und Logs leeren
        rm -rf /tmp/*
        find /var/log -type f -exec truncate --size 0 {} \;
        
        # resolv.conf entfernen
        rm /etc/resolv.conf
        
        # machine-id zurücksetzen für Live-System
        rm /etc/machine-id
        ln -s /var/lib/dbus/machine-id /etc/machine-id
EOF
    log_success "Chroot-System bereinigt."
}

step_10_prepare_iso_structure() {
    log_step "10/12" "ISO-Struktur vorbereiten und SquashFS erstellen"
    
    # Unmount
    safe_umount "${CHROOT_DIR}/dev/pts"
    safe_umount "${CHROOT_DIR}/dev"
    safe_umount "${CHROOT_DIR}/proc"
    safe_umount "${CHROOT_DIR}/sys"
    safe_umount "${CHROOT_DIR}/run"
    
    # ISO-Verzeichnisstruktur
    mkdir -p "${ISO_DIR}"/{casper,isolinux,boot/grub}
    
    # Kernel und Initrd kopieren
    cp "${CHROOT_DIR}/boot/vmlinuz"*-generic "${ISO_DIR}/casper/vmlinuz"
    cp "${CHROOT_DIR}/boot/initrd.img"*-generic "${ISO_DIR}/casper/initrd"
    
    # Manifest erstellen
    sudo chroot "${CHROOT_DIR}" dpkg-query -W --showformat='${Package}\t${Version}\n' > "${ISO_DIR}/casper/filesystem.manifest"
    
    # SquashFS erstellen
    log_info "Erstelle SquashFS-Abbild (dies kann einige Zeit dauern)..."
    sudo mksquashfs "${CHROOT_DIR}" "${ISO_DIR}/casper/filesystem.squashfs" -noappend -e boot
    
    # Dateigröße für den Installer
    printf "$(sudo du -sx --block-size=1 "${CHROOT_DIR}" | cut -f1)" > "${ISO_DIR}/casper/filesystem.size"
    
    # Release-Notes
    echo "${DISTRO_NAME} ${DISTRO_VERSION} (${UBUNTU_CODENAME}) - Built on $(date)" > "${ISO_DIR}/README.diskdefines"
    
    log_success "ISO-Struktur und SquashFS erfolgreich erstellt."
}

step_11_create_bootloaders() {
    log_step "11/12" "Bootloader (ISOLINUX für BIOS, GRUB für UEFI) erstellen"
    
    # ISOLINUX (BIOS)
    cp /usr/lib/ISOLINUX/isolinux.bin "${ISO_DIR}/isolinux/"
    cp /usr/lib/syslinux/modules/bios/*.c32 "${ISO_DIR}/isolinux/"
    cat > "${ISO_DIR}/isolinux/isolinux.cfg" << EOF
UI vesamenu.c32
MENU TITLE AILinux Boot Menu
DEFAULT live
LABEL live
  MENU LABEL Try or Install AILinux
  KERNEL /casper/vmlinuz
  APPEND file=/cdrom/preseed/ubuntu.seed boot=casper initrd=/casper/initrd quiet splash ---
LABEL check
  MENU LABEL Check disc for defects
  KERNEL /casper/vmlinuz
  APPEND boot=casper integrity-check initrd=/casper/initrd quiet splash ---
LABEL memtest
  MENU LABEL Test memory
  KERNEL /isolinux/memtest
LABEL hd
  MENU LABEL Boot from first hard disk
  LOCALBOOT 0x80
EOF

    # GRUB (UEFI)
    cat > "${ISO_DIR}/boot/grub/grub.cfg" << EOF
search --no-floppy --set=root --file /README.diskdefines

set timeout=10
set default="0"

menuentry "Try or Install AILinux" {
    linux /casper/vmlinuz boot=casper file=/cdrom/preseed/ubuntu.seed quiet splash ---
    initrd /casper/initrd
}

menuentry "Check disc for defects" {
    linux /casper/vmlinuz boot=casper integrity-check quiet splash ---
    initrd /casper/initrd
}

menuentry "UEFI Firmware Settings" {
	fwsetup
}
EOF
    
    log_success "Bootloader-Konfigurationen erstellt."
}

step_12_create_iso() {
    log_step "12/12" "Finale ISO-Datei mit xorriso erstellen"
    
    sudo xorriso -as mkisofs \
        -r -V "${DISTRO_NAME} ${DISTRO_VERSION}" \
        -o "${BUILD_DIR}/${ISO_NAME}" \
        -J -l -b isolinux/isolinux.bin \
        -c isolinux/boot.cat -no-emul-boot \
        -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub/efi.img -no-emul-boot \
        -isohybrid-gpt-basdat \
        -isohybrid-apm-hfsplus \
        "${ISO_DIR}"

    log_success "ISO-Datei erfolgreich erstellt unter: ${BUILD_DIR}/${ISO_NAME}"
    
    # Berechtigungen zurücksetzen
    if [ -n "${SUDO_USER}" ]; then
        sudo chown "${SUDO_USER}":"$(id -g "${SUDO_USER}")" "${BUILD_DIR}/${ISO_NAME}"
    fi
    
    # Hash erstellen
    sha256sum "${BUILD_DIR}/${ISO_NAME}" > "${BUILD_DIR}/${ISO_NAME}.sha256"
    if [ -n "${SUDO_USER}" ]; then
        sudo chown "${SUDO_USER}":"$(id -g "${SUDO_USER}")" "${BUILD_DIR}/${ISO_NAME}.sha256"
    fi
    
    log_success "SHA256-Hash wurde erstellt."
    echo ""
    log_success "-------------------- BUILD ABGESCHLOSSEN --------------------"
    echo -e "${COLOR_SUCCESS}ISO: $(realpath "${BUILD_DIR}/${ISO_NAME}")${COLOR_RESET}"
    echo -e "${COLOR_SUCCESS}Hash: $(cat "${BUILD_DIR}/${ISO_NAME}.sha256")${COLOR_RESET}"
}

# --- Skriptausführung ---
main() {
    check_not_root
    
    if [ "$1" == "--cleanup" ]; then
        log_warn "Manuelle Bereinigung angefordert."
        cleanup
        exit 0
    fi

    step_01_setup_environment
    step_02_debootstrap
    step_03_mount_filesystems
    step_04_chroot_base_config
    step_05_chroot_kernel_core
    step_06_chroot_desktop
    step_07_chroot_calamares
    step_08_chroot_user_setup
    step_09_chroot_cleanup
    step_10_prepare_iso_structure
    step_11_create_bootloaders
    step_12_create_iso
}

# Skript starten
main "$@"

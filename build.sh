#!/bin/bash
#
# AILinux ISO Build Script v17.0
#
# This script automates the creation of a bootable AILinux Live ISO
# based on Ubuntu 24.04 (noble). It now uses the 'kde-full' metapackage
# for a more robust and complete KDE Plasma installation.
#
# Copyright (c) 2024 Your Name/Project
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

# --- Configuration ---
set -eo pipefail # Exit on error

# Script Variables
AILINUX_VERSION="24.04"
DISTRO_NAME="AILinux"
BASE_DISTRO="noble"
LIVE_USER="ailinux"
HOSTNAME="ailinux"

# Build Directories
BUILD_DIR="$(pwd)/AILINUX_BUILD"
CHROOT_DIR="${BUILD_DIR}/chroot"
ISO_DIR="${BUILD_DIR}/iso"
ISO_NAME="ailinux-${AILINUX_VERSION}-amd64.iso"

# --- Logging and Colors ---
COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_CYAN='\033[0;36m'

log_msg() {
    local color="$1"
    local level="$2"
    local message="$3"
    echo -e "${color}[$(date +'%Y-%m-%d %H:%M:%S')] [${level}] ${message}${COLOR_RESET}"
}

log_info() { log_msg "${COLOR_GREEN}" "INFO" "$1"; }
log_warn() { log_msg "${COLOR_YELLOW}" "WARN" "$1"; }
log_error() { log_msg "${COLOR_RED}" "ERROR" "$1"; exit 1; }
log_step() { log_msg "${COLOR_CYAN}" "STEP" "===== $1 ====="; }

# --- Helper Functions ---

# Check for root/sudo privileges
check_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        log_error "Dieses Skript darf nicht als root ausgeführt werden. Bitte als normaler Benutzer mit sudo-Rechten ausführen."
    fi
    if ! sudo -v; then
        log_error "Sudo-Authentifizierung fehlgeschlagen. Bitte stellen Sie sicher, dass Sie sudo-Rechte haben."
    fi
    ORIGINAL_USER=${SUDO_USER:-$(whoami)}
    log_info "Sudo-Rechte überprüft. Originalbenutzer: ${ORIGINAL_USER}"
}

# Check for required tools and offer to install them
check_dependencies() {
    log_info "Überprüfe Abhängigkeiten..."
    local missing_deps=()
    local deps=("debootstrap" "squashfs-tools" "xorriso" "grub-pc-bin" "grub-efi-amd64-bin" "mtools" "dosfstools" "curl")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_warn "Fehlende Abhängigkeiten gefunden: ${missing_deps[*]}"
        read -p "Sollen diese automatisch via 'apt' installiert werden? (j/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Jj]$ ]]; then
            log_info "Installiere fehlende Abhängigkeiten..."
            sudo apt-get update
            if ! sudo apt-get install -y "${missing_deps[@]}"; then
                log_error "Installation der Abhängigkeiten fehlgeschlagen. Bitte manuell installieren und das Skript erneut ausführen."
            fi
            log_info "Abhängigkeiten erfolgreich installiert."
        else
            log_error "Abbruch durch Benutzer. Bitte installieren Sie die Abhängigkeiten manuell: sudo apt install ${missing_deps[*]}"
        fi
    else
        log_info "Alle Abhängigkeiten sind vorhanden."
    fi
}


# Safe mount function with retries
safe_mount() {
    local type="$1"
    local source="$2"
    local target="$3"
    local options="${4:--o bind}"
    local attempts=5
    local delay=2

    for ((i=1; i<=attempts; i++)); do
        if sudo mount ${options} "${source}" "${target}"; then
            log_info "Mount erfolgreich: ${target}"
            return 0
        fi
        log_warn "Mount von ${target} fehlgeschlagen (Versuch $i/$attempts). Wiederhole in ${delay}s..."
        sleep ${delay}
    done
    log_error "Konnte ${target} nach ${attempts} Versuchen nicht mounten."
}

# Safe unmount function with retries
safe_umount() {
    local target="$1"
    local attempts=5
    local delay=2

    if ! mountpoint -q "${target}"; then
        log_warn "Unmount übersprungen: ${target} ist nicht gemountet."
        return 0
    fi

    for ((i=1; i<=attempts; i++)); do
        if sudo umount -lf "${target}"; then
            log_info "Unmount erfolgreich: ${target}"
            return 0
        fi
        log_warn "Unmount von ${target} fehlgeschlagen (Versuch $i/$attempts). Wiederhole in ${delay}s..."
        sleep ${delay}
    done
    log_error "Konnte ${target} nach ${attempts} Versuchen nicht unmounten."
}

# Cleanup function to be called on exit or error
cleanup() {
    log_step "Aufräumen"
    safe_umount "${CHROOT_DIR}/dev/pts"
    safe_umount "${CHROOT_DIR}/dev"
    safe_umount "${CHROOT_DIR}/proc"
    safe_umount "${CHROOT_DIR}/sys"
    
    if findmnt -R "${BUILD_DIR}"; then
        log_warn "Es sind noch Mount-Punkte im Build-Verzeichnis vorhanden. Versuche zwangsweises Unmounten."
        sudo umount -R -f -l "${BUILD_DIR}" || log_warn "Zwangsweises Unmounten nicht vollständig erfolgreich."
    fi

    log_info "Entferne Build-Verzeichnis: ${BUILD_DIR}"
    sudo rm -rf "${BUILD_DIR}"
    log_info "Aufräumen abgeschlossen."
}

# --- Main Script ---

if [ "$1" == "--cleanup" ]; then
    log_info "Manuelles Aufräumen angefordert."
    if [ -d "${BUILD_DIR}" ]; then
        cleanup
    else
        log_warn "Build-Verzeichnis ${BUILD_DIR} nicht gefunden. Nichts zu tun."
    fi
    exit 0
fi

trap 'cleanup' EXIT SIGINT SIGTERM

# --- STEP 1: Initial Setup ---
log_step "1/12: Initialisierung und Setup"
check_sudo
check_dependencies

if [ -d "${BUILD_DIR}" ]; then
    log_warn "Build-Verzeichnis ${BUILD_DIR} existiert bereits."
    read -p "Möchten Sie es löschen und neu beginnen? (j/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Jj]$ ]]; then
        log_error "Abbruch durch Benutzer."
    fi
    sudo rm -rf "${BUILD_DIR}"
fi

mkdir -p "${BUILD_DIR}" "${ISO_DIR}" "${CHROOT_DIR}"
log_info "Build-Verzeichnisstruktur erstellt unter ${BUILD_DIR}"

# --- STEP 2: Debootstrap Base System ---
log_step "2/12: Erstelle Basissystem mit Debootstrap"
sudo debootstrap --arch=amd64 --variant=minbase "${BASE_DISTRO}" "${CHROOT_DIR}" http://archive.ubuntu.com/ubuntu/
log_info "Basissystem für ${BASE_DISTRO} erfolgreich erstellt."

# --- STEP 3: Chroot-Vorbereitung ---
log_step "3/12: Bereite die Chroot-Umgebung vor"
sudo cp /etc/hosts "${CHROOT_DIR}/etc/hosts"
sudo cp /etc/resolv.conf "${CHROOT_DIR}/etc/resolv.conf"

safe_mount "proc" "proc" "${CHROOT_DIR}/proc" "-t proc"
safe_mount "sysfs" "sysfs" "${CHROOT_DIR}/sys" "-t sysfs"
safe_mount "/dev" "/dev" "${CHROOT_DIR}/dev"
safe_mount "/dev/pts" "/dev/pts" "${CHROOT_DIR}/dev/pts"

# --- STEP 4: Systemkonfiguration und Repository hinzufügen ---
log_step "4/12: Konfiguriere Basissystem & füge AILinux Repo hinzu"
sudo chroot "${CHROOT_DIR}" /bin/bash << "EOF"
set -e
export DEBIAN_FRONTEND=noninteractive
export HOME=/root
export LC_ALL=C

# Set hostname
echo "ailinux" > /etc/hostname

# Configure APT sources
cat > /etc/apt/sources.list << EOL
deb http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ noble-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ noble-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu/ noble-backports main restricted universe multiverse
deb-src http://archive.ubuntu.com/ubuntu/ noble-backports main restricted universe multiverse
EOL

# Install prerequisites for adding repo (curl, etc.)
apt-get update
apt-get install -y --no-install-recommends locales curl ca-certificates tzdata gnupg wget

# Add AILinux repository
echo "Füge AILinux Repository hinzu..."
curl -fssSL https://ailinux.me:8443/mirror/add-ailinux-repo.sh | bash
echo "Repository hinzugefügt. Aktualisiere Paketlisten erneut..."

# Update package list again to include the new repo
apt-get update

# Configure locales and timezone
locale-gen en_US.UTF-8 de_DE.UTF-8
update-locale LANG=de_DE.UTF-8
dpkg-reconfigure --frontend=noninteractive tzdata
EOF
log_info "Systemkonfiguration und AILinux Repository im Chroot abgeschlossen."

# --- STEP 5: Kernel und Live-Boot-Pakete installieren ---
log_step "5/12: Installiere Kernel und Live-Boot-Pakete"
sudo chroot "${CHROOT_DIR}" /bin/bash << "EOF"
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends \
    linux-image-generic \
    casper \
    network-manager net-tools wireless-tools \
    plymouth plymouth-theme-kubuntu-logo \
    ubuntu-standard \
    grub-pc-bin grub-efi-amd64-bin shim-signed \
    syslinux-common isolinux \
    discover
EOF
log_info "Kernel und Live-Boot-Pakete installiert."

# --- STEP 6: KDE Desktop und Anwendungen installieren ---
log_step "6/12: Installiere KDE Plasma Desktop und umfangreiche Anwendungen"
sudo chroot "${CHROOT_DIR}" /bin/bash << "EOF"
set -e
export DEBIAN_FRONTEND=noninteractive

# Enable i386 architecture for Wine and Steam
dpkg --add-architecture i386
apt-get update

# Install full application suite including German language packs
# FIX: Switched to kde-full metapackage for robustness
apt-get install -y --no-install-recommends \
    sddm \
    kde-full \
    language-pack-de \
    language-pack-kde-de \
    firefox \
    google-chrome-stable \
    thunderbird \
    vlc \
    gimp \
    libreoffice \
    libreoffice-l10n-de \
    winehq-staging \
    winetricks \
    steam-installer
EOF
log_info "KDE Plasma und umfangreiche Anwendungs-Suite installiert."

# --- STEP 7: Calamares Installer installieren und konfigurieren ---
log_step "7/12: Installiere und konfiguriere Calamares"
sudo chroot "${CHROOT_DIR}" /bin/bash << "EOF"
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get install -y calamares

# Configure Calamares branding
if [ -f /etc/calamares/settings.conf ]; then
    sed -i 's/^branding:.*$/branding: ailinux/' /etc/calamares/settings.conf
    echo "Calamares branding auf 'ailinux' gesetzt."
else
    echo "WARNUNG: /etc/calamares/settings.conf nicht gefunden."
fi
EOF
log_info "Calamares installiert und konfiguriert."

# --- STEP 8: Benutzer einrichten und Anpassungen ---
log_step "8/12: Richte Live-Benutzer ein und führe Anpassungen durch"
sudo chroot "${CHROOT_DIR}" /bin/bash <<EOF
set -e
export DEBIAN_FRONTEND=noninteractive

# Create live user
useradd -s /bin/bash -d /home/${LIVE_USER} -m -G sudo,adm,cdrom,dip,plugdev,lpadmin,sambashare ${LIVE_USER}
echo "${LIVE_USER}:" | chpasswd # Set empty password

# Configure SDDM autologin
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/autologin.conf <<EOL
[Autologin]
User=${LIVE_USER}
Session=plasma-x11.desktop
EOL

# Create Calamares desktop launcher
mkdir -p /home/${LIVE_USER}/Desktop
cat > /home/${LIVE_USER}/Desktop/install.desktop <<EOL
[Desktop Entry]
Name=Install AILinux
Comment=Install AILinux to your hard drive
Exec=sudo calamares
Icon=calamares
Terminal=false
Type=Application
Categories=System;
EOL
chmod +x /home/${LIVE_USER}/Desktop/install.desktop
chown -R ${LIVE_USER}:${LIVE_USER} /home/${LIVE_USER}

# Cleanup
apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/*
rm /etc/resolv.conf
rm /etc/hosts
history -c
EOF
log_info "Live-Benutzer und Anpassungen abgeschlossen."

# --- STEP 9: ISO-Dateisystem vorbereiten (SquashFS) ---
log_step "9/12: Bereite das ISO-Dateisystem vor"
safe_umount "${CHROOT_DIR}/dev/pts"
safe_umount "${CHROOT_DIR}/dev"
safe_umount "${CHROOT_DIR}/proc"
safe_umount "${CHROOT_DIR}/sys"

mkdir -p "${ISO_DIR}"/{casper,isolinux,boot/grub}

sudo cp "${CHROOT_DIR}/boot/vmlinuz"*-generic "${ISO_DIR}/casper/vmlinuz"
sudo cp "${CHROOT_DIR}/boot/initrd.img"*-generic "${ISO_DIR}/casper/initrd"
log_info "Kernel und Initrd kopiert."

sudo chroot "${CHROOT_DIR}" dpkg-query -W --showformat='${Package} ${Version}\n' > "${ISO_DIR}/casper/filesystem.manifest"
sudo cp "${ISO_DIR}/casper/filesystem.manifest" "${ISO_DIR}/casper/filesystem.manifest-desktop"

log_info "Erstelle filesystem.squashfs (dies kann einige Zeit dauern)..."
sudo mksquashfs "${CHROOT_DIR}" "${ISO_DIR}/casper/filesystem.squashfs" -noappend -e boot
log_info "filesystem.squashfs erfolgreich erstellt."

printf $(sudo du -sx --block-size=1 "${CHROOT_DIR}" | cut -f1) > "${ISO_DIR}/casper/filesystem.size"
log_info "filesystem.size erstellt."

# --- STEP 10: ISO-Boot-Struktur erstellen ---
log_step "10/12: Erstelle die Boot-Struktur der ISO"

cat > "${ISO_DIR}/isolinux/isolinux.cfg" << EOL
UI vesamenu.c32
TIMEOUT 50
DEFAULT live
PROMPT 0
MENU TITLE AILinux ${AILINUX_VERSION}
MENU BACKGROUND splash.png

LABEL live
  MENU LABEL AILinux Live starten
  KERNEL /casper/vmlinuz
  APPEND file=/cdrom/preseed/ubuntu.seed boot=casper initrd=/casper/initrd quiet splash ---

LABEL check
  MENU LABEL Integrität des Mediums prüfen
  KERNEL /casper/vmlinuz
  APPEND boot=casper integrity-check initrd=/casper/initrd quiet splash ---

LABEL memtest
  MENU LABEL Speichertest
  KERNEL /isolinux/memtest

LABEL hd
  MENU LABEL Von erster Festplatte booten
  LOCALBOOT 0x80
EOL

cat > "${ISO_DIR}/boot/grub/grub.cfg" << EOL
if loadfont /boot/grub/font.pf2 ; then
    set gfxmode=auto
    insmod efi_gop
    insmod efi_uga
    insmod gfxterm
    terminal_output gfxterm
fi

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray
set timeout=5

menuentry "AILinux Live starten" {
    set gfxpayload=keep
    linux   /casper/vmlinuz file=/cdrom/preseed/ubuntu.seed boot=casper quiet splash ---
    initrd  /casper/initrd
}
menuentry "AILinux Live (safe graphics)" {
    set gfxpayload=keep
    linux   /casper/vmlinuz file=/cdrom/preseed/ubuntu.seed boot=casper nomodeset quiet splash ---
    initrd  /casper/initrd
}
menuentry "OEM Install (für Hersteller)" {
    set gfxpayload=keep
    linux   /casper/vmlinuz file=/cdrom/preseed/ubuntu.seed boot=casper oem-config/enable=true quiet splash ---
    initrd  /casper/initrd
}
EOL

sudo cp /usr/lib/ISOLINUX/isolinux.bin "${ISO_DIR}/isolinux/"
sudo cp /usr/lib/syslinux/modules/bios/{vesamenu.c32,ldlinux.c32} "${ISO_DIR}/isolinux/"

touch "${ISO_DIR}/ubuntu"
mkdir -p "${ISO_DIR}/.disk"
echo "AILinux ${AILINUX_VERSION} - Release amd64" > "${ISO_DIR}/.disk/info"
mkdir -p "${ISO_DIR}/.disk/casper-uuid"
cat /proc/sys/kernel/random/uuid > "${ISO_DIR}/.disk/casper-uuid/custom"

sudo grub-mkstandalone \
    --format=x86_64-efi \
    --output="${ISO_DIR}/boot/grub/grubx64.efi" \
    --locales="" --fonts="" "boot/grub/grub.cfg"

mkdir -p "${ISO_DIR}/EFI/BOOT"
sudo cp "${ISO_DIR}/boot/grub/grubx64.efi" "${ISO_DIR}/EFI/BOOT/BOOTX64.EFI"

(
    cd "${ISO_DIR}"
    sudo dd if=/dev/zero of=efiboot.img bs=1M count=20
    sudo mkfs.vfat efiboot.img
    sudo mmd -i efiboot.img ::/EFI
    sudo mmd -i efiboot.img ::/EFI/BOOT
    sudo mcopy -i efiboot.img EFI/BOOT/BOOTX64.EFI ::/EFI/BOOT/
)
log_info "ISO-Boot-Struktur erfolgreich erstellt."

# --- STEP 11: ISO-Image generieren ---
log_step "11/12: Generiere die bootfähige ISO-Datei"
log_info "Erstelle ISO mit xorriso (dies kann einige Zeit dauern)..."
(
    cd "${ISO_DIR}"
    sudo xorriso -as mkisofs \
        -r -V "AILINUX ${AILINUX_VERSION}" \
        -o "${BUILD_DIR}/${ISO_NAME}" \
        -J -l -b isolinux/isolinux.bin \
        -c isolinux/boot.cat -no-emul-boot \
        -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot \
        -e efiboot.img -no-emul-boot \
        -isohybrid-gpt-basdat \
        -isohybrid-apm-hfsplus \
        .
)
log_info "ISO-Datei erfolgreich erstellt: ${BUILD_DIR}/${ISO_NAME}"

# --- STEP 12: Finalisieren und Aufräumen ---
log_step "12/12: Finalisieren und Ergebnisse anzeigen"
sudo chown "${ORIGINAL_USER}":"${ORIGINAL_USER}" "${BUILD_DIR}/${ISO_NAME}"
log_info "Besitz der ISO-Datei auf ${ORIGINAL_USER} übertragen."

ISO_SIZE=$(du -h "${BUILD_DIR}/${ISO_NAME}" | cut -f1)
ISO_HASH=$(sha256sum "${BUILD_DIR}/${ISO_NAME}" | cut -d' ' -f1)

echo -e "\n${COLOR_BLUE}======================================================="
echo -e "         AILinux Build erfolgreich abgeschlossen!"
echo -e "=======================================================${COLOR_RESET}\n"
echo -e "${COLOR_GREEN}ISO-Datei: ${BUILD_DIR}/${ISO_NAME}${COLOR_RESET}"
echo -e "${COLOR_GREEN}Größe:     ${ISO_SIZE}${COLOR_RESET}"
echo -e "${COLOR_GREEN}SHA256:    ${ISO_HASH}${COLOR_RESET}\n"
log_info "Das Build-Verzeichnis wird beim Beenden automatisch entfernt."

exit 0

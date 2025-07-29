#!/bin/bash
#
# AILinux ISO Build Cleanup-Skript
# Bereinigt Reste eines fehlgeschlagenen oder unterbrochenen Build-Prozesses.
# Unmountet alle Pseudo-Dateisysteme und löscht das Build-Verzeichnis.

set -e

# --- Konfiguration ---
# Stelle sicher, dass diese Variable mit deinem build.sh Skript übereinstimmt
BUILD_DIR="AILINUX_BUILD"
CHROOT_DIR="${BUILD_DIR}/chroot"

# --- Farb- und Logging-Funktionen ---
COLOR_RESET='\033[0m'
COLOR_INFO='\033[0;34m'
COLOR_SUCCESS='\033[0;32m'
COLOR_WARN='\033[0;33m'
COLOR_ERROR='\033[0;31m'

log() {
    local level_color="$1"
    local level_text="$2"
    local message="$3"
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${level_color}[${level_text}]${COLOR_RESET} ${message}"
}

# --- Haupt-Aufräumlogik ---

log "${COLOR_WARN}" "CLEANUP" "Starte die Bereinigung für AILinux Build..."

# Fehler während der Bereinigung ignorieren, damit das Skript nicht abbricht
set +e

# Unmount in umgekehrter Reihenfolge, um Abhängigkeiten aufzulösen
log "${COLOR_INFO}" "INFO" "Versuche, alle Mount-Punkte zu lösen..."
if mountpoint -q "${CHROOT_DIR}/run"; then sudo umount -f -l "${CHROOT_DIR}/run"; fi
if mountpoint -q "${CHROOT_DIR}/sys"; then sudo umount -f -l "${CHROOT_DIR}/sys"; fi
if mountpoint -q "${CHROOT_DIR}/proc"; then sudo umount -f -l "${CHROOT_DIR}/proc"; fi
if mountpoint -q "${CHROOT_DIR}/dev/pts"; then sudo umount -f -l "${CHROOT_DIR}/dev/pts"; fi
if mountpoint -q "${CHROOT_DIR}/dev"; then sudo umount -f -l "${CHROOT_DIR}/dev"; fi

# Prüfen, ob das Build-Verzeichnis existiert
if [ -d "${BUILD_DIR}" ]; then
    log "${COLOR_WARN}" "CLEANUP" "Build-Verzeichnis '${BUILD_DIR}' gefunden. Entferne es jetzt..."
    
    # Das Verzeichnis mit root-Rechten löschen
    sudo rm -rf "${BUILD_DIR}"
    
    # Überprüfen, ob das Löschen erfolgreich war
    if [ -d "${BUILD_DIR}" ]; then
        log "${COLOR_ERROR}" "ERROR" "Das Verzeichnis '${BUILD_DIR}' konnte nicht vollständig entfernt werden."
        log "${COLOR_ERROR}" "ERROR" "Bitte führe manuell aus: sudo rm -rf ${BUILD_DIR}"
        exit 1
    else
        log "${COLOR_SUCCESS}" "SUCCESS" "Build-Verzeichnis erfolgreich entfernt."
    fi
else
    log "${COLOR_INFO}" "INFO" "Kein Build-Verzeichnis '${BUILD_DIR}' gefunden. Nichts zu tun."
fi

log "${COLOR_SUCCESS}" "SUCCESS" "Bereinigung abgeschlossen. Dein Arbeitsverzeichnis ist jetzt sauber."
echo ""

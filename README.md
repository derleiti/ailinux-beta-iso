AILinux ISO Build Skript
Dieses Repository enthält das offizielle Build-Skript zur Erstellung einer bootfähigen AILinux Live-ISO. Das Skript ist darauf ausgelegt, einen vollständigen, robusten und wiederholbaren Build-Prozess auf einem Debian-basierten Host-System (wie Ubuntu) durchzuführen.

✨ Features
Automatisierter 12-Schritte-Prozess: Von der System-Basis bis zur finalen ISO-Datei ist der gesamte Ablauf automatisiert.

UEFI & BIOS Support: Erstellt eine hybride ISO, die sowohl auf modernen UEFI-Systemen als auch auf älteren BIOS-Rechnern bootet.

Grafischer Installer: Integriert den Calamares Installer für eine benutzerfreundliche Systeminstallation.

Robustes Fehler-Handling: Umfasst eine sichere Mount-/Unmount-Logik und eine automatische Cleanup-Funktion, die bei Fehlern oder am Ende des Builds aufräumt.

Zentralisierte Konfiguration: Nutzt ein externes Skript (add-ailinux-repo.sh) zur Einrichtung aller Paketquellen, was die Wartung vereinfacht.

Anpassbar: Das Skript ist durch Variablen und klar getrennte Funktionsblöcke leicht anpassbar.

🚀 Erste Schritte
1. Voraussetzungen (Host-System)
Stelle sicher, dass dein Host-System (z. B. Ubuntu 24.04) über alle notwendigen Werkzeuge verfügt. Führe dazu folgenden Befehl aus:

Bash

sudo apt-get update
sudo apt-get install debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin \
  shim-signed ovmf mtools wget curl gnupg isolinux syslinux-common dosfstools psmisc lsof
2. Skript ausführen
Um den Build-Prozess zu starten, mache das Skript ausführbar und führe es aus:

Bash

chmod +x build.sh
./build.sh
Das Skript darf nicht mit sudo oder als root gestartet werden. Es wird bei Bedarf selbstständig nach sudo-Rechten fragen.

3. Notfall-Cleanup
Sollte der Build-Prozess einmal fehlschlagen und Mount-Punkte oder Verzeichnisse zurücklassen, kannst du die Notfall-Cleanup-Funktion nutzen:

Bash

./build.sh --cleanup
🛠️ Der Build-Prozess im Detail
Das Skript folgt einem bewährten 12-Schritte-Ablauf, um eine konsistente und funktionale ISO zu gewährleisten.

Schritt	Aktion	Beschreibung
1	Host vorbereiten	Installiert alle Abhängigkeiten auf dem Build-Rechner.
2	Verzeichnisstruktur anlegen	Erstellt eine saubere Arbeitsumgebung (AILINUX_BUILD/chroot und AILINUX_BUILD/iso).
3	Basissystem installieren	Installiert via debootstrap ein Ubuntu-Minimalsystem in das chroot-Verzeichnis.
4	Netzwerk & Service-Block	Konfiguriert DNS für die Chroot-Umgebung und verhindert den Start von Diensten.
5	Chroot-Skript erstellen	Generiert dynamisch ein Skript, das alle Operationen innerhalb des Chroots ausführt.
6	Chroot-Umgebung einrichten	Führt das Chroot-Skript aus: Repositories hinzufügen, Pakete installieren, System
konfigurieren (Live-User, Autologin, Calamares).
7	Pseudo-Dateisysteme unmounten	Bereinigt nach dem Chroot alle System-Mounts (/dev, /proc, etc.) sicher.
8	SquashFS erzeugen	Komprimiert das gesamte chroot-Verzeichnis in die filesystem.squashfs-Datei.
9	Manifest & Metadaten generieren	Erstellt eine Paketliste (.manifest), die Größen-Info und das .disk/info-Branding.
10	Bootloader einrichten	Konfiguriert ISOLINUX für BIOS-Boot und GRUB in einem efi.img für UEFI-Boot.
11	Finale ISO erzeugen	Nutzt xorriso, um alle Komponenten zu einer bootfähigen Hybrid-ISO zusammenzufügen.
12	Abschluss & Validierung	Setzt den Besitz der ISO-Datei auf den ursprünglichen Benutzer zurück und gibt Größe
sowie die SHA256-Prüfsumme aus.

In Google Sheets exportieren
🔧 Calamares-Integration
Der grafische Installer Calamares wird automatisch in das System integriert:

Installation: Das Paket calamares wird zusammen mit der Desktop-Umgebung installiert.

Desktop-Launcher: Eine .desktop-Datei (install-ailinux.desktop) wird auf dem Desktop des Live-Users platziert, die den Installer mit pkexec calamares startet.

Branding: Das Skript passt die settings.conf von Calamares an, um das Branding ailinux zu verwenden. Eigene Branding-Assets können im Chroot unter /etc/calamares/branding/ailinux/ platziert werden.

Wichtiger Hinweis: Der Build-Prozess erzeugt ein einzelnes filesystem.squashfs, da dies die von Calamares erwartete und am besten unterstützte Methode ist.

📜 Lizenz
Dieses Projekt steht unter der MIT-Lizenz.

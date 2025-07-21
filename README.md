AILinux Premium 24.04 - ISO Build-Skript
Willkommen beim offiziellen Repository für das AILinux Premium 24.04 Build-Skript. Dieses Projekt stellt ein automatisiertes Skript zur Verfügung, um eine voll ausgestattete, bootfähige Live-ISO von AILinux zu erstellen, die auf Ubuntu 24.04 LTS "Noble Numbat" basiert.

🌟 Vision & Ziel
Das Ziel dieses Projekts ist die Erstellung einer "Premium Edition" von AILinux. Diese Edition soll eine nahtlose "Out-of-the-Box"-Erfahrung für Power-User, Entwickler und Kreative bieten. Der Fokus liegt auf einer stabilen Ubuntu-Basis, angereichert mit einer sorgfältig kuratierten Auswahl an vorinstallierter Software und einer modernen KDE Plasma Desktop-Umgebung.

✨ Features
Solide Basis: Baut auf der Stabilität und Kompatibilität von Ubuntu 24.04 LTS auf.

Vollständiger KDE Desktop: Enthält die komplette KDE Plasma Desktop-Umgebung (kde-full) für eine maximale Funktionalität.

Umfangreiche Software-Suite: Eine breite Palette an vorinstallierter Software für Produktivität, Entwicklung und Multimedia (siehe Liste unten).

Einfacher Installer: Verwendet Calamares mit AILinux-Branding für eine unkomplizierte Installation auf der Festplatte.

Universell bootfähig: Unterstützt sowohl modernen UEFI- als auch traditionellen BIOS-Boot.

Optimierter Build-Prozess: Das Erstellen der ISO ist vollständig automatisiert und für Geschwindigkeit mit zstd-Kompression optimiert.

Zentralisierte Paketquellen: Nutzt einen eigenen AILinux-Mirror, um konsistente und schnelle Paket-Downloads zu gewährleisten.

📦 Enthaltene Software (Auszug)
Kategorie

Software

Web & Kommunikation

Firefox, Google Chrome, Thunderbird

Office

Vollständige LibreOffice Suite

Multimedia

VLC Media Player, GIMP

Windows-Kompatibilität

Wine (Staging) & Winetricks

Entwicklung

VS Code, Git, Build-Essentials, Python, Node.js, JDK

Systemwerkzeuge

Konsole, GParted, Htop, Neofetch

🚀 Wie man die ISO erstellt
Voraussetzungen
Stellen Sie sicher, dass Sie ein Debian-basiertes System (vorzugsweise Ubuntu 24.04) verwenden und die folgenden Pakete installiert sind: git, debootstrap, xorriso, squashfs-tools, grub-pc-bin, grub-efi-amd64-bin und weitere, die das Skript bei Bedarf automatisch nachinstalliert.

Build-Anleitung
Repository klonen:

git clone https://github.com/derleiti/ailinux-beta-iso.git
cd ailinux-beta-iso

Build-Skript ausführbar machen:

chmod +x build.sh

Build-Prozess starten:
Das Skript benötigt sudo-Rechte für Operationen wie mount und debootstrap. Führen Sie es als normaler Benutzer aus; es wird bei Bedarf nach Ihrem Passwort fragen.

./build.sh

Der Prozess wird einige Zeit in Anspruch nehmen, abhängig von Ihrer Internetverbindung und Systemleistung. Nach Abschluss finden Sie die fertige ailinux-24.04-premium-amd64.iso und die zugehörige .sha256-Prüfsummendatei direkt im Projektverzeichnis.

Aufräumen nach einem fehlgeschlagenen Build
Wenn der Build-Prozess unterbrochen wird, können temporäre Dateien mit root-Rechten zurückbleiben. Verwenden Sie das cleanup.sh-Skript, um Ihr Verzeichnis zu bereinigen:

chmod +x cleanup.sh
./cleanup.sh

📜 Lizenz
Dieses Projekt steht unter der MIT-Lizenz. Details finden Sie in der LICENSE-Datei.

📄 Vorgeschlagene README.md für dein Repository ailinux-beta-iso
markdown
Kopieren
Bearbeiten
# AILinux 24.04 Premium – AI-powered Linux Distribution

**AILinux** ist eine moderne, KI-integrierte Live-Linux-Distribution auf Basis von **Ubuntu 24.04 (Noble Numbat)**.  
Sie wurde entwickelt, um ein vollständig offline-fähiges System mit eingebautem KI-Assistenten bereitzustellen –  
einschließlich Live-Modus, Calamares-Installer und einem lokalen `aihelp` CLI-Tool für KI-gestützte Systemanalyse.

---

## 📦 ISO-Download

> 🔗 **[Download der aktuellen ISO (5.1 GB)](https://ailinux.me/iso/ailinux-24.04-premium-amd64.iso)**  
> 🔐 [SHA256 Prüfsumme](https://ailinux.me/iso/ailinux-24.04-premium-amd64.iso.sha256)

---

## ✨ Features

- 🧠 **AILinux Helper** – KI-gestützter Systemassistent (`aihelp`), powered by Mistral API
- 💻 **Plasma Desktop** – Voll ausgestatteter KDE 6.x mit SDDM Autologin
- 🌐 **Web & Media** – Firefox, Chrome, VLC, LibreOffice, GIMP, Thunderbird
- 🎮 **Gaming-ready** – WineHQ (Staging), Winetricks, Steam-kompatibel
- 🧰 **Entwicklungstools** – Python3, NodeJS, VS Code, Build-Essentials, JDK
- 🛠️ **System-Tools** – Calamares Installer, GParted, Htop, Bluetooth, Druckertreiber
- 🔒 **UEFI Secure Boot kompatibel** – mit `shimx64.efi.signed` und GRUB

---

## 🔧 ISO selbst bauen

Du kannst die ISO jederzeit lokal mit dem `build.sh` Skript erzeugen:

```bash
git clone https://github.com/derleiti/ailinux-beta-iso.git
cd ailinux-beta-iso

# Optional: .env Datei für KI-Zugang
cp .env.example .env
nano .env   # trage deinen Mistral API Key ein

# Build starten (dauert ca. 15–25 Minuten)
./build.sh
💡 Du brauchst rootfähigen Benutzerzugang (per sudo) und ca. 10 GB freien Speicher.

📁 Projektstruktur
bash
Kopieren
Bearbeiten
.
├── build.sh              # Haupt-Buildskript für ISO
├── clean.sh              # Bereinigt Mounts & TEMP
├── branding/             # Logo, Icon, Welcome-Bild für Calamares
├── AILINUX_BUILD/        # Temporäres Arbeitsverzeichnis beim Build
├── .env / .env.example   # API-Konfiguration für AILinux Helper
├── prompt.txt            # Prompt zur Claude-Kommunikation
├── push.sh               # Sicheres Git-Push-Skript mit PAT
└── README.md             # Dieses Dokument
🔐 Lizenz
MIT License
© 2024 derleiti

🤖 Kontakt & Mitwirken
Fragen oder Beiträge willkommen!
Brumo, Nova & Markus freuen sich über jeden, der bei AILinux mitbasteln möchte.
➡️ ailinux.me

yaml
Kopieren
Bearbeiten

---

✅ Wenn du willst, kann ich dir das direkt als Datei `README.md` ausgeben oder in dein Repo-Verzeichnis schreiben lassen.  
Willst du auch eine passende `index.html` für die ISO-Downloadseite?


# AILinux Beta

![AILinux](https://img.shields.io/badge/AILinux-24.04%20Premium-blue.svg)
!([https://img.shields.io/badge/Status-Beta-orange.svg](https://img.shields.io/badge/Status-Beta-orange.svg))
![License](https://img.shields.io/badge/License-MIT-green.svg)

AILinux ist ein experimentelles, bootfähiges Linux-Betriebssystem, das eine tief integrierte, KI-gestützte Systemassistenz direkt auf den Desktop bringt. Dieses Projekt zielt darauf ab, die Lücke zwischen dem Betriebssystem und künstlicher Intelligenz zu schließen und eine Umgebung zu schaffen, in der die KI ein aktiver Partner bei der Systemverwaltung und Fehlerbehebung ist.

**Dieses Projekt befindet sich in einer frühen Beta-Phase. Es ist für Entwickler, Tester und Enthusiasten gedacht. Rechnen Sie mit Fehlern und Instabilität. Nicht für den produktiven Einsatz empfohlen.**

---

## 核心功能 (Core Features)

*   **Vollständiges Betriebssystem (ISO):** AILinux wird als bootfähige `.iso`-Datei vertrieben. Sie können es in einer Live-Sitzung ausprobieren oder es mithilfe des Calamares-Installers auf Ihrer Festplatte installieren.
*   **Integrierter KI-Assistent:** Der Kern von AILinux ist der `aihelp`-Befehl, ein Konversations-KI-Agent, der darauf trainiert ist, bei Linux-Systemproblemen zu helfen.
*   **Cloud-gestützte Intelligenz:** Um modernste Leistung zu gewährleisten, nutzt der Assistent eine externe, Cloud-basierte Large Language Model (LLM) API.
*   **Premium Desktop-Erlebnis:** Basiert auf Ubuntu 24.04 LTS mit einem vorkonfigurierten KDE Plasma Desktop und einer umfassenden Suite von vorinstallierten Anwendungen (Chrome, VS Code, LibreOffice, GIMP, Wine etc.).
*   **Anpassbare KI-Persönlichkeit:** Das Verhalten und die Rolle der KI werden durch eine lokale `prompt.txt`-Datei definiert, die eine konsistente und fokussierte Interaktion gewährleistet.

## ⚙️ Konfiguration: Der API-Schlüssel

Da AILinux eine externe KI-API verwendet, **müssen Sie Ihren eigenen API-Schlüssel angeben**, damit der `aihelp`-Assistent funktioniert.

1.  **Erstellen Sie eine `.env`-Datei:** Kopieren Sie die Vorlage `.env.example` in eine neue Datei mit dem Namen `.env`:bash
    cp.env.example.env
    ```
2.  **Fügen Sie Ihren Schlüssel hinzu:** Öffnen Sie die `.env`-Datei mit einem Texteditor und fügen Sie Ihren API-Schlüssel ein. Die Datei sollte so aussehen:
    ```
    #.env - API-Schlüssel für den Zugriff auf die KI
    MISTRALAPIKEY=ihr_persoenlicher_api_schluessel_hier
    ```

**Ihre Anfragen werden zur Verarbeitung an den externen API-Anbieter gesendet. Seien Sie sich der Datenschutzimplikationen bewusst.**

## 🚀 Erste Schritte

1.  **ISO herunterladen:** Laden Sie die neueste `.iso`-Datei aus dem(https://github.com/derleiti/ailinux-beta-iso/releases) dieses Repositorys herunter.
2.  **Bootfähigen USB-Stick erstellen:** Verwenden Sie ein Tool wie(https://www.balena.io/etcher/) oder `dd`, um die `.iso`-Datei auf einen USB-Stick zu schreiben.
3.  **Live-System booten:** Starten Sie Ihren Computer vom USB-Stick, um AILinux im Live-Modus auszuprobieren.
4.  **(Optional) Installieren:** Verwenden Sie das "AILinux installieren"-Symbol auf dem Desktop, um den Calamares-Installer zu starten und AILinux dauerhaft auf Ihrer Festplatte zu installieren.

## 🤖 Verwendung des `aihelp`-Assistenten

Öffnen Sie ein Terminal (`konsole`) und verwenden Sie den `aihelp`-Befehl, um Unterstützung zu erhalten.

**Beispiel 1: Analyse einer Fehlermeldung**
```bash
aihelp "Mein apt update schlägt mit dem Fehler 'E: Could not get lock /var/lib/dpkg/lock-frontend' fehl."
```

**Beispiel 2: Analyse einer Log-Datei**
```bash
aihelp --log /var/log/syslog
```

**Beispiel 3: Interaktive Sitzung**
Führen Sie einfach `aihelp` ohne Argumente aus, um eine interaktive Sitzung zu starten. Fügen Sie Ihre Frage ein und drücken Sie `Ctrl+D`, wenn Sie fertig sind.

## 🛠️ Aus dem Quellcode erstellen

Für fortgeschrittene Benutzer, die die ISO selbst erstellen möchten:

1.  **Repository klonen:**
    ```bash
    git clone [https://github.com/derleiti/ailinux-beta-iso.git](https://github.com/derleiti/ailinux-beta-iso.git)
    cd ailinux-beta-iso
    ```
2.  **Abhängigkeiten installieren:**
    Stellen Sie sicher, dass alle für den Build erforderlichen Pakete installiert sind (z.B. `debootstrap`, `squashfs-tools`, `xorriso`, `git`).
    ```bash
    sudo apt-get install debootstrap squashfs-tools xorriso git curl...
    ```
3.  **(Optional) API-Schlüssel für den Build bereitstellen:** Wenn Sie möchten, dass Ihr API-Schlüssel direkt in die ISO integriert wird, erstellen Sie jetzt Ihre `.env`-Datei.
4.  **Build-Skript ausführen:**
    ```bash
   ./build.sh
    ```
    Die fertige `.iso`-Datei befindet sich nach Abschluss im Hauptverzeichnis des Projekts.

## Lizenz

Dieses Projekt ist unter der MIT-Lizenz lizenziert. Siehe die `LICENSE`-Datei für weitere Details.
```


AILinux Beta ISO Builder



Version: 18.0Codename: Premium AI EditionAuthor: @derleiti

🚀 Übersicht

Dieses Repository enthält das vollständige Buildsystem zur Erstellung einer AILinux Live-ISO, basierend auf Ubuntu 24.04 (Noble) und erweitert um:

🧠 KI-Funktionen über Mixtral (aihelp)

🖥️ Vollständige KDE Plasma-Desktopumgebung

⚙️ Automatischer Installer via Calamares

🔧 Eigene Tools, Branding und Post-Install-Hooks

🪄 Offlinefähig & systemdiagnosebereit per Terminal

🧰 Voraussetzungen

Betriebssystem

Ubuntu/Debian-basiertes Hostsystem (getestet unter Ubuntu 24.04)

Abhängigkeiten

sudo apt install -y debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin \
  mtools dosfstools isolinux syslinux-common shim-signed gnupg \
  git curl jq python3 python3-pip python3-venv

🔐 .env Datei (für KI-Integration)

Erstelle eine .env-Datei im Projektverzeichnis mit folgendem Inhalt:

MISTRALAPIKEY=your_mixtral_api_key_here

Tipp: Nutze cp .env.example .env als Vorlage.

🛠️ Build starten

./build.sh

Nach dem erfolgreichen Durchlauf findest du:

ailinux-24.04-premium-amd64.iso

ailinux-24.04-premium-amd64.iso.sha256

ailinux-build-info.txt

🧠 AI-Funktionen: aihelp

Nach dem Booten der Live-ISO:

aihelp "Warum startet mein Netzwerkdienst nicht?"
aihelp --sysinfo
aihelp --log /var/log/syslog

Beispielausgabe:

### 🚨 Problem Summary
Der Netzwerkdienst startet nicht zuverlässig beim Booten.

### ⚙️ Likely Cause
Möglicherweise fehlt eine Abhängigkeit oder der NetworkManager ist nicht aktiviert...

### ✅ Suggested Solution
```bash
sudo systemctl enable NetworkManager
sudo systemctl restart NetworkManager


---

## 📦 Enthaltene Komponenten

### Desktop
- KDE Plasma (kde-full)
- SDDM Autologin mit Live-User
- Anwendungen: Firefox, Chrome, LibreOffice, VLC, GIMP, VS Code, Wine, Konsole u.v.m.

### Calamares
- Voll konfiguriert mit eigenem Branding
- Postinstall-Skript kopiert `.env` & aktiviert KI-Hinweis im Zielsystem

### Bootloader
- ISOLINUX (BIOS)
- GRUB2 + Shim (UEFI, Secure Boot ready)
- EFI-Image `efi.img` eingebunden

---

## 🧪 Build testen

```bash
qemu-system-x86_64 -cdrom ailinux-24.04-premium-amd64.iso -m 4096 -enable-kvm

🧵 Claude Prompt zur Replikation

Prompt für Claude.ai oder andere LLMs:

"""
Erstelle ein vollständiges ISO-Buildsystem in Bash zur Erstellung einer Live-ISO basierend auf Ubuntu 24.04. Die Distribution heißt AILinux und enthält:

KDE Plasma Desktop

Calamares Installer mit eigenem Branding (Logo, Farben, Texte)

Einen Live-Benutzer mit Autologin

Eine eigene CLI-Integration namens aihelp, die über die Mixtral API mit einem Key aus .env kommuniziert

Die Funktionalität, Logdateien zu analysieren, Systeminfos zu liefern und Fehler mit Markdown-strukturierten Antworten auszugeben

Die KI-Funktionalität soll automatisch beim Installieren aktiviert werden (durch Postinstall Hook im Calamares Installer)

Nutze zstd-komprimiertes SquashFS

Erzeuge ein funktionierendes ISO-Image mit BIOS+UEFI-Boot

Stelle sicher, dass das Skript robust ist, .env prüft und im Fehlerfall abbricht. Benenne die finale ISO-Datei automatisch und gib nach dem Build eine Build-Info mit Zeitstempel und Feature-Übersicht aus.
"""

📄 Lizenz

MIT License(c) 2024 derleiti / AILinux Project

🔗 Links

🔗 Website

🧠 Mixtral API

🐙 GitHub: AILinux Beta ISO

# AILinux - The Intelligent Linux Environment

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![Version](https://img.shields.io/badge/version-0.2.0--beta-blue)
![License](https://img.shields.io/badge/license-MIT-green)

AILinux ist ein experimentelles Linux-ISO-Image, das eine KI-gestützte Umgebung für Systemanalyse, Protokollinterpretation und interaktive Unterstützung direkt in der Shell bietet.

---

## Inhaltsverzeichnis

1.  [Über das Projekt](#über-das-projekt)
2.  [Architektur](#architektur)
3.  [Erste Schritte](#erste-schritte)
    * [Voraussetzungen](#voraussetzungen)
    * [Installation & Konfiguration](#installation--konfiguration)
4.  [Verwendung](#verwendung)
5.  [Mitwirken](#mitwirken)
6.  [Lizenz](#lizenz)

## Über das Projekt

Dieses Projekt zielt darauf ab, die Lücke zwischen komplexen Systemproblemen und dem Benutzer zu schließen, indem es die Leistungsfähigkeit moderner Sprachmodelle (LLMs) nutzt. Anstatt stundenlang Logdateien zu durchsuchen, können Sie einfach eine Frage stellen.

**Kernfunktionen:**

* **Interaktiver KI-Assistent:** Ein Chatbot in der Shell, der bei Befehlen, Skripten und allgemeinen Fragen hilft.
* **Automatisierte Log-Analyse:** Überwacht Systemprotokolle und nutzt die KI, um Fehler proaktiv zu identifizieren und zu erklären.
* **Bootfähiges ISO-Image:** Eine vollständig eigenständige Linux-Umgebung, die auf jedem kompatiblen System ausgeführt werden kann.

## Architektur

AILinux basiert auf einer Client-Server-Architektur:

* **`ailinux-server`**: Das Backend, das die Logik für die KI-Interaktion enthält. Es verarbeitet Anfragen, kommuniziert mit der Mixtral-API und verwaltet den Systemkontext.
* **`ailinux-client`**: Eine Terminal-Anwendung, die dem Benutzer eine Schnittstelle zum Server bietet.
* **`ailinux-beta-iso`**: Dieses Repository enthält die Build-Skripte, um alle Komponenten zu einem bootfähigen ISO-Image zusammenzufügen.

## Erste Schritte

Folgen Sie diesen Schritten, um Ihr eigenes AILinux-Image zu erstellen.

### Voraussetzungen

* Git
* Docker (oder `qemu`, `debootstrap` etc., je nach Build-Skript)
* Ein gültiger API-Schlüssel von [Mistral AI](https://mistral.ai/)

### Installation & Konfiguration

1.  **Repository klonen:**
    ```sh
    git clone [https://github.com/derleiti/ailinux-beta-iso.git](https://github.com/derleiti/ailinux-beta-iso.git)
    cd ailinux-beta-iso
    ```

2.  **API-Schlüssel konfigurieren:**
    Das System verwendet eine `.env`-Datei, um Ihren API-Schlüssel sicher zu speichern. Erstellen Sie eine Kopie der Vorlage:
    ```sh
    cp .env.example .env
    ```
    Öffnen Sie die `.env`-Datei mit einem Texteditor (z.B. `nano` oder `vim`):
    ```sh
    nano .env
    ```
    Fügen Sie Ihren Mixtral-API-Schlüssel ein. Die Datei sollte so aussehen:
    ```
    # .env - API-Schlüssel für den Zugriff auf Mixtral AI
    MISTRALAPIKEY=Ihr_Mixtral_API_Schlüssel_hier
    ```
    Speichern und schließen Sie die Datei.

3.  **Build-Skript ausführen:**
    Starten Sie den Build-Prozess. Dies kann je nach Systemleistung einige Zeit dauern.
    ```sh
    ./build.sh
    ```

## Verwendung

Nachdem das Build-Skript erfolgreich durchgelaufen ist, finden Sie die `.iso`-Datei im `build/`-Verzeichnis. Sie können diese Datei in einer virtuellen Maschine (wie VirtualBox oder QEMU) booten oder auf einen USB-Stick schreiben.

Nach dem Booten starten Sie die Client-Anwendung über das Terminal, um mit dem KI-Assistenten zu interagieren.

## Mitwirken

Beiträge sind das, was die Open-Source-Community zu einem so großartigen Ort zum Lernen, Inspirieren und Gestalten macht. Jeder Beitrag, den Sie leisten, wird **sehr geschätzt**.

1.  Forken Sie das Projekt
2.  Erstellen Sie Ihren Feature-Branch (`git checkout -b feature/AmazingFeature`)
3.  Committen Sie Ihre Änderungen (`git commit -m 'Add some AmazingFeature'`)
4.  Pushen Sie zum Branch (`git push origin feature/AmazingFeature`)
5.  Öffnen Sie einen Pull-Request

## Lizenz

Dieses Projekt ist unter der MIT-Lizenz lizenziert. Weitere Informationen finden Sie in der `LICENSE`-Datei.

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

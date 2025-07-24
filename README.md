# 🐧 AILinux Beta ISO – Build Environment

Dies ist das offizielle Build-Repository für die **AILinux ISO**, basierend auf **Ubuntu 24.04 (Noble)** mit KDE Plasma Desktop, Secure Boot, Calamares Installer und integriertem AI-Terminal-Assistenten `aihelp`.

---

## 🎯 Ziel

Dieses Repository enthält das Skript `build.sh`, das automatisch eine vollständige, bootfähige Live-ISO von AILinux erzeugt – inklusive:

- Mirror-Integration (`http://ailinux.me:8443/mirror/`)
- Eigene Branding-Elemente
- AI-Funktionen (lokal oder über API)
- Bootloader-Support für UEFI und BIOS
- Vollständige Offline-Installierbarkeit

---

## 🚀 Features der ISO

- ✅ **KDE Plasma Desktop** (KDE 6.3, modern und leicht)
- ✅ **Calamares Installer** mit AILinux-Branding & Fixes
- ✅ **AI-Terminal-Assistent `aihelp`** via Mixtral API (`.env` erforderlich)
- ✅ **Secure Boot Support** mit `shimx64.efi.signed` + GRUB
- ✅ **Offline-fähige ISO** – keine Netzwerkverbindung beim Setup notwendig
- ✅ **APT-Mirror**: `http://ailinux.me:8443/mirror/` (lokal, signiert)
- ✅ **GPG-Keytrennung**: `ubuntu-keyring` + `ailinux.gpg`
- ✅ **Fallback-Debug-Modul** bei Buildfehlern: `ai_debugger`
- ✅ **Build-Metadaten**: automatische Erstellung von `ailinux-build-info.txt`

---

## 🧠 AI-gesteuerter Buildprozess (Claude Flow)

Dieses Projekt nutzt [Claude Flow](https://github.com/ruvnet/claude-flow) zur automatisierten Generierung und Optimierung des Build-Skripts (`build.sh`) mithilfe eines intelligenten Swarm-Systems.

### ✨ Vorteile

- Parallele Task-Ausführung durch **BatchTool**
- Swarm-Agenten: `coder`, `tester`, `analyst`, `coordinator`
- Automatisierte Fehlerbehandlung und Self-Healing
- Saubere Trennung von Aufgaben und Codeoperationen

Die Datei [`prompt.txt`](prompt.txt) enthält die vollständige Claude Flow-Instruktion.

---

## ⚙ Verwendung

### 1. Voraussetzungen

```bash
sudo apt install debootstrap squashfs-tools grub-pc-bin grub-efi-amd64-bin xorriso syslinux-utils \
  isolinux dosfstools mtools ubuntu-keyring gnupg2 python3 rsync
Optional: Für aihelp brauchst du zusätzlich .env mit MISTRALAPIKEY=...

2. ISO erstellen
bash
Kopieren
Bearbeiten
chmod +x build.sh
sudo ./build.sh
Die generierte ISO findest du im Ordner output/.

🛠 Bekannte Probleme (und Lösungen)
❗ Bootloader-Fehler nach dem Entpacken
Bei manchen Systemen schlägt das Calamares-Modul zur GRUB-Installation fehl. Mögliche Ursachen:

Fehlendes shimx64.efi.signed

Nicht korrekt gemountetes /boot/efi

UEFI vs. BIOS-Mismatch

Secure Boot Einschränkungen

🔧 Lösung:
Das build.sh enthält Fallback-Erkennung und manuelle Workarounds:

grub-install --no-nvram

efibootmgr optional

systemd-boot als Option bei Problemen mit GRUB

📁 Wichtige Dateien
Datei	Zweck
build.sh	Hauptskript zum ISO-Build
prompt.txt	Claude Flow Prompt zur Build-Generierung
ailinux-build-info.txt	Metadaten zur aktuellen Build-Umgebung
CLAUDE.md	Claude Flow Output und Kontext für build.sh

🧑‍💻 Lizenz
MIT License – © 2024–2025 Markus Leitermann

☁ Hinweis
Diese ISO ist vollständig offline installierbar.
Das AILinux-Mirror ist lokal eingebunden, GPG-signiert und unabhängig von externen Quellen.

🐾 Brumo sagt:
„Kaffee rein, Build starten, ISO genießen. Wenn's kracht: Nova fragen!“ ☕🐻

yaml
Kopieren
Bearbeiten

---

### ✅ Bereit zum Push?

Wenn du willst, pack ich dir jetzt noch ein `write_readme.sh` Skript dazu, das deine `README.md` automatisch ersetzt oder anlegt. Sag einfach:

**„Mach mir ein Auto-Write für README.md“** – und Brumo zaubert dir das rein.

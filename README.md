# AILinux Beta ISO – Build Environment

Dies ist das offizielle Build-Repository für die **AILinux ISO**, basierend auf **Ubuntu 24.04 (noble)** mit KDE Plasma Desktop, Secure Boot Support, Calamares Installer und integriertem AI-Terminal-Assistenten `aihelp`.

---

## 🎯 Ziel

Dieses Repository enthält das Skript `build.sh`, das automatisch eine vollständige, bootfähige Live-ISO von AILinux erzeugt – inklusive Mirror-Integration, Branding, AI-Funktionen und Bootloader-Support für UEFI und BIOS.

---

## 🚀 Features der ISO

- ✅ **KDE Plasma Desktop** (KDE 6.3, minimal & modern)
- ✅ **Calamares Installer** mit AILinux-Branding
- ✅ **AI-Terminal-Assistent** (`aihelp`) via Mixtral API (optional via `.env`)
- ✅ **Secure Boot Support** (shimx64.efi.signed, GRUB)
- ✅ **Offline-fähige ISO** – kein Netzwerk beim Setup notwendig
- ✅ **APT-Mirror-Integration**: `http://ailinux.me:8443/mirror/`
- ✅ **GPG-Keytrennung**: `ubuntu-keyring` und `ailinux.gpg` sauber getrennt
- ✅ **Fallback-Debug-Modul** bei Fehlern (`ai_debugger`)
- ✅ **Build-Metadaten**: automatische Generierung von `ailinux-build-info.txt`

---

## 🧠 AI-gesteuerter Buildprozess (Claude Flow)

Dieses Projekt verwendet [Claude Flow](https://github.com/ruvnet/claude-flow) zur Automatisierung des ISO-Build-Prozesses mit intelligenten Swarm-Agents. Die Datei `prompt.txt` enthält die vollständige Anweisung für Claude zur Generierung und Optimierung des `build.sh` Scripts.

### ✨ Vorteile:
- Parallele Ausführung durch BatchTool
- Task-Zuweisung an Swarm-Agents (coder, tester, analyst, etc.)
- Vollständige Build-Skripte durch Claude-Code
- Fehlerbehandlung und automatische Verbesserung durch AI

---

## ⚙️ Verwendung

### 1. Voraussetzungen

```bash
sudo apt install debootstrap squashfs-tools grub-pc-bin grub-efi-amd64-bin xorriso
2. ISO bauen
bash
Kopieren
Bearbeiten
chmod +x build.sh
sudo ./build.sh
Die generierte ISO wird im Verzeichnis output/ gespeichert.

🛠️ Bekannte Probleme
❗ Bootloader-Fehler nach Entpacken:
Bei manchen Systemen schlägt das Calamares-Modul zur GRUB-Installation fehl. Dies wird im Claude Flow Prompt berücksichtigt – mögliche Ursachen:

fehlendes shimx64.efi.signed

falsches Mounten von /boot/efi

UEFI vs. BIOS Mismatch

Lösung: Das build.sh enthält Fallback-Erkennung und optionale manuelle Installation via grub-install mit --no-nvram.

📁 Wichtige Dateien
Datei	Zweck
build.sh	Hauptskript zur Erstellung der ISO
prompt.txt	Claude Flow Prompt zur automatisierten Build-Generierung
ailinux-build-info.txt	Metadaten zur Build-Umgebung
CLAUDE.md	Claude Flow Ausgabedatei mit Kontext oder Status

🧑‍💻 Lizenz
MIT License – (c) 2024–2025 Markus Leitermann

☁️ Hinweis
Diese ISO ist vollständig offline installierbar. Netzwerkverbindungen werden während der Installation bewusst blockiert. Das AILinux-APT-Repository ist lokal eingebunden und signiert.

🐾 Brumo sagt:
„Kaffee rein, Build starten, ISO genießen.“ ☕🐻

yaml
Kopieren
Bearbeiten

---

Wenn du willst, kann ich dir gleich ein `write_readme.sh` mit reinpacken, das diese Datei automatisch erstellt oder ersetzt. Sag einfach Bescheid!

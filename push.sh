#!/bin/bash
#
# AILinux Safe Push-Skript (v2.2 - GitHub mit PAT und optionalem Force)
# Automatisierter Commit + Push mit interaktiver Eingabe
# Unterstützt sichere Authentifizierung mit GitHub-PAT
# Verhindert versehentlichen Upload großer ISO-Dateien (>2 GiB)

set -e

BRANCH=$(git rev-parse --abbrev-ref HEAD)
REMOTE_URL="https://github.com/derleiti/ailinux-beta-iso.git"

echo -n "🔐 Gib deinen GitHub PAT ein (wird nicht angezeigt): "
read -s PAT
echo

if [ -z "$PAT" ]; then
    echo -e "\n❌ Fehler: GitHub PAT darf nicht leer sein."
    exit 1
fi

AUTH_URL="https://oauth2:${PAT}@github.com/derleiti/ailinux-beta-iso.git"

# ISO-Dateien automatisch ignorieren
if ! grep -q '\*.iso' .gitignore 2>/dev/null; then
    echo "*.iso" >> .gitignore
    echo "*.iso.sha256" >> .gitignore
    echo "📁 .gitignore um ISO-Dateien ergänzt."
fi

# Großes ISO versehentlich getrackt?
LARGE_ISO=$(git ls-files | grep '\.iso$' || true)
if [ -n "$LARGE_ISO" ]; then
    echo "⚠️  Entferne versehentlich getrackte ISO-Dateien:"
    echo "$LARGE_ISO"
    git rm --cached $LARGE_ISO
fi

# Änderungen commiten, falls vorhanden
if [ -n "$(git status --porcelain)" ]; then
    echo -e "\n📝 Änderungen gefunden:"
    git status -s
    echo
    read -p "Gib eine Commit-Nachricht ein (Standard: 'Update'): " COMMIT_MSG
    COMMIT_MSG=${COMMIT_MSG:-Update}
    git add .
    git commit -m "$COMMIT_MSG"
    echo "✅ Committed: $COMMIT_MSG"
else
    echo -e "\n📦 Keine neuen Änderungen zum Commit."
fi

# Optionaler Force-Push
FORCE=""
if [[ "$1" == "--force" ]]; then
    echo "⚠️  Du hast '--force' angegeben. Ein Force-Push wird durchgeführt."
    FORCE="--force"
fi

echo
echo "📤 Pushe Branch '$BRANCH' nach:"
echo "➡  $REMOTE_URL"

git push $FORCE "$AUTH_URL" "$BRANCH"

if [ $? -eq 0 ]; then
    echo -e "\n✅ Push erfolgreich abgeschlossen!"
else
    echo -e "\n❌ Push fehlgeschlagen!"
    echo "💡 Tipps:"
    echo " - Prüfe Internetverbindung und Branch-Status."
    echo " - Verwende ggf. '--force' nach History-Bereinigung."
fi

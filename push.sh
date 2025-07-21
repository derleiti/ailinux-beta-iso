#!/bin/bash
#
# AILinux Safe Push-Skript (v2.1 - Interactive Commit)
# Pusht den aktuellen Branch sicher zum Remote-Repository.
# Prüft auf uncommitted Änderungen, fragt nach einer Commit-Nachricht
# und committet sie vor dem Push.
# Verwendet Force-Push nur, wenn es explizit mit dem --force-Flag aufgerufen wird.

set -e

BRANCH=$(git rev-parse --abbrev-ref HEAD) # Aktuellen Branch automatisch erkennen
REMOTE_URL="https://github.com/derleiti/ailinux-beta-iso.git"

echo -n "🔐 Gib deinen GitHub PAT ein (wird nicht angezeigt): "
read -s PAT
echo

if [ -z "$PAT" ]; then
    echo -e "\n❌ Fehler: GitHub PAT darf nicht leer sein."
    exit 1
fi

# Authentifizierte URL für den Push erstellen
# Verwendet oauth2 für PAT-Authentifizierung
AUTH_URL="https://oauth2:${PAT}@github.com/derleiti/ailinux-beta-iso.git"

# Prüfen, ob ein Commit notwendig ist
if [ -n "$(git status --porcelain)" ]; then
    echo -e "\n📝 Änderungen zum Commit gefunden."
    git status -s # Zeigt eine kurze Zusammenfassung der Änderungen
    echo
    read -p "Gib eine Commit-Nachricht ein (Standard: 'Update'): " COMMIT_MSG

    # Fallback auf Standard-Commit-Text
    if [ -z "$COMMIT_MSG" ]; then
        COMMIT_MSG="Update"
    fi

    # Änderungen vorbereiten und committen
    echo -e "\n✨ Committe Änderungen..."
    git add .
    git commit -m "$COMMIT_MSG"
    echo "✅ Änderungen committed: $COMMIT_MSG"
else
    echo -e "\n📦 Keine neuen Änderungen zum Commit gefunden."
fi

# Prüfen auf --force Flag für den einmaligen Fix nach dem History-Cleanup
FORCE_FLAG=""
if [ "$1" == "--force" ]; then
    FORCE_FLAG="--force"
    echo -e "\n🟠 WARNUNG: Force-Push wird ausgeführt! Dies sollte nur nach dem Bereinigen der Git-Historie notwendig sein."
fi

echo
echo "📤 Pushe Branch '$BRANCH' auf Remote..."
echo "➡  $REMOTE_URL"

# Push ausführen
git push $FORCE_FLAG "$AUTH_URL" "$BRANCH"

if [ $? -eq 0 ]; then
    echo -e "\n✅ Push erfolgreich!"
else
    echo -e "\n❌ Push fehlgeschlagen!"
    echo "Mögliche Gründe:"
    echo "  - Dein lokaler Branch ist nicht aktuell. Führe 'git pull' aus."
    echo "  - Der PAT ist ungültig oder hat nicht die nötigen Berechtigungen."
fi

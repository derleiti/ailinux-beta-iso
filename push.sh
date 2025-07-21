#!/bin/bash

echo -n "🔐 Gib deinen GitHub PAT ein: "
read -s PAT
echo

BRANCH="main"
REMOTE_URL="https://github.com/derleiti/ailinux-beta-iso.git"
AUTH_URL="https://${PAT}@github.com/derleiti/ailinux-beta-iso.git"

# origin sicher neu setzen (falls gelöscht wurde)
git remote remove origin 2>/dev/null
git remote add origin "$REMOTE_URL"

# Änderungen erkennen
CHANGES=$(git status --porcelain)
if [ -z "$CHANGES" ]; then
  echo "📦 Keine Änderungen zum Commit gefunden."
else
  echo
  echo "📝 Gib einen Commit-Text ein (Standard: 'Update'): "
  read COMMIT_MSG

  # Fallback auf Standard-Commit-Text
  if [ -z "$COMMIT_MSG" ]; then
    COMMIT_MSG="Update"
  fi

  # Änderungen vorbereiten
  git add .
  git commit -m "$COMMIT_MSG"
  echo "✅ Änderungen committed: $COMMIT_MSG"
fi

echo
echo "📤 Pushe Branch '$BRANCH' mit Force auf:"
echo "➡  $REMOTE_URL"

# Push ausführen
git push -f "$AUTH_URL" "$BRANCH"

if [ $? -eq 0 ]; then
  echo "✅ Push erfolgreich!"
else
  echo "❌ Push fehlgeschlagen!"
fi

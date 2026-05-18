#!/bin/bash
# Save the Field CRM — commits and pushes any changes to GitHub.
# Double-click this file in Finder to run it.

cd "$(dirname "$0")"

echo "Saving Field CRM..."
echo ""

git add -A

if git diff --cached --quiet; then
    echo "Nothing to save — your file matches the last save."
else
    git commit -m "save $(date '+%Y-%m-%d %H:%M')"
    echo ""
    if git push; then
        echo ""
        echo "Saved. GitHub Pages will update in about a minute."
    else
        echo ""
        echo "Local save worked, but pushing to GitHub failed."
        echo "Check your internet connection, then double-click save again."
    fi
fi

echo ""
read -p "Press Return to close this window..."

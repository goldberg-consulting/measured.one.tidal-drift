#!/bin/bash

# Bump version in all build scripts
# Usage: ./bump-version.sh 1.3.15

if [ -z "$1" ]; then
    echo "Current versions:"
    grep 'VERSION=' *.sh | grep -v "bump"
    echo ""
    echo "Usage: ./bump-version.sh <new-version>"
    echo "Example: ./bump-version.sh 1.3.15"
    exit 1
fi

NEW_VERSION="$1"

# Update all scripts
for script in build-app.sh build-release.sh; do
    if [ -f "$script" ]; then
        # Get old version
        OLD=$(grep 'VERSION=' "$script" | head -1 | cut -d'"' -f2)
        sed -i '' "s/VERSION=\"[^\"]*\"/VERSION=\"$NEW_VERSION\"/" "$script"
        echo "Updated $script: $OLD → $NEW_VERSION"
    fi
done

echo ""
echo "Don't forget to commit: git commit -am \"v$NEW_VERSION: <description>\""

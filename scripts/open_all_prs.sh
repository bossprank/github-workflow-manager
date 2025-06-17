#!/bin/bash

# Script to open all open pull requests in the browser
# Usage: ./scripts/open_all_prs.sh

set -e

# Source common configuration
source "$(dirname "$0")/common-config.sh"

echo "Fetching open pull requests..."

# Fetch all open PRs
OPEN_PRS=$(rest_api_call "GET" "/repos/$REPO/pulls?state=open" | \
    jq -r '.[] | .html_url')

if [ -z "$OPEN_PRS" ]; then
    echo "No open pull requests found."
    exit 0
fi

# Count PRs
PR_COUNT=$(echo "$OPEN_PRS" | wc -l)
echo "Found $PR_COUNT open pull request(s):"
echo "$OPEN_PRS"

# Check if xdg-open is available (Linux)
if command -v xdg-open &> /dev/null; then
    OPEN_CMD="xdg-open"
# Check if open is available (macOS)
elif command -v open &> /dev/null; then
    OPEN_CMD="open"
# Check if start is available (Windows)
elif command -v start &> /dev/null; then
    OPEN_CMD="start"
else
    echo "Could not find a command to open URLs. Please open manually:"
    echo "$OPEN_PRS"
    exit 1
fi

echo ""
echo "Opening all PRs in your browser..."

# Open each PR
while IFS= read -r url; do
    echo "Opening: $url"
    $OPEN_CMD "$url" 2>/dev/null || echo "Failed to open: $url"
    # Small delay to avoid overwhelming the browser
    sleep 0.5
done <<< "$OPEN_PRS"

echo "Done!"
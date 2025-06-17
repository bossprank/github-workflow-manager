#!/bin/bash

# Script to check recent comments on a GitHub issue
# Usage: ./scripts/check-issue-comments.sh <issue-number> [limit]

set -e

# Source common configuration
source "$(dirname "$0")/common-config.sh"

# Check arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <issue-number> [limit]"
    echo "Example: $0 123      # Shows last 5 comments"
    echo "Example: $0 123 10   # Shows last 10 comments"
    exit 1
fi

ISSUE_NUMBER="$1"
LIMIT="${2:-5}"

echo -e "${BOLD}Recent comments on Issue #$ISSUE_NUMBER${NC}"
echo ""

# Get issue details first
ISSUE_DATA=$(rest_api_call "GET" "/repos/$REPO/issues/$ISSUE_NUMBER")
ISSUE_TITLE=$(echo "$ISSUE_DATA" | jq -r '.title')
ISSUE_STATE=$(echo "$ISSUE_DATA" | jq -r '.state')
ISSUE_URL=$(echo "$ISSUE_DATA" | jq -r '.html_url')

echo -e "${BLUE}Title:${NC} $ISSUE_TITLE"
echo -e "${BLUE}State:${NC} $ISSUE_STATE"
echo -e "${BLUE}URL:${NC} $ISSUE_URL"
echo ""

# Get comments
echo -e "${BOLD}Last $LIMIT comments:${NC}"
echo ""

COMMENTS=$(rest_api_call "GET" "/repos/$REPO/issues/$ISSUE_NUMBER/comments?per_page=$LIMIT&sort=created&direction=desc")

# Check if there are any comments
COMMENT_COUNT=$(echo "$COMMENTS" | jq '. | length')
if [ "$COMMENT_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}No comments found on this issue${NC}"
    exit 0
fi

# Display comments in reverse order (oldest of the recent ones first)
echo "$COMMENTS" | jq -r 'reverse | .[] | 
    "──────────────────────────────────────────\n" +
    "📅 \(.created_at) by @\(.user.login)\n" +
    if .updated_at != .created_at then "✏️  Updated: \(.updated_at)\n" else "" end +
    "\n\(.body)\n"' | while IFS= read -r line; do
    # Format timestamps
    if [[ "$line" =~ ^📅.*([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z) ]]; then
        timestamp="${BASH_REMATCH[1]}"
        formatted_time=$(date -d "$timestamp" "+%Y-%m-%d %H:%M UTC" 2>/dev/null || echo "$timestamp")
        line=$(echo "$line" | sed "s/$timestamp/$formatted_time/")
    fi
    echo "$line"
done

echo "──────────────────────────────────────────"
echo ""
echo -e "${YELLOW}Showing $COMMENT_COUNT of last $LIMIT comments${NC}"

# Check if issue has a linked PR
PR_REFS=$(echo "$ISSUE_DATA" | jq -r '.pull_request.url // "none"')
if [ "$PR_REFS" != "none" ]; then
    echo ""
    echo -e "${BLUE}Note: This issue has a linked pull request${NC}"
fi
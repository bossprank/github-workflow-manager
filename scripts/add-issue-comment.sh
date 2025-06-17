#!/bin/bash

# Script to add a comment to a GitHub issue
# Usage: ./scripts/add-issue-comment.sh <issue-number> "Comment text"

set -e

# Source common configuration
source "$(dirname "$0")/common-config.sh"

# Check arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 <issue-number> \"Comment text\""
    echo "Example: $0 123 \"Boss, I've completed the initial implementation. Please review.\""
    exit 1
fi

ISSUE_NUMBER="$1"
COMMENT="$2"

echo -e "${BOLD}Adding comment to Issue #$ISSUE_NUMBER${NC}"
echo ""

# Post comment via REST API
COMMENT_RESPONSE=$(rest_api_call "POST" "/repos/$REPO/issues/$ISSUE_NUMBER/comments" "{
    \"body\": $(echo "$COMMENT" | jq -Rs .)
}")

# Check if successful
COMMENT_ID=$(echo "$COMMENT_RESPONSE" | jq -r '.id // "null"')
COMMENT_URL=$(echo "$COMMENT_RESPONSE" | jq -r '.html_url // "null"')

if [ "$COMMENT_ID" = "null" ]; then
    echo -e "${RED}Error: Failed to add comment${NC}"
    echo "$COMMENT_RESPONSE" | jq '.'
    exit 1
fi

echo -e "${GREEN}✓ Comment added successfully${NC}"
echo -e "${BLUE}Comment URL:${NC} $COMMENT_URL"
echo ""
echo -e "${YELLOW}Preview:${NC}"
echo "$COMMENT" | head -3
if [ $(echo "$COMMENT" | wc -l) -gt 3 ]; then
    echo "..."
fi
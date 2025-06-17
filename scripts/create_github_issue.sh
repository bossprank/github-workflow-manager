#!/bin/bash

# Script to create GitHub issues with project board integration
# Usage: ./scripts/create_github_issue.sh "Issue Title" "Issue Body" "label1,label2" "priority" "size"
# Priority: P0, P1, P2 (optional, defaults to P2)
# Size: XS, S, M, L, XL (optional, defaults to M)

set -e

# Source common configuration
source "$(dirname "$0")/common-config.sh"

# Check arguments
if [ $# -lt 2 ]; then
    echo "Usage: $0 \"Issue Title\" \"Issue Body\" [\"label1,label2\"] [priority] [size]"
    echo "Priority options: P0, P1, P2 (default: P2)"
    echo "Size options: XS, S, M, L, XL (default: M)"
    exit 1
fi

TITLE="$1"
BODY="$2"
LABELS="${3:-}"
PRIORITY="${4:-P2}"
SIZE="${5:-M}"

echo -e "${BOLD}Creating GitHub Issue${NC}"
echo -e "${BLUE}Title:${NC} $TITLE"
echo -e "${BLUE}Priority:${NC} $PRIORITY"
echo -e "${BLUE}Size:${NC} $SIZE"
echo ""

# Convert labels to JSON array
if [ -n "$LABELS" ]; then
    LABELS_JSON=$(echo "$LABELS" | awk -F',' '{printf "["; for(i=1;i<=NF;i++) printf "\"%s\"%s", $i, (i<NF?",":""); printf "]"}')
else
    LABELS_JSON="[]"
fi

# Create the issue via REST API
echo "Creating issue..."
# Escape the body for JSON
ESCAPED_BODY=$(echo "$BODY" | jq -Rs '.')
ISSUE_RESPONSE=$(rest_api_call "POST" "/repos/$REPO/issues" "{
    \"title\": \"$TITLE\",
    \"body\": $ESCAPED_BODY,
    \"labels\": $LABELS_JSON
}")

# Extract issue number and node ID
ISSUE_NUMBER=$(echo "$ISSUE_RESPONSE" | jq -r '.number')
ISSUE_NODE_ID=$(echo "$ISSUE_RESPONSE" | jq -r '.node_id')
ISSUE_URL=$(echo "$ISSUE_RESPONSE" | jq -r '.html_url')

if [ "$ISSUE_NUMBER" = "null" ]; then
    echo -e "${RED}Error: Failed to create issue${NC}"
    echo "$ISSUE_RESPONSE" | jq '.'
    exit 1
fi

echo -e "${GREEN}✓ Created issue #$ISSUE_NUMBER${NC}"
echo -e "${BLUE}URL:${NC} $ISSUE_URL"

# Add issue to project board
echo ""
echo "Adding to project board..."

# First, add the issue to the project
ADD_TO_PROJECT_QUERY="mutation {
  addProjectV2ItemById(input: {
    projectId: \"$PROJECT_ID\"
    contentId: \"$ISSUE_NODE_ID\"
  }) {
    item {
      id
    }
  }
}"

PROJECT_ITEM_RESPONSE=$(graphql_query "$ADD_TO_PROJECT_QUERY")
PROJECT_ITEM_ID=$(echo "$PROJECT_ITEM_RESPONSE" | jq -r '.data.addProjectV2ItemById.item.id')

if [ "$PROJECT_ITEM_ID" = "null" ]; then
    echo -e "${YELLOW}Warning: Failed to add to project board${NC}"
    echo "$PROJECT_ITEM_RESPONSE" | jq '.'
else
    echo -e "${GREEN}✓ Added to project board${NC}"
    
    # Map priority and size to IDs
    case "$PRIORITY" in
        P0) PRIORITY_ID="$P0_ID" ;;
        P1) PRIORITY_ID="$P1_ID" ;;
        P2) PRIORITY_ID="$P2_ID" ;;
        *) PRIORITY_ID="$P2_ID" ;;
    esac
    
    case "$SIZE" in
        XS) SIZE_ID="$XS_ID" ;;
        S) SIZE_ID="$S_ID" ;;
        M) SIZE_ID="$M_ID" ;;
        L) SIZE_ID="$L_ID" ;;
        XL) SIZE_ID="$XL_ID" ;;
        *) SIZE_ID="$M_ID" ;;
    esac
    
    # Set status to Backlog
    echo "Setting status to Backlog..."
    STATUS_QUERY="mutation {
      updateProjectV2ItemFieldValue(input: {
        projectId: \"$PROJECT_ID\"
        itemId: \"$PROJECT_ITEM_ID\"
        fieldId: \"$STATUS_FIELD_ID\"
        value: { singleSelectOptionId: \"$BACKLOG_ID\" }
      }) {
        projectV2Item { id }
      }
    }"
    
    STATUS_RESPONSE=$(graphql_query "$STATUS_QUERY")
    if echo "$STATUS_RESPONSE" | jq -e '.data.updateProjectV2ItemFieldValue.projectV2Item.id' > /dev/null; then
        echo -e "${GREEN}✓ Set status to Backlog${NC}"
    else
        echo -e "${YELLOW}Warning: Failed to set status${NC}"
    fi
    
    # Set priority
    echo "Setting priority to $PRIORITY..."
    PRIORITY_QUERY="mutation {
      updateProjectV2ItemFieldValue(input: {
        projectId: \"$PROJECT_ID\"
        itemId: \"$PROJECT_ITEM_ID\"
        fieldId: \"$PRIORITY_FIELD_ID\"
        value: { singleSelectOptionId: \"$PRIORITY_ID\" }
      }) {
        projectV2Item { id }
      }
    }"
    
    PRIORITY_RESPONSE=$(graphql_query "$PRIORITY_QUERY")
    if echo "$PRIORITY_RESPONSE" | jq -e '.data.updateProjectV2ItemFieldValue.projectV2Item.id' > /dev/null; then
        echo -e "${GREEN}✓ Set priority to $PRIORITY${NC}"
    else
        echo -e "${YELLOW}Warning: Failed to set priority${NC}"
    fi
    
    # Set size
    echo "Setting size to $SIZE..."
    SIZE_QUERY="mutation {
      updateProjectV2ItemFieldValue(input: {
        projectId: \"$PROJECT_ID\"
        itemId: \"$PROJECT_ITEM_ID\"
        fieldId: \"$SIZE_FIELD_ID\"
        value: { singleSelectOptionId: \"$SIZE_ID\" }
      }) {
        projectV2Item { id }
      }
    }"
    
    SIZE_RESPONSE=$(graphql_query "$SIZE_QUERY")
    if echo "$SIZE_RESPONSE" | jq -e '.data.updateProjectV2ItemFieldValue.projectV2Item.id' > /dev/null; then
        echo -e "${GREEN}✓ Set size to $SIZE${NC}"
    else
        echo -e "${YELLOW}Warning: Failed to set size${NC}"
    fi
    
    # Set estimate based on size
    ESTIMATE_HOURS=$(get_estimate_for_size "$SIZE")
    echo "Setting estimate to $ESTIMATE_HOURS hours..."
    ESTIMATE_QUERY="mutation {
      updateProjectV2ItemFieldValue(input: {
        projectId: \"$PROJECT_ID\"
        itemId: \"$PROJECT_ITEM_ID\"
        fieldId: \"$ESTIMATE_FIELD_ID\"
        value: { number: $ESTIMATE_HOURS }
      }) {
        projectV2Item { id }
      }
    }"
    
    ESTIMATE_RESPONSE=$(graphql_query "$ESTIMATE_QUERY")
    if echo "$ESTIMATE_RESPONSE" | jq -e '.data.updateProjectV2ItemFieldValue.projectV2Item.id' > /dev/null; then
        echo -e "${GREEN}✓ Set estimate to $ESTIMATE_HOURS hours${NC}"
    else
        echo -e "${YELLOW}Warning: Failed to set estimate${NC}"
    fi
fi

echo ""
echo -e "${BOLD}${GREEN}Issue created successfully!${NC}"
echo -e "${BLUE}Issue URL:${NC} $ISSUE_URL"
echo -e "${BLUE}Issue Number:${NC} #$ISSUE_NUMBER"
echo -e "${BLUE}Project Status:${NC} Backlog"
echo -e "${BLUE}Priority:${NC} $PRIORITY"
echo -e "${BLUE}Size:${NC} $SIZE"
echo -e "${BLUE}Estimate:${NC} ${ESTIMATE_HOURS:-N/A} hours"
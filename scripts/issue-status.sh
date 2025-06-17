#!/bin/bash

# Script to update issue status in GitHub project board
# Usage: ./scripts/issue-status.sh <issue-number> <status>
# Status options: backlog, ready, in-progress, in-review, done

set -e

# Source common configuration
source "$(dirname "$0")/common-config.sh"

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <issue-number> <status>"
    echo "Status options: backlog, ready, in-progress, in-review, done"
    exit 1
fi

ISSUE_NUMBER="$1"
STATUS_NAME="$2"

# Map status names to IDs
case "$STATUS_NAME" in
    backlog) 
        STATUS_ID="$BACKLOG_ID"
        STATUS_DISPLAY="Backlog"
        ;;
    ready) 
        STATUS_ID="$READY_ID"
        STATUS_DISPLAY="Ready"
        ;;
    in-progress) 
        STATUS_ID="$IN_PROGRESS_ID"
        STATUS_DISPLAY="In progress"
        ;;
    in-review) 
        STATUS_ID="$IN_REVIEW_ID"
        STATUS_DISPLAY="In review"
        ;;
    done) 
        STATUS_ID="$DONE_ID"
        STATUS_DISPLAY="Done"
        ;;
    *)
        echo -e "${RED}Error: Invalid status '$STATUS_NAME'${NC}"
        echo "Valid options: backlog, ready, in-progress, in-review, done"
        exit 1
        ;;
esac

echo -e "${BOLD}Updating Issue Status${NC}"
echo -e "${BLUE}Issue:${NC} #$ISSUE_NUMBER"
echo -e "${BLUE}New Status:${NC} $STATUS_DISPLAY"
echo ""

# First, get the issue's project item ID
echo "Finding issue in project board..."
FIND_ITEM_QUERY='query {
  user(login: "bossprank") {
    projectsV2(first: 1) {
      nodes {
        items(first: 100) {
          nodes {
            id
            content {
              ... on Issue {
                number
                title
              }
            }
            fieldValues(first: 10) {
              nodes {
                ... on ProjectV2ItemFieldSingleSelectValue {
                  field { ... on ProjectV2SingleSelectField { name } }
                  name
                }
              }
            }
          }
        }
      }
    }
  }
}'

FIND_RESPONSE=$(graphql_query "$FIND_ITEM_QUERY")

# Extract the project item ID for our issue
PROJECT_ITEM_ID=$(echo "$FIND_RESPONSE" | jq -r ".data.user.projectsV2.nodes[0].items.nodes[] | select(.content.number == $ISSUE_NUMBER) | .id")

if [ -z "$PROJECT_ITEM_ID" ] || [ "$PROJECT_ITEM_ID" = "null" ]; then
    echo -e "${YELLOW}Issue #$ISSUE_NUMBER not found in project board. Adding it now...${NC}"
    
    # Get issue node ID
    ISSUE_DATA=$(rest_api_call "GET" "/repos/$REPO/issues/$ISSUE_NUMBER")
    ISSUE_NODE_ID=$(echo "$ISSUE_DATA" | jq -r '.node_id')
    
    if [ "$ISSUE_NODE_ID" = "null" ]; then
        echo -e "${RED}Error: Issue #$ISSUE_NUMBER not found${NC}"
        exit 1
    fi
    
    # Add to project
    ADD_QUERY="mutation {
      addProjectV2ItemById(input: {
        projectId: \"$PROJECT_ID\"
        contentId: \"$ISSUE_NODE_ID\"
      }) {
        item { id }
      }
    }"
    
    ADD_RESPONSE=$(graphql_query "$ADD_QUERY")
    PROJECT_ITEM_ID=$(echo "$ADD_RESPONSE" | jq -r '.data.addProjectV2ItemById.item.id')
    
    if [ -z "$PROJECT_ITEM_ID" ] || [ "$PROJECT_ITEM_ID" = "null" ]; then
        echo -e "${RED}Error: Failed to add issue to project${NC}"
        echo "$ADD_RESPONSE" | jq '.'
        exit 1
    fi
    
    echo -e "${GREEN}✓ Added issue to project board${NC}"
else
    # Get current status
    CURRENT_STATUS=$(echo "$FIND_RESPONSE" | jq -r ".data.user.projectsV2.nodes[0].items.nodes[] | select(.content.number == $ISSUE_NUMBER) | .fieldValues.nodes[] | select(.field.name == \"Status\") | .name // \"No Status\"")
    echo -e "${BLUE}Current Status:${NC} $CURRENT_STATUS"
fi

# Update the status
echo "Updating status to $STATUS_DISPLAY..."
UPDATE_QUERY="mutation {
  updateProjectV2ItemFieldValue(input: {
    projectId: \"$PROJECT_ID\"
    itemId: \"$PROJECT_ITEM_ID\"
    fieldId: \"$STATUS_FIELD_ID\"
    value: { singleSelectOptionId: \"$STATUS_ID\" }
  }) {
    projectV2Item { 
      id 
      fieldValues(first: 10) {
        nodes {
          ... on ProjectV2ItemFieldSingleSelectValue {
            field { ... on ProjectV2SingleSelectField { name } }
            name
          }
        }
      }
    }
  }
}"

UPDATE_RESPONSE=$(graphql_query "$UPDATE_QUERY")

# Check if update was successful
if echo "$UPDATE_RESPONSE" | jq -e '.data.updateProjectV2ItemFieldValue.projectV2Item.id' > /dev/null; then
    NEW_STATUS=$(echo "$UPDATE_RESPONSE" | jq -r '.data.updateProjectV2ItemFieldValue.projectV2Item.fieldValues.nodes[] | select(.field.name == "Status") | .name')
    echo -e "${GREEN}✓ Status updated successfully${NC}"
    echo -e "${BLUE}New Status:${NC} $NEW_STATUS"
    
    # Also update issue labels to match status (optional)
    if [ "$STATUS_NAME" = "in-progress" ] || [ "$STATUS_NAME" = "in-review" ]; then
        echo ""
        echo "Adding matching label to issue..."
        
        # Remove old status labels
        for label in "in-progress" "in review"; do
            rest_api_call "DELETE" "/repos/$REPO/issues/$ISSUE_NUMBER/labels/$label" 2>/dev/null || true
        done
        
        # Add new status label
        LABEL_NAME=$(echo "$STATUS_NAME" | sed 's/-/ /g')
        rest_api_call "POST" "/repos/$REPO/issues/$ISSUE_NUMBER/labels" "[\"$LABEL_NAME\"]" > /dev/null
        echo -e "${GREEN}✓ Added '$LABEL_NAME' label${NC}"
    fi
else
    echo -e "${RED}Error: Failed to update status${NC}"
    echo "$UPDATE_RESPONSE" | jq '.'
    exit 1
fi

echo ""
echo -e "${BOLD}${GREEN}Status updated successfully!${NC}"
echo -e "Issue #$ISSUE_NUMBER is now in status: ${BOLD}$STATUS_DISPLAY${NC}"
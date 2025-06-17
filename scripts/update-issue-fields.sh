#!/bin/bash

# Script to update issue fields in GitHub project board
# Usage: ./scripts/update-issue-fields.sh <issue-number> <field> <value>
# Fields: priority (P0, P1, P2), size (XS, S, M, L, XL)

set -e

# Source common configuration
source "$(dirname "$0")/common-config.sh"

# Check arguments
if [ $# -ne 3 ]; then
    echo "Usage: $0 <issue-number> <field> <value>"
    echo "Fields: priority (P0, P1, P2), size (XS, S, M, L, XL), estimate (hours)"
    exit 1
fi

ISSUE_NUMBER="$1"
FIELD_NAME="$2"
FIELD_VALUE="$3"

# Determine field ID and value ID
case "$FIELD_NAME" in
    priority)
        FIELD_ID="$PRIORITY_FIELD_ID"
        case "$FIELD_VALUE" in
            P0) VALUE_ID="$P0_ID" ;;
            P1) VALUE_ID="$P1_ID" ;;
            P2) VALUE_ID="$P2_ID" ;;
            *) echo -e "${RED}Invalid priority: $FIELD_VALUE${NC}"; exit 1 ;;
        esac
        ;;
    size)
        FIELD_ID="$SIZE_FIELD_ID"
        case "$FIELD_VALUE" in
            XS) VALUE_ID="$XS_ID" ;;
            S) VALUE_ID="$S_ID" ;;
            M) VALUE_ID="$M_ID" ;;
            L) VALUE_ID="$L_ID" ;;
            XL) VALUE_ID="$XL_ID" ;;
            *) echo -e "${RED}Invalid size: $FIELD_VALUE${NC}"; exit 1 ;;
        esac
        ;;
    estimate)
        FIELD_ID="$ESTIMATE_FIELD_ID"
        # Validate it's a number and follows Fibonacci
        if ! [[ "$FIELD_VALUE" =~ ^[0-9]+$ ]]; then
            echo -e "${RED}Estimate must be a number${NC}"
            exit 1
        fi
        VALUE_ID="$FIELD_VALUE"  # For number fields, we use the value directly
        IS_NUMBER_FIELD=true
        ;;
    *)
        echo -e "${RED}Invalid field: $FIELD_NAME${NC}"
        echo "Valid fields: priority, size, estimate"
        exit 1
        ;;
esac

echo -e "${BOLD}Updating Issue #$ISSUE_NUMBER${NC}"
echo -e "${BLUE}Field:${NC} $FIELD_NAME"
echo -e "${BLUE}Value:${NC} $FIELD_VALUE"
echo ""

# Find the project item ID
FIND_QUERY='query {
  user(login: "bossprank") {
    projectsV2(first: 1) {
      nodes {
        items(first: 100) {
          nodes {
            id
            content {
              ... on Issue {
                number
              }
            }
          }
        }
      }
    }
  }
}'

FIND_RESPONSE=$(graphql_query "$FIND_QUERY")
PROJECT_ITEM_ID=$(echo "$FIND_RESPONSE" | jq -r ".data.user.projectsV2.nodes[0].items.nodes[] | select(.content.number == $ISSUE_NUMBER) | .id")

if [ -z "$PROJECT_ITEM_ID" ] || [ "$PROJECT_ITEM_ID" = "null" ]; then
    echo -e "${RED}Issue #$ISSUE_NUMBER not found in project board${NC}"
    exit 1
fi

# Update the field
if [ "${IS_NUMBER_FIELD:-false}" = "true" ]; then
    UPDATE_QUERY="mutation {
      updateProjectV2ItemFieldValue(input: {
        projectId: \"$PROJECT_ID\"
        itemId: \"$PROJECT_ITEM_ID\"
        fieldId: \"$FIELD_ID\"
        value: { number: $VALUE_ID }
      }) {
        projectV2Item { id }
      }
    }"
else
    UPDATE_QUERY="mutation {
      updateProjectV2ItemFieldValue(input: {
        projectId: \"$PROJECT_ID\"
        itemId: \"$PROJECT_ITEM_ID\"
        fieldId: \"$FIELD_ID\"
        value: { singleSelectOptionId: \"$VALUE_ID\" }
      }) {
        projectV2Item { id }
      }
    }"
fi

UPDATE_RESPONSE=$(graphql_query "$UPDATE_QUERY")

if echo "$UPDATE_RESPONSE" | jq -e '.data.updateProjectV2ItemFieldValue.projectV2Item.id' > /dev/null; then
    echo -e "${GREEN}✓ Updated $FIELD_NAME to $FIELD_VALUE${NC}"
else
    echo -e "${RED}Failed to update field${NC}"
    echo "$UPDATE_RESPONSE" | jq '.'
    exit 1
fi
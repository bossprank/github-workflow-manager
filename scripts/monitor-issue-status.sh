#!/bin/bash

# Script to monitor issue status changes and resume work when moved back to in-progress
# Usage: ./scripts/monitor-issue-status.sh <issue-number>

set -e

# Source common configuration
source "$(dirname "$0")/common-config.sh"

# Check arguments
if [ $# -ne 1 ]; then
    echo "Usage: $0 <issue-number>"
    exit 1
fi

ISSUE_NUMBER="$1"
STATE_FILE=".claude/issue-${ISSUE_NUMBER}.json"

echo -e "${BOLD}Monitoring Issue #$ISSUE_NUMBER for status changes${NC}"
echo -e "${BLUE}Press Ctrl+C to stop monitoring${NC}"
echo ""

# Function to get current project status
get_current_status() {
    local query='query {
      user(login: "bossprank") {
        projectsV2(first: 1) {
          nodes {
            items(first: 100) {
              nodes {
                content {
                  ... on Issue { number }
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
    
    local response=$(graphql_query "$query")
    echo "$response" | jq -r ".data.user.projectsV2.nodes[0].items.nodes[] | select(.content.number == $ISSUE_NUMBER) | .fieldValues.nodes[] | select(.field.name == \"Status\") | .name // \"Unknown\"" 2>/dev/null || echo "Error"
}

# Main monitoring loop
LAST_STATUS=""
CHECK_INTERVAL=30  # Check every 30 seconds

while true; do
    # Get current status
    CURRENT_STATUS=$(get_current_status)
    
    if [ "$CURRENT_STATUS" = "Error" ]; then
        echo -e "${RED}Error checking status. Retrying...${NC}"
        sleep "$CHECK_INTERVAL"
        continue
    fi
    
    # Display current status if changed
    if [ "$CURRENT_STATUS" != "$LAST_STATUS" ]; then
        echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] Status: ${BOLD}$CURRENT_STATUS${NC}"
        
        # Check if moved back to in-progress from another status
        if [ "$CURRENT_STATUS" = "In progress" ] && [ -n "$LAST_STATUS" ] && [ "$LAST_STATUS" != "In progress" ]; then
            echo -e "${YELLOW}Issue moved back to In Progress!${NC}"
            
            # Check if state file exists
            if [ -f "$STATE_FILE" ]; then
                echo -e "${GREEN}Resuming work on issue #$ISSUE_NUMBER...${NC}"
                
                # Add to work log
                STATE=$(cat "$STATE_FILE")
                NEW_LOG_ENTRY=$(jq -n \
                    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
                    --arg from "$LAST_STATUS" \
                    '{timestamp: $timestamp, action: "Issue moved back to In Progress from \($from)"}')
                
                STATE=$(echo "$STATE" | jq ".work_log += [$NEW_LOG_ENTRY]")
                echo "$STATE" > "$STATE_FILE"
                
                echo -e "${GREEN}✓ Updated work log${NC}"
                echo -e "${YELLOW}Run './scripts/claude-work.sh continue $ISSUE_NUMBER' to resume work${NC}"
                
                # Send notification (you could add more notification methods here)
                echo -e "\a" # Terminal bell
            fi
        fi
        
        LAST_STATUS="$CURRENT_STATUS"
    fi
    
    sleep "$CHECK_INTERVAL"
done
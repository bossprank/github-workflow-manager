#!/bin/bash

# Enhanced script to manage Claude work sessions with automatic issue reading
# Usage: ./scripts/claude-work-enhanced.sh <action> <issue-number>
# Actions: start, continue, review, done
#
# ENHANCEMENT: Automatically fetches and displays full issue details when starting work

set -e

# Source common configuration
source "$(dirname "$0")/common-config.sh"

# Check arguments
if [ $# -ne 2 ]; then
    echo "Usage: $0 <action> <issue-number>"
    echo "Actions: start, continue, review, done"
    exit 1
fi

ACTION="$1"
ISSUE_NUMBER="$2"
CLAUDE_DIR=".claude"
STATE_FILE="$CLAUDE_DIR/issue-${ISSUE_NUMBER}.json"
ISSUE_DETAILS_FILE="$CLAUDE_DIR/issue-${ISSUE_NUMBER}-details.md"

# Create .claude directory if it doesn't exist
mkdir -p "$CLAUDE_DIR"

# Function to get issue details
get_issue_details() {
    local issue_data=$(rest_api_call "GET" "/repos/$REPO/issues/$ISSUE_NUMBER")
    echo "$issue_data"
}

# Function to fetch and format full issue details
fetch_and_format_issue_details() {
    local issue_number="$1"
    
    echo -e "${BOLD}${BLUE}Fetching Issue #$issue_number details from GitHub...${NC}"
    echo ""
    
    # Get issue data
    local issue_data=$(get_issue_details)
    local issue_title=$(echo "$issue_data" | jq -r '.title')
    local issue_body=$(echo "$issue_data" | jq -r '.body // "No description provided"')
    local issue_state=$(echo "$issue_data" | jq -r '.state')
    local issue_labels=$(echo "$issue_data" | jq -r '.labels[].name' | tr '\n' ',' | sed 's/,$//')
    local issue_assignee=$(echo "$issue_data" | jq -r '.assignee.login // "unassigned"')
    local issue_created=$(echo "$issue_data" | jq -r '.created_at')
    local issue_updated=$(echo "$issue_data" | jq -r '.updated_at')
    local issue_url=$(echo "$issue_data" | jq -r '.html_url')
    
    # Format the details
    cat > "$ISSUE_DETAILS_FILE" << EOF
# GitHub Issue #$issue_number: $issue_title

**Status:** $issue_state
**Labels:** ${issue_labels:-none}
**Assignee:** $issue_assignee
**Created:** $issue_created
**Updated:** $issue_updated
**URL:** $issue_url

## Description

$issue_body

## Comments

EOF
    
    # Fetch comments
    local comments_data=$(rest_api_call "GET" "/repos/$REPO/issues/$ISSUE_NUMBER/comments")
    local comment_count=$(echo "$comments_data" | jq '. | length')
    
    if [ "$comment_count" -gt 0 ]; then
        echo "$comments_data" | jq -r '.[] | "### Comment by \(.user.login) on \(.created_at)\n\n\(.body)\n\n---\n"' >> "$ISSUE_DETAILS_FILE"
    else
        echo "No comments yet." >> "$ISSUE_DETAILS_FILE"
    fi
    
    # Display formatted output
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}ISSUE #$issue_number: $issue_title${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BOLD}Status:${NC} $issue_state"
    echo -e "${BOLD}Labels:${NC} ${issue_labels:-none}"
    echo -e "${BOLD}Assignee:${NC} $issue_assignee"
    echo -e "${BOLD}Created:${NC} $issue_created"
    echo -e "${BOLD}URL:${NC} $issue_url"
    echo ""
    echo -e "${BOLD}${BLUE}Description:${NC}"
    echo -e "${GREEN}──────────────────────────────────────────────────────────────────${NC}"
    echo "$issue_body" | sed 's/^/  /'
    echo ""
    
    if [ "$comment_count" -gt 0 ]; then
        echo -e "${BOLD}${BLUE}Comments ($comment_count):${NC}"
        echo -e "${GREEN}──────────────────────────────────────────────────────────────────${NC}"
        echo "$comments_data" | jq -r '.[] | "  \(.user.login) (\(.created_at)):\n  \(.body)\n"'
    fi
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Full issue details saved to: $ISSUE_DETAILS_FILE${NC}"
    echo ""
}

# Function to get project status
get_project_status() {
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
    echo "$response" | jq -r ".data.user.projectsV2.nodes[0].items.nodes[] | select(.content.number == $ISSUE_NUMBER) | .fieldValues.nodes[] | select(.field.name == \"Status\") | .name // \"Unknown\""
}

# Function to save state
save_state() {
    local state_json="$1"
    echo "$state_json" | jq '.' > "$STATE_FILE"
}

# Function to load state
load_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "{}"
    fi
}

case "$ACTION" in
    start)
        echo -e "${BOLD}Starting work on Issue #$ISSUE_NUMBER${NC}"
        echo ""
        
        # ENHANCEMENT: Automatically fetch and display full issue details
        fetch_and_format_issue_details "$ISSUE_NUMBER"
        
        # Get issue details for state
        ISSUE_DATA=$(get_issue_details)
        ISSUE_TITLE=$(echo "$ISSUE_DATA" | jq -r '.title')
        ISSUE_BODY=$(echo "$ISSUE_DATA" | jq -r '.body // ""')
        ISSUE_LABELS=$(echo "$ISSUE_DATA" | jq -r '.labels[].name' | tr '\n' ',' | sed 's/,$//')
        
        # Check current branch
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
        echo -e "${BLUE}Current branch:${NC} $CURRENT_BRANCH"
        
        # Check for uncommitted changes
        echo ""
        echo "Checking for uncommitted changes..."
        UNCOMMITTED_CHANGES=$(git status --porcelain)
        if [ -n "$UNCOMMITTED_CHANGES" ]; then
            echo -e "${RED}Error: Uncommitted changes detected${NC}"
            echo "$UNCOMMITTED_CHANGES"
            echo ""
            echo -e "${YELLOW}Please commit or stash your changes before starting new work${NC}"
            exit 1
        fi
        echo -e "${GREEN}✓ No uncommitted changes${NC}"
        
        # Check if wip branch exists
        echo ""
        echo "Checking for wip branch..."
        if git show-ref --verify --quiet refs/heads/wip; then
            echo -e "${GREEN}✓ WIP branch exists${NC}"
            # Checkout wip branch
            git checkout wip
            # Pull latest changes
            echo "Pulling latest changes..."
            git pull origin wip 2>/dev/null || echo -e "${YELLOW}No remote wip branch yet${NC}"
        else
            echo -e "${YELLOW}WIP branch doesn't exist. Creating it...${NC}"
            # Create wip branch from master
            git checkout -b wip
            echo -e "${GREEN}✓ Created WIP branch${NC}"
        fi
        
        # Update status to in-progress
        echo ""
        ./scripts/issue-status.sh "$ISSUE_NUMBER" "in-progress"
        
        # Check if PR exists for wip -> master
        echo ""
        echo "Checking for existing WIP pull request..."
        EXISTING_PR=$(rest_api_call "GET" "/repos/$REPO/pulls?state=open&head=bossprank:wip&base=master" | jq -r '.[0].number // "none"')
        
        if [ "$EXISTING_PR" = "none" ]; then
            echo "Creating WIP pull request..."
            PR_BODY="This is the shared Work In Progress branch where all active development happens.

## Active Issues
- Issue #$ISSUE_NUMBER: $ISSUE_TITLE

## Guidelines
- All agents work on this branch
- Commits should reference issue numbers: [#123] Description
- This PR accumulates changes until ready for batch merge to master"
            
            PR_RESPONSE=$(rest_api_call "POST" "/repos/$REPO/pulls" "{
                \"title\": \"[WIP] Active development branch\",
                \"body\": $(echo "$PR_BODY" | jq -Rs .),
                \"head\": \"wip\",
                \"base\": \"master\",
                \"draft\": true
            }")
            
            PR_NUMBER=$(echo "$PR_RESPONSE" | jq -r '.number // "failed"')
            if [ "$PR_NUMBER" != "failed" ]; then
                echo -e "${GREEN}✓ Created WIP PR #$PR_NUMBER${NC}"
            else
                echo -e "${YELLOW}Warning: Failed to create PR${NC}"
                echo "$PR_RESPONSE" | jq '.'
            fi
        else
            echo -e "${GREEN}✓ Using existing WIP PR #$EXISTING_PR${NC}"
            PR_NUMBER="$EXISTING_PR"
        fi
        
        # Create initial state file
        STATE_JSON=$(jq -n \
            --arg number "$ISSUE_NUMBER" \
            --arg title "$ISSUE_TITLE" \
            --arg branch "wip" \
            --arg pr "$PR_NUMBER" \
            --arg started "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
            '{
                issue_number: $number,
                title: $title,
                branch: $branch,
                pr_number: $pr,
                status: "in-progress",
                started_at: $started,
                work_log: [{
                    timestamp: $started,
                    action: "Started work on issue"
                }],
                files_modified: [],
                next_steps: [],
                test_instructions: ""
            }')
        
        save_state "$STATE_JSON"
        
        echo ""
        echo -e "${GREEN}✓ Work session started${NC}"
        echo -e "State saved to: $STATE_FILE"
        echo -e "Issue details saved to: $ISSUE_DETAILS_FILE"
        echo -e "${BLUE}Working branch:${NC} wip"
        echo -e "${BLUE}Pull Request:${NC} #$PR_NUMBER"
        echo ""
        echo -e "${YELLOW}Next steps:${NC}"
        echo "1. Make your code changes"
        echo "2. Use 'git commit -m \"[#$ISSUE_NUMBER] Your message\"' for commits"
        echo "3. Run './scripts/claude-work-enhanced.sh review $ISSUE_NUMBER' when ready for testing"
        ;;
        
    continue)
        echo -e "${BOLD}Continuing work on Issue #$ISSUE_NUMBER${NC}"
        echo ""
        
        if [ ! -f "$STATE_FILE" ]; then
            echo -e "${YELLOW}No previous work session found. Starting new session...${NC}"
            exec "$0" start "$ISSUE_NUMBER"
        fi
        
        # ENHANCEMENT: Show issue details if available
        if [ -f "$ISSUE_DETAILS_FILE" ]; then
            echo -e "${BLUE}Loading cached issue details...${NC}"
            echo ""
            cat "$ISSUE_DETAILS_FILE"
            echo ""
        else
            # Fetch fresh details if not cached
            fetch_and_format_issue_details "$ISSUE_NUMBER"
        fi
        
        # Load state
        STATE=$(load_state)
        ISSUE_TITLE=$(echo "$STATE" | jq -r '.title')
        STARTED_AT=$(echo "$STATE" | jq -r '.started_at')
        WORK_BRANCH=$(echo "$STATE" | jq -r '.branch // "wip"')
        PR_NUMBER=$(echo "$STATE" | jq -r '.pr_number // ""')
        
        echo -e "${BLUE}Session Info:${NC}"
        echo -e "  Started: $STARTED_AT"
        echo -e "  Work Branch: $WORK_BRANCH"
        if [ -n "$PR_NUMBER" ]; then
            echo -e "  Pull Request: #$PR_NUMBER"
        fi
        echo ""
        
        # Check current branch
        CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
        if [ "$CURRENT_BRANCH" != "$WORK_BRANCH" ]; then
            echo "Switching to work branch..."
            
            # Check for uncommitted changes
            UNCOMMITTED_CHANGES=$(git status --porcelain)
            if [ -n "$UNCOMMITTED_CHANGES" ]; then
                echo -e "${RED}Error: Uncommitted changes detected${NC}"
                echo "$UNCOMMITTED_CHANGES"
                echo ""
                echo -e "${YELLOW}Please commit or stash your changes before continuing${NC}"
                exit 1
            fi
            
            # Switch to work branch
            git checkout "$WORK_BRANCH"
            echo -e "${GREEN}✓ Switched to $WORK_BRANCH branch${NC}"
            
            # Pull latest changes
            echo "Pulling latest changes..."
            git pull origin "$WORK_BRANCH" 2>/dev/null || echo -e "${YELLOW}No remote updates${NC}"
        fi
        
        # Get current project status
        PROJECT_STATUS=$(get_project_status)
        echo -e "${BLUE}Project Status:${NC} $PROJECT_STATUS"
        
        # Check if status was moved back from review
        if [ "$PROJECT_STATUS" = "In progress" ]; then
            LAST_STATUS=$(echo "$STATE" | jq -r '.last_status // ""')
            if [ "$LAST_STATUS" = "In review" ]; then
                echo -e "${YELLOW}Note: Issue was moved back from 'In review' to 'In progress'${NC}"
                echo -e "${YELLOW}This usually means changes were requested during testing${NC}"
                
                # Update state
                STATE=$(echo "$STATE" | jq '.status = "in-progress"')
                save_state "$STATE"
            fi
        fi
        
        # Show work log
        echo ""
        echo -e "${BOLD}Work Log:${NC}"
        echo "$STATE" | jq -r '.work_log[] | "  • \(.timestamp): \(.action)"'
        
        # Show files modified
        FILES_COUNT=$(echo "$STATE" | jq '.files_modified | length')
        if [ "$FILES_COUNT" -gt 0 ]; then
            echo ""
            echo -e "${BOLD}Files Modified:${NC}"
            echo "$STATE" | jq -r '.files_modified[]' | while read -r file; do
                echo "  • $file"
            done
        fi
        
        # Show next steps
        NEXT_STEPS_COUNT=$(echo "$STATE" | jq '.next_steps | length')
        if [ "$NEXT_STEPS_COUNT" -gt 0 ]; then
            echo ""
            echo -e "${BOLD}Next Steps:${NC}"
            echo "$STATE" | jq -r '.next_steps[]' | while read -r step; do
                echo "  • $step"
            done
        fi
        
        # Update work log
        NEW_LOG_ENTRY=$(jq -n \
            --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
            '{timestamp: $timestamp, action: "Resumed work on issue"}')
        
        STATE=$(echo "$STATE" | jq ".work_log += [$NEW_LOG_ENTRY]")
        save_state "$STATE"
        
        echo ""
        echo -e "${GREEN}✓ Resumed work session${NC}"
        echo -e "${YELLOW}Remember to commit with: git commit -m \"[#$ISSUE_NUMBER] Description\"${NC}"
        ;;
        
    review)
        echo -e "${BOLD}Marking Issue #$ISSUE_NUMBER ready for review${NC}"
        echo ""
        
        if [ ! -f "$STATE_FILE" ]; then
            echo -e "${RED}Error: No work session found for issue #$ISSUE_NUMBER${NC}"
            exit 1
        fi
        
        # Load state
        STATE=$(load_state)
        
        # Prompt for test instructions
        echo -e "${YELLOW}Enter testing instructions (press Ctrl+D when done):${NC}"
        TEST_INSTRUCTIONS=$(cat)
        
        # Update state with test instructions and status
        STATE=$(echo "$STATE" | jq --arg test "$TEST_INSTRUCTIONS" '.test_instructions = $test | .last_status = "In review" | .status = "in-review"')
        
        # Add to work log
        NEW_LOG_ENTRY=$(jq -n \
            --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
            '{timestamp: $timestamp, action: "Marked ready for review"}')
        
        STATE=$(echo "$STATE" | jq ".work_log += [$NEW_LOG_ENTRY]")
        save_state "$STATE"
        
        # Update project status
        echo ""
        ./scripts/issue-status.sh "$ISSUE_NUMBER" "in-review"
        
        # Update PR if exists
        echo ""
        echo -e "${BLUE}Test Instructions saved. Update PR manually with:${NC}"
        echo ""
        echo "$TEST_INSTRUCTIONS"
        
        echo ""
        echo -e "${GREEN}✓ Issue marked for review${NC}"
        ;;
        
    done)
        echo -e "${BOLD}Marking Issue #$ISSUE_NUMBER as done${NC}"
        echo ""
        
        # Update project status
        ./scripts/issue-status.sh "$ISSUE_NUMBER" "done"
        
        # Archive state file
        if [ -f "$STATE_FILE" ]; then
            ARCHIVE_DIR="$CLAUDE_DIR/archive"
            mkdir -p "$ARCHIVE_DIR"
            mv "$STATE_FILE" "$ARCHIVE_DIR/issue-${ISSUE_NUMBER}-$(date +%Y%m%d-%H%M%S).json"
            echo -e "${GREEN}✓ Work session archived${NC}"
        fi
        
        # Archive issue details
        if [ -f "$ISSUE_DETAILS_FILE" ]; then
            mv "$ISSUE_DETAILS_FILE" "$ARCHIVE_DIR/issue-${ISSUE_NUMBER}-details-$(date +%Y%m%d-%H%M%S).md"
        fi
        
        echo ""
        echo -e "${GREEN}✓ Issue marked as done${NC}"
        ;;
        
    *)
        echo -e "${RED}Error: Invalid action '$ACTION'${NC}"
        echo "Valid actions: start, continue, review, done"
        exit 1
        ;;
esac
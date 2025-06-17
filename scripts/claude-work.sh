#!/bin/bash

# Script to manage Claude work sessions with persistence
# Usage: ./scripts/claude-work.sh <action> <issue-number>
# Actions: start, continue, review, done

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

# Create .claude directory if it doesn't exist
mkdir -p "$CLAUDE_DIR"

# Function to get issue details
get_issue_details() {
    local issue_data=$(rest_api_call "GET" "/repos/$REPO/issues/$ISSUE_NUMBER")
    echo "$issue_data"
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

# Function to check for recent comments
check_recent_comments() {
    local issue_num="$1"
    local pr_num="$2"
    
    echo ""
    echo "Checking for recent comments..."
    
    # Check issue comments
    echo -e "${BLUE}Issue Comments:${NC}"
    local issue_comments=$(rest_api_call "GET" "/repos/$REPO/issues/$issue_num/comments" | jq -r '.[-2:] | reverse | .[] | "  " + .created_at + " by " + .user.login + ": " + (.body | split("\n")[0] | .[0:100]) + if length > 100 then "..." else "" end')
    if [ -n "$issue_comments" ]; then
        echo "$issue_comments"
    else
        echo "  No recent comments"
    fi
    
    # Check PR comments if PR exists
    if [ -n "$pr_num" ] && [ "$pr_num" != "" ]; then
        echo ""
        echo -e "${BLUE}PR Comments:${NC}"
        local pr_comments=$(rest_api_call "GET" "/repos/$REPO/issues/$pr_num/comments" | jq -r '.[-2:] | reverse | .[] | "  " + .created_at + " by " + .user.login + ": " + (.body | split("\n")[0] | .[0:100]) + if length > 100 then "..." else "" end')
        if [ -n "$pr_comments" ]; then
            echo "$pr_comments"
        else
            echo "  No recent comments"
        fi
    fi
    
    echo ""
    echo -e "${YELLOW}Note: Check GitHub for full comment history if needed${NC}"
}

# Function to track files for issue
track_files_for_issue() {
    local issue_num="$1"
    local state_file=".claude/issue-${issue_num}.json"
    
    # Get current git status
    local modified_files=$(git diff --name-only HEAD)
    local staged_files=$(git diff --cached --name-only)
    
    # Combine and deduplicate
    local all_files=$(echo -e "$modified_files\n$staged_files" | sort -u | grep -v '^$')
    
    if [ -n "$all_files" ]; then
        # Load current state
        local state=$(load_state)
        
        # Update files_modified in state
        local files_json=$(echo "$all_files" | jq -R . | jq -s .)
        state=$(echo "$state" | jq --argjson files "$files_json" '.files_modified = ($files + .files_modified) | .files_modified |= unique')
        
        # Save updated state
        save_state "$state"
        
        echo -e "${GREEN}✓ Tracking $(echo "$all_files" | wc -l) files for issue #$issue_num${NC}"
    fi
}

# Function to get commits for issue
get_issue_commits() {
    local issue_num="$1"
    local since_date="$2"
    
    # Get commits that mention this issue number
    git log --since="$since_date" --pretty=format:"%H" --grep="\[#$issue_num\]" | head -20
}

# Function to update PR changelog for issue
update_pr_changelog_for_issue() {
    local issue_num="$1"
    local pr_num="$2"
    local issue_title="$3"
    
    # Get current PR body
    local current_body=$(rest_api_call "GET" "/repos/$REPO/pulls/$pr_num" | jq -r '.body')
    
    # Check if issue already in changelog
    if echo "$current_body" | grep -q "### Issue #$issue_num"; then
        echo -e "${YELLOW}Issue #$issue_num already in PR changelog${NC}"
        return
    fi
    
    # Add issue to changelog
    local new_section="### Issue #$issue_num: $issue_title\n- Started: $(date -u +"%Y-%m-%d %H:%M UTC")\n- Developer: $(git config user.name || echo "Unknown")\n- Files: _to be updated_\n"
    
    # Insert after "Changes by Issue" section
    local new_body=$(echo "$current_body" | awk -v section="$new_section" '
        /## Changes by Issue/ { print; print ""; print section; next }
        { print }
    ')
    
    rest_api_call "PATCH" "/repos/$REPO/pulls/$pr_num" "{
        \"body\": $(echo "$new_body" | jq -Rs .)
    }" > /dev/null
    
    echo -e "${GREEN}✓ Added issue #$issue_num to PR changelog${NC}"
}

# Function to update PR with issue-specific commits
update_pr_for_issue() {
    local issue_num="$1"
    local pr_num="$2"
    local state=$(load_state)
    
    # Get tracked files from state
    local tracked_files=$(echo "$state" | jq -r '.files_modified[]')
    
    if [ -z "$tracked_files" ]; then
        return
    fi
    
    # Get issue title
    local issue_title=$(echo "$state" | jq -r '.title')
    
    # Update PR description with files list
    local current_body=$(rest_api_call "GET" "/repos/$REPO/pulls/$pr_num" | jq -r '.body')
    
    # Build updated section for this issue
    local issue_section="### Issue #$issue_num: $issue_title\n- Started: $(echo "$state" | jq -r '.started_at')\n- Developer: $(git config user.name || echo "Unknown")\n- Files modified:"
    
    echo "$tracked_files" | while read -r file; do
        issue_section+="\n  - $file"
    done
    
    # Update the issue section in the PR
    local new_body
    if echo "$current_body" | grep -q "### Issue #$issue_num:"; then
        # Replace existing section
        new_body=$(echo "$current_body" | awk -v issue="$issue_num" -v section="$issue_section" '
            BEGIN { in_section = 0 }
            /^### Issue #/ {
                if ($0 ~ "### Issue #" issue ":") {
                    print section
                    in_section = 1
                    next
                } else if (in_section) {
                    in_section = 0
                }
            }
            !in_section { print }
        ')
    else
        # Should not happen as we add it when starting
        new_body="$current_body"
    fi
    
    rest_api_call "PATCH" "/repos/$REPO/pulls/$pr_num" "{
        \"body\": $(echo "$new_body" | jq -Rs .)
    }" > /dev/null
    
    echo -e "${GREEN}✓ Updated PR changelog for issue #$issue_num${NC}"
}

# Function to update issue with feedback section
update_issue_feedback() {
    local issue_num="$1"
    local state=$(load_state)
    
    # Get tracked files
    local tracked_files=$(echo "$state" | jq -r '.files_modified[]')
    
    # Build feedback section
    local feedback="## Work Completed\n\n"
    feedback+="**Branch**: wip\n"
    feedback+="**PR**: #$(echo "$state" | jq -r '.pr_number')\n"
    feedback+="**Started**: $(echo "$state" | jq -r '.started_at')\n\n"
    
    if [ -n "$tracked_files" ]; then
        feedback+="**Files Modified**:\n"
        echo "$tracked_files" | while read -r file; do
            feedback+="- $file\n"
        done
        feedback+="\n"
    fi
    
    # Get recent commits for this issue
    local commits=$(git log --oneline --grep="\[#$issue_num\]" -20 | head -10)
    if [ -n "$commits" ]; then
        feedback+="**Commits**:\n\`\`\`\n$commits\n\`\`\`\n\n"
    fi
    
    feedback+="**Status**: Ready for testing\n\n"
    feedback+="---\n\n"
    feedback+="## Testing Feedback\n\n"
    feedback+="_Boss, please add testing instructions and results here. Update this comment with:_\n"
    feedback+="- [ ] Manual testing steps and results\n"
    feedback+="- [ ] Any issues found\n"
    feedback+="- [ ] Changes requested\n"
    feedback+="- [ ] Approval to merge\n"
    
    # Post as comment to issue
    rest_api_call "POST" "/repos/$REPO/issues/$issue_num/comments" "{
        \"body\": $(echo "$feedback" | jq -Rs .)
    }" > /dev/null
    
    echo -e "${GREEN}✓ Added work summary to issue #$issue_num${NC}"
}

case "$ACTION" in
    start)
        echo -e "${BOLD}Starting work on Issue #$ISSUE_NUMBER${NC}"
        echo ""
        
        # Get issue details
        ISSUE_DATA=$(get_issue_details)
        ISSUE_TITLE=$(echo "$ISSUE_DATA" | jq -r '.title')
        ISSUE_BODY=$(echo "$ISSUE_DATA" | jq -r '.body // ""')
        ISSUE_LABELS=$(echo "$ISSUE_DATA" | jq -r '.labels[].name' | tr '\n' ',' | sed 's/,$//')
        
        echo -e "${BLUE}Title:${NC} $ISSUE_TITLE"
        echo -e "${BLUE}Labels:${NC} ${ISSUE_LABELS:-none}"
        
        # Check project status
        echo ""
        echo "Checking issue status in project board..."
        PROJECT_STATUS=$(get_project_status)
        echo -e "${BLUE}Current Status:${NC} $PROJECT_STATUS"
        
        if [ "$PROJECT_STATUS" != "Ready" ] && [ "$PROJECT_STATUS" != "In progress" ]; then
            echo -e "${RED}Error: Issue must be in 'Ready' or 'In progress' status to start work${NC}"
            echo -e "${YELLOW}Current status is: $PROJECT_STATUS${NC}"
            echo -e "${YELLOW}Please move the issue to 'Ready' status before starting work${NC}"
            exit 1
        fi
        echo ""
        
        # Check for recent comments
        check_recent_comments "$ISSUE_NUMBER" ""
        
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
        
        # Check for existing shared PR from wip branch
        echo ""
        echo "Checking for shared PR from wip branch..."
        EXISTING_PR=$(rest_api_call "GET" "/repos/$REPO/pulls?state=open&head=bossprank:wip&base=master" | jq -r '.[0].number // "none"')
        
        if [ "$EXISTING_PR" = "none" ]; then
            echo "Creating shared PR for this sprint/session..."
            PR_BODY="## Sprint Development PR

This is the shared development PR for all active work on the wip branch.

## Active Development

This PR tracks all changes being made during this sprint. Each commit is prefixed with [#issue] for tracking.

## Changes by Issue

_This section is automatically updated as work progresses_

### Issue #$ISSUE_NUMBER: $ISSUE_TITLE
- Started: $(date -u +"%Y-%m-%d %H:%M UTC")
- Developer: $(git config user.name || echo "Unknown")
- Files: _to be updated_

## How This Works

1. All developers work on the shared wip branch
2. Commits are prefixed with [#issue] for attribution  
3. This PR serves as a changelog of all active development
4. Testing and feedback happens in each issue, not here
5. At sprint end, this PR is reviewed and merged"
        
        PR_RESPONSE=$(rest_api_call "POST" "/repos/$REPO/pulls" "{
            \"title\": \"[WIP] Sprint Development - Active Work\",
            \"body\": $(echo "$PR_BODY" | jq -Rs .),
            \"head\": \"wip\",
            \"base\": \"master\",
            \"draft\": true
        }")
        
            PR_NUMBER=$(echo "$PR_RESPONSE" | jq -r '.number // "failed"')
            if [ "$PR_NUMBER" != "failed" ]; then
                echo -e "${GREEN}✓ Created shared sprint PR #$PR_NUMBER${NC}"
            else
                echo -e "${YELLOW}Warning: Failed to create PR${NC}"
                echo "$PR_RESPONSE" | jq '.'
            fi
        else
            echo -e "${GREEN}✓ Using existing shared PR #$EXISTING_PR${NC}"
            PR_NUMBER="$EXISTING_PR"
            
            # Update PR to add this issue to the changelog
            echo "Updating PR to include issue #$ISSUE_NUMBER..."
            update_pr_changelog_for_issue "$ISSUE_NUMBER" "$PR_NUMBER" "$ISSUE_TITLE"
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
        echo -e "${BLUE}Working branch:${NC} wip"
        echo -e "${BLUE}Pull Request:${NC} #$PR_NUMBER"
        echo ""
        echo -e "${YELLOW}Next steps:${NC}"
        echo "1. Make your code changes"
        echo "2. Use 'git add <files>' to stage only files for this issue"
        echo "3. Use 'git commit -m \"[#$ISSUE_NUMBER] Your message\"' for commits"
        echo "4. Files will be automatically tracked for this issue's PR"
        echo "5. Run './scripts/claude-work.sh review $ISSUE_NUMBER' when ready for testing"
        ;;
        
    continue)
        echo -e "${BOLD}Continuing work on Issue #$ISSUE_NUMBER${NC}"
        echo ""
        
        if [ ! -f "$STATE_FILE" ]; then
            echo -e "${YELLOW}No previous work session found. Starting new session...${NC}"
            exec "$0" start "$ISSUE_NUMBER"
        fi
        
        # Check project status before allowing work
        echo "Checking issue status in project board..."
        PROJECT_STATUS=$(get_project_status)
        echo -e "${BLUE}Current Status:${NC} $PROJECT_STATUS"
        
        if [ "$PROJECT_STATUS" != "In progress" ]; then
            echo -e "${RED}Error: Issue must be in 'In progress' status to continue work${NC}"
            echo -e "${YELLOW}Current status is: $PROJECT_STATUS${NC}"
            if [ "$PROJECT_STATUS" = "In review" ]; then
                echo -e "${YELLOW}If changes were requested, please wait for the issue to be moved back to 'In progress'${NC}"
            else
                echo -e "${YELLOW}Please ensure the issue is in the correct status before continuing${NC}"
            fi
            exit 1
        fi
        
        # Load state
        STATE=$(load_state)
        ISSUE_TITLE=$(echo "$STATE" | jq -r '.title')
        STARTED_AT=$(echo "$STATE" | jq -r '.started_at')
        WORK_BRANCH=$(echo "$STATE" | jq -r '.branch // "wip"')
        PR_NUMBER=$(echo "$STATE" | jq -r '.pr_number // ""')
        
        echo -e "${BLUE}Title:${NC} $ISSUE_TITLE"
        echo -e "${BLUE}Started:${NC} $STARTED_AT"
        echo -e "${BLUE}Work Branch:${NC} $WORK_BRANCH"
        if [ -n "$PR_NUMBER" ]; then
            echo -e "${BLUE}Pull Request:${NC} #$PR_NUMBER"
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
        
        # Check for recent comments
        check_recent_comments "$ISSUE_NUMBER" "$PR_NUMBER"
        
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
        
        # Track current files
        track_files_for_issue "$ISSUE_NUMBER"
        
        # Update PR if exists
        if [ -n "$PR_NUMBER" ] && [ "$PR_NUMBER" != "" ]; then
            update_pr_for_issue "$ISSUE_NUMBER" "$PR_NUMBER"
        fi
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
        PR_NUMBER=$(echo "$STATE" | jq -r '.pr_number // ""')
        
        # Final file tracking update
        track_files_for_issue "$ISSUE_NUMBER"
        
        # Update PR with final file list
        if [ -n "$PR_NUMBER" ] && [ "$PR_NUMBER" != "" ]; then
            update_pr_for_issue "$ISSUE_NUMBER" "$PR_NUMBER"
        fi
        
        # Post work summary to issue
        echo ""
        echo "Creating work summary in issue..."
        update_issue_feedback "$ISSUE_NUMBER"
        
        # Update state status
        STATE=$(echo "$STATE" | jq '.last_status = "In review" | .status = "in-review"')
        
        # Add to work log
        NEW_LOG_ENTRY=$(jq -n \
            --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
            '{timestamp: $timestamp, action: "Marked ready for review"}')
        
        STATE=$(echo "$STATE" | jq ".work_log += [$NEW_LOG_ENTRY]")
        save_state "$STATE"
        
        # Update project status
        echo ""
        ./scripts/issue-status.sh "$ISSUE_NUMBER" "in-review"
        
        echo ""
        echo -e "${GREEN}✓ Issue marked for review${NC}"
        echo -e "${YELLOW}Boss, please check issue #$ISSUE_NUMBER for the work summary and add testing feedback${NC}"
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
        
        echo ""
        echo -e "${GREEN}✓ Issue marked as done${NC}"
        ;;
        
    *)
        echo -e "${RED}Error: Invalid action '$ACTION'${NC}"
        echo "Valid actions: start, continue, review, done"
        exit 1
        ;;
esac
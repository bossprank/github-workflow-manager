#!/bin/bash

# Script to audit open GitHub issues and identify files to be edited
# Usage: ./scripts/audit_open_issues.sh

set -e

# Source common configuration
source "$(dirname "$0")/common-config.sh"

# Common code file extensions to look for
CODE_EXTENSIONS=(
    "py" "js" "ts" "jsx" "tsx" "java" "c" "cpp" "h" "hpp"
    "go" "rs" "php" "rb" "swift" "kt" "cs" "sh" "bash"
    "sql" "html" "css" "scss" "json" "yaml" "yml" "xml"
    "md" "txt" "ini" "conf" "env" "dockerfile" "makefile"
)

# Create regex pattern for file detection
FILE_PATTERN=""
for ext in "${CODE_EXTENSIONS[@]}"; do
    if [ -z "$FILE_PATTERN" ]; then
        FILE_PATTERN="[a-zA-Z0-9_\-/]+\.${ext}"
    else
        FILE_PATTERN="${FILE_PATTERN}|[a-zA-Z0-9_\-/]+\.${ext}"
    fi
done

echo -e "${BOLD}GitHub Issues Audit Report${NC}"
echo -e "${BOLD}Repository: ${BLUE}$REPO${NC}"
echo "========================="
echo ""

# Fetch all open issues (excluding pull requests)
echo "Fetching open issues..."
OPEN_ISSUES=$(rest_api_call "GET" "/repos/$REPO/issues?state=open&per_page=100" | \
    jq -c '.[] | select(.pull_request == null)')

if [ -z "$OPEN_ISSUES" ]; then
    echo -e "${GREEN}✓ No open issues found.${NC}"
    exit 0
fi

# Count issues
ISSUE_COUNT=$(echo "$OPEN_ISSUES" | wc -l)
echo -e "${YELLOW}Found $ISSUE_COUNT open issue(s)${NC}"
echo ""

# Process each issue
while IFS= read -r issue; do
    # Extract issue details
    ISSUE_NUMBER=$(echo "$issue" | jq -r '.number')
    ISSUE_TITLE=$(echo "$issue" | jq -r '.title')
    ISSUE_URL=$(echo "$issue" | jq -r '.html_url')
    ISSUE_AUTHOR=$(echo "$issue" | jq -r '.user.login')
    ISSUE_CREATED=$(echo "$issue" | jq -r '.created_at')
    ISSUE_UPDATED=$(echo "$issue" | jq -r '.updated_at')
    ISSUE_BODY=$(echo "$issue" | jq -r '.body // "No description"')
    ISSUE_LABELS=$(echo "$issue" | jq -r '.labels[].name' | tr '\n' ',' | sed 's/,$//')
    ISSUE_ASSIGNEES=$(echo "$issue" | jq -r '.assignees[].login' | tr '\n' ',' | sed 's/,$//')
    
    # Calculate age
    CREATED_TIMESTAMP=$(date -d "$ISSUE_CREATED" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ISSUE_CREATED" +%s 2>/dev/null || echo "0")
    CURRENT_TIMESTAMP=$(date +%s)
    if [ "$CREATED_TIMESTAMP" -ne "0" ]; then
        AGE_SECONDS=$((CURRENT_TIMESTAMP - CREATED_TIMESTAMP))
        AGE_DAYS=$((AGE_SECONDS / 86400))
    else
        AGE_DAYS="unknown"
    fi
    
    echo -e "${BOLD}Issue #$ISSUE_NUMBER: $ISSUE_TITLE${NC}"
    echo -e "  ${BLUE}URL:${NC} $ISSUE_URL"
    echo -e "  ${BLUE}Author:${NC} @$ISSUE_AUTHOR"
    echo -e "  ${BLUE}Created:${NC} $ISSUE_CREATED (${AGE_DAYS} days ago)"
    echo -e "  ${BLUE}Last Updated:${NC} $ISSUE_UPDATED"
    
    if [ -n "$ISSUE_LABELS" ]; then
        echo -e "  ${BLUE}Labels:${NC} $ISSUE_LABELS"
    fi
    
    if [ -n "$ISSUE_ASSIGNEES" ]; then
        echo -e "  ${BLUE}Assignees:${NC} $ISSUE_ASSIGNEES"
    else
        echo -e "  ${YELLOW}Assignees:${NC} Unassigned"
    fi
    
    # Get comments count
    COMMENTS_COUNT=$(echo "$issue" | jq -r '.comments')
    echo -e "  ${BLUE}Comments:${NC} $COMMENTS_COUNT"
    
    # Extract file references from issue body and title
    echo -e "\n  ${BOLD}${CYAN}Files Referenced:${NC}"
    
    # Combine title and body for searching
    FULL_TEXT="$ISSUE_TITLE $ISSUE_BODY"
    
    # Find file references
    FILES_FOUND=""
    
    # Look for file references with common extensions
    ALL_FILES=""
    
    # Search for each extension separately to avoid regex issues
    for ext in "${CODE_EXTENSIONS[@]}"; do
        # Look for files ending with this extension
        EXT_FILES=$(echo "$FULL_TEXT" | grep -oE "[a-zA-Z0-9_/.-]+\\.${ext}\\b" | sort -u)
        if [ -n "$EXT_FILES" ]; then
            ALL_FILES="$ALL_FILES$EXT_FILES"$'\n'
        fi
    done
    
    # Remove duplicates and empty lines
    ALL_FILES=$(echo "$ALL_FILES" | grep -v '^$' | sort -u)
    
    if [ -n "$ALL_FILES" ]; then
        while IFS= read -r file; do
            # Clean up the file path
            CLEAN_FILE=$(echo "$file" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ -n "$CLEAN_FILE" ]; then
                echo -e "    ${CYAN}• $CLEAN_FILE${NC}"
                FILES_FOUND="yes"
            fi
        done <<< "$ALL_FILES"
    fi
    
    # Also look for general code references that might indicate areas to work on
    if [ "$FILES_FOUND" != "yes" ]; then
        # Look for function/class names that might help identify files
        FUNCTIONS=$(echo "$FULL_TEXT" | grep -oE "(function |def |class |method |endpoint |route |api |component )[a-zA-Z0-9_]+" | grep -oE "[a-zA-Z0-9_]+$" | sort -u | head -5)
        if [ -n "$FUNCTIONS" ]; then
            echo -e "    ${YELLOW}No specific files found, but these code elements were mentioned:${NC}"
            while IFS= read -r func; do
                echo -e "    ${YELLOW}• $func (search codebase for this)${NC}"
            done <<< "$FUNCTIONS"
        else
            echo -e "    ${YELLOW}No specific files mentioned${NC}"
        fi
    fi
    
    # Get linked PRs
    echo -e "\n  ${BOLD}${BLUE}Linked Pull Requests:${NC}"
    
    # Search for PR references in comments
    COMMENTS=$(rest_api_call "GET" "/repos/$REPO/issues/$ISSUE_NUMBER/comments" | \
        jq -r '.[].body' 2>/dev/null)
    
    # Combine issue body and comments
    ALL_TEXT="$ISSUE_BODY $COMMENTS"
    
    # Find PR references
    PR_REFS=$(echo "$ALL_TEXT" | grep -oE "#[0-9]+" | sort -u)
    
    if [ -n "$PR_REFS" ]; then
        FOUND_PR=false
        while IFS= read -r pr_ref; do
            PR_NUM=${pr_ref#"#"}
            # Check if this reference is actually a PR
            PR_CHECK=$(rest_api_call "GET" "/repos/$REPO/pulls/$PR_NUM" 2>/dev/null | \
                jq -r '.number // "null"')
            
            if [ "$PR_CHECK" != "null" ]; then
                PR_STATE=$(rest_api_call "GET" "/repos/$REPO/pulls/$PR_NUM" | \
                    jq -r '.state')
                echo -e "    • PR #$PR_NUM (${PR_STATE})"
                FOUND_PR=true
            fi
        done <<< "$PR_REFS"
        
        if [ "$FOUND_PR" = false ]; then
            echo -e "    ${YELLOW}No linked PRs found${NC}"
        fi
    else
        echo -e "    ${YELLOW}No linked PRs found${NC}"
    fi
    
    # Status analysis
    echo -e "\n  ${BOLD}${YELLOW}Status Analysis:${NC}"
    
    # Check if it's a bug
    if [[ "$ISSUE_LABELS" == *"bug"* ]]; then
        echo -e "    ${RED}• Bug report - needs fixing${NC}"
    fi
    
    # Check if it's assigned
    if [ -z "$ISSUE_ASSIGNEES" ]; then
        echo -e "    ${YELLOW}• Unassigned - needs someone to work on it${NC}"
    fi
    
    # Check age
    if [ "$AGE_DAYS" != "unknown" ] && [ "$AGE_DAYS" -gt 30 ]; then
        echo -e "    ${RED}• Over 30 days old - may need attention${NC}"
    elif [ "$AGE_DAYS" != "unknown" ] && [ "$AGE_DAYS" -gt 14 ]; then
        echo -e "    ${YELLOW}• Over 2 weeks old${NC}"
    fi
    
    # Check for recent activity
    UPDATED_TIMESTAMP=$(date -d "$ISSUE_UPDATED" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ISSUE_UPDATED" +%s 2>/dev/null || echo "0")
    if [ "$UPDATED_TIMESTAMP" -ne "0" ]; then
        INACTIVE_SECONDS=$((CURRENT_TIMESTAMP - UPDATED_TIMESTAMP))
        INACTIVE_DAYS=$((INACTIVE_SECONDS / 86400))
        if [ "$INACTIVE_DAYS" -gt 7 ]; then
            echo -e "    ${YELLOW}• No activity for $INACTIVE_DAYS days${NC}"
        fi
    fi
    
    echo ""
    echo "---"
    echo ""
    
done <<< "$OPEN_ISSUES"

# Summary
echo -e "${BOLD}Summary:${NC}"
echo -e "Total open issues: ${YELLOW}$ISSUE_COUNT${NC}"

# Count by labels
echo -e "\n${BOLD}Issues by Label:${NC}"
echo "$OPEN_ISSUES" | jq -r '.labels[].name' | sort | uniq -c | sort -rn | while read count label; do
    echo -e "  $count - $label"
done

# Count unassigned
UNASSIGNED_COUNT=$(echo "$OPEN_ISSUES" | jq -r '. | select(.assignees | length == 0) | .number' | wc -l)
echo -e "\n${YELLOW}Unassigned issues: $UNASSIGNED_COUNT${NC}"

echo ""
echo -e "${BLUE}Run this command anytime to check issue status:${NC}"
echo "./scripts/audit_open_issues.sh"
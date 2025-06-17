#!/bin/bash

# Script to audit open pull requests and show what needs to be done
# Usage: ./scripts/audit_open_prs.sh

set -e

# Source common configuration
source "$(dirname "$0")/common-config.sh"

echo -e "${BOLD}GitHub PR Audit Report${NC}"
echo -e "${BOLD}Repository: ${BLUE}$REPO${NC}"
echo "========================="
echo ""

# Fetch all open PRs with detailed information
echo "Fetching open pull requests..."
OPEN_PRS=$(rest_api_call "GET" "/repos/$REPO/pulls?state=open" | \
    jq -c '.[]')

if [ -z "$OPEN_PRS" ]; then
    echo -e "${GREEN}✓ No open pull requests found.${NC}"
    exit 0
fi

# Count PRs
PR_COUNT=$(echo "$OPEN_PRS" | wc -l)
echo -e "${YELLOW}Found $PR_COUNT open pull request(s)${NC}"
echo ""

# Process each PR
while IFS= read -r pr; do
    # Extract PR details
    PR_NUMBER=$(echo "$pr" | jq -r '.number')
    PR_TITLE=$(echo "$pr" | jq -r '.title')
    PR_AUTHOR=$(echo "$pr" | jq -r '.user.login')
    PR_URL=$(echo "$pr" | jq -r '.html_url')
    PR_CREATED=$(echo "$pr" | jq -r '.created_at')
    PR_UPDATED=$(echo "$pr" | jq -r '.updated_at')
    PR_DRAFT=$(echo "$pr" | jq -r '.draft')
    PR_MERGEABLE_STATE=$(echo "$pr" | jq -r '.mergeable_state // "unknown"')
    PR_BODY=$(echo "$pr" | jq -r '.body // "No description"')
    
    # Calculate age
    CREATED_TIMESTAMP=$(date -d "$PR_CREATED" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$PR_CREATED" +%s 2>/dev/null || echo "0")
    CURRENT_TIMESTAMP=$(date +%s)
    if [ "$CREATED_TIMESTAMP" -ne "0" ]; then
        AGE_SECONDS=$((CURRENT_TIMESTAMP - CREATED_TIMESTAMP))
        AGE_DAYS=$((AGE_SECONDS / 86400))
    else
        AGE_DAYS="unknown"
    fi
    
    echo -e "${BOLD}PR #$PR_NUMBER: $PR_TITLE${NC}"
    echo -e "  ${BLUE}URL:${NC} $PR_URL"
    echo -e "  ${BLUE}Author:${NC} @$PR_AUTHOR"
    echo -e "  ${BLUE}Created:${NC} $PR_CREATED (${AGE_DAYS} days ago)"
    echo -e "  ${BLUE}Last Updated:${NC} $PR_UPDATED"
    
    if [ "$PR_DRAFT" = "true" ]; then
        echo -e "  ${YELLOW}Status: DRAFT${NC}"
    fi
    
    # Fetch additional PR details (reviews, checks, comments)
    echo -e "  ${BLUE}Checking PR status...${NC}"
    
    # Get review status
    REVIEWS=$(rest_api_call "GET" "/repos/$REPO/pulls/$PR_NUMBER/reviews" | \
        jq -r 'map(.state) | unique | join(", ")')
    
    if [ -n "$REVIEWS" ] && [ "$REVIEWS" != "null" ]; then
        echo -e "  ${BLUE}Reviews:${NC} $REVIEWS"
    else
        echo -e "  ${YELLOW}Reviews:${NC} No reviews yet"
    fi
    
    # Get check runs status
    CHECK_RUNS=$(rest_api_call "GET" "/repos/$REPO/commits/$(echo "$pr" | jq -r '.head.sha')/check-runs" | \
        jq -r '.check_runs | if length > 0 then map("\(.name): \(.conclusion // .status)") | join(", ") else "No checks" end')
    
    echo -e "  ${BLUE}Checks:${NC} $CHECK_RUNS"
    
    # Get PR comments count
    COMMENTS_COUNT=$(rest_api_call "GET" "/repos/$REPO/issues/$PR_NUMBER/comments" | \
        jq '. | length')
    
    echo -e "  ${BLUE}Comments:${NC} $COMMENTS_COUNT"
    
    # Check if PR is mergeable
    PR_DETAIL=$(rest_api_call "GET" "/repos/$REPO/pulls/$PR_NUMBER")
    
    MERGEABLE=$(echo "$PR_DETAIL" | jq -r '.mergeable // "unknown"')
    MERGE_CONFLICTS=$(echo "$PR_DETAIL" | jq -r '.mergeable_state // "unknown"')
    
    echo -e "  ${BLUE}Mergeable:${NC} $MERGEABLE (state: $MERGE_CONFLICTS)"
    
    # Analyze what needs to be done
    echo -e "\n  ${BOLD}${YELLOW}TODO:${NC}"
    
    TODO_COUNT=0
    
    # Check for merge conflicts
    if [ "$MERGEABLE" = "false" ] || [ "$MERGE_CONFLICTS" = "conflicting" ]; then
        echo -e "    ${RED}• Resolve merge conflicts${NC}"
        TODO_COUNT=$((TODO_COUNT + 1))
    fi
    
    # Check for reviews
    if [ -z "$REVIEWS" ] || [ "$REVIEWS" = "null" ] || [ "$REVIEWS" = "" ]; then
        echo -e "    ${YELLOW}• Needs code review${NC}"
        TODO_COUNT=$((TODO_COUNT + 1))
    elif [[ "$REVIEWS" == *"CHANGES_REQUESTED"* ]]; then
        echo -e "    ${RED}• Address requested changes${NC}"
        TODO_COUNT=$((TODO_COUNT + 1))
    elif [[ ! "$REVIEWS" == *"APPROVED"* ]]; then
        echo -e "    ${YELLOW}• Awaiting approval${NC}"
        TODO_COUNT=$((TODO_COUNT + 1))
    fi
    
    # Check if draft
    if [ "$PR_DRAFT" = "true" ]; then
        echo -e "    ${YELLOW}• Mark as ready for review (currently draft)${NC}"
        TODO_COUNT=$((TODO_COUNT + 1))
    fi
    
    # Check for failing checks
    if [[ "$CHECK_RUNS" == *"failure"* ]]; then
        echo -e "    ${RED}• Fix failing checks${NC}"
        TODO_COUNT=$((TODO_COUNT + 1))
    elif [[ "$CHECK_RUNS" == *"in_progress"* ]] || [[ "$CHECK_RUNS" == *"queued"* ]]; then
        echo -e "    ${YELLOW}• Waiting for checks to complete${NC}"
        TODO_COUNT=$((TODO_COUNT + 1))
    fi
    
    # Check age
    if [ "$AGE_DAYS" != "unknown" ] && [ "$AGE_DAYS" -gt 7 ]; then
        echo -e "    ${YELLOW}• PR is ${AGE_DAYS} days old - consider prioritizing${NC}"
        TODO_COUNT=$((TODO_COUNT + 1))
    fi
    
    if [ $TODO_COUNT -eq 0 ]; then
        echo -e "    ${GREEN}✓ Ready to merge!${NC}"
    fi
    
    # Extract issue references from PR body
    if [ "$PR_BODY" != "No description" ] && [ "$PR_BODY" != "null" ]; then
        ISSUE_REFS=$(echo "$PR_BODY" | grep -oE "(#[0-9]+|[Ff]ix(es)?|[Cc]lose(s)?|[Rr]esolve(s)? #[0-9]+)" | grep -oE "#[0-9]+" | sort -u | tr '\n' ' ')
        if [ -n "$ISSUE_REFS" ]; then
            echo -e "\n  ${BLUE}Related Issues:${NC} $ISSUE_REFS"
        fi
    fi
    
    echo ""
    echo "---"
    echo ""
    
done <<< "$OPEN_PRS"

# Summary
echo -e "${BOLD}Summary:${NC}"
echo -e "Total open PRs: ${YELLOW}$PR_COUNT${NC}"
echo ""
echo -e "${BLUE}Run this command anytime to check PR status:${NC}"
echo "./scripts/audit_open_prs.sh"
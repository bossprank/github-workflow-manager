#!/bin/bash

# GitHub Workflow Manager - Configuration Template
# Copy this to scripts/common-config.sh and customize for your project

# ============================================
# REPOSITORY CONFIGURATION
# ============================================

# Your GitHub repository (format: "owner/repo")
export REPO="YOUR_GITHUB_USERNAME/YOUR_REPO_NAME"

# ============================================
# AUTHENTICATION CONFIGURATION
# ============================================

# Token access method - choose one:
# - "env": Read from environment variable
# - "file": Read from file
# - "gcloud": Read from Google Secret Manager
export TOKEN_METHOD="env"

# Configuration for each method:
# For "env" method:
export TOKEN_ENV_VAR="GITHUB_TOKEN"

# For "file" method:
export TOKEN_FILE="$HOME/.github-token"

# For "gcloud" method:
export TOKEN_SECRET="github-workflow-token"

# ============================================
# PROJECT BOARD CONFIGURATION
# ============================================

# Your project board details (run setup-workflow.sh to discover these)
export PROJECT_ID="YOUR_PROJECT_ID"
export PROJECT_NAME="Your Project Name"

# Field IDs (discovered via setup script)
export STATUS_FIELD_ID="YOUR_STATUS_FIELD_ID"
export PRIORITY_FIELD_ID="YOUR_PRIORITY_FIELD_ID"
export SIZE_FIELD_ID="YOUR_SIZE_FIELD_ID"
export ESTIMATE_FIELD_ID="YOUR_ESTIMATE_FIELD_ID"

# Status option IDs
export BACKLOG_ID="YOUR_BACKLOG_ID"
export READY_ID="YOUR_READY_ID"
export IN_PROGRESS_ID="YOUR_IN_PROGRESS_ID"
export IN_REVIEW_ID="YOUR_IN_REVIEW_ID"
export DONE_ID="YOUR_DONE_ID"

# Priority option IDs
export P0_ID="YOUR_P0_ID"
export P1_ID="YOUR_P1_ID"
export P2_ID="YOUR_P2_ID"

# Size option IDs
export XS_ID="YOUR_XS_ID"
export S_ID="YOUR_S_ID"
export M_ID="YOUR_M_ID"
export L_ID="YOUR_L_ID"
export XL_ID="YOUR_XL_ID"

# ============================================
# HELPER FUNCTIONS (DO NOT MODIFY)
# ============================================

# Function to get estimate hours based on size (Fibonacci sequence)
get_estimate_for_size() {
    local size="$1"
    case "$size" in
        XS) echo "1" ;;   # 1 hour
        S)  echo "2" ;;   # 2 hours
        M)  echo "4" ;;   # ~half day
        L)  echo "8" ;;   # 1 day
        XL) echo "16" ;;  # 2 days
        *)  echo "4" ;;   # Default to medium
    esac
}

# Colors for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export NC='\033[0m' # No Color
export BOLD='\033[1m'

# Function to get GitHub token based on configured method
get_github_token() {
    local token=""
    
    case "$TOKEN_METHOD" in
        env)
            token="${!TOKEN_ENV_VAR}"
            if [ -z "$token" ]; then
                echo -e "${RED}Error: Environment variable '$TOKEN_ENV_VAR' is not set${NC}" >&2
                echo -e "${YELLOW}Run: export $TOKEN_ENV_VAR='your-github-token'${NC}" >&2
                exit 1
            fi
            ;;
        file)
            if [ -f "$TOKEN_FILE" ]; then
                token=$(cat "$TOKEN_FILE" | tr -d '\n')
            else
                echo -e "${RED}Error: Token file '$TOKEN_FILE' not found${NC}" >&2
                echo -e "${YELLOW}Create it with: echo 'your-token' > $TOKEN_FILE${NC}" >&2
                exit 1
            fi
            ;;
        gcloud)
            if command -v gcloud >/dev/null 2>&1; then
                token=$(gcloud secrets versions access latest --secret="$TOKEN_SECRET" 2>/dev/null)
                if [ -z "$token" ]; then
                    echo -e "${RED}Error: Failed to retrieve token from Google Secret Manager${NC}" >&2
                    echo -e "${YELLOW}Ensure secret '$TOKEN_SECRET' exists and you have access${NC}" >&2
                    exit 1
                fi
            else
                echo -e "${RED}Error: gcloud CLI not found but TOKEN_METHOD is set to 'gcloud'${NC}" >&2
                echo -e "${YELLOW}Install gcloud CLI or change TOKEN_METHOD in config${NC}" >&2
                exit 1
            fi
            ;;
        *)
            echo -e "${RED}Error: Invalid TOKEN_METHOD '$TOKEN_METHOD'${NC}" >&2
            echo -e "${YELLOW}Valid options: env, file, gcloud${NC}" >&2
            exit 1
            ;;
    esac
    
    echo "$token"
}

# Function to make GraphQL queries
graphql_query() {
    local query="$1"
    local token=$(get_github_token)
    
    # Create a proper JSON object with the query
    local json_payload=$(jq -n --arg q "$query" '{query: $q}')
    
    curl -s -H "Authorization: token $token" \
         -H "Content-Type: application/json" \
         -H "X-Github-Next-Global-ID: 1" \
         -X POST https://api.github.com/graphql \
         -d "$json_payload"
}

# Function to make REST API calls
rest_api_call() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local token=$(get_github_token)
    
    if [ -z "$data" ]; then
        curl -s -X "$method" \
             -H "Authorization: token $token" \
             -H "Accept: application/vnd.github.v3+json" \
             "https://api.github.com$endpoint"
    else
        curl -s -X "$method" \
             -H "Authorization: token $token" \
             -H "Accept: application/vnd.github.v3+json" \
             -H "Content-Type: application/json" \
             -d "$data" \
             "https://api.github.com$endpoint"
    fi
}
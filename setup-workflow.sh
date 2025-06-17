#!/bin/bash

# GitHub Workflow Manager - Setup Script
# This script helps configure the workflow manager for your project

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BOLD}GitHub Workflow Manager Setup${NC}"
echo "================================="
echo ""

# Check if --discover-only flag is set
DISCOVER_ONLY=false
if [ "$1" = "--discover-only" ]; then
    DISCOVER_ONLY=true
fi

# Function to check dependencies
check_dependencies() {
    echo -e "${BOLD}Checking dependencies...${NC}"
    
    local missing=()
    
    for cmd in bash git curl jq; do
        if command -v $cmd >/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} $cmd found: $(command -v $cmd)"
        else
            echo -e "  ${RED}✗${NC} $cmd not found"
            missing+=($cmd)
        fi
    done
    
    # Optional: Check for gcloud
    if command -v gcloud >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} gcloud found (optional): $(command -v gcloud)"
    else
        echo -e "  ${YELLOW}i${NC} gcloud not found (optional - only needed for Google Secret Manager)"
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo ""
        echo -e "${RED}Error: Missing required dependencies: ${missing[*]}${NC}"
        echo ""
        echo "Installation instructions:"
        echo "  macOS:        brew install ${missing[*]}"
        echo "  Ubuntu/Debian: sudo apt-get install ${missing[*]}"
        echo "  Other:        Check your package manager"
        exit 1
    fi
    
    echo -e "${GREEN}All required dependencies found!${NC}"
    echo ""
}

# Function to setup GitHub token
setup_github_token() {
    echo -e "${BOLD}GitHub Token Configuration${NC}"
    echo ""
    
    # Check if token already exists in environment
    if [ -n "$GITHUB_TOKEN" ]; then
        echo -e "${GREEN}Found GITHUB_TOKEN in environment${NC}"
        echo -n "Use this token? [Y/n]: "
        read -r use_existing
        if [[ "$use_existing" != "n" && "$use_existing" != "N" ]]; then
            TOKEN_METHOD="env"
            TOKEN_ENV_VAR="GITHUB_TOKEN"
            return
        fi
    fi
    
    echo "Choose token storage method:"
    echo "  1) Environment variable (simplest)"
    echo "  2) File-based (more secure)"
    echo "  3) Google Secret Manager (most secure - requires gcloud)"
    echo -n "Choice [1-3]: "
    read -r choice
    
    case "$choice" in
        1)
            TOKEN_METHOD="env"
            echo ""
            echo "You'll need to set the GITHUB_TOKEN environment variable."
            echo "Add this to your shell profile (.bashrc, .zshrc, etc.):"
            echo ""
            echo "  export GITHUB_TOKEN='your-github-token'"
            echo ""
            TOKEN_ENV_VAR="GITHUB_TOKEN"
            ;;
        2)
            TOKEN_METHOD="file"
            TOKEN_FILE="$HOME/.github-workflow-token"
            echo ""
            echo -n "Enter your GitHub token: "
            read -rs token
            echo ""
            echo "$token" > "$TOKEN_FILE"
            chmod 600 "$TOKEN_FILE"
            echo -e "${GREEN}Token saved to $TOKEN_FILE${NC}"
            ;;
        3)
            if ! command -v gcloud >/dev/null 2>&1; then
                echo -e "${RED}Error: gcloud not installed${NC}"
                exit 1
            fi
            TOKEN_METHOD="gcloud"
            TOKEN_SECRET="github-workflow-token"
            echo ""
            echo -n "Enter your GitHub token: "
            read -rs token
            echo ""
            echo "Creating secret in Google Secret Manager..."
            echo "$token" | gcloud secrets create "$TOKEN_SECRET" --data-file=-
            echo -e "${GREEN}Token saved to Google Secret Manager as '$TOKEN_SECRET'${NC}"
            ;;
        *)
            echo -e "${RED}Invalid choice${NC}"
            exit 1
            ;;
    esac
}

# Function to get repository info
get_repository_info() {
    echo -e "${BOLD}Repository Configuration${NC}"
    echo ""
    
    # Try to detect from git remote
    if git remote get-url origin >/dev/null 2>&1; then
        local remote_url=$(git remote get-url origin)
        local detected_repo=""
        
        # Extract owner/repo from URL
        if [[ "$remote_url" =~ github\.com[:/]([^/]+)/([^/]+)(\.git)?$ ]]; then
            detected_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
            detected_repo="${detected_repo%.git}"  # Remove .git suffix if present
            
            echo -e "Detected repository: ${CYAN}$detected_repo${NC}"
            echo -n "Use this repository? [Y/n]: "
            read -r use_detected
            
            if [[ "$use_detected" != "n" && "$use_detected" != "N" ]]; then
                REPO="$detected_repo"
                return
            fi
        fi
    fi
    
    # Manual input
    echo -n "Enter repository (format: owner/repo): "
    read -r REPO
    
    if [[ ! "$REPO" =~ ^[^/]+/[^/]+$ ]]; then
        echo -e "${RED}Error: Invalid repository format. Use: owner/repo${NC}"
        exit 1
    fi
}

# Function to discover project board
discover_project_board() {
    echo -e "${BOLD}Discovering Project Boards...${NC}"
    echo ""
    
    # Create temporary config for API calls
    cat > "$SCRIPT_DIR/.temp-config.sh" << EOF
export TOKEN_METHOD="$TOKEN_METHOD"
export TOKEN_ENV_VAR="${TOKEN_ENV_VAR:-GITHUB_TOKEN}"
export TOKEN_FILE="${TOKEN_FILE:-}"
export TOKEN_SECRET="${TOKEN_SECRET:-}"
$(declare -f get_github_token)
$(declare -f graphql_query)
$(declare -f rest_api_call)
EOF
    
    source "$SCRIPT_DIR/.temp-config.sh"
    
    # Get repository node ID
    local repo_data=$(rest_api_call "GET" "/repos/$REPO")
    local repo_node_id=$(echo "$repo_data" | jq -r '.node_id // ""')
    
    if [ -z "$repo_node_id" ] || [ "$repo_node_id" = "null" ]; then
        echo -e "${RED}Error: Could not access repository $REPO${NC}"
        echo "Please check:"
        echo "  - Repository name is correct"
        echo "  - Token has 'repo' scope"
        echo "  - You have access to the repository"
        rm -f "$SCRIPT_DIR/.temp-config.sh"
        exit 1
    fi
    
    # Query for project boards
    local query='query($repo_id: ID!) {
        node(id: $repo_id) {
            ... on Repository {
                projectsV2(first: 20) {
                    nodes {
                        id
                        title
                        number
                        fields(first: 20) {
                            nodes {
                                ... on ProjectV2Field {
                                    id
                                    name
                                }
                                ... on ProjectV2SingleSelectField {
                                    id
                                    name
                                    options {
                                        id
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
    
    local variables=$(jq -n --arg repo_id "$repo_node_id" '{repo_id: $repo_id}')
    local response=$(echo '{"query": '"$(echo "$query" | jq -Rs .)"', "variables": '"$variables"'}' | \
        curl -s -H "Authorization: token $(get_github_token)" \
             -H "Content-Type: application/json" \
             -H "X-Github-Next-Global-ID: 1" \
             -X POST https://api.github.com/graphql -d @-)
    
    local projects=$(echo "$response" | jq -r '.data.node.projectsV2.nodes[]')
    
    if [ -z "$projects" ]; then
        echo -e "${YELLOW}No project boards found for repository${NC}"
        echo ""
        echo "You'll need to:"
        echo "  1. Create a project board on GitHub"
        echo "  2. Add these fields:"
        echo "     - Status (single select): Backlog, Ready, In progress, In review, Done"
        echo "     - Priority (single select): P0, P1, P2"
        echo "     - Size (single select): XS, S, M, L, XL"
        echo "     - Estimate (number)"
        echo "  3. Run this setup again"
        rm -f "$SCRIPT_DIR/.temp-config.sh"
        exit 1
    fi
    
    echo "Found project boards:"
    echo ""
    
    # List projects
    local project_count=0
    local project_ids=()
    local project_names=()
    
    while IFS= read -r project; do
        if [ -n "$project" ]; then
            ((project_count++))
            local id=$(echo "$project" | jq -r '.id')
            local title=$(echo "$project" | jq -r '.title')
            local number=$(echo "$project" | jq -r '.number')
            
            project_ids+=("$id")
            project_names+=("$title")
            
            echo "  $project_count) $title (#$number)"
        fi
    done <<< "$(echo "$response" | jq -c '.data.node.projectsV2.nodes[]')"
    
    if [ "$project_count" -eq 0 ]; then
        echo -e "${RED}No projects found${NC}"
        rm -f "$SCRIPT_DIR/.temp-config.sh"
        exit 1
    fi
    
    echo ""
    echo -n "Select project [1-$project_count]: "
    read -r selection
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "$project_count" ]; then
        echo -e "${RED}Invalid selection${NC}"
        rm -f "$SCRIPT_DIR/.temp-config.sh"
        exit 1
    fi
    
    PROJECT_ID="${project_ids[$((selection-1))]}"
    PROJECT_NAME="${project_names[$((selection-1))]}"
    
    echo ""
    echo -e "${GREEN}Selected: $PROJECT_NAME${NC}"
    echo ""
    
    # Extract field IDs
    local selected_project=$(echo "$response" | jq -c ".data.node.projectsV2.nodes[$((selection-1))]")
    
    echo -e "${BOLD}Discovering Field IDs...${NC}"
    echo ""
    
    # Parse fields
    local status_field=$(echo "$selected_project" | jq -r '.fields.nodes[] | select(.name == "Status")')
    local priority_field=$(echo "$selected_project" | jq -r '.fields.nodes[] | select(.name == "Priority")')
    local size_field=$(echo "$selected_project" | jq -r '.fields.nodes[] | select(.name == "Size")')
    local estimate_field=$(echo "$selected_project" | jq -r '.fields.nodes[] | select(.name == "Estimate")')
    
    if [ -n "$status_field" ]; then
        STATUS_FIELD_ID=$(echo "$status_field" | jq -r '.id')
        echo -e "  ${GREEN}✓${NC} Status field found"
        
        # Get status options
        BACKLOG_ID=$(echo "$status_field" | jq -r '.options[] | select(.name == "Backlog") | .id // ""')
        READY_ID=$(echo "$status_field" | jq -r '.options[] | select(.name == "Ready") | .id // ""')
        IN_PROGRESS_ID=$(echo "$status_field" | jq -r '.options[] | select(.name == "In progress") | .id // ""')
        IN_REVIEW_ID=$(echo "$status_field" | jq -r '.options[] | select(.name == "In review") | .id // ""')
        DONE_ID=$(echo "$status_field" | jq -r '.options[] | select(.name == "Done") | .id // ""')
    else
        echo -e "  ${YELLOW}!${NC} Status field not found"
    fi
    
    if [ -n "$priority_field" ]; then
        PRIORITY_FIELD_ID=$(echo "$priority_field" | jq -r '.id')
        echo -e "  ${GREEN}✓${NC} Priority field found"
        
        # Get priority options
        P0_ID=$(echo "$priority_field" | jq -r '.options[] | select(.name == "P0") | .id // ""')
        P1_ID=$(echo "$priority_field" | jq -r '.options[] | select(.name == "P1") | .id // ""')
        P2_ID=$(echo "$priority_field" | jq -r '.options[] | select(.name == "P2") | .id // ""')
    else
        echo -e "  ${YELLOW}!${NC} Priority field not found"
    fi
    
    if [ -n "$size_field" ]; then
        SIZE_FIELD_ID=$(echo "$size_field" | jq -r '.id')
        echo -e "  ${GREEN}✓${NC} Size field found"
        
        # Get size options
        XS_ID=$(echo "$size_field" | jq -r '.options[] | select(.name == "XS") | .id // ""')
        S_ID=$(echo "$size_field" | jq -r '.options[] | select(.name == "S") | .id // ""')
        M_ID=$(echo "$size_field" | jq -r '.options[] | select(.name == "M") | .id // ""')
        L_ID=$(echo "$size_field" | jq -r '.options[] | select(.name == "L") | .id // ""')
        XL_ID=$(echo "$size_field" | jq -r '.options[] | select(.name == "XL") | .id // ""')
    else
        echo -e "  ${YELLOW}!${NC} Size field not found"
    fi
    
    if [ -n "$estimate_field" ]; then
        ESTIMATE_FIELD_ID=$(echo "$estimate_field" | jq -r '.id')
        echo -e "  ${GREEN}✓${NC} Estimate field found"
    else
        echo -e "  ${YELLOW}!${NC} Estimate field not found"
    fi
    
    # Clean up temp config
    rm -f "$SCRIPT_DIR/.temp-config.sh"
}

# Function to generate configuration
generate_config() {
    echo ""
    echo -e "${BOLD}Generating Configuration...${NC}"
    
    local config_file="$SCRIPT_DIR/scripts/common-config.sh"
    
    # Create scripts directory if it doesn't exist
    mkdir -p "$SCRIPT_DIR/scripts"
    
    # Generate config from template
    cat "$SCRIPT_DIR/config.template.sh" | \
        sed "s|YOUR_GITHUB_USERNAME/YOUR_REPO_NAME|$REPO|g" | \
        sed "s|TOKEN_METHOD=\"env\"|TOKEN_METHOD=\"$TOKEN_METHOD\"|g" | \
        sed "s|TOKEN_ENV_VAR=\"GITHUB_TOKEN\"|TOKEN_ENV_VAR=\"${TOKEN_ENV_VAR:-GITHUB_TOKEN}\"|g" | \
        sed "s|TOKEN_FILE=\"\$HOME/.github-token\"|TOKEN_FILE=\"${TOKEN_FILE:-\$HOME/.github-token}\"|g" | \
        sed "s|TOKEN_SECRET=\"github-workflow-token\"|TOKEN_SECRET=\"${TOKEN_SECRET:-github-workflow-token}\"|g" | \
        sed "s|YOUR_PROJECT_ID|$PROJECT_ID|g" | \
        sed "s|Your Project Name|$PROJECT_NAME|g" | \
        sed "s|YOUR_STATUS_FIELD_ID|${STATUS_FIELD_ID:-YOUR_STATUS_FIELD_ID}|g" | \
        sed "s|YOUR_PRIORITY_FIELD_ID|${PRIORITY_FIELD_ID:-YOUR_PRIORITY_FIELD_ID}|g" | \
        sed "s|YOUR_SIZE_FIELD_ID|${SIZE_FIELD_ID:-YOUR_SIZE_FIELD_ID}|g" | \
        sed "s|YOUR_ESTIMATE_FIELD_ID|${ESTIMATE_FIELD_ID:-YOUR_ESTIMATE_FIELD_ID}|g" | \
        sed "s|YOUR_BACKLOG_ID|${BACKLOG_ID:-YOUR_BACKLOG_ID}|g" | \
        sed "s|YOUR_READY_ID|${READY_ID:-YOUR_READY_ID}|g" | \
        sed "s|YOUR_IN_PROGRESS_ID|${IN_PROGRESS_ID:-YOUR_IN_PROGRESS_ID}|g" | \
        sed "s|YOUR_IN_REVIEW_ID|${IN_REVIEW_ID:-YOUR_IN_REVIEW_ID}|g" | \
        sed "s|YOUR_DONE_ID|${DONE_ID:-YOUR_DONE_ID}|g" | \
        sed "s|YOUR_P0_ID|${P0_ID:-YOUR_P0_ID}|g" | \
        sed "s|YOUR_P1_ID|${P1_ID:-YOUR_P1_ID}|g" | \
        sed "s|YOUR_P2_ID|${P2_ID:-YOUR_P2_ID}|g" | \
        sed "s|YOUR_XS_ID|${XS_ID:-YOUR_XS_ID}|g" | \
        sed "s|YOUR_S_ID|${S_ID:-YOUR_S_ID}|g" | \
        sed "s|YOUR_M_ID|${M_ID:-YOUR_M_ID}|g" | \
        sed "s|YOUR_L_ID|${L_ID:-YOUR_L_ID}|g" | \
        sed "s|YOUR_XL_ID|${XL_ID:-YOUR_XL_ID}|g" \
        > "$config_file"
    
    chmod +x "$config_file"
    
    echo -e "${GREEN}Configuration saved to: scripts/common-config.sh${NC}"
}

# Function to copy scripts
copy_scripts() {
    echo ""
    echo -e "${BOLD}Setting up scripts...${NC}"
    
    # Check if we're in the package directory or if scripts exist in current repo
    if [ -d "$SCRIPT_DIR/../scripts" ] && [ -f "$SCRIPT_DIR/../scripts/claude-work.sh" ]; then
        # We're in a repo with existing scripts
        echo "Found existing scripts in parent directory"
        cp -r "$SCRIPT_DIR/../scripts/"*.sh "$SCRIPT_DIR/scripts/" 2>/dev/null || true
    fi
    
    # Make all scripts executable
    chmod +x "$SCRIPT_DIR/scripts/"*.sh 2>/dev/null || true
    
    # Create .claude directory
    mkdir -p "$SCRIPT_DIR/.claude"
    touch "$SCRIPT_DIR/.claude/.gitkeep"
    
    echo -e "${GREEN}Scripts ready in: $SCRIPT_DIR/scripts/${NC}"
}

# Function to test setup
test_setup() {
    echo ""
    echo -e "${BOLD}Testing Setup...${NC}"
    
    # Source the generated config
    source "$SCRIPT_DIR/scripts/common-config.sh"
    
    # Test API access
    echo -n "Testing GitHub API access... "
    local user_data=$(rest_api_call "GET" "/user" 2>&1)
    
    if echo "$user_data" | jq -e '.login' >/dev/null 2>&1; then
        local username=$(echo "$user_data" | jq -r '.login')
        echo -e "${GREEN}✓ Authenticated as @$username${NC}"
    else
        echo -e "${RED}✗ Authentication failed${NC}"
        echo "Error: $user_data"
        exit 1
    fi
    
    # Test repository access
    echo -n "Testing repository access... "
    local repo_data=$(rest_api_call "GET" "/repos/$REPO" 2>&1)
    
    if echo "$repo_data" | jq -e '.full_name' >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Can access $REPO${NC}"
    else
        echo -e "${RED}✗ Cannot access repository${NC}"
        echo "Error: $repo_data"
        exit 1
    fi
    
    echo ""
    echo -e "${GREEN}${BOLD}Setup Complete!${NC}"
}

# Main execution
main() {
    if [ "$DISCOVER_ONLY" = true ]; then
        # Just run discovery
        check_dependencies
        
        # Get minimal info for discovery
        echo -n "Enter repository (owner/repo): "
        read -r REPO
        
        echo -n "Enter GitHub token: "
        read -rs token
        echo ""
        export GITHUB_TOKEN="$token"
        TOKEN_METHOD="env"
        TOKEN_ENV_VAR="GITHUB_TOKEN"
        
        discover_project_board
        
        echo ""
        echo -e "${YELLOW}Discovery complete. Copy these IDs to your configuration.${NC}"
        exit 0
    fi
    
    # Full setup
    check_dependencies
    
    if [ ! -f "$SCRIPT_DIR/scripts/common-config.sh" ]; then
        setup_github_token
        get_repository_info
        discover_project_board
        generate_config
        copy_scripts
        test_setup
        
        echo ""
        echo "Next steps:"
        echo "  1. Review the configuration in scripts/common-config.sh"
        echo "  2. Test with: ./scripts/audit_open_issues.sh"
        echo "  3. Read WORKFLOW_GUIDE.md for usage instructions"
    else
        echo -e "${YELLOW}Configuration already exists at scripts/common-config.sh${NC}"
        echo -n "Reconfigure? [y/N]: "
        read -r reconfigure
        
        if [[ "$reconfigure" == "y" || "$reconfigure" == "Y" ]]; then
            setup_github_token
            get_repository_info
            discover_project_board
            generate_config
            test_setup
        else
            echo "Setup cancelled."
            exit 0
        fi
    fi
}

# Run main function
main "$@"
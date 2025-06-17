# GitHub Workflow Manager - Installation Guide

This package provides a complete GitHub issue and project board workflow management system that can be integrated into any development project.

## Prerequisites

### Required System Tools
- **bash** (v4.0+) - Shell scripting environment
- **git** - Version control system
- **curl** - HTTP client for API calls
- **jq** - JSON processor for parsing API responses

### Optional Tools
- **gcloud** - Google Cloud SDK (only if using Google Secret Manager for token storage)
- **gh** - GitHub CLI (not required, scripts use direct API calls)

### Installation Check
Run this command to verify prerequisites:
```bash
which bash git curl jq || echo "Missing required tools"
```

## Quick Start

1. **Extract the package** to your project root:
   ```bash
   unzip github-workflow-manager.zip -d .
   cd github-workflow-manager
   ```

2. **Run the setup script**:
   ```bash
   ./setup-workflow.sh
   ```
   This will guide you through:
   - Dependency verification
   - GitHub token configuration
   - Project board discovery
   - Configuration file generation

3. **Test the installation**:
   ```bash
   ./scripts/audit_open_issues.sh
   ```

## Manual Setup

If you prefer manual configuration:

### 1. GitHub Personal Access Token

Create a token with these scopes:
- `repo` - Full control of private repositories
- `project` - Full control of projects (classic and beta)

**Creating the token:**
1. Go to GitHub → Settings → Developer settings → Personal access tokens
2. Click "Generate new token (classic)"
3. Select scopes: `repo` and `project`
4. Generate and save the token securely

### 2. Configure Token Access

Choose one of these methods:

**Option A: Environment Variable (Simplest)**
```bash
export GITHUB_TOKEN="your-token-here"
```

**Option B: File-based (More Secure)**
```bash
echo "your-token-here" > ~/.github-token
chmod 600 ~/.github-token
```

**Option C: Google Secret Manager (Most Secure)**
```bash
gcloud secrets create github-workflow-token --data-file=- <<< "your-token-here"
```

### 3. Configure the Scripts

1. Copy the template configuration:
   ```bash
   cp config.template.sh scripts/common-config.sh
   ```

2. Edit `scripts/common-config.sh`:
   ```bash
   # Repository settings
   export REPO="owner/repository"  # e.g., "facebook/react"
   
   # Token access method (choose one)
   export TOKEN_METHOD="env"  # Options: env, file, gcloud
   export TOKEN_ENV_VAR="GITHUB_TOKEN"  # If using env method
   export TOKEN_FILE="$HOME/.github-token"  # If using file method
   export TOKEN_SECRET="github-workflow-token"  # If using gcloud method
   ```

### 4. Discover Project Board IDs

Run the discovery script:
```bash
./setup-workflow.sh --discover-only
```

This will:
- List all project boards in your repository
- Show field IDs (Status, Priority, Size, etc.)
- Display option IDs for each field

Copy the IDs into your `scripts/common-config.sh`.

## Integration with Your Project

### For iOS Development
1. Place the `github-workflow-manager` folder in your iOS project root
2. Add to `.gitignore`:
   ```
   github-workflow-manager/scripts/common-config.sh
   github-workflow-manager/.claude/
   ```
3. Use from Terminal or integrate with Xcode build phases

### For Other Projects
1. Copy scripts to a `scripts/` or `.github/scripts/` directory
2. Ensure scripts are executable: `chmod +x scripts/*.sh`
3. Add configuration to your project's setup documentation

## Environment-Specific Configuration

### Project Board Setup
Each project needs a GitHub Project (v2) board with these fields:

**Required Fields:**
- Status (Single select): Backlog, Ready, In progress, In review, Done
- Priority (Single select): P0, P1, P2
- Size (Single select): XS, S, M, L, XL
- Estimate (Number): Hours estimation

**Creating the Board:**
1. Go to your repository → Projects → New project
2. Select "Team planning" template (or create custom)
3. Add custom fields as needed
4. Run `./setup-workflow.sh --discover-only` to get field IDs

### Branch Strategy
The workflow uses a shared `wip` (work-in-progress) branch:
- All development happens on `wip`
- Commits reference issues: `[#123] Description`
- Periodic merges to main/master
- No feature branches needed

## Testing Your Setup

1. **Create a test issue:**
   ```bash
   ./scripts/create_github_issue.sh "Test Issue" "Testing workflow setup" "test" "P2" "S"
   ```

2. **Check project board integration:**
   ```bash
   ./scripts/audit_open_issues.sh
   ```

3. **Start work on the issue:**
   ```bash
   ./scripts/claude-work.sh start [issue-number]
   ```

## Troubleshooting

### Common Issues

**"Permission denied" errors**
```bash
chmod +x scripts/*.sh setup-workflow.sh
```

**"Bad credentials" error**
- Verify token has correct scopes
- Check token hasn't expired
- Ensure token is properly configured

**"Project not found" error**
- Ensure project board exists
- Verify PROJECT_ID in configuration
- Run discovery script to update IDs

**"jq: command not found"**
- macOS: `brew install jq`
- Ubuntu/Debian: `sudo apt-get install jq`
- Other: See https://stedolan.github.io/jq/download/

### Debug Mode
Enable debug output:
```bash
export DEBUG=1
./scripts/audit_open_issues.sh
```

## Security Considerations

1. **Never commit tokens** to version control
2. **Use environment variables** or secret managers in CI/CD
3. **Rotate tokens** periodically
4. **Limit token scopes** to minimum required
5. **Use read-only tokens** where possible

## Next Steps

1. Read `WORKFLOW_GUIDE.md` for usage instructions
2. Customize scripts for your team's workflow
3. Set up aliases for common operations:
   ```bash
   alias gi-create="./scripts/create_github_issue.sh"
   alias gi-work="./scripts/claude-work.sh"
   alias gi-status="./scripts/audit_open_issues.sh"
   ```

## Support

For issues or improvements:
1. Check existing scripts for examples
2. Modify `common-config.sh` for customization
3. Extend scripts as needed for your workflow

Remember: These scripts are designed to be modified. Adapt them to fit your team's specific needs!
# GitHub Workflow Manager - Usage Guide

This guide explains how to use the GitHub workflow management system for efficient development with issue tracking and project board integration.

## Core Workflow

### 1. Creating Issues

Create new issues with automatic project board integration:

```bash
./scripts/create_github_issue.sh "Title" "Body" "label1,label2" "P2" "M"
```

**Parameters:**
- **Title**: Issue title (required)
- **Body**: Detailed description (required)
- **Labels**: Comma-separated list (optional)
- **Priority**: P0 (urgent), P1 (high), P2 (normal) - default: P2
- **Size**: XS, S, M, L, XL - default: M

**Size Guidelines:**
- **XS** (1 hour): Tiny changes, typos, config updates
- **S** (2 hours): Small bug fixes, minor features
- **M** (4 hours): Standard features, moderate refactoring
- **L** (8 hours): Large features, significant changes
- **XL** (16 hours): Major features, architectural changes

**Example:**
```bash
./scripts/create_github_issue.sh \
  "Add user authentication" \
  "Implement JWT-based authentication with refresh tokens" \
  "enhancement,backend" \
  "P1" \
  "L"
```

### 2. Working on Issues

The workflow uses a shared `wip` branch for all development:

#### Start Work
```bash
./scripts/claude-work.sh start 123
```
This will:
- Check issue is in "Ready" status
- Create/switch to `wip` branch
- Update status to "In progress"
- Create/update shared PR
- Initialize work session tracking

#### Continue Work
```bash
./scripts/claude-work.sh continue 123
```
Use this to:
- Resume after breaks
- Check recent comments
- Update file tracking
- See work history

#### Committing Changes
Always reference the issue number:
```bash
git add src/auth.js
git commit -m "[#123] Add JWT validation logic"
```

#### Mark for Review
```bash
./scripts/claude-work.sh review 123
```
This will:
- Post work summary to issue
- Update status to "In review"
- List all files modified
- Request testing feedback

#### Complete Work
```bash
./scripts/claude-work.sh done 123
```
Updates status to "Done" and archives the work session.

### 3. Monitoring and Auditing

#### Check All Open Issues
```bash
./scripts/audit_open_issues.sh
```
Shows:
- All open issues with status
- Priority and size estimates
- File references in descriptions
- Linked pull requests
- Summary statistics

#### Check Pull Requests
```bash
./scripts/audit_open_prs.sh
```
Displays:
- Review status
- CI/CD check results
- Merge conflicts
- Required actions

#### Monitor Specific Issue
```bash
./scripts/monitor-issue-status.sh 123
```
Useful for:
- Watching for status changes
- Getting alerts when moved back to "In progress"
- Terminal notifications

### 4. Communication

#### Check Recent Comments
```bash
./scripts/check-issue-comments.sh 123 10
```
Shows last 10 comments (default: 5)

#### Add Comment
```bash
./scripts/add-issue-comment.sh 123 "Completed initial implementation, ready for review"
```

## Best Practices

### 1. Issue Creation
- **Be specific** in titles and descriptions
- **Include context**: What problem does this solve?
- **Add acceptance criteria** in the description
- **Reference related issues**: Use #123 format
- **Attach mockups/screenshots** when relevant

### 2. Development Flow
- **One issue at a time**: Avoid context switching
- **Commit frequently**: Small, focused commits
- **Reference issues**: Every commit should have [#123]
- **Update regularly**: Use `continue` action daily
- **Clean up**: Mark issues done promptly

### 3. Communication Protocol
- **Status updates**: Post progress in issue comments
- **Blockers**: Immediately comment on blockers
- **Questions**: Use @mentions for specific people
- **Handoffs**: Provide clear next steps

### 4. Branch Management
- **Shared wip branch**: All work happens here
- **No feature branches**: Simplifies collaboration
- **Regular syncs**: Pull latest changes often
- **Batch merges**: Merge to main periodically

## Multi-Agent Coordination

When multiple developers work simultaneously:

### Setup
1. Each developer clones the repository
2. Everyone uses the same `wip` branch
3. Configure individual work directories

### Coordination Rules
1. **Claim issues** by starting work (updates status)
2. **Avoid conflicts** by working on different files
3. **Communicate** through issue comments
4. **Sync regularly** with `git pull origin wip`

### Example Multi-Agent Flow
```bash
# Agent 1
./scripts/claude-work.sh start 123
git add frontend/
git commit -m "[#123] Update UI components"
git push origin wip

# Agent 2 (different issue)
git pull origin wip
./scripts/claude-work.sh start 124
git add backend/
git commit -m "[#124] Add API endpoint"
git push origin wip
```

## Advanced Usage

### 1. Custom Workflows

Extend the scripts for your needs:

```bash
# Create custom wrapper
cat > my-workflow.sh << 'EOF'
#!/bin/bash
ISSUE=$1
./scripts/claude-work.sh start $ISSUE
echo "Running linter..."
npm run lint
echo "Running tests..."
npm test
./scripts/claude-work.sh review $ISSUE
EOF
chmod +x my-workflow.sh
```

### 2. Automation

Integrate with CI/CD:

```yaml
# .github/workflows/issue-update.yml
on:
  pull_request:
    types: [opened, synchronize]
jobs:
  update-issues:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Update linked issues
        run: |
          # Extract issue numbers from PR
          ISSUES=$(echo "${{ github.event.pull_request.body }}" | grep -oE '#[0-9]+')
          for issue in $ISSUES; do
            ./scripts/add-issue-comment.sh ${issue#'#'} "PR updated: ${{ github.event.pull_request.html_url }}"
          done
```

### 3. Reporting

Generate weekly reports:

```bash
# List issues completed this week
./scripts/audit_open_issues.sh | grep "Done" > weekly-completed.txt

# Active development
./scripts/audit_open_issues.sh | grep "In progress" > active-work.txt
```

## Troubleshooting

### Common Issues

**"Issue not in correct status"**
- Check project board status
- Use `issue-status.sh` to update
- Ensure proper permissions

**"Merge conflicts on wip"**
```bash
git pull origin wip --rebase
# Resolve conflicts
git add .
git rebase --continue
git push origin wip --force-with-lease
```

**"Can't find project board"**
- Verify PROJECT_ID in config
- Run setup script to rediscover
- Check repository permissions

### Debug Commands

```bash
# Check issue details
curl -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/OWNER/REPO/issues/123

# Verify project board
./setup-workflow.sh --discover-only

# Test token permissions
curl -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/user
```

## Quick Reference

### Essential Commands
```bash
# Create issue
./scripts/create_github_issue.sh "Title" "Body" "" "P2" "M"

# Start work
./scripts/claude-work.sh start 123

# Commit with reference
git commit -m "[#123] Description"

# Check status
./scripts/audit_open_issues.sh

# Add comment
./scripts/add-issue-comment.sh 123 "Update"

# Complete work
./scripts/claude-work.sh review 123
./scripts/claude-work.sh done 123
```

### Status Flow
```
Backlog → Ready → In progress → In review → Done
```

### File Locations
- Work state: `.claude/issue-{number}.json`
- Configuration: `scripts/common-config.sh`
- Scripts: `scripts/*.sh`

Remember: The workflow is designed to be simple and consistent. When in doubt, check issue status and comments for context!
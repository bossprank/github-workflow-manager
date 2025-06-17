# Claude Code Integration Guide

This document provides specific guidance for using the GitHub Workflow Manager with Claude Code or other LLM assistants.

## Communication Protocol

When working with Claude Code or similar AI assistants, establish clear communication patterns:

### Addressing the Project Owner
- When asking questions or seeking clarification, always refer to the project owner as "boss"
- Examples:
  - "Boss, should I add error handling for this case?"
  - "Boss, which approach would you prefer?"
  - "Boss, I found an issue with X, how should I proceed?"

### Status Updates
The workflow scripts automatically post updates to issues, but you should also:
- Use issue comments for significant progress updates
- Ask clarifying questions in issue comments
- Document decisions and rationale

## LLM-Specific Best Practices

### 1. Work Session Management
- **Always use the workflow scripts** - they track state across sessions
- **Start each session** with `claude-work.sh continue` to see context
- **Commit frequently** with descriptive messages referencing issues

### 2. Context Preservation
The `.claude/` directory stores work state between sessions:
```json
{
  "issue_number": "123",
  "title": "Add authentication",
  "branch": "wip",
  "pr_number": "456",
  "status": "in-progress",
  "started_at": "2024-01-01T00:00:00Z",
  "work_log": [...],
  "files_modified": [...],
  "next_steps": [...]
}
```

### 3. Multi-Agent Coordination
When multiple Claude instances work on the same project:
- Each agent claims issues by starting work (updates status)
- Commits are tagged with issue numbers for attribution
- The shared `wip` branch prevents merge conflicts
- Regular `git pull` keeps agents synchronized

### 4. Handling Interruptions
If a session is interrupted:
1. The work state is preserved in `.claude/issue-{number}.json`
2. Use `claude-work.sh continue {number}` to resume
3. Check recent comments for any updates
4. Review the work log to understand progress

## Integration with Development Commands

### For Python Projects
Combine with your existing development commands:
```bash
# In your CLAUDE.md or project instructions
./scripts/claude-work.sh start 123
./devserver.sh  # Your existing dev server
python -m pytest tests/
./scripts/claude-work.sh review 123
```

### For iOS Projects
```bash
./scripts/claude-work.sh start 123
xcodebuild test -scheme YourApp
./scripts/claude-work.sh review 123
```

### Custom Integration
Create wrapper scripts that combine workflow management with your build process:

```bash
#!/bin/bash
# work-on-issue.sh
ISSUE=$1
./scripts/claude-work.sh start $ISSUE

# Your project-specific setup
source .venv/bin/activate
npm install

echo "Ready to work on issue #$ISSUE"
echo "Remember to commit with: git commit -m '[#$ISSUE] Description'"
```

## Prompt Engineering Tips

When instructing Claude Code or other LLMs:

### Clear Task Definition
```
Please work on issue #123. Use the workflow scripts to:
1. Start work: ./scripts/claude-work.sh start 123
2. Make the necessary code changes
3. Commit with [#123] prefix
4. Mark for review when complete
```

### Context Requests
```
Before starting, please:
1. Run ./scripts/audit_open_issues.sh to see all tasks
2. Check comments: ./scripts/check-issue-comments.sh 123
3. Review the current PR status
```

### Handoff Instructions
```
I'm finishing work on issue #123. Please:
1. Continue with: ./scripts/claude-work.sh continue 123
2. Check the work log for what's been done
3. Complete the remaining tasks listed in next_steps
```

## Troubleshooting

### "Previous session state not found"
- Check `.claude/` directory for state files
- Use `audit_open_issues.sh` to find issue status
- Start fresh with `claude-work.sh start`

### "Token not configured"
- Run `./setup-workflow.sh` to reconfigure
- Check environment variables are set
- Verify token has correct GitHub scopes

### "Issue not in correct status"
- Use `./scripts/issue-status.sh {number} ready` to update
- Check project board on GitHub
- Ensure you have project write permissions

## Important Reminders

1. **Never commit the token** or `common-config.sh`
2. **Always use issue references** in commits: `[#123]`
3. **Update status accurately** - it helps coordination
4. **Check for updates** before starting work
5. **Document decisions** in issue comments

This workflow system is designed to maintain context and coordination across multiple work sessions and agents. Use it consistently for best results!
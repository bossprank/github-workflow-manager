# GitHub Workflow Manager

A portable GitHub issue and project board workflow management system designed for efficient development with Claude Code or any LLM-assisted development environment.

## Features

- **Complete Issue Lifecycle Management**: Create, track, and manage GitHub issues with project board integration
- **Shared Branch Workflow**: All development on a single `wip` branch with issue-tagged commits
- **Project Board Integration**: Automatic status updates, priority/size tracking, and time estimates
- **Multi-Agent Support**: Multiple developers/LLMs can work simultaneously without conflicts
- **Persistent Work Sessions**: Track work progress across sessions with state management
- **Rich CLI Interface**: Color-coded output, progress tracking, and interactive prompts

## Quick Start

1. **Extract and setup**:
   ```bash
   unzip github-workflow-manager.zip
   cd github-workflow-manager
   chmod +x setup-workflow.sh
   ./setup-workflow.sh
   ```

2. **Create your first issue**:
   ```bash
   ./scripts/create_github_issue.sh "Setup project" "Initial configuration" "" "P2" "S"
   ```

3. **Start working**:
   ```bash
   ./scripts/claude-work.sh start 1
   ```

## What's Included

- **12 Workflow Scripts**: Complete suite for issue management
- **Automated Setup**: Interactive configuration wizard
- **Comprehensive Documentation**: Installation and workflow guides
- **Configuration Templates**: Easy customization for any project
- **State Management**: Persistent work tracking in `.claude/` directory

## Use Cases

- **iOS Development**: Integrate with Xcode projects
- **Web Development**: Manage frontend/backend tasks
- **AI-Assisted Coding**: Perfect for Claude Code or GitHub Copilot workflows
- **Team Collaboration**: Coordinate multiple developers on shared branches

## Requirements

- Bash 4.0+
- Git, curl, jq
- GitHub account with personal access token
- GitHub Project (v2) board

## Documentation

- `INSTALLATION.md` - Detailed setup instructions
- `WORKFLOW_GUIDE.md` - Usage patterns and best practices
- `scripts/README.md` - Individual script documentation

## License

This workflow management system is provided as-is for use in your projects. Feel free to modify and extend as needed.
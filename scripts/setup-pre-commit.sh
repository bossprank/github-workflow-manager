#!/bin/bash

# Script to set up pre-commit hooks for the project

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Setting up pre-commit hooks..."

# Check if pre-commit is installed
if ! command -v pre-commit &> /dev/null; then
    echo -e "${YELLOW}pre-commit not found. Installing...${NC}"
    pip install pre-commit
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to install pre-commit${NC}"
        exit 1
    fi
fi

# Install pre-commit hooks
echo -n "Installing pre-commit hooks... "
pre-commit install
if [ $? -eq 0 ]; then
    echo -e "${GREEN}done${NC}"
else
    echo -e "${RED}failed${NC}"
    exit 1
fi

# Run pre-commit on all files to check current state
echo ""
echo "Running pre-commit on all files to check current state..."
pre-commit run --all-files

echo ""
echo -e "${GREEN}Pre-commit hooks are now installed!${NC}"
echo "The hooks will run automatically on git commit."
echo ""
echo "To run manually:"
echo "  pre-commit run                # on staged files"
echo "  pre-commit run --all-files    # on all files"
echo ""
echo "To skip hooks temporarily:"
echo "  git commit --no-verify"
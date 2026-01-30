#!/usr/bin/env bash

# Sync downstream changes to upstream
# This script rebases the upstream-public branch onto main,
# ensuring private assets remain excluded

# ============================================
# CONFIGURATION: Files/directories to exclude from upstream
# ============================================
PRIVATE_FILES=(
    "private-asset.txt"
    "POC-SUMMARY.md"
    "integration/"
    # Add more private files here:
    # "integration-tests/"
    # "platform/assets/aap-logo.svg"
)

set -e  # Exit on error

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}==> Starting upstream sync...${NC}"

# Save current branch
ORIGINAL_BRANCH=$(git branch --show-current)

# Ensure we're on a clean working tree
if [[ -n $(git status --porcelain) ]]; then
    echo -e "${RED}✗ Working directory is not clean. Commit or stash changes first.${NC}"
    exit 1
fi

echo -e "${YELLOW}==> Fetching latest changes...${NC}"
git fetch origin
git fetch upstream

# Check if upstream has new commits that aren't in downstream main yet
# (e.g., from merged PRs that need to be integrated)
# Use cherry to check by content, not SHA (handles cherry-picks)
# Exclude merge commits (--no-merges) since we cherry-pick actual changes
UPSTREAM_NEW_COMMITS=$(git log main..upstream/main --oneline --cherry-pick --right-only --no-merges 2>/dev/null | wc -l | tr -d ' ')

if [[ "$UPSTREAM_NEW_COMMITS" -gt 0 ]]; then
    echo -e "${YELLOW}⚠ Upstream has $UPSTREAM_NEW_COMMITS new commit(s) not in downstream main.${NC}"
    echo ""
    echo "These commits need to be integrated into downstream main first:"
    git log main..upstream/main --oneline --cherry-pick --right-only --no-merges
    echo ""
    echo -e "${YELLOW}Recommended workflow:${NC}"
    echo "  1. Create a branch: git checkout -b sync-from-upstream"
    echo "  2. Cherry-pick or merge: git cherry-pick <commit> (or git merge upstream/main)"
    echo "  3. Push and create PR: git push origin sync-from-upstream"
    echo "  4. Run CI tests (including downstream integration tests)"
    echo "  5. After PR merges, run this script again"
    echo ""
    echo "Aborting. Please sync upstream changes to main first."
    exit 1
fi

echo -e "${YELLOW}==> Checking out upstream-public branch...${NC}"
git checkout upstream-public

echo -e "${YELLOW}==> Rebasing upstream-public onto main...${NC}"
if git rebase main; then
    echo -e "${GREEN}✓ Rebase successful${NC}"
else
    echo -e "${YELLOW}⚠ Rebase has conflicts. Checking if auto-resolvable...${NC}"
    
    # Get list of conflicted files
    CONFLICTS=$(git diff --name-only --diff-filter=U 2>/dev/null || true)
    
    if [[ -z "$CONFLICTS" ]]; then
        echo -e "${RED}✗ Rebase failed but no conflicts detected. Manual intervention required.${NC}"
        git rebase --abort
        exit 1
    fi
    
    # Check if conflicts are only private files
    AUTO_RESOLVED=false
    for conflict in $CONFLICTS; do
        IS_PRIVATE=false
        for private_file in "${PRIVATE_FILES[@]}"; do
            if [[ "$conflict" == "$private_file" ]] || [[ "$conflict" == $private_file ]]; then
                IS_PRIVATE=true
                break
            fi
        done
        
        if [[ "$IS_PRIVATE" == "false" ]]; then
            echo -e "${RED}✗ Unexpected conflict in: $conflict${NC}"
            echo -e "${RED}This is not a known private file. Please resolve manually:${NC}"
            echo "  1. Fix conflicts"
            echo "  2. git add/rm conflicted files"
            echo "  3. git rebase --continue"
            echo "  4. Re-run this script"
            exit 1
        fi
    done
    
    # All conflicts are private files - auto-resolve by removing them
    echo -e "${YELLOW}==> Auto-resolving conflicts (removing private files)...${NC}"
    for private_file in "${PRIVATE_FILES[@]}"; do
        git rm "$private_file" 2>/dev/null || true
    done
    
    # Check if all conflicts are resolved
    REMAINING_CONFLICTS=$(git diff --name-only --diff-filter=U 2>/dev/null || true)
    if [[ -n "$REMAINING_CONFLICTS" ]]; then
        echo -e "${RED}✗ Some conflicts remain after auto-resolution:${NC}"
        echo "$REMAINING_CONFLICTS"
        echo "Please resolve manually and run 'git rebase --continue'"
        exit 1
    fi
    
    # Continue rebase
    if GIT_EDITOR=true git rebase --continue; then
        echo -e "${GREEN}✓ Conflicts auto-resolved${NC}"
    else
        echo -e "${RED}✗ Failed to continue rebase after conflict resolution${NC}"
        exit 1
    fi
fi

echo -e "${YELLOW}==> Pushing to upstream...${NC}"
if git push upstream upstream-public:main --force-with-lease; then
    echo -e "${GREEN}✓ Successfully synced to upstream!${NC}"
else
    echo -e "${RED}✗ Push failed. Check remote configuration.${NC}"
    exit 1
fi

echo -e "${YELLOW}==> Returning to original branch...${NC}"
git checkout "$ORIGINAL_BRANCH"

echo -e "${GREEN}==> Sync complete!${NC}"
echo ""
echo "Upstream status:"
git log upstream-public --oneline -3

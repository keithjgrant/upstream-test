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

echo -e "${YELLOW}==> Checking out upstream-public branch...${NC}"
git checkout upstream-public
    
    # Get list of conflicted files
    CONFLICTS=$(git diff --name-only --diff-filter=U 2>/dev/null || true)
    
    if [[ -z "$CONFLICTS" ]]; then
        echo -e "${RED}✗ Rebase failed but no conflicts detected. Manual intervention required.${NC}"
        git rebase --abort
        exit 1
    fi
    
    # Check if conflicts are only private files or upstream-modified files
    ALL_AUTO_RESOLVABLE=true
    for conflict in $CONFLICTS; do
        IS_PRIVATE=false
        for private_file in "${PRIVATE_FILES[@]}"; do
            if [[ "$conflict" == "$private_file" ]] || [[ "$conflict" == $private_file ]]; then
                IS_PRIVATE=true
                break
            fi
        done
        
        # Check if conflict exists in upstream (indicates upstream PR changes)
        IS_IN_UPSTREAM=false
        if git ls-tree -r upstream/main --name-only | grep -q "^$conflict$"; then
            IS_IN_UPSTREAM=true
        fi
        
        if [[ "$IS_PRIVATE" == "false" ]] && [[ "$IS_IN_UPSTREAM" == "false" ]]; then
            echo -e "${RED}✗ Unexpected conflict in: $conflict${NC}"
            echo -e "${RED}This is not a known private file or upstream change.${NC}"
            echo "Please resolve manually:"
            echo "  1. Fix conflicts"
            echo "  2. git add/rm conflicted files"
            echo "  3. git rebase --continue"
            echo "  4. Re-run this script"
            ALL_AUTO_RESOLVABLE=false
        fi
    done
    
    if [[ "$ALL_AUTO_RESOLVABLE" == "false" ]]; then
        git rebase --abort
        exit 1
    fi
    
    # Check if any conflicts are from upstream changes
    HAS_UPSTREAM_CONFLICTS=false
    for conflict in $CONFLICTS; do
        if git ls-tree -r upstream/main --name-only | grep -q "^$conflict$"; then
            IS_PRIVATE=false
            for private_file in "${PRIVATE_FILES[@]}"; do
                if [[ "$conflict" == "$private_file" ]]; then
                    IS_PRIVATE=true
                    break
                fi
            done
            if [[ "$IS_PRIVATE" == "false" ]]; then
                HAS_UPSTREAM_CONFLICTS=true
                break
            fi
        fi
    done
    
    if [[ "$HAS_UPSTREAM_CONFLICTS" == "true" ]]; then
        echo -e "${YELLOW}⚠ Conflicts detected in files modified by upstream PRs.${NC}"
        echo ""
        echo -e "${YELLOW}Recommended: Integrate upstream changes first via PR:${NC}"
        echo "  1. git rebase --abort"
        echo "  2. git checkout main"
        echo "  3. git checkout -b sync-from-upstream"
        echo "  4. git cherry-pick <upstream-commits>"
        echo "  5. Create PR and run CI tests"
        echo "  6. After PR merges, re-run this script"
        echo ""
        read -p "Continue with auto-resolution anyway? (yes/no): " continue_confirm
        
        if [[ "$continue_confirm" != "yes" ]]; then
            git rebase --abort
            echo "Aborted. Please integrate upstream changes via PR first."
            exit 1
        fi
    fi
    
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

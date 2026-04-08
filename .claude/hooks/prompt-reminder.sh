#!/bin/bash
# =============================================================================
# UserPromptSubmit Hook: Inject critical rules reminder on every prompt
#
# Prevents Claude from skipping rules in favor of task completion speed.
#
# chmod +x .claude/hooks/prompt-reminder.sh
# =============================================================================

cat <<'REMINDER'
--- CRITICAL RULES REMINDER (hook-injected, do not skip) ---
* DB operations: run `grep "^DATABASE_URL" .env` before every DB operation (no exceptions)
* New work: always create a Worktree (do not switch branches in main workspace)
* Commits: include Background/Changes/Affected-files in commit body (required)
* git push / PR creation: always get user confirmation first
* Production DB operations: present plan, impact, rollback -> get explicit approval
---
REMINDER

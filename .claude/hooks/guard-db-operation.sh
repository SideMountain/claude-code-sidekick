#!/bin/bash
# =============================================================================
# PreToolUse Hook (Bash): Detect DB connection target and warn accordingly
#
# Detects prisma/script commands that interact with the database, reads
# DATABASE_URL from .env or inline env vars, and displays environment-aware
# warnings.
#
# Pattern matching for STG/PRD is read from CLAUDE.md Project Configuration
# (SIDEKICK_STG_DB_PATTERN / SIDEKICK_PRD_DB_PATTERN env override — see
# hook-helpers.sh get_db_pattern):
#   - STG_DB_PATTERN: substring to identify staging DB (e.g., "ep-bitter-salad")
#   - PRD_DB_PATTERN: substring to identify production DB (e.g., "ep-weathered-mode")
#   - If neither pattern is set, the hook skips environment detection
#
# This hook BLOCKS production DB operations (deny) when PRD_DB_PATTERN is set.
# STG and unknown connections show context only (allow).
#
# Output: JSON (hookSpecificOutput) to stdout, human-readable to stderr
#
# chmod +x .claude/hooks/guard-db-operation.sh
# =============================================================================

source "$(dirname "$0")/hook-helpers.sh"

INPUT=$(cat)

if command -v jq &>/dev/null; then
  COMMAND=$(printf '%s\n' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
  CWD=$(printf '%s\n' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
else
  COMMAND=$(printf '%s\n' "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//')
  CWD=""
fi

# Fallback: if jq failed (COMMAND is empty but INPUT exists), use grep
if [ -z "$COMMAND" ] && [ -n "$INPUT" ]; then
  COMMAND=$(printf '%s\n' "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

# --- Configuration: STG/PRD identification substrings ---
# Read from CLAUDE.md Project Configuration (SIDEKICK_STG_DB_PATTERN /
# SIDEKICK_PRD_DB_PATTERN env override; empty = fail-open). See hook-helpers.sh.
CLAUDE_MD="$(dirname "$0")/../../CLAUDE.md"
STG_DB_PATTERN=$(get_db_pattern "$CLAUDE_MD" STG_DB_PATTERN)
PRD_DB_PATTERN=$(get_db_pattern "$CLAUDE_MD" PRD_DB_PATTERN)

# Check if this is a DB-related command
IS_DB_CMD=false
if printf '%s\n' "$COMMAND" | grep -qiE 'prisma\s+(migrate|studio|db)'; then IS_DB_CMD=true; fi
if printf '%s\n' "$COMMAND" | grep -qiE 'npx\s+tsx.*scripts/|node.*scripts/'; then IS_DB_CMD=true; fi

if [ "$IS_DB_CMD" = false ]; then allow_silent; fi

# --- Detect inline DATABASE_URL= override in command ---
INLINE_DB_URL=""
if printf '%s\n' "$COMMAND" | grep -qE 'DATABASE_URL='; then
  INLINE_DB_URL=$(printf '%s\n' "$COMMAND" | grep -oE 'DATABASE_URL="[^"]*"' | head -1 | sed 's/DATABASE_URL="//;s/"$//')
  if [ -z "$INLINE_DB_URL" ]; then
    INLINE_DB_URL=$(printf '%s\n' "$COMMAND" | grep -oE "DATABASE_URL='[^']*'" | head -1 | sed "s/DATABASE_URL='//;s/'$//")
  fi
fi

# Determine connection target (inline override takes priority, then .env)
if [ -n "$INLINE_DB_URL" ]; then
  DB_URL="$INLINE_DB_URL"
  SOURCE="inline env var override"
else
  ENV_FILE="${CWD:-.}/.env"
  DB_URL=$(grep "^DATABASE_URL" "$ENV_FILE" 2>/dev/null | head -1 | sed 's/^DATABASE_URL=//;s/^"//;s/"$//')
  SOURCE=".env"
fi

# --- Environment detection & warning ---
if [ -z "$DB_URL" ]; then
  allow_with_context "[DB Guard] WARNING: DATABASE_URL not found (${SOURCE}). Verify connection target."
elif [ -n "$PRD_DB_PATTERN" ] && printf '%s\n' "$DB_URL" | grep -q "$PRD_DB_PATTERN"; then
  deny "[DB Guard] PRODUCTION DB detected ($PRD_DB_PATTERN). Source: ${SOURCE}. Production DB operations require explicit approval."
elif [ -n "$STG_DB_PATTERN" ] && printf '%s\n' "$DB_URL" | grep -q "$STG_DB_PATTERN"; then
  allow_with_context "[DB Guard] Connection: STG DB ($STG_DB_PATTERN) -- ${SOURCE}"
elif [ -n "$STG_DB_PATTERN" ] || [ -n "$PRD_DB_PATTERN" ]; then
  allow_with_context "[DB Guard] WARNING: Unknown connection target (${SOURCE}). Verify DATABASE_URL."
else
  allow_with_context "[DB Guard] DB operation detected. Verify DATABASE_URL before proceeding."
fi
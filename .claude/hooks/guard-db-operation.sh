#!/bin/bash
# =============================================================================
# PreToolUse Hook (Bash): Detect DB connection target and warn accordingly
#
# Detects prisma/script commands that interact with the database, reads
# DATABASE_URL from .env or inline env vars, and displays environment-aware
# warnings.
#
# Pattern matching for STG/PRD is configurable:
#   - STG_DB_PATTERN: substring to identify staging DB (e.g., "ep-bitter-salad")
#   - PRD_DB_PATTERN: substring to identify production DB (e.g., "ep-weathered-mode")
#   - If neither pattern is set, the hook skips environment detection
#
# This hook does NOT block (always exit 0). It provides information for the
# user to make informed decisions via the permission dialog.
#
# chmod +x .claude/hooks/guard-db-operation.sh
# =============================================================================

INPUT=$(cat)

if command -v jq &>/dev/null; then
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')
  CWD=$(echo "$INPUT" | jq -r '.cwd // ""')
else
  COMMAND=$(echo "$INPUT" | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//;s/"$//')
  CWD=""
fi

# --- Configuration: Set these patterns for your project ---
# Leave empty to skip environment detection for that tier
STG_DB_PATTERN=""
PRD_DB_PATTERN=""

# Check if this is a DB-related command
IS_DB_CMD=false
if echo "$COMMAND" | grep -qiE 'prisma\s+(migrate|studio|db)'; then IS_DB_CMD=true; fi
if echo "$COMMAND" | grep -qiE 'npx\s+tsx.*scripts/|node.*scripts/'; then IS_DB_CMD=true; fi

if [ "$IS_DB_CMD" = false ]; then exit 0; fi

# --- Detect inline DATABASE_URL= override in command ---
INLINE_DB_URL=""
if echo "$COMMAND" | grep -qE 'DATABASE_URL='; then
  INLINE_DB_URL=$(echo "$COMMAND" | grep -oE 'DATABASE_URL="[^"]*"' | head -1 | sed 's/DATABASE_URL="//;s/"$//')
  if [ -z "$INLINE_DB_URL" ]; then
    INLINE_DB_URL=$(echo "$COMMAND" | grep -oE "DATABASE_URL='[^']*'" | head -1 | sed "s/DATABASE_URL='//;s/'$//")
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
  echo "WARNING: [DB Guard] DATABASE_URL not found (${SOURCE}). Verify connection target." >&2
elif [ -n "$PRD_DB_PATTERN" ] && echo "$DB_URL" | grep -q "$PRD_DB_PATTERN"; then
  echo "DANGER: [DB Guard] ===== PRODUCTION DB detected ($PRD_DB_PATTERN) =====" >&2
  echo "DANGER: [DB Guard] Source: ${SOURCE}" >&2
  echo "DANGER: [DB Guard] Production writes have user impact. Review carefully." >&2
elif [ -n "$STG_DB_PATTERN" ] && echo "$DB_URL" | grep -q "$STG_DB_PATTERN"; then
  echo "[DB Guard] Connection: STG DB ($STG_DB_PATTERN) -- ${SOURCE}" >&2
elif [ -n "$STG_DB_PATTERN" ] || [ -n "$PRD_DB_PATTERN" ]; then
  echo "WARNING: [DB Guard] Unknown connection target (${SOURCE}). Verify DATABASE_URL." >&2
else
  echo "[DB Guard] DB operation detected. Verify DATABASE_URL before proceeding." >&2
fi

exit 0

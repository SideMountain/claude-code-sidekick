# ccs lifecycle map

*The whole of ccs as a set of closed loops — not a pile of features.* This is the maintainer-facing
map: every capability, which lifecycle loop it sits on, and whether that loop is **closed** (its
output is consumed by a next step) or **open** (a stage has no tool, or an output has no consumer).
North star: an unused feature is worthless — features must form loops that run with no gaps and no waste.

JA: [lifecycle.ja.md](./lifecycle.ja.md) · Philosophy digest: [design.md](./design.md) · Decisions: [decisions/README.md](./decisions/README.md)

## Spine (the through-line)

- **North star (ADR-0018):** the downstream developer feels the benefit without feeling the harness.
  Default-safe; nothing to assemble; only **three verbs by hand** — `/news` → your work → `/close-chat`
  (plus weekly `/weekly-inventory`). Everything else is plumbing that fires on its own.
- **仕組み化 = 認知 → 強制 → 検知** (Awareness → Enforcement → Detection). Rules alone don't hold, so
  CLAUDE.md HARD/SOFT/GUIDE rules (re-asserted every turn by `prompt-reminder.sh`) are physically backed
  by PreToolUse guards + a `settings.json` deny list + a git-native PII pre-commit hook, and slips are
  caught by `/review` (deterministic fitness + official `/code-review` + REVIEW.md norms).
- **Knowledge compounding (the moat, ADR-0007/0016):** session feedback → auto-memory → `/close-chat`
  reflux flags → `/weekly-inventory` promotion → PJ brain → personal brain → OSS template → applied next
  session. AGENTS.md-style instruction sharing cannot carry this judgment layer.

## The loops

| # | Loop | Stage chain (feature at each stage) | Closed? |
|---|---|---|---|
| 1 | **Session** (daily, the 3 verbs) | `session-start.sh` (ff-pull + surface Active Work/staleness/critical/brain) → `/news` → work (worktree + guards) → `/review` → PR → `/close-chat` → weekly `/weekly-inventory` → back to `/news` | ✅ |
| 2 | **Knowledge compounding** | feedback → auto-memory `feedback_*.md` → `/close-chat` reflux flags → `/weekly-inventory` (3-item rule) → PJ brain → personal brain → OSS template → next session | ✅ |
| 3 | **Dev pipeline** | `/discover` (investigate + may file Issues) → `/record-decision` (ADR) → `/auto-implement` (`gh issue view` → worktree → impl+test → `/review` → PR) → `/review` → PR | ✅ |
| 4 | **Release → Adopt** | `/release` (`verify-release-notes.sh` gate → severity marker on GitHub Release; migration notes in `docs/migrations/`) → `/inventory` (downstream: version/severity gap) → `session-start.sh` surfaces critical flag → `/adopt-sidekick-update` (batched apply, bump `SIDEKICK_VERSION`, never overwrites personal brain) | ✅ |
| 5 | **Enforcement ×3** (認知→強制→検知) | worktree discipline (H9/H12 → `prompt-reminder` → `guard-bash`/`guard-protected-branch-edit` DENY) · PII (`pii-prevention` → `/review`/`/close-chat` scan → `githooks/pre-commit` block) · commit body (H15 → `guard-commit-message` block) | ✅ |
| 6 | **Reverse signal** (downstream → maintainer) | GitHub Issue (`.github/ISSUE_TEMPLATE/`) → `/inventory` Step 3 (`gh issue list`) → `/discover`/`/auto-implement` → `/release` | ✅ (reads one-way in README — doc gap, not a break) |
| 7 | **Stack-pack app build** (opt-in Next.js) | `STACK_PACK=nextjs` → `ARCHITECTURE.md` (認知) → `scaffold.js` (強制/generate) → `fitness-functions`/`test:arch` (検知) → `system-map` (visualize) | ⚠️ **open** — see below |
| 8 | **Upstream watch** (Claude Code official → ccs) | `official-freshness.sh` (in-repo floor-drift check → `gh issue create`, official-adoption label) + `news-upstream` (maintainer-only weekly read) → gap analysis → backlog → `/weekly-inventory` → ADR / skill / OSS-template | ⚠️ **partly closed** — see below |

## Open loops (where the wheel doesn't fully close)

- **7. Stack-pack re-run is gated on `/review`, not fully auto-wired.** No background hook / PostToolUse /
  `.github/workflows` runs `test:arch` or `system-map` on its own — the downstream PJ wires its own CI.
  Inside the loop, though, `/review` (user-invoked) runs the fitness fast-gate and a `system-map` drift
  nudge (canonical-counts `--drift`) when `STACK_PACK: nextjs` (v0.11.0), and the hard-layer adapters
  (route/authz/links/schema/indexes) ship and share the canonical `route-enumerator.js` with `fitness`.
  What stays open: map **regeneration** is on-demand (`/system-map`, intentionally not auto-regenerated),
  the soft **enrich** layer is LLM-at-runtime (not mechanized), and `uncertainties` (golden-path
  non-compliance) reach the user as a report rather than routing back into `fitness` / `ARCHITECTURE.md`.
  **Partly by design** (the downstream owns its CI; a map is a visualization, not a gate) — the honest
  statement is in the README stack-pack section.
- **8. Upstream watch is now partly closed inside the repo.** `official-freshness.sh` (weekly-inventory
  Step 5d, v0.13.0 / ADR-0027 決定4) mechanically detects drift between the running Claude Code CLI and the
  version floors ccs wraps, and files a `gh issue create` (official-adoption label) that rides the
  reverse-signal loop (6) back into `/discover` / `/auto-implement`. What stays manual **by design**:
  reading upstream release notes and the broader `news-upstream` watch run only on the maintainer's machine
  (`~/.claude/skills/`, ADR-0017/ADR-0006) — judging whether a new official feature matters, and spotting
  behavioral changes, cannot be mechanized. The in-repo `/news` still watches the *codebase*, not Claude
  Code upstream, so a reader of the distributed repo sees the floor-drift issue path but not the maintainer
  read — a one-line README note keeps that from looking like a missing stage.

## Maintainer-only vs distributed

| Surface | Status |
|---|---|
| `news-upstream` (upstream watch) | maintainer-only `~/.claude/skills/` (ADR-0017/0006) — not in this repo |
| `sync-oss` | retired (ADR-0006 single-repo consolidation) |
| OSS-template reflux | now a **same-repo** edit (post-ADR-0006), no longer a cross-repo PR |
| Judgment-log Notion sync (ADR-0012) | opt-in, default-off, write-only export sink (not a closed loop, by design) |

## Capability inventory

> Verified against `claude-code-sidekick` at main (2026-07-06, post-v0.14.0). **13 distributed core skills**
> + **1 opt-in stack-pack skill** (`system-map`, Next.js).

### Skills — session / lifecycle
| Skill | What | Trigger |
|---|---|---|
| `/setup` | Bootstrap new/overlay PJ; init personal brain; register ccs remote; opt-in Next.js pack; set `core.hooksPath` | user (one-time) |
| `/news` | ff-pull main + categorized change summary since last HEAD | user (verb ①) |
| `/inventory` | Cross-source roundup (Notion + `gh issue list` + Backlog) + version/severity check; writes critical flag | user |
| `/close-chat` | End-of-session capture: backlog + reflux flags + PII/CHANGELOG checks | user (verb ③) / `/auto-implement` |
| `/weekly-inventory` | Compaction: brain health, MEMORY tidy, feedback 3-item promotion, reflux processing, drift; `official-freshness.sh` (Step 5d: version-floor drift check of wrapped official features) | user (weekly) |

### Skills — dev pipeline & review
| Skill | What | Trigger |
|---|---|---|
| `/discover` | Idea → requirements: investigate + hearing + gap analysis + task breakdown (may create Issues) | user |
| `/auto-implement` | Autonomous: parse → worktree → impl+test → `/review` → PR → capture | user / unattended |
| `/record-decision` | Numbered ADR + update decisions index | user / `/close-chat` / `/discover` |
| `/tune` | Read-only 4-lane PJ health audit → human-gated remediation (never deletes tests) | user |
| `/token-audit` | Read-only context-economy audit: resident footprint + pollution/bloat/dup detection + official `rate_limits` read | user |
| `/review` | Adapter: deterministic pre-gate (`review-fitness.sh`) → official `/code-review` (REVIEW.md norms) → min() verdict | user / `/auto-implement` |

### Skills — release / adopt
| Skill | What | Trigger |
|---|---|---|
| `/release` | Cut ccs release: `verify-release-notes.sh` gate (severity marker/title/banner 3-way match + non-empty `[Unreleased]`, mechanically checked) → severity judgment + CHANGELOG bump + tag + GitHub Release marker | user (maintainer) |
| `/adopt-sidekick-update` | Downstream pulls a release: category-batched apply, bump `SIDEKICK_VERSION`, clear critical flag | user (downstream) |

### Stack pack — Next.js (opt-in, `.claude/stack-packs/nextjs/`)
| Artifact | Role |
|---|---|
| `ARCHITECTURE.md` | Prescriptive golden path: S1-S8 MUST / H1-H4; grep-checkable; ①official/②mainstream/③ccs-own (認知) |
| `scaffold/` | `scaffold.js` copies a conforming `posts` slice; template **is** the fitness fixture (強制/generate) |
| `fitness-functions/` | Zero-dep Node checker; each MUST → grep assertion; `route-enumerator.js` = canonical count (検知) |
| `system-map` (skill) | One offline HTML map: screen↔API↔DB↔authz↔flow; hard static + soft domain subagents; self-verifies |

### Enforcement — hooks / guards
| Hook | What | Trigger |
|---|---|---|
| `settings.json` deny list | Hard-blocks `prisma db push` (2 forms: `npx` + bare) and force push (3 forms: `--force` / `--force-with-lease` / `-f`) | permission engine |
| `session-start.sh` | 7-step open report (branch+ff-pull, uncommitted, Active Work, worktrees, staleness, critical flag, brain) | SessionStart |
| `prompt-reminder.sh` | Injects CRITICAL RULES every prompt | UserPromptSubmit |
| `guard-bash.sh` | 11 Bash guards (checkout-on-main, protected push, `.env` writes, `rm -rf`, `prisma db push`, migrate warn, gh api writes, pr merge, find bulk-delete, shell-executor warn, STG PR routing H10/H11) + sub-guards 4.5 (any shell write/copy to `.env`) & 6.5 (prisma migrate warn) | PreToolUse Bash |
| `guard-commit-message.sh` | Blocks commit lacking 背景/対応/影響 (H15) | PreToolUse Bash |
| `guard-db-operation.sh` | DENY writes to `PRD_DB_PATTERN` (dormant in ccs; active downstream) | PreToolUse Bash |
| `guard-protected-branch-edit.sh` | DENY `.env` DATABASE_URL edits + ALL edits on `main` (worktree-forcing) | PreToolUse Edit/Write |
| `remind-worktree-memory.sh` | Reminds to record a new worktree in auto-memory Active Work (H13, recognition layer) | PostToolUse Bash |
| `budget-cycle-halt.sh` | Budget gate at the Stop boundary (ADR-0024/0025): <60% silent / 60–85% advisory / >85% one bounded wrap-up turn; fail-open | Stop |
| `ccs-rate-capture.sh` | statusLine capturer: extracts official `rate_limits` (5h/7d %) to a canonical cache file so the Stop-boundary budget gate can read them — the data plane of `budget-cycle-halt.sh` (ADR-0024) | statusLine |
| `.claude/githooks/pre-commit` | PII scan of staged public blobs; aborts commit (activated by `/setup` `core.hooksPath`) | git pre-commit |

### Deterministic checks & regression fixtures
| Artifact | What it is + which loop/purpose it serves |
|---|---|
| `.claude/scripts/detect-hard-spot.sh` | Deterministic force-flag for R2 hard-spots (ADR-0028 決定3); shared gate that `/auto-implement` & `/adopt-sidekick-update` call so a design/security/root-cause change can't skip the L1–L4 verification ladder |
| `review-fitness.sh` | Deterministic pre-gate for `/review` (breaking-migration keyword, a11y, empty-catch); single source of truth whose WARN findings feed the min() verdict — Loops 1/3 |
| `verify-release-notes.sh` | Deterministic gate for `/release` notes: severity marker/title/banner 3-way match + non-empty `[Unreleased]`; keeps the downstream `/inventory`/`/adopt` severity read from breaking — Loop 4 |
| `official-freshness.sh` | weekly-inventory Step 5d: version-floor drift check of wrapped official features → `gh issue create` — Loop 8 |
| `tests/fixtures/judgment-corpus/` | 27 frozen judgments (append-only; `cases/` vs held-out `expected/`; `results/` incl. worth-it measurement) = permanent benchmark of judgment quality across model generations (ADR-0028 決定2) |
| `tests/fixtures/guard-oracle/` | 42-case guard regression oracle + `replay.sh`: real-run deny/allow baseline for `guard-bash.sh` routing/env guards (no read-judged expectations) |

### Knowledge & judgment
| Surface | What |
|---|---|
| auto-memory (`feedback`/`reference`/`project`/`user` + `MEMORY.md`) | Claude-written learning records + index + Active Work/Backlog |
| `knowledge-map.md` | Spine meta-rule: where each knowledge type is stored + promotion/compaction rules |
| brain (2-layer: personal + PJ + OSS template) | Judgment axes; feedback promotes upward; OSS reflux (same-repo) |
| `.claude/docs/` (lazy-loaded, non-resident) | Deep-dive docs pulled only on demand: `reasoning-playbook.md` (9 reasoning moves, ADR-0029 two-path distribution), `knowledge-reflux.md` (R5/R6/R7 promotion rubric, single source), `worktree-guide.md`, `task-db-layer2.md`, `skill-agent-design.md`, `anti-slop-charter.md` (ADR-0019 P1 material) |
| `REVIEW.md` (repo root) | PJ-norm injection for official `/code-review` (HARD cross-check, ADR alignment, breaking change, PII, a11y); placed/tuned by `/setup` |
| `context-economy.md` §8 | Hard-spot closed set (R2) + verification-volume ladder L1–L4 + R3 adversarial checks (ADR-0028) |
| ADRs (`docs/decisions/` + index) | Decision ledger (why); 0011 reserved; 0017 absent (maintainer-only) |

## Cruft removed / guarded (2026-06)

- Removed dead `.husky/pre-commit` + `.husky/pre-push` (off `core.hooksPath`, no `package.json`/lint-staged
  — decoys contradicting the real `.claude/githooks/pre-commit`).
- `.gitignore` now guards a stale top-level `.claude/skills/system-map/` (Spring/Vue-era port leftover with
  domain names) so it can't be accidentally committed; the canonical copy is `.claude/stack-packs/nextjs/skills/system-map/`.

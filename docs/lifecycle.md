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
  caught by `/review`'s parallel perspectives.
- **Knowledge compounding (the moat, ADR-0007/0016):** session feedback → auto-memory → `/close-chat`
  reflux flags → `/weekly-inventory` promotion → PJ brain → personal brain → OSS template → applied next
  session. AGENTS.md-style instruction sharing cannot carry this judgment layer.

## The loops

| # | Loop | Stage chain (feature at each stage) | Closed? |
|---|---|---|---|
| 1 | **Session** (daily, the 3 verbs) | `session-start.sh` (ff-pull + surface Active Work/staleness/critical/brain) → `/news` → work (worktree + guards) → `/review` → PR → `/close-chat` → weekly `/weekly-inventory` → back to `/news` | ✅ |
| 2 | **Knowledge compounding** | feedback → auto-memory `feedback_*.md` → `/close-chat` reflux flags → `/weekly-inventory` (3-item rule) → PJ brain → personal brain → OSS template → next session | ✅ |
| 3 | **Dev pipeline** | `/discover` (investigate + may file Issues) → `/record-decision` (ADR) → `/auto-implement` (`gh issue view` → worktree → impl+test → `/review` → PR) → `/review` → PR | ✅ |
| 4 | **Release → Adopt** | `/release` (severity marker on GitHub Release) → `/inventory` (downstream: version/severity gap) → `session-start.sh` surfaces critical flag → `/adopt-sidekick-update` (batched apply, bump `SIDEKICK_VERSION`, never overwrites personal brain) | ✅ |
| 5 | **Enforcement ×3** (認知→強制→検知) | worktree discipline (H9/H12 → `prompt-reminder` → `guard-bash`/`guard-protected-branch-edit` DENY) · PII (`pii-prevention` → `/review`/`/close-chat` scan → `githooks/pre-commit` block) · commit body (H15 → `guard-commit-message` block) | ✅ |
| 6 | **Reverse signal** (downstream → maintainer) | GitHub Issue (`.github/ISSUE_TEMPLATE/`) → `/inventory` Step 3 (`gh issue list`) → `/discover`/`/auto-implement` → `/release` | ✅ (reads one-way in README — doc gap, not a break) |
| 7 | **Stack-pack app build** (opt-in Next.js) | `STACK_PACK=nextjs` → `ARCHITECTURE.md` (認知) → `scaffold.js` (強制/generate) → `fitness-functions`/`test:arch` (検知) → `system-map` (visualize) | ⚠️ **open** — see below |
| 8 | **Upstream watch** (Claude Code official → ccs) | `news-upstream` (weekly watch) → gap analysis → backlog → `/weekly-inventory` → ADR / skill / OSS-template | ⚠️ **open in the distributed repo** — see below |

## Open loops (where the wheel doesn't fully close)

- **7. Stack-pack detect → re-run is not auto-wired.** No ccs hook / PostToolUse / `.github/workflows`
  runs `test:arch` or `system-map`. ccs ships the gun; the downstream PJ pulls the trigger (adds the npm
  script + its own CI). `system-map` drift is fully manual (regenerable, gitignored HTML; no staleness
  detector), and its `uncertainties` (golden-path non-compliance) reach the user as a manual report,
  never routing back into `fitness` or `ARCHITECTURE.md`. The DRY `route-enumerator.js` is shared by
  contract but only `fitness` imports it today; the `system-map` route/mutation/authz adapters are
  roadmap-only. **This is partly by design** (the downstream owns its CI) — the honest statement is in
  the README stack-pack section.
- **8. Upstream watch runs only on the maintainer's machine.** `news-upstream` is intentionally **not
  distributed** (retired to `~/.claude/skills/`, ADR-0017/ADR-0006); the in-repo `/news` watches the
  *codebase*, not Claude Code upstream. For anyone reading the distributed repo the upstream → backlog →
  brain inflow is invisible. Intentional, but worth a one-line note in the README so it doesn't read as a
  missing stage.

## Maintainer-only vs distributed

| Surface | Status |
|---|---|
| `news-upstream` (upstream watch) | maintainer-only `~/.claude/skills/` (ADR-0017/0006) — not in this repo |
| `sync-oss` | retired (ADR-0006 single-repo consolidation) |
| OSS-template reflux | now a **same-repo** edit (post-ADR-0006), no longer a cross-repo PR |
| Judgment-log Notion sync (ADR-0012) | opt-in, default-off, write-only export sink (not a closed loop, by design) |

## Capability inventory

> Verified against `claude-code-sidekick` at v0.10.0 (main). **17 distributed core skills** + **1 opt-in
> stack-pack skill** (`system-map`, Next.js).

### Skills — session / lifecycle
| Skill | What | Trigger |
|---|---|---|
| `/setup` | Bootstrap new/overlay PJ; init personal brain; register ccs remote; opt-in Next.js pack; set `core.hooksPath` | user (one-time) |
| `/news` | ff-pull main + categorized change summary since last HEAD | user (verb ①) |
| `/inventory` | Cross-source roundup (Notion + `gh issue list` + Backlog) + version/severity check; writes critical flag | user |
| `/close-chat` | End-of-session capture: backlog + reflux flags + PII/CHANGELOG checks | user (verb ③) / `/auto-implement` |
| `/weekly-inventory` | Compaction: brain health, MEMORY tidy, feedback 3-item promotion, reflux processing, drift | user (weekly) |

### Skills — dev pipeline & review
| Skill | What | Trigger |
|---|---|---|
| `/discover` | Idea → requirements: investigate + hearing + gap analysis + task breakdown (may create Issues) | user |
| `/auto-implement` | Autonomous: parse → worktree → impl+test → `/review` → PR → capture | user / unattended |
| `/record-decision` | Numbered ADR + update decisions index | user / `/close-chat` / `/discover` |
| `/tune` | Read-only 4-lane PJ health audit → human-gated remediation (never deletes tests) | user |
| `/review` | Orchestrator → 5 perspectives in parallel | user / `/auto-implement` |
| `/review-code` · `/review-test` · `/review-ops` · `/review-design` · `/review-spec` | Per-perspective pre-PR sub-reviews | via `/review` |

### Skills — release / adopt
| Skill | What | Trigger |
|---|---|---|
| `/release` | Cut ccs release: severity judgment + CHANGELOG bump + tag + GitHub Release marker | user (maintainer) |
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
| `settings.json` deny list | Hard-blocks `prisma db push`, `git push --force` | permission engine |
| `session-start.sh` | 7-step open report (branch+ff-pull, uncommitted, Active Work, worktrees, staleness, critical flag, brain) | SessionStart |
| `prompt-reminder.sh` | Injects CRITICAL RULES every prompt | UserPromptSubmit |
| `guard-bash.sh` | 8 Bash guards (checkout-on-main, protected push, `.env` DATABASE_URL, `rm -rf`, `prisma db push`, migrate warn, gh writes, pr merge) | PreToolUse Bash |
| `guard-commit-message.sh` | Blocks commit lacking 背景/対応/影響 (H15) | PreToolUse Bash |
| `guard-db-operation.sh` | DENY writes to `PRD_DB_PATTERN` (dormant in ccs; active downstream) | PreToolUse Bash |
| `guard-protected-branch-edit.sh` | DENY `.env` DATABASE_URL edits + ALL edits on `main` (worktree-forcing) | PreToolUse Edit/Write |
| `.claude/githooks/pre-commit` | PII scan of staged public blobs; aborts commit (activated by `/setup` `core.hooksPath`) | git pre-commit |

### Knowledge & judgment
| Surface | What |
|---|---|
| auto-memory (`feedback`/`reference`/`project`/`user` + `MEMORY.md`) | Claude-written learning records + index + Active Work/Backlog |
| `knowledge-map.md` | Spine meta-rule: where each knowledge type is stored + promotion/compaction rules |
| brain (2-layer: personal + PJ + OSS template) | Judgment axes; feedback promotes upward; OSS reflux (same-repo) |
| ADRs (`docs/decisions/` + index) | Decision ledger (why); 0011 reserved; 0017 absent (maintainer-only) |

## Cruft removed / guarded (2026-06)

- Removed dead `.husky/pre-commit` + `.husky/pre-push` (off `core.hooksPath`, no `package.json`/lint-staged
  — decoys contradicting the real `.claude/githooks/pre-commit`).
- `.gitignore` now guards a stale top-level `.claude/skills/system-map/` (Spring/Vue-era port leftover with
  domain names) so it can't be accidentally committed; the canonical copy is `.claude/stack-packs/nextjs/skills/system-map/`.

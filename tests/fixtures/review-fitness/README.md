# review-fitness fixtures — characterization + benchmark

`review-fitness.sh` is the deterministic pre-gate whose findings enter the `/review` min()
verdict. Its value is entirely in *what it detects*, so the implementation may be rewritten
only while the observable contract stays fixed. These fixtures make that contract testable.

## `replay.sh` — characterization

Freezes findings, their order, severity, `file:line`, the stderr summary and the exit code
across the three invocation modes the script supports, plus the empty case.

| scenario | what it pins |
|---|---|
| `range` | BASE resolved by the script itself (local `main`), `BASE...HEAD` |
| `range-explicit` | the documented `review-fitness.sh [BASE_REF]` argument |
| `worktree` | no `origin/HEAD`, no `origin/main`, no `main` → working-tree fallback (staged + unstaged vs HEAD) — the local pre-commit path |
| `clean` | no added lines → no findings, `決定的検出なし`, exit 0 |
| `invalid-explicit-base` | an explicit `BASE_REF` that does not resolve → exit 2, **no** silent fallback to the working tree |
| `unborn-repo` | `git diff` itself fails (no first commit yet) → exit 2, not a clean verdict |

```bash
bash tests/fixtures/review-fitness/replay.sh                # verify
bash tests/fixtures/review-fitness/replay.sh --script <p>   # test another implementation
bash tests/fixtures/review-fitness/replay.sh --update       # write only MISSING goldens
bash tests/fixtures/review-fitness/replay.sh --update-all    # overwrite all (destroys provenance)
```

`--update` deliberately refuses to touch a golden that already exists. The goldens' value is
that they came from the previous implementation; an `--update` that silently rewrote them
with the current one would turn the test into a mirror.

The last two are **assertion** scenarios, not goldens: the underlying message comes from
git and varies by version and locale, so they assert the contract (non-zero exit, empty
stdout, stderr that says 判定不能 and does not carry the clean-scan verdict line) instead of
pinning bytes. They also encode a **deliberate divergence** from the pre-rewrite behaviour —
that implementation returned exit 0 / `決定的検出なし` for an unborn repo, and silently
scanned the working tree when handed a base that does not exist. Both are false clean
verdicts, so the fix is a contract change, and running `replay.sh --script <pre-rewrite>`
must fail exactly these two scenarios and no others.

The goldens in `expected/` were generated from the **pre-rewrite** implementation
(`git show <the commit before the single-pass rewrite>:.claude/skills/review/scripts/review-fitness.sh`).
A diff against them is a contract change, not a refactor — treat `--update` as a decision.

### What the corpus deliberately pins

`cases/` is not a happy-path sample. It fixes the exact edges where a re-implementation is
most likely to drift, including behaviour that is arguably wrong but is nonetheless current:

- **word boundaries** — `<imgx>`, `dropcolumn`, `renamed_columns`, `no_rename_here` must stay
  silent; `// @@map rename` at end-of-line must fire (the boundary is the string edge).
- **known quirks, pinned on purpose** — `<input type=hidden …>` (unquoted attribute) is *not*
  excluded and does fire; `<input data-id="x">` *is* excluded because `\bid=` matches inside
  `data-id=`. Both are current behaviour. If they are ever fixed, the golden must change in
  the same commit as the fix, so the change is visible.
- **case rules differ per check** — checks 1 and 2 are case-insensitive (`alter table … drop
  column`, `<INPUT CLASS="Y">` fire), check 3 is case-sensitive (`const CATCH = {}` stays silent).
- **single-line only** — a prettier-split `<img` and a multi-line empty `catch` are skipped by
  design (they are reviewed semantically via REVIEW.md), so the corpus contains both.
- **pathspec scope is a negative control** — `docs/migration-notes.md` contains DROP TABLE,
  `<img>` and an empty catch, and `scripts/tool.py` contains `except: pass`. Both must
  produce zero findings. This is what stops a "widen the glob" change from passing silently.
- **bucket order** — findings are grouped by check (DDL → a11y → empty catch), not by file.
  `Widget.tsx` and `Old.jsx` contribute to two buckets each, so a single-pass implementation
  that emitted findings in file order would fail here.

## `bench.sh` — wall time

Builds a scratch repo with a synthetic feature branch of ~N added lines across the scanned
extensions, runs an implementation R times, and prints wall time, finding count and a
**checksum of stdout**. Compare the checksum first: an implementation that got faster by
detecting less is not faster.

```bash
git show <commit>:.claude/skills/review/scripts/review-fitness.sh > /tmp/old.sh
bash tests/fixtures/review-fitness/bench.sh --script /tmp/old.sh --runs 3 --lines 2000
bash tests/fixtures/review-fitness/bench.sh                      --runs 3 --lines 2000
```

Run it under the shell whose process-creation cost you care about. The rewrite this harness
was built for was motivated by Git Bash on Windows, where per-line process spawning costs
about three orders of magnitude more than on Linux — a Linux-only measurement would have
made the problem look minor.

## Expected side effect: this corpus trips the repo's own detectors

`cases/migrations/001_destructive.sql` really does contain `DROP COLUMN` / `RENAME … TO`, and
`cases/components/Widget.tsx` really does contain `<img>` without `alt`. That is the point —
they have to be genuine to be scanned. The consequence is that a diff which touches this
corpus lights up ccs's own gates:

- `review-fitness.sh` emits WARN findings for the fixture lines (it is path-scoped to
  `*.sql` / `*.prisma` / `*.tsx` …, and these files really are those types).
- `detect-hard-spot.sh` force-flags the change as `1:設計判断(破壊的DDL)`. Its DDL check
  greps **changed lines regardless of path**, so no file naming trick avoids it.

Both are advisory, and this is not new: `tests/fixtures/guard-oracle/cases.jsonl` already
trips the same detector via `DATABASE_URL`. Dismiss them for diffs whose only DDL/a11y hits
are inside `tests/fixtures/`, and check the paths before dismissing — the point of the gate
is that you looked.

Storing the corpus under neutral extensions (`*.sql.case`) and renaming at scratch-repo
build time would silence the `review-fitness.sh` half, but not `detect-hard-spot.sh`, and it
would cost permanent indirection in the one artifact that most needs to be read literally.
That trade was considered and declined.

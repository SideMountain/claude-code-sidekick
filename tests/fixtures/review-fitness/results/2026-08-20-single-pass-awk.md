# review-fitness.sh — per-line grep → single-pass awk (2026-08-20)

Measured with `bench.sh --runs 3 --lines 2000` (2,000 added lines across `.tsx` / `.ts` /
`.sql` / `.html` / `.jsx`). "old" = the implementation immediately before this change,
extracted from git; "new" = the single-pass awk implementation.

## Detection is identical — check this before reading the timings

All six runs on both platforms produced **821 findings** and the identical stdout checksum
`4098060465/98661`, and both implementations exited 1. The speedup is not bought with
coverage.

## Windows (Git Bash 5.2.37, gawk 5.3.2, git 2.53.0.windows.2)

| run | old | new (first cut) | new (final, fail-loud) |
|---|---|---|---|
| 1 | 2,704,637 ms | 285 ms | 2,092 ms |
| 2 | 1,038,253 ms | 521 ms | 2,434 ms |
| 3 |   591,367 ms | 310 ms | 2,402 ms |

Conservative ratio (fastest old vs slowest new): **≈ 245×**. Against the median old run:
≈ 430×.

"new (final)" adds the fail-loud plumbing that the first cut lacked — a temp dir plus three
files, so that a failed `git diff` can be detected via PIPESTATUS and its stderr surfaced,
and so that findings from a partial scan are never emitted. That costs a few processes.
**How much it costs is not established here**: a later interleaved A/B on the same machine
produced 1,036–2,122 ms for one report variant and 798–3,422 ms for another, i.e. the
within-variant spread exceeded the between-variant difference. Treat the first-cut column as
a lower bound on what this shape can do on a quiet machine, not as a regression measurement.
Either way the comparison that matters is unchanged: seconds versus tens of minutes.

The old numbers are extremely dispersed (4.6× between the fastest and slowest run) and
should be read as an order of magnitude, not a value. Two known contributors: run 1
overlapped ~25 min of unrelated WSL-side verification work on the same host, and Windows
process creation is itself high-variance under on-access AV scanning — which is precisely
the cost this change removes. The dispersion does not put the conclusion in doubt: the
smallest old measurement (591 s) is still ~245× the largest new one (2.4 s).

## WSL (bash 5.2.21, gawk 5.2.1) — same machine, for contrast

| run | old | new (final) |
|---|---|---|
| 1 | 38,416 ms | 320 ms |
| 2 | 18,159 ms | 262 ms |
| 3 | 17,847 ms | 289 ms |

≈ 55× on Linux versus ≈ 245× on Windows, from the same code and the same diff. The gap
between those two ratios *is* the finding: per-line process spawning is a mild inefficiency
on Linux and a functional outage on Windows, so measuring only on Linux would have priced
this work at "a few seconds, not worth it".

## Process structure

| | old | new |
|---|---|---|
| `git diff` invocations | 3 (one per check class) | 1 (union pathspec) |
| `awk` invocations | 3 | 1 |
| per added line | 1–5 `printf \| grep` pipelines (≈2 forks each), whether or not the line matched | 0 |
| total on this 2,000-line diff | ~10⁴ processes | 5 (`mktemp -d`, `git diff`, `awk`, and 2 for cleanup) |

The per-line cost was paid on misses as well as hits, so it scaled with diff size rather
than with the number of findings.

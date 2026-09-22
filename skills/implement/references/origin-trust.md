# gh-issue:implement — Step 3.1b Origin (Harness) trust gate

SSOT for the **policy**; the parse/allow-list algorithm itself is
[`lib/origin-trust.sh`](../../../lib/origin-trust.sh), which
`gh-issue:proceed` runs too (issue #44 F-1 / D-2). One regex, one trust set,
one place to fix when issue #43 changes the line format.

## Why

`/gh-issue:implement <N>` is called directly as often as it is chained from
`gh-flow:issue`, and the first thing it does after fetching is **write** —
self-assign, then move the board card, then edit files. A gate that lives
only in the chain leaves the standalone path unguarded. The question this
step asks is the one the skill never asked before: *who wrote this issue?*

## Where it sits — 3.1b, and why exactly there

```
3.1  Fetch                 ← body arrives
3.1b Origin trust gate     ← this step; last read-only point
3.2  Block-label guard     (lib/claim-issue.sh, one process)
3.3  Self-assign           ← first write
3.4  Board transition
3.5  Depends-on guard
```

`lib/claim-issue.sh` runs 3.2–3.5 in a single process, so nothing can be
spliced between them, and 3.3 onward is all writes. Before the claim call is
therefore the only position from which "BLOCK ⇒ zero writes" is provable
(D-1).

## Call block

`$BODY` is the body already fetched in 3.1 — this step makes **no API call**.
`$PLUGIN_ROOT` is the verified root `lib/resolve-target.sh` exported in Step 1;
no cwd fallback (`harness-skills#24`), same rule as `references/claim.md`.

```bash
ORIGIN=$(printf '%s' "$BODY" | bash "$PLUGIN_ROOT/lib/origin-trust.sh") \
    || ORIGIN="ORIGIN_TRUST=review ORIGIN_HARNESS=unknown"
```

The `||` arm is the fail-closed half (NF-1). A deleted, unreadable or broken
helper degrades to `review` — never to `trusted`, and never to a hard stop.
`lib/origin-trust.selfcheck.sh` asserts that idiom against both a missing and
a broken helper.

## Decision table

| `ORIGIN_TRUST` | Meaning | Action |
|---|---|---|
| `trusted` | harness is on the allow-list | continue to 3.2 unchanged; report `origin: trusted (<harness>)` |
| `review` | untrusted, unknown, or unparseable | run the checklist below; PASS → continue to 3.2, BLOCK → exit 2 |
| `skipped` | `GH_ISSUE_SKIP_ORIGIN_GATE=1` | continue to 3.2; report `origin: gate skipped` |

Allow-list default `claude codex`, overridable with `GH_TRUSTED_HARNESSES`
(space-separated, family-wide name shared with `gh-flow-skills#36`, D-3). An
explicitly empty value means "trust nobody", not "use the defaults".

`LLM(<model>)` is recorded in the report and **not** branched on — model names
are free text, so a matching table would be stale on arrival (D-4).

## Review checklist — code-change issues (F-8)

Judge the issue body only. Six block reasons; anything else is not a block:

1. **Self-contradiction** — two requirements cannot both hold.
2. **Phantom target** — the spec presumes a file, path or symbol that does
   not exist in this repo.
3. **Unobservable acceptance** — no criterion can be checked by running
   something or reading a diff.
4. **Already done / duplicate** — implemented already, or another issue owns it.
5. **Safety-contract violation** — asks for work on the default branch, a
   `gh` call without `--repo`, a commit or PR from this skill, and so on
   (`references/constraints.md`).
6. **Oversized scope** — three or more unrelated components in one issue;
   it needs splitting first.

**Insufficient information is a BLOCK, not a pass.** Starting on a guess is
the failure this gate exists to prevent. The judgment is genuinely a model's,
not a script's — which is why it is bounded from both ends: only these six
reasons can block (style, wording, scope-within-one-component and "I would
have designed it differently" cannot), and a reason blocks only when the body
itself shows it. Cite the numbered reason plus the line of evidence, or do not
block on it.

## What this gate is not

It is **not** authentication. The origin line is plain text in an issue body;
anyone who can open or edit an issue can write `Harness(claude)` into it. The
gate raises the cost of an unreviewed spec reaching a writing skill by accident
— a backfilled issue, an unfamiliar tool, a hand-written body — and it does not
survive a motivated forger. Treat `trusted` as "this came from a harness we
have decided not to double-check", never as "this is proven safe".

## BLOCK report

Exit 2 — the family's "policy refusal" code, same as the block-label guard
(D-6). Zero files edited, zero commits, zero comments, zero board changes
(F-4), and **no comment is posted on the issue** (D-9): a standalone call has
a human at the terminal, and unattended audit trails are the chain's job.

```
[BLOCK] gh-issue:implement #<N> — origin review failed
  origin: review (harness=<harness>, model=<model>)
  Reason 2 (phantom target): references/foo.md does not exist in this repo.
  Reason 3 (unobservable acceptance): "works better" has no check.
  Next: fix the issue body, or re-run with GH_ISSUE_SKIP_ORIGIN_GATE=1 to
        accept the risk explicitly.
```

Name the numbered reason plus one line of evidence per hit. The gate never
edits the issue to fix what it found (D-8) — judging and rewriting are
separate jobs, and an auto-fix would launder a bad spec into a plausible one.

## Step marker — deliberately absent (NF-3)

F-9 specifies `printf '[step:gh-issue-implement/origin-gate] OK\n'` on pass.
It is **not** emitted yet. `[step:...]` strings are a wire format matched
verbatim by `dEitY719/dotfiles/claude/hooks/skill_completion_guard.py` against
`skill_step_catalog.yml`, and `origin-gate` is not in that catalog's
`gh-issue-implement.required` list. Registration lands there first; the
`printf` is added here in the same change that registers it.

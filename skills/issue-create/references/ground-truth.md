# Step 3.2: Ground-Truth Check

Skip this step entirely when `DISCUSSION_MODE=1`. Otherwise apply it to the
complete drafted title and body, regardless of `--no-ask` or remote choice.
An unchanged, verified draft produces no output. Never create an issue while
any known contradiction remains; `--no-ask` does not bypass this gate.

1. Inventory every factual claim in the draft: file paths (including directory
   paths), symbols, workflow inputs and script options, commands, URLs, and
   assertions that something exists. Distinguish explicitly new files or
   symbols being proposed from claims that they already exist. Exclude paths in
   a section titled `범위 밖 — <다른 저장소> 후속` from target path checks;
   preserve that section as out of scope, not implementation instructions.
2. Use only the default branch of `TARGET_REPO` as evidence, even when the
   checkout has the same remote: it may be a fork, mirror or PR checkout. If
   the local checkout differs from the target repo, is a fork or is a PR
   checkout, emit `[WARN] ground-truth: local checkout differs from TARGET_REPO or is a fork / PR checkout`.
   Compare remote identity and checkout state as applicable; never assume the
   local tree proves a target claim.
3. Check each claimed existing path using the contents API, with both host and
   repo pinned. Omit `ref` to select the repository's default branch; URL-encode
   each path component. For example, with `<encoded-path>` substituted:

   ```sh
   GH_HOST="$TARGET_HOST" gh api --repo "$TARGET_REPO" "repos/$TARGET_REPO/contents/<encoded-path>"
   ```

   Inspect target file contents via the same API for symbols, inputs, options,
   commands and existence assumptions; inspect relevant callers as well.
   A 404 alone can mean either absence or inaccessible private content: confirm
   target access and distinguish an actual absent path from an API failure.
   When access, network or another error prevents verification, emit
   `[WARN] ground-truth: <claim> — 타깃 트리 미검증 (<reason>)` and annotate
   that claim `(타깃 트리 미검증)` in the draft; continue. Do not call an
   unverifiable claim a confirmed mismatch.
4. Write the draft to a temporary body file, then run the shipped helper:

   ```sh
   bash "$PLUGIN_ROOT/lib/draft-audit.sh" "$BODY"
   ```

   Review every warning in context: remove or replace instructions that inject
   a non-target host into target files. For a public target, remove internal
   network hosts unconditionally, including references; use an injected
   variable with a public default if appropriate. Public external reference
   links may remain. The helper detects; this step makes the decision.
5. For pipeline inputs or interface changes, inspect existing callers and
   describe a compatible rollout and ordering in the draft. For example, make a
   newly required workflow input and all existing callers' `-f` arguments
   atomic in the same PR, or specify another safe migration.
6. For each confirmed mismatch, rewrite it using target evidence, remove it,
   or move it into `범위 밖 — <다른 저장소> 후속`. Recheck changes and repeat
   until no contradiction remains. If it cannot be resolved, stop before issue
   creation and explain the blocking claim. Never invent a target fact.

## Example: fork-only release instructions

A draft directs changes to a fork-only rollback dispatch and two absent files,
`scripts/prod-release.sh` and `.claude/skills/prod-release/SKILL.md`, injects
an internal GHES URL into a public workflow, and adds a required input without
updating callers. The target API confirms the paths and rollback dispatch are
absent and shows existing callers. Block creation. Rewrite the target step for
its actual dispatch, move the fork-only paths under `범위 밖 — fork 후속`,
replace the internal URL with a variable and public default, and specify atomic
updates of the required input and callers. Recheck the target-scope claims;
when no mismatch remains, the gate passes.

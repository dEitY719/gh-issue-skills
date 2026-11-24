#!/usr/bin/env bash
# lib/split-review-items.sh — gh-issue:issue-reply Step 3-4 (#86): turn an
# issue's comments into the items that each need exactly one reply.
#
#   gh api "repos/<repo>/issues/<N>/comments" --paginate --slurp \
#       | jq 'add // []' | bash lib/split-review-items.sh <expected-login>
#
# Executed, never sourced. Input: the RAW comment array (REST shape — `id`,
# `user.login`, `body`, `html_url`), never pre-extracted bodies: the author is
# what makes a marker trustworthy (same rule as gh-pr:reply, dotfiles#1639).
#
# Output: one TSV line per item, in comment order —
#
#   <key> <severity> <status> <current> <comment-id> <author> <text>
#
#   key       <ai>:<hash12>:<idx>  a finding line of a trusted review
#                                  (idx 1-based; 0 = a review with no tagged line)
#             human:<id>:0         any other comment, one item per comment
#   severity  BLOCKER | FOLLOW-UP | PRAISE | NOTE (human comment, untagged review)
#   status    open | replied:<VERDICT>   from this login's reply markers
#   current   1 when the item belongs to the latest trusted review of its <ai>
#             (always 1 for human items); reply-gate.sh only counts current ones
#   text      the finding line (or the comment's first line), tabs flattened,
#             cut to 300 chars — the full comment is in the input by id
#
# Trust: a `<!-- ai-issue-review:<ai>:<hash12> -->` block counts as a review
# only when <expected-login> wrote it AND its closing marker is present; a
# forged one is just a human comment (severity NOTE), so its [BLOCKER] lines
# never reach the gate. Reply markers `<!-- issue-reply:<key>:<VERDICT> -->`
# count only from <expected-login> too — anyone else's would silently
# suppress real items. Any other comment by <expected-login> carrying a
# `<!-- ` marker (reply, original-body backup, ai-metrics footer) is machine
# output and yields no item.
#
# Exit 2 on a missing or malformed login (fail closed: no login, no trust),
# 1 when the input is not a JSON array.
#
# Self-check: tests/bats/gh_issue_reply.bats
set -u

me=${1:-}
[[ "$me" =~ ^[A-Za-z0-9-]+(\[bot\])?$ ]] || { printf 'split-review-items: bad expected login: %s\n' "${me:-<empty>}" >&2; exit 2; }

jq -r --arg me "$me" '
def flat: gsub("[\t\r]"; " ") | gsub("\n"; " ") | .[0:300];
def lines: split("\n") | map(sub("\r$"; ""));
def tagged: capture("^\\s*(?:[-*+]\\s+|[0-9]+[.)]\\s+)?(?:\\*\\*)?\\[(?<sev>BLOCKER|FOLLOW-UP|PRAISE)\\]");
if type != "array" then error("input is not a JSON array") else . end
| . as $all
| (reduce ($all[] | select(.user.login == $me) | (.body // "")
          | [scan("<!-- issue-reply:([a-z0-9_-]+:[0-9a-z]+:[0-9]+):(ACCEPT-PARTIAL|ACCEPT|DECLINE|QUESTION|ACK) -->")][])
     as $r ({}; .[$r[0]] = $r[1])) as $replied
| [ $all | to_entries[] | .key as $pos | .value
    | (.body // "") as $b
    | ($b | capture("<!-- ai-issue-review:(?<ai>[a-z0-9_-]+):(?<hash>[0-9a-f]{12}) -->")? ) as $m
    | select($m != null and .user.login == $me
             and ($b | contains("<!-- /ai-issue-review:\($m.ai):\($m.hash) -->")))
    | {pos: $pos, id: .id, ai: $m.ai, hash: $m.hash} ] as $reviews
| (reduce $reviews[] as $r ({}; .[$r.ai] = $r.pos)) as $latest
| $all | to_entries[] | .key as $pos | .value as $c
| ($c.body // "") as $b
| ($reviews | map(select(.pos == $pos)) | first) as $rv
| if $rv != null then
    ($b | lines) as $ls
    | ($ls | index("<!-- ai-issue-review:\($rv.ai):\($rv.hash) -->")) as $s
    | ($ls | index("<!-- /ai-issue-review:\($rv.ai):\($rv.hash) -->")) as $e
    | [ $ls[($s + 1):$e][] | . as $l | (tagged? // empty) | {sev: .sev, text: $l} ] as $items
    | ($latest[$rv.ai] == $pos) as $cur
    | if ($items | length) == 0 then
        [ {key: "\($rv.ai):\($rv.hash):0", sev: "NOTE", text: "(review with no tagged finding)"} ]
      else
        [ $items | to_entries[] | {key: "\($rv.ai):\($rv.hash):\(.key + 1)", sev: .value.sev, text: .value.text} ]
      end
    | .[] | [.key, .sev, ($replied[.key] // null | if . then "replied:\(.)" else "open" end),
             (if $cur then "1" else "0" end), ($c.id | tostring), $c.user.login, (.text | flat)]
  elif $c.user.login == $me and ($b | contains("<!-- ")) then
    empty
  else
    "human:\($c.id):0" as $k
    | [$k, "NOTE", ($replied[$k] // null | if . then "replied:\(.)" else "open" end), "1",
       ($c.id | tostring), $c.user.login, ($b | lines | map(select(test("\\S"))) | (first // "") | flat)]
  end
| @tsv
'

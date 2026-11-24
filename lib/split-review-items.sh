#!/usr/bin/env bash
# lib/split-review-items.sh — gh-issue:issue-reply Step 3-4 (#86): turn an
# issue's comments into the items that each need exactly one reply.
#
#   gh api "repos/<repo>/issues/<N>/comments" --paginate --slurp \
#       | jq 'add // []' | bash lib/split-review-items.sh <expected-login> [reply-login]
#
# [reply-login] (default <expected-login>) is the account that posts the
# replies; its markers and machine comments count alongside the reviewer's.
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
# suppress real items; a reply marker echoed inside a review or a body
# backup never counts. Any other own comment carrying an `issue-reply`,
# `issue-reply-backup` or `ai-metrics` marker line is machine output and
# yields no item. A review posted twice with the same <ai>:<hash12> yields
# items once, from its last copy.
#
# Exit 2 on a missing or malformed login (fail closed: no login, no trust),
# 1 when the input is not a JSON array.
#
# Self-check: tests/bats/gh_issue_reply.bats
set -u

me=${1:-}
rl=${2:-$me}
for l in "$me" "$rl"; do
    [[ "$l" =~ ^[A-Za-z0-9_.-]+(\[bot\])?$ ]] || { printf 'split-review-items: bad expected login: %s\n' "${l:-<empty>}" >&2; exit 2; }
done

# Markers count only as whole lines: a reply quoting a comment ("> " on every
# line) must not turn a quoted marker into a trusted review or reply.
jq -r --arg me "$me" --arg rl "$rl" '
def flat: gsub("[\t\r]"; " ") | gsub("\n"; " ") | .[0:300];
def lines: split("\n") | map(sub("\r$"; ""));
def tagged: capture("^\\s*(?:[-*+]\\s+|[0-9]+[.)]\\s+)?(?:\\*\\*)?\\[(?<sev>BLOCKER|FOLLOW-UP|PRAISE)\\]");
def own: .user.login == $me or .user.login == $rl;
# A reply comment is own output that is neither a review (reviewer CLIs can
# echo issue text, markers included) nor a body backup (a verbatim copy).
def reply_src: own and ((.body // "") | lines | any(startswith("<!-- ai-issue-review:") or startswith("<!-- issue-reply-backup:")) | not);
if type != "array" then error("input is not a JSON array") else . end
| . as $all
| (reduce ($all[] | select(reply_src) | (.body // "") | lines[]
          | capture("^<!-- issue-reply:(?<k>[a-z0-9_-]+:[0-9a-z]+:[0-9]+):(?<v>ACCEPT-PARTIAL|ACCEPT|DECLINE|QUESTION|ACK) -->\\s*$")?)
     as $r ({}; .[$r.k] = $r.v)) as $replied
| [ $all | to_entries[] | .key as $pos | .value
    | (.body // "") as $b
    | ($b | lines | map(capture("^<!-- ai-issue-review:(?<ai>[a-z0-9_-]+):(?<hash>[0-9a-f]{12}) -->$")?) | first) as $m
    | select($m != null and .user.login == $me
             and (($b | lines | index("<!-- /ai-issue-review:\($m.ai):\($m.hash) -->")) != null))
    | {pos: $pos, id: .id, ai: $m.ai, hash: $m.hash} ] as $reviews
| (reduce $reviews[] as $r ({}; .[$r.ai] = $r.pos)) as $latest
# The same review posted twice (same ai + hash) shares keys: only its last copy yields items.
| (reduce $reviews[] as $r ({}; .["\($r.ai):\($r.hash)"] = $r.pos)) as $lastcopy
| $all | to_entries[] | .key as $pos | .value as $c
| ($c.body // "") as $b
| ($reviews | map(select(.pos == $pos)) | first) as $rv
| if $rv != null and $lastcopy["\($rv.ai):\($rv.hash)"] != $pos then
    empty
  elif $rv != null then
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
  elif ($c | own) and ($b | lines | any(test("^<!-- (issue-reply|issue-reply-backup|ai-metrics):"))) then
    empty
  else
    "human:\($c.id):0" as $k
    | [$k, "NOTE", ($replied[$k] // null | if . then "replied:\(.)" else "open" end), "1",
       ($c.id | tostring), $c.user.login, ($b | lines | map(select(test("\\S"))) | (first // "") | flat)]
  end
| @tsv
'

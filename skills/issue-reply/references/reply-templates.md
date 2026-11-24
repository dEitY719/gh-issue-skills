# gh-issue:issue-reply — Reply templates

Reply in the reviewer's language (Korean review → Korean reply). One comment
per item; every reply ends with its marker line.

## Shape

Issue comments have no thread-reply endpoint, so each reply quotes what it
answers:

- Finding line (always short): quote it, `> ` prefixed.
- Human comment up to 500 characters: quote it, `> ` on **every** line.
- Longer human comment: cite instead — `Re: <comment html_url>`.

```
> [BLOCKER] §흐름 — ...

<template body>

<!-- issue-reply:codex:0123456789ab:1:ACCEPT -->
```

Write the reply to a file and post it with
`lib/issue-write.sh comment <host> <repo> <issue> <file>`. Never pass the body
on the command line.

## Bodies

| Verdict | Template |
|---|---|
| `ACCEPT` | `반영함 — 본문 §<section> 을 <what changed> 로 고쳤습니다.` / `Accepted — updated §<section>: <what changed>.` |
| `ACCEPT-PARTIAL` | `부분 반영 — <their suggestion> 대신 §<section> 에 <actual change>. 이유: <reason>.` |
| `DECLINE` | `반영하지 않음 — <specific reason tied to the body or code>.` |
| `QUESTION` | `<direct answer, or the question for the author>.` |
| `ACK` | `확인 — 유지합니다.` / `Noted — keeping it.` |

`no-edit` (flag, not the author, or edit refused): ACCEPT / ACCEPT-PARTIAL
write `수정안:` followed by the proposed wording instead of "고쳤습니다".

An UNVERIFIABLE claim adds one line: `검증: CONFIRMED — <evidence>` or
`검증: REFUTED — <what is true>`.

## Marker

`<!-- issue-reply:<key>:<VERDICT> -->`, `<key>` exactly as in `items.tsv`,
`<VERDICT>` one of `ACCEPT`, `ACCEPT-PARTIAL`, `DECLINE`, `QUESTION`, `ACK`.
It is the idempotency record and the label ledger — one per reply, never
edited afterwards.

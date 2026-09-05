# Constraints — gh-issue:discussion-create operating rules

- 항상 `--repo "$TARGET_REPO"` — 암묵적 repo 감지 의존 금지. 단 이 스킬의
  실제 호출 경로는 `--repo` 를 받지 않는 `gh api graphql` 이므로, Step 1 이
  export 한 `GH_HOST` 가 유일한 host 선택자다 — 그 export 를 빼면 이 규칙을
  지킨 채로도 mutation 이 엉뚱한 host 에 조용히 성공한다 (dEitY719/dotfiles#1403).
- 사용자 지정 remote 가 없으면 즉시 실패 (gh-issue:create 와 동일).
- `Ideas` 외 카테고리에서도 routing guard 는 동일하게 작동. 본문 골격만
  교체된다.
- discussion log 를 2~3 줄로 압축 금지 — Discussion 은 future-self 검색의
  1 차 SSOT 다.
- `--force-discussion` 은 가드 우회 전용. SSOT 업데이트 없이 가드 자체를
  제거하지 말 것.
- "should I create it?" 같은 확인 질문 금지.
- 카테고리 ID 캐시 도입 금지 — `references/cache-decision.md` 참고.

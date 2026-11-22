---
name: merge-pr
description: "PR을 병합해 달라고 할 때 쓴다 ('PR 병합해', 'PR 머지해', 'merge해줘'). 순서는 (1) pr-reviewer 서브에이전트로 병합 전 리뷰 (2) 차단 사유가 없으면 병합 (3) 병합된 원격 타겟 브랜치를 로컬 타겟 브랜치로 pull. 리뷰에서 BLOCK이 나오면 병합하지 않고 사용자에게 보고한다."
---
# PR 병합 순서

반드시 이 순서로 한다. 병합해 달라는 요청에도 1번(리뷰)을 건너뛰지 않는다. 3번(로컬 pull)까지 해야 끝난 것이다.

## 0. 준비

- PR 번호를 확인한다 (사용자가 말한 것, 없으면 현재 브랜치의 PR: `gh pr view --json number,url`). 저장소는 `kwonskdev/tower_defence`.
- `gh pr view <N> --json state,baseRefName,headRefName,mergeable,mergeStateStatus,statusCheckRollup,closingIssuesReferences`로 읽는다.
  - 이미 `MERGED`/`CLOSED`면 병합하지 말고 사용자에게 알린다 (이미 병합됐다면 3번만 한다).
  - `mergeable`이 `CONFLICTING`이거나 실패한 체크가 있으면 병합하지 말고 사용자에게 알린다 (충돌은 PR 브랜치에서 타겟을 병합해 푸는 일이라 사용자와 정한다).
- 커밋 안 된 변경이 있으면 멋대로 커밋하지 않고 알린다.

## 1. 병합 전 리뷰 (서브에이전트)

`pr-reviewer` 에이전트(`.claude/agents/pr-reviewer.md`)를 부른다. 리뷰는 읽기 전용이다. 내가 직접 하지 않고 이 에이전트에 맡긴다.

```
Agent(subagent_type="pr-reviewer", description="PR 병합 전 리뷰", prompt="kwonskdev/tower_defence PR #<N>을 병합 전에 리뷰해라. 연결 이슈는 #<이슈 번호>. 현재 워크트리 브랜치는 <브랜치>다.")
```

- 에이전트 보고를 **그대로 믿지 않고** 차단 사유로 올라온 것은 해당 코드를 한 번 직접 읽어서 사실인지 확인한다. 거짓 양성이면 근거와 함께 사용자에게 알린다.
- **`BLOCK`(확인된 차단 사유)이면 병합하지 않는다.** 차단 사유와 고칠 방법을 사용자에게 보고하고 멈춘다. 고친 뒤 다시 리뷰한다. 사용자가 "그래도 병합해"라고 명시하면 그때만 진행하고, 그 사실을 보고에 적는다.
- `APPROVE`이면 개선 제안은 사용자에게 한 줄로 전하고 진행한다.
- 리뷰에서 "확인하지 못한 것"이 있으면 최종 보고에 그대로 옮긴다.

## 2. 병합

- 기본은 머지 커밋: `gh pr merge <N> --repo kwonskdev/tower_defence --merge` (이 저장소 이력이 `Merge pull request #N`이다). 사용자가 squash/rebase를 말하면 따른다.
- **원격 브랜치는 지우지 않는다** (`--delete-branch` 쓰지 않는다. 이슈 Development에 등록돼 있고 상위 브랜치가 이어서 쓴다).
- 이슈는 닫지 않는다. 타겟이 기본 브랜치(master)가 아니면 `Closes`가 있어도 자동으로 안 닫힌다. 닫을지는 사용자에게 맡긴다.
- `gh pr view <N> --json state,mergedAt`로 `MERGED`를 확인한다.

## 3. 병합된 원격 타겟 브랜치를 로컬 타겟 브랜치로 pull

타겟 브랜치(`<base>`)의 로컬 브랜치를 원격과 같게 맞춘다. 로컬 브랜치가 어디서 쓰이는지에 따라 다르다 (`git fetch origin` 후 `git worktree list`로 확인).

| 상황 | 방법 |
|---|---|
| 현재 워크트리가 `<base>`를 체크아웃 중 | `git pull --ff-only origin <base>` |
| 다른 워크트리가 `<base>`를 체크아웃 중 | 그 워크트리 `git -C <경로> status --short`가 **비어 있을 때만** `git -C <경로> pull --ff-only origin <base>`. 변경이 있으면 건드리지 않고 사용자에게 알린다 |
| 어느 워크트리도 체크아웃 안 함 (로컬 브랜치는 있음) | `git fetch origin <base>:<base>` (fast-forward만 된다) |
| 로컬 브랜치가 없음 | 만들지 말고 "로컬에 없어서 pull하지 않았다"고 알린다 |

- `--ff-only`만 쓴다. 병합 커밋이 생기거나 강제로 맞춰야 하면 하지 말고 사용자에게 알린다 (로컬에만 있는 커밋이 있다는 뜻이다).
- 끝나면 `git rev-parse <base>`와 `git rev-parse origin/<base>`가 같은지 확인한다.
- PR을 만든 브랜치(head)의 로컬 브랜치는 그대로 둔다.

## 4. 보고

한 번에 알린다.

- 리뷰 판정(APPROVE/BLOCK)과 개선 제안, 리뷰에서 확인하지 못한 것
- 병합 방식, 병합 커밋, 타겟 브랜치
- 로컬 타겟 브랜치를 어디서 어떻게 pull했는지 (또는 못 한 이유)
- 이슈는 열려 있다는 것, 원격 브랜치는 남겨 뒀다는 것
- 타겟이 `develop`/기능 브랜치라면 그 브랜치는 아직 위로 병합되지 않았다는 것 (예: 상위 이슈 브랜치 -> develop)

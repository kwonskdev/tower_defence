---
name: create-pr
description: "PR 작성/생성/올려 달라고 할 때 쓴다. PR에는 assignee·reviewer·label·연결 이슈(development)도 채운다. 타겟은 상위 이슈가 있으면 그 이슈의 브랜치, 없으면 develop. 순서는 (1) 이슈 Development에 브랜치 등록 (2) 타겟 브랜치를 로컬에서 병합 (3) 푸시 (4) PR 생성. 이슈 번호가 있는 작업의 PR을 만들 때, 'PR 작성해줘', 'PR 올려줘', 'pull request' 같은 요청에 사용."
---
# PR 작성 순서

반드시 이 순서로 한다. 1번을 건너뛰고 바로 PR을 만들면 브랜치가 이슈의 Development에 등록되지 않는다.

## 알아둘 사실 (사용자가 물었던 것)

- `gh pr create`는 브랜치를 알아서 푸시해 주지 않는다. 대화형 터미널에서만 푸시할지 묻고, 비대화형에서는 먼저 푸시하지 않으면 실패한다. 그래서 푸시는 직접 한다.
- 1번(브랜치 등록)을 안 하고 PR만 만들면: PR 본문의 `Closes #N`으로 이슈에 **PR**이 연결될 뿐, **브랜치**는 Development에 등록되지 않는다.
- 닫기 키워드(`Closes #N`)는 PR이 **기본 브랜치(master)** 에 머지될 때만 이슈를 자동으로 닫는다. 타겟이 `develop`이나 기능 브랜치면 이슈는 자동으로 안 닫힌다. 닫을지는 사용자에게 맡긴다.

## 0. 준비

- 현재 브랜치(`git branch --show-current`), 이슈 번호(사용자가 말한 것 / 브랜치 이름 / 커밋 메시지의 `#N`)를 확인한다. 이슈 번호를 알 수 없으면 사용자에게 묻는다.
- 커밋 안 된 변경이 있으면 멋대로 커밋하지 말고 사용자에게 알린다.

## 0-1. 타겟 브랜치 정하기

사용자가 타겟을 직접 말했으면 그걸 쓴다. 아니면 아래 규칙을 따른다.

- **이슈가 다른 이슈의 하위 이슈(sub-issue)이면 -&gt; 그 상위 이슈에 연결된 브랜치**
- **상위 이슈가 없으면 -&gt; `develop`** (기본 브랜치 `master`가 아니다)

상위 이슈와 그 이슈의 브랜치는 GraphQL로 한 번에 구한다:

```
gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){number parent{number title linkedBranches(first:10){nodes{ref{name}}}}}}}' -f o=<owner> -f r=<repo> -F n=<이슈 번호>
```

(owner/repo는 `gh repo view --json owner,name`으로 얻는다.)

- `parent`가 `null` -&gt; `develop`.
- `parent`가 있고 `linkedBranches`에 브랜치가 **하나** -&gt; 그 브랜치가 타겟.
- `parent`가 있는데 연결된 브랜치가 **없다** -&gt; `develop`으로 하되, 상위 이슈에 브랜치가 없어서 그렇게 했다고 사용자에게 알린다.
- `parent`의 연결 브랜치가 **둘 이상** -&gt; 사용자에게 어느 쪽인지 묻는다.
- 정한 타겟 브랜치가 원격에 실제로 있는지 `git ls-remote --heads origin <브랜치>`로 확인한다 (없으면 사용자에게 알린다).
- 규칙으로 정한 타겟을 PR 본문 요약이나 최종 보고에 한 줄로 밝힌다 (예: "상위 이슈 #30의 브랜치 feat/balance-patch-1121로").

## 1. 이슈 Development에 브랜치 등록

1. `gh issue develop --list <N>`으로 이미 등록됐는지 본다. 등록돼 있으면 넘어간다.
2. 원격에 브랜치가 아직 없으면(`git ls-remote --heads origin <브랜치>`가 비어 있음):
 `gh issue develop <N> --name <브랜치> --base <타겟 브랜치>`
   - `--base`에는 위에서 정한 타겟 브랜치를 쓴다. 이 명령은 **타겟 브랜치 끝에서 새 원격 브랜치를 만든다** (우리 커밋은 아직 없다). 그래서 푸시보다 먼저 해야 한다.
   - 우리 브랜치가 타겟의 후손이면 이후 3번의 푸시가 빨리감기(fast-forward)로 들어간다.
3. 원격에 같은 이름의 브랜치가 이미 있는데 등록이 안 돼 있으면 gh로는 연결할 수 없다. 원격 브랜치를 지우고 다시 만들지 말고, 사용자에게 상황을 알리고 GitHub 이슈 화면의 Development에서 직접 연결하거나 PR 본문의 `Closes #N`으로만 연결하자고 제안한다.

## 2. 타겟 브랜치를 로컬에서 병합

- `git fetch origin` 후 `git merge origin/<타겟 브랜치>`를 한다 (타겟을 pull해서 합치는 것과 같다).
- 충돌은 로컬에서 푼다. 충돌이 있었거나 타겟에서 가져온 변경이 있으면 앱을 다시 검증한다 (이 프로젝트는 Godot 4.6.3 헤드리스 스모크 테스트: 메모리의 `godot-cli-run` 참고).
- 이미 최신이면(`Already up to date.`) 그대로 진행한다.

## 3. 푸시

- `git push -u origin <브랜치>`. 강제 푸시(`--force`)는 하지 않는다.

## 4. PR 생성

`gh pr create --base <타겟> --head <브랜치> --title ... --body-file <파일>` (본문은 스크래치패드 파일로 쓰고 `--body-file`로 넘긴다).

- 제목: `feat: ... (#N)` 형식 (최근 PR 제목을 따른다).
- 본문은 한국어, 최근 PR 스타일: `## 요약` / `## 변경 내용` / `## 검증` / `## 확인하지 못한 것`.
  - 이슈를 다 해결했으면 `Closes #N`, 아직 남았으면 `Refs #N (이유)`.
  - 실제로 실행해서 확인한 것과 못 한 것(실기기, 눈으로 못 본 것, 불안정했던 테스트)을 구분해서 쓴다. 안 해 본 것을 했다고 쓰지 않는다.
  - 맨 끝에 `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

## 5. PR 메타데이터 (전부 채운다)

PR을 만든 직후 채운다. `gh pr create`에 `--assignee kwonskdev --label ...`를 같이 줘도 된다.


| 항목              | 규칙                                                                                                                            |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| **assignees**   | 항상 `kwonskdev`.                                                                                                               |
| **reviewers**   | 아래 "리뷰어 목록"의 모든 계정. `gh pr edit <PR> --add-reviewer <계정>`                                                                     |
| **labels**      | 처리한 이슈의 라벨을 그대로 붙이되 `epic`은 뺀다. 이슈에 없지만 PR에 필요하면 더한다 (예: 문서만 바꿨으면 `documentation`). 없는 라벨은 만들지 않는다.                           |
| **development** | 처리한 이슈를 연결한다. 본문에 `Closes #N` / `Refs #N`을 쓰고(위 4번), 이슈의 Development에 이 PR의 브랜치가 등록돼 있어야 한다(위 1번). 여러 이슈를 처리했으면 이슈마다 한 줄씩 쓴다. |


**리뷰어 목록**: `kwonskdev` (나중에 봇이나 다른 사람을 쓰게 되면 여기에 줄을 추가한다. 예: `@copilot`)

주의할 점 (실제로 확인한 것):

- **작성자 본인은 리뷰어로 지정할 수 없다.** PR 작성자가 `kwonskdev`이면 `--add-reviewer kwonskdev`는 오류 없이 끝나지만 실제로는 지정되지 않는다. 그래서 만든 뒤 반드시 `gh pr view <PR> --json reviewRequests`로 확인하고, 비어 있으면 "작성자 본인이라 리뷰어를 지정하지 못했다"고 보고한다. 억지로 다른 방법을 찾지 않는다. 봇/다른 계정이 리뷰어 목록에 있으면 그 계정은 지정된다.
- **development 연결은 API로 직접 만들 수 없다.** 닫기 키워드는 PR이 기본 브랜치(master)로 갈 때만 `closingIssuesReferences`에 잡힌다. `develop`이나 기능 브랜치로 가는 PR은 키워드를 써도 이 값이 비어 있고, 이슈에는 PR이 "언급됨(cross-reference)"으로만 남는다. 이 경우 `gh pr view <PR> --json closingIssuesReferences`가 `[]`이어도 정상이니, 보고에 "타겟이 기본 브랜치가 아니라 자동 연결/자동 종료는 안 된다"고 한 줄 적는다. GitHub 화면 Development에서 직접 연결하는 건 사용자가 할 일이다.

## 6. 마무리 확인과 보고

다음을 읽어서 확인하고 한 줄로 보고한다.

```
gh pr view [[ORCA_RICH_MD:9bfa38102279050a760fcba1883c10d4:inline-html:%3CPR%3E]] --repo <owner/repo> --json url,baseRefName,assignees,labels,reviewRequests,closingIssuesReferences
gh issue develop --list [[ORCA_RICH_MD:9bfa38102279050a760fcba1883c10d4:inline-html:%3CN%3E]] --repo <owner/repo>
```

- PR URL, 타겟 브랜치(규칙으로 정했다면 어떤 규칙인지), assignee, label, reviewer, 연결한 이슈, Development에 브랜치 등록 여부.
- 채우지 못한 항목은 이유와 함께 말한다.
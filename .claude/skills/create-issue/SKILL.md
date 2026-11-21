---
name: create-issue
description: "GitHub 이슈를 작성/등록/만들어 달라고 할 때 쓴다 ('이슈 만들어줘', '이슈로 정리해줘', '에픽 만들어줘' 등). 본문은 정해진 한국어 형식(문제 / 고치는 방법 / 정해야 할 것 / 확인 체크리스트, 에픽은 배경 / 목표 / 하위 이슈 ...)으로 쓰고, assignee, label, type, relationships(parent, blocked by), 이슈 필드(Priority, Effort 등)까지 채울 수 있는 건 전부 채운다."
---
# 이슈 작성

이슈는 아래 형식으로만 쓴다. 이 문서의 형식을 그대로 따른다. 본문은 한국어, 코드 위치는 `파일:줄`이나 ``Balance.gd`` 처럼 백틱으로 쓴다.

## 1. 제목

- **일반 이슈**: 한 문장. 문제 이슈는 현상으로, 기능 이슈는 하고 싶은 것으로 쓰고, 보충 설명은 끝에 괄호로 붙인다.
  - 예: `상단 UI에 타워/몬스터/업그레이드 탭을 항상 고정 (기본 화면은 타워)`, `타워를 팔 수 있어야 한다 (판매 기능 없음)`
- **에픽**: `[에픽 - 에픽 간단한 주제] 제목`. 예를 들어 멀티플레이 에픽은 `[에픽 - 멀티플레이] 협력 멀티 플레이 도입`
- **에픽의 하위 이슈**: `[에픽 간단한 주제 - N] 제목`. N은 기존 `[에픽 간단한 주제 - N]` 이슈 중 가장 큰 번호 + 1 (`gh issue list --search "[에픽 간단한 주제" --state all`로 확인). 예를 들어 `[멀티플레이 - 3] 멀티플레이를 위한 서버를 구현해야한다.`
- 제목에 이슈 번호, 날짜, 담당자를 쓰지 않는다.

## 2. 본문 (일반 이슈)

아래 네 섹션을 이 순서, 이 제목 그대로 모두 쓴다. 섹션을 빼거나 이름을 바꾸거나 다른 섹션을 더하지 않는다.

```
## 문제

현재 동작과 왜 문제인지. 코드를 먼저 읽고 실제 위치(`파일:줄`)와 수치를 적는다.
새 기능이면 "지금은 ~가 없다"로 시작한다. 재현 방법이 있으면 번호 목록으로 쓴다.

## 고치는 방법

1. 번호 목록. 무엇을 어디서 어떻게 바꾸는지 (`파일`, 함수 이름 포함).
2. 이슈를 처리하는 사람이 설계를 다시 하지 않아도 될 만큼 구체적으로.

## 정해야 할 것

- 아직 결정되지 않은 것을 한 줄씩. 사용자가 이미 정한 것은 여기 말고 "고치는 방법"에 "결정:"으로 쓴다.
- 없으면 `- 없음`이라고 쓴다.

## 확인 체크리스트

- [ ] 실행해서 확인할 수 있는 한 문장 하나당 한 항목. 모호한 표현(잘, 적당히)을 쓰지 않는다.
- [ ] 수치와 화면 동작은 기대 값을 적는다 (예: "체력 100/100에 강화 1중첩이면 105/105가 된다").
- [ ] 헤드리스 스모크 테스트가 통과한다.
```

- 체크리스트는 새 이슈에서는 전부 `- [ ]`로 쓴다. **마지막 항목은 항상** `- [ ] 헤드리스 스모크 테스트가 통과한다.`
- 사용자가 말한 요구, 제약, 결정은 하나도 빼먹지 않고 본문에 반영한다. 사용자가 말하지 않은 내용을 지어내지 않는다 (모르면 "정해야 할 것"에 쓴다).

## 3. 본문 (에픽)

에픽(여러 이슈를 묶는 상위 이슈)은 아래 다섯 섹션을 이 순서로 모두 쓴다.

```
## 배경

왜 이 묶음이 필요한지.

## 목표

- 이 묶음이 끝나면 달라져 있어야 하는 것을 한 줄씩.

## 하위 이슈

- [ ] #N 한 줄 요약
- [ ] #N 한 줄 요약

## 작업 순서와 의존

- 어떤 이슈가 어떤 이슈 뒤에 와야 하는지, 이유와 함께. 없으면 `- 순서 제한 없음`.

## 공통 확인

- [ ] 하위 이슈 전체를 마친 뒤에야 확인할 수 있는 것들.
- [ ] 헤드리스 스모크 테스트가 통과한다.
```

에픽을 먼저 만들고 하위 이슈를 나중에 만들면 "하위 이슈" 목록은 하위 이슈를 만든 뒤 본문을 수정해서 채운다 (`gh issue edit <N> --body-file`).

## 4. 메타데이터 (전부 채운다)


| 항목                        | 규칙                                                                                                    |
| ------------------------- | ----------------------------------------------------------------------------------------------------- |
| **assignee**              | 항상 `kwonskdev` (`--assignee kwonskdev`).                                                              |
| **label**                 | 아래 표에서 해당하는 것을 **모두** 붙인다. 하나도 안 붙이면 안 된다. 라벨 추가가 "꼭" 필요할 경우 추가해도 된다. 웬만하면 기존에 있는 라벨 중 제일 가까운 것을 고른다. |
| **type**                  | `Bug` / `Feature` / `Task` 중 하나 (아래 표).                                                               |
| **parent**                | 에픽에 속하는 이슈면 그 에픽을 상위 이슈로 지정한다 (`--parent <에픽 번호>`).                                                   |
| **blocked by / blocking** | 다른 이슈가 먼저 끝나야 하거나 다른 이슈를 막고 있으면 지정한다 (`--blocked-by`, `--blocking`).                                  |
| **fields**                | Priority, Effort는 항상 채운다. Start date, Target date는 날짜를 알 때만 (아래 5번 참고).                                          |
| **milestone**             | 열려 있는 마일스톤이 있고 이슈가 거기에 맞으면 지정한다 (`--milestone`). 없으면 비운다.                                             |


**라벨**


| 이슈 성격                          | 라벨              |
| ------------------------------ | --------------- |
| 잘못 동작하는 것을 고친다                 | `bug`           |
| 새 기능, 기존 기능 개선, UI/UX 개선, 리팩터링 | `enhancement`   |
| 밸런스 수치 조정                      | `balance`       |
| 문서, 설명서, 스토어 문구                | `documentation` |
| 멀티플레이 도입 작업                    | `multiplayer`   |
| 에픽                             | `epic`          |


(`enhancement`와 `balance`처럼 둘 이상 해당하면 모두 붙인다.)

**타입**


| 이슈 성격                             | 타입        |
| --------------------------------- | --------- |
| 버그 수정                             | `Bug`     |
| 새 기능, 기능/UI 개선 (라벨 `enhancement`) | `Feature` |
| 밸런스 조정, 리팩터링, 문서, 테스트, 에픽         | `Task`    |


**관계(parent) 찾기**

- 에픽 후보: `gh issue list --repo <owner/repo> --label epic --state open --json number,title`
- 이슈 내용이 어느 에픽에 속하는지 분명하면 지정한다. 여러 에픽에 걸치거나 모호하면 사용자에게 묻는다. 어느 에픽에도 안 속하면 parent 없이 만든다 (그러면 이후 PR의 타겟 브랜치는 `develop`이다. `create-pr` 스킬 참고).
- 선행 이슈 판단: 본문에 "~~가 먼저", "~~ 위에서", "~에 의존"이 있거나 같은 에픽의 앞 번호(`[주제 - N-1]`)가 결과를 만들어야 하는 경우.

## 5. 이슈 필드

프로젝트(GitHub Projects)는 쓰지 않는다. 이슈 자체의 필드만 채운다. 이 저장소의 이슈 필드는 다음과 같다.

| 필드 | 종류 | 값 | 채우는 규칙 |
|---|---|---|---|
| **Priority** | 단일 선택 | `Urgent` / `High` / `Medium` / `Low` | **항상 채운다.** `Urgent`: 게임이 멈추거나 크래시, 데이터가 틀어지는 버그. `High`: 핵심 흐름을 막는 버그, 에픽의 선행 이슈, 다른 이슈를 막고 있는 이슈. `Medium`: 일반 기능/개선/밸런스. `Low`: 사소한 다듬기, 있으면 좋은 것. |
| **Effort** | 단일 선택 | `High` / `Medium` / `Low` | **항상 채운다.** `Low`: 파일 1~2개, 한 곳만 고침. `Medium`: 여러 파일이나 한 시스템 안의 변경. `High`: 여러 시스템에 걸치거나 설계가 필요하거나 에픽 규모. |
| **Start date** | 날짜 | `YYYY-MM-DD` | 사용자가 날짜를 말했을 때만. 짐작해서 넣지 않는다. |
| **Target date** | 날짜 | `YYYY-MM-DD` | 사용자가 날짜를 말했을 때만. 짐작해서 넣지 않는다. |

Priority와 Effort는 내가 이슈 내용으로 판단한 값이다. 보고할 때 "Priority High, Effort Medium (판단 근거 한 줄)"로 알려서 사용자가 바로 고칠 수 있게 한다.

**설정 방법** (필드/옵션 ID는 저장소마다 다르니 매번 조회해서 쓴다. ID를 이 문서에 적어 두지 않는다):

1. 필드와 옵션 ID 조회:
   ```
   gh api graphql -f query='query($o:String!,$r:String!){repository(owner:$o,name:$r){issueFields(first:20){nodes{... on IssueFieldSingleSelect{id name options{id name}} ... on IssueFieldDate{id name}}}}}' -f o=<owner> -f r=<repo>
   ```
2. 이슈의 노드 ID 조회: `gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){id}}}' -f o=<owner> -f r=<repo> -F n=<번호> -q .data.repository.issue.id`
3. 한 번에 설정 (단일 선택은 `singleSelectOptionId`, 날짜는 `dateValue`):
   ```
   gh api graphql -f query='mutation($id:ID!,$p:ID!,$po:ID!,$e:ID!,$eo:ID!){setIssueFieldValue(input:{issueId:$id,issueFields:[{fieldId:$p,singleSelectOptionId:$po},{fieldId:$e,singleSelectOptionId:$eo}]}){issue{number}}}' -f id=<이슈 노드 ID> -f p=<Priority 필드 ID> -f po=<Priority 옵션 ID> -f e=<Effort 필드 ID> -f eo=<Effort 옵션 ID>
   ```
   날짜가 있으면 `{fieldId:$d,dateValue:"2026-12-01"}`를 `issueFields` 배열에 더한다.
4. 설정이 됐는지 `issueFieldValues`로 읽어서 확인한다 (아래 6번의 확인 쿼리에 포함).

## 6. 만드는 순서

1. 사용자 요구와 관련 코드를 읽는다 (문제 섹션의 코드 위치는 실제로 열어 보고 쓴다).
2. 본문을 스크래치패드 파일에 쓴다 (`--body-file`로 넘긴다).
3. 이슈를 만든다 (필드는 5번 방법으로 만든 직후 설정한다):
   ```
    gh issue create --repo <owner/repo> --title "<제목>" --body-file <본문 파일> \
      --assignee kwonskdev --label <라벨> [--label <라벨>] --type <Bug|Feature|Task> \
      [--parent <에픽 번호>] [--blocked-by <번호,번호>] [--blocking <번호>] \
      [--milestone "<이름>"]
   ```
4. 만든 뒤 GraphQL로 읽어서 빠진 것이 없는지 확인한다:
   ```
    gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n){number issueType{name} issueFieldValues(first:10){nodes{__typename ... on IssueFieldSingleSelectValue{field{... on IssueFieldSingleSelect{name}} name} ... on IssueFieldDateValue{field{... on IssueFieldDate{name}} value}}} assignees(first:3){nodes{login}} labels(first:10){nodes{name}} parent{number} blockedBy(first:10){nodes{number}} blocking(first:10){nodes{number}} subIssues(first:20){nodes{number}}}}}' -f o=<owner> -f r=<repo> -F n=<번호>
   ```
5. 에픽에 하위 이슈를 넣었거나 에픽이 새로 하위 이슈를 갖게 됐으면 에픽 본문의 "하위 이슈" 목록도 갱신한다.
6. 사용자에게 이슈 URL과 채운 메타데이터(assignee, label, type, parent, blocked by, Priority/Effort와 그 판단 근거)를 한 줄로 알린다. 채우지 못한 항목은 이유와 함께 말한다.

## 하지 말 것

- 사용자가 요청하지 않았는데 이슈를 만들지 않는다.
- 같은 내용의 이슈가 이미 있는지 먼저 `gh issue list --search "<키워드>" --state all`로 확인하고, 있으면 만들지 말고 알린다.
- 이슈를 만들면서 코드를 구현하지 않는다 (구현은 `handle-issue`).
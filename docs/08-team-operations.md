# 08. 팀 운영 절차

AGENTS.md에서 옮긴 긴 절차·관측 이력이다. 문장은 옮기기만 하고 바꾸지 않았다(#13). AGENTS.md와 같은 효력이며, 각 절 이름은 AGENTS.md의 절을 따른다.

## §1 팀 구성


### 팀원 복구 절차

(이 절의 「위 표」는 AGENTS.md §1 팀 구성 표다.)
- 구현 agy는 이전 대화를 `agy --conversation <id> --model gemini-4-argon-high --mode accept-edits --sandbox`(`scripts/team-up.sh --up <id>` — 대화 id는 `--check`의 cf-impl 줄 `대화=`에서 읽는다)로 잇는다(같은 id가 다른 pane에 살아 있으면 하지 않는다). critic은 요청마다 `/new`로 초기화하므로 이전 세션을 잇지 않고 `scripts/team-up.sh --up`으로 위 표의 명령 그대로 새로 띄운다 — `codex resume <id>`만으로 뜨면 기동 옵션(`--yolo`·추론 `high`)이 빠진다(2026-10-14 cf-lead 관측: herdr 재시작 뒤 복원된 critic). critic을 띄운 뒤와 `/new` 뒤에는 상태줄에 `high`, 시작 화면에 `permissions: YOLO mode`가 보이는지 확인하고, 아니면 idle일 때 `/quit` 후 `--up`으로 다시 띄운다. 외부 팀장은 Herdr 재시작을 화면으로 보지 못하므로, 감시가 팀원 `unnamed`·사라짐·예상 밖 상태로 끝나거나 herdr 명령이 실패해도 바로 점검한다.

### 부팀장 `cf-vice` 행(선택 역할 — 지금 없음)

| 이름 | 실행 | 맡는 일 | 하지 않는 일 |
|---|---|---|---|
| `cf-vice` 부팀장 (Claude Code) | (선택 역할 — 없으면 팀장이 혼자 운영한다) `claude` (opus) — Herdr 안 팀 작업공간 pane(label `CF 부팀장 · Claude`, `CF_EXTERNAL_LEAD` 없음) | 팀원 화면·상태의 읽기 전용 감시, 팀장의 배정·재검증·커밋·푸시의 독립 재확인, 팀장 초안 검토 의견, 이상을 팀장에게 세션 간 메시지로 알림, `cf-work/issues/<번호>/vice/`에 감시 기록·검토 문서 쓰기 | 팀원에게 입력(prompt·키·rename), 확인창 응답, 바꾸는 `team-up.sh` 모드(Herdr 재시작·재부팅 뒤 팀원 복구 `--up`(대화 id를 주는 꼴 포함) — 팀장만 한다), 저장소 쓰기·커밋·푸시, 사용자 승인 전달·대행, `vice/` 밖 쓰기, 다른 팀과 직접 소통(팀장이 CF 사용자 지시에 따라 요청한 경우만) |

## §5 전달 방법


### 입력란 판독 세부

- Codex는 `›` 행, agy는 구분선 사이 `>` 행이며, 흐린 글씨(SGR 2) 추천 문구는 빈 것이다. 글이 있으면 사람이 치는 중이니 10초쯤 기다렸다 다시 보고, 1분이 지나도 차 있거나 확인할 수 없으면 보내지 말고 자기 창에 한 줄로 남긴다(받는 쪽이 읽어 간다). 입력란은 보내기 직전에 보고, 확인한 뒤 바로 보낸다. 입력란 모양을 모르는 화면(새 버전·잘린 화면 등)은 「확인할 수 없음」으로 보고 비어 있다고 추정하지 않는다.

### `focused`는 전송 조건이 아님

- herdr `focused`는 전송 조건으로 쓰지 않는다 — 작업공간마다 늘 하나씩 있는 서버 상태라 사람이 보고 있다는 뜻이 아니다(2026-10-17 관측: 사용자가 다른 작업공간에 있는 동안에도 팀원 pane이 `focused: true`).

### 우편함과 재부팅

- /tmp는 재부팅이나 시스템 정리로 지워질 수 있다. 팀장은 판정 때마다 옮긴다(§9). 재부팅 뒤에는 팀장이 팀원 화면과 열린 작업 이슈(마지막 코멘트)로 상태를 다시 맞추고, 필요한 보고는 다시 요청한다.

### critic 초기화(/new)·이름 재등록 절차

- critic이 idle이고 입력란이 비었는지 확인하고 `herdr pane send-text <critic pane> "/new"` + `herdr pane send-keys <critic pane> enter`를 보낸다. worktree 선택 등 대화상자가 뜨면(기동 명령의 `--disable worktrees`로 worktree 선택창은 뜨지 않는 것이 정상이다 — 사용자 승인 2026-10-14) 요청을 보내지 않고 lead에 `BLOCKER` — lead가 `Use current Git worktree`를 1회 선택하고, 새 worktree는 만들지 않는다. 새 대화의 입력란이 비었고 `herdr agent list`에서 `cf-critic`이 그 pane을 가리킬 때 `herdr agent prompt cf-critic "<메시지>"`를 보낸다. 2026-10-11 cf-lead는 `/new` 뒤 첫 입력이 들어갈 때 agent 세션 id가 바뀌고 이름 등록이 풀린 사례를 관측했다: 보낸 뒤 `herdr agent list`에서 `cf-critic`이 그 pane을 가리키지 않으면, 다른 pane이 그 이름을 쓰지 않음을 확인한 뒤 `herdr agent rename <critic pane> cf-critic`으로 다시 등록하고 `herdr agent get cf-critic`으로 확인한다. 보내기 전이나 뒤에 준비 상태·이름을 확인할 수 없으면 lead에 `BLOCKER`.

### agy 확인창 예외(Context7)·sandbox 밖 명령

- 예외: Context7 읽기 전용 두 도구(서버 `context7`의 `resolve-library-id`·`query-docs`)는 3번으로 영구 허용한다(사용자 승인 2026-10-16 「1. 둘다 승인, 2. 합니다. 3. 네」). 확인창의 서버·도구 이름이 정확히 이 둘일 때만 3번을 고르고, 같은 도구 이름의 다른 서버(예: `wf3-code-research_context7`)와 그 밖의 MCP 도구는 이름과 인자를 읽고 1번으로 답한다. sandbox 밖이 필요한 명령(예: `/opt/local/bin/bash` 테스트)은 1회 허용으로 처리하고, sandbox 안에서 도는 경로(`/bin/bash`)가 있으면 그쪽을 쓴다.

### 확인창 펼쳐 읽기(ctrl+g·Page Down)·zoom 금지

(아래 「위 「확인창이 떠 있으면 보내지 않는다」」·「위 「포커스는 옮기지 않는다」」는 AGENTS.md §5 「보내기 전에 받는 쪽 입력란을 본다」 항목을 가리킨다.)
- 확인창 내용이 잘려 보이면 팀장은 zoom 없이 펼친다: `herdr pane send-keys <pane> ctrl+g`(agy 명령 확인창) 뒤 `herdr pane read <pane> --source visible`로 화면에 「Full Command」가 보이는지 확인하고 읽는다. 표시가 `(a–b of N lines)`이고 b가 N보다 작으면 `herdr pane send-text <pane> $'\e[6~'`(Page Down — herdr `send-keys`에는 이 키 이름이 없다. `$'…'`를 해석하는 bash·zsh에서)를 보내고 다시 읽기를 b가 N이 될 때까지 되풀이한 뒤 `esc`. Page Down과 `esc`는 펼친 화면(「Full Command」)이 보일 때만 보낸다 — 안 보이면 더 보내지 않고 사용자에게 알린다(선택 메뉴에서는 Page Down이 커서를 마지막 항목으로, `esc`가 확인창 취소로 이어질 수 있다). 답하기 전에 원래 확인창으로 돌아왔고 커서가 1번에 있는지 `pane read`로 확인한다. MCP 도구 확인창의 `ctrl+o` 펼침은 같은 방식으로 시도하되 미시험이라, 펼쳐지지 않으면 사용자에게 알린다. 위 「확인창이 떠 있으면 보내지 않는다」의 예외는 이렇게 팀장이 확인창을 읽고 답하려고 보내는 키뿐이다. `herdr pane zoom`은 쓰지 않는다 — 그 pane으로 포커스를 옮긴다(2026-10-17 관측; 위 「포커스는 옮기지 않는다」와 어긋난다).

### 부팀장이 있을 때

- 부팀장이 있을 때: 팀장과 부팀장은 Claude 세션 간 메시지(`SendMessage`·`ListAgents`)로 연락한다. 부팀장의 메시지는 사용자 승인이 아니다(권위 1). 부팀장 pane에서 돌린 `scripts/team-up.sh` 점검은 Herdr 모드라 lead 행이 `cf-lead` 없음으로 나오고 종료 코드가 1이다(`scripts/team-up.sh` classify_all·all_alive) — 부팀장은 팀원 행과 `↳ 옵션` 줄만 본다. 부팀장 pane의 `/clear`는 SessionStart 훅(`--hook-clear`)이 label 불일치로 아무것도 하지 않고 실패로 끝나며 `cf-vice` 이름이 풀릴 수 있다 — 팀장이 `herdr agent rename <pane> cf-vice`로 다시 붙인다. Herdr 재시작·재부팅 뒤 팀원 복구(`--up`, 대화 id를 주는 꼴 포함)는 팀장만 한다 — 부팀장 pane에서 `--up`을 돌리면 그 pane을 `cf-lead`로 다시 잡아 팀장이 둘이 된다(`secure_lead`). 부팀장은 점검 결과를 팀장에게 알리기만 한다.

## §6 일하는 방식


### Context7 세부

  - 우선순위: 이 머신의 `--help`·소스·실측이 먼저이고 Context7은 그다음 근거다. 둘이 다르면 로컬을 따르고 차이를 결과 파일에 적는다.
  - 기록: 결과(REPORT·VERDICT·ANSWER)에 라이브러리 ID와 확인 내용을 짧게 적는다. 버전·날짜가 없으면 「버전·날짜 미제공」, 없는 라이브러리는 「Context7 미수록」으로 적는다. 핵심 근거는 기존 규칙대로 cf-lead가 대조한다.
  - 쓸 수 없을 때(도구 미노출·sandbox·연결 실패): 우회하거나 설정을 바꾸지 않는다. 사유를 적고 로컬 근거로 진행한다.

## §7 팀장의 감시와 개입


### 되돌리기(외부 팀장 → Herdr 안 팀장)

- **되돌리기(외부 팀장 → Herdr 안 팀장)**: 외부 팀장이 팀원 입력을 멈추고 → 사용자가 데스크톱 로컬 환경에서 `CF_EXTERNAL_LEAD`를 빼고 `.local/team/external-lead`를 지운 뒤 외부 팀장 세션을 닫고 → 부팀장 pane(없으면 팀 작업공간에 pane을 열어 `claude`를 띄운 pane)에서 `scripts/team-up.sh --up`(이 pane을 `cf-lead`로, label `CF 팀장 · Claude` — 배치까지 맞춘다).

### 부팀장이 없을 때의 독립 재확인(D5)

- **부팀장이 없을 때의 독립 재확인**(D5, 사용자 결정 2026-10-18): 규칙 변경과 커밋은 지금처럼 critic 리뷰를 받는다. 공개 게시와 푸시 뒤에는 팀장이 원격 결과(`gh issue view`·`git ls-remote` 등)를 다시 읽어 초안 파일·해시와 대조한다. 닫기 코멘트에는 팀장이 직접 돌린 결과만 쓰고, 팀원 보고만 있는 것은 「미확인」으로 적는다. 부팀장이 하던 실시간 감시는 팀장 백그라운드 감시(`scripts/team-watch.sh`, 상태 심장박동)가 맡고, `team-watch.sh`가 보지 않는 것(배치 모양, 이슈 상태, GitHub 원격 자체 — 로컬 `origin/main` 추적 ref만 본다, 저장소 밖 파일)은 팀장이 사건 단위로 직접 다시 읽는다.

## §9 작업 파일·데이터 운영


### 하위 구조

- **하위 구조**: `issues/<번호>/`(회차는 `r<N>/`), `misc/<주제>-<YYYY-MM-DD>/`, `handoff/<YYYY-MM-DD>-<주제>.md`, `tools/`, `research/`, `archive/`, `discarded/`.

### `/tmp` — 동결 사본·우편함·전환 중

  - 리뷰 동결 사본: `mktemp -d /tmp/cf-<회차ID>-review.XXXXXX`처럼 절대 경로 템플릿으로 만든다. `-t`는 쓰지 않는다.
  - cf-impl 셸용 입력 사본함 `/tmp/cf-<회차ID>/`
    - 회차ID는 `i<번호>-r<N>`이고 회차마다 새로 만든다.
    - `mkdir -m 700`으로 만들고 소유자를 확인한다.
    - 팀원 보고는 여기 두지 않고 `cf-work/issues/<번호>/<회차>/to-lead/`에 파일 도구로 쓴다(AGENTS.md §5·§9). `<회차>`는 회차ID 끝의 `r<N>`·`d<N>`·`c<N>`이다. 순번 확인도 파일 도구로 한다(cf-impl 셸은 cf-work를 읽지 못한다).
  - **전환 중**: `scripts/team-watch.sh`가 공통 꼴로 바뀔 때까지는 지금 이름(`cf-<회차ID>`, `cf-<회차ID>-review`)을 쓴다.

### 이관 — 세부

  - 동결 사본에서는 요청서·판정서·시험 로그만 옮기고 저장소 복사본(repo/)은 뺀다.
  - 옮기기 전과 뒤에 manifest(`상대경로<TAB>크기<TAB>sha256`, 파일 `MANIFEST.tsv`)를 재서 대조한다. 원본은 두고, 이관 명령 자신의 출력은 대상에서 뺀다.
  - 이슈를 닫을 때는 그 이슈 폴더가 완결됐는지 점검하고, 닫는 코멘트에 manifest의 sha256 앞 16자를 적는다.

### 버리기 — discarded 비우기

  - `discarded/`는 30일 뒤 비울지 사용자에게 묻는다. 닫힌 이슈 기록은 남긴다.

### 인계·결정 기록

- **인계·결정 기록**
  - 인계 문서는 `cf-work/handoff/`에 둔다.
  - 사용자 결정은 결정 기록 파일에 물은 선택지·원문·팀장 해석과 함께 적는다.
  - 대화에만 있는 결정은 없는 것으로 본다.
  - Claude 메모리는 운영 사실용이고 증거·작업 파일은 두지 않는다.

## 안전


### agy 전역 설정 바꾸는 순서

- 바꿀 때는 ① 변경 주체가 다른 팀장에게 미리 알리고 ② 각 팀장이 자기 agy만 종료했음을 확인한 뒤 ③ 변경 주체가 그 키만 백업·변경하고 ④ 각 팀이 다시 띄운 뒤 ⑤ 마지막 재기동이 끝나면 변경 주체가 값을 다시 읽어 공유한다(다른 팀 agy는 그 팀장이 끄고 띄운다).

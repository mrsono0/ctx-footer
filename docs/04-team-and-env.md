# 04. herdr 기반 에이전트 팀 구성과 환경 구축

lectureforge-infra(LFI) 팀 운영에서 검증한 것을 그대로 옮기고, 이 프로젝트 크기(모듈 1개)에 맞게 줄인다.

## 1. 팀 (상주 3석, 조사는 cf-critic)
| 이름 | 역할 | 실행 | 권한 |
|---|---|---|---|
| `cf-lead` | 팀장 (Claude Code) | `claude --name cf-lead --permission-mode auto` — 공용 herdr-core(Core) 터미널 `cf-lead`(탑주가 명부 「Core 길」 명령으로 띄움, `env CF_EXTERNAL_LEAD=1`) — 사용자 결정 2026-11-09. M5 이동 전까지는 데스크톱 외부 팀장 세션(2026-10-17 꼴). 되돌리면 데스크톱 또는 Herdr 안 pane(§7) | 추적 파일 내용을 편집·커밋하지 않는다(예외: `i<번호>` 생성·삭제, `main`↔`i<번호>` 전환, `main`으로 `merge --ff-only`, 작업 뿌리 `cf-work/` 쓰기와 이관(AGENTS.md §9). 그 밖의 git 쓰기는 하지 않는다). 배정·이슈 관리(AGENTS.md §8)·사용자 승인·최종 확인 |
| `cf-vice` | 부팀장 (Claude Code, 선택 — 없으면 팀장이 혼자 운영한다) | `claude` (opus) — Herdr 안 팀 작업공간 pane(label `CF 부팀장 · Claude`) | 저장소 파일을 쓰지 않고 팀원에게 입력하지 않는다. 읽기 전용 감시·독립 재확인·초안 검토 의견, 팀장과 세션 간 메시지(AGENTS.md §1·§5) |
| `cf-impl` | 구현 (agy) | `agy --model gemini-4-argon-high --mode accept-edits --sandbox` | **유일한 쓰기·커밋 담당**(sandbox 켬, 전역 `toolPermission` `proceed-in-sandbox`, 2026-10-15 교체 승인 — 이전 GJC `gjc --mpreset opus5-codex56-pro`) |
| `cf-critic` | 비판적 검토 + 조사(웹 검색) (Codex) | `codex --search --yolo --disable worktrees --disable memories -m gpt-6.1-sol -c model_reasoning_effort="high"` | 샌드박스·승인 없음(--yolo, 사용자 결정). 저장소 쓰기·커밋은 하지 않는다. 판정 담당(구현자와 다른 모델 계열). 자기가 조사한 사실은 판정하지 않는다(cf-lead가 원문 대조) |

- 근거: 사용자 결정(2026-10-11, lfi-lead 경유). LFI 조사 비교에서 Codex 계열이 가장 빨랐다(24~117초). 긴 조사에서 지어낸 인용 1건이 있어 critic 조사 인용은 cf-lead가 원문과 대조한다.
- 상주 scout가 필요해지면 4석째 `cf-scout`(GJC kimi3)를 추가한다(스크립트에 자리만 비워 둔다).

## 2. 작업공간 배치
- herdr 새 작업공간 `ctx-footer`(LFI의 wH와 분리). cwd = 이 저장소 루트.
- 팀장 세션은 하나다: Core 터미널 `cf-lead` 하나(M5 이동 전까지는 데스크톱 외부 팀장 세션 하나 — 넘기는 순서는 `.claude/rules/lead-operations.md` 「잠금 인수 순서」). 팀원은 `cf-impl`·`cf-critic`(이동 전 TUI pane, 이동 뒤 Core 터미널). 팀원에게 입력하는 것은 팀장뿐이다. 데스크톱 외부 팀장·Herdr 안 팀장 형태는 되돌리기 때 쓴다. `CF_EXTERNAL_LEAD=1`이 없는 Herdr 밖 Claude 세션은 팀원에게 어떤 입력도 하지 않는다. agent 이름은 전역이라 접두어 `cf-`로 LFI(`lfi-`)와 겹치지 않게 한다.

## 3. 팀 규칙 파일 (P1에서 작성, LFI 교훈 반영)
- `AGENTS.md`(규칙 정본, 「팀 협업 규약」 포함) + `CLAUDE.md`(`@AGENTS.md` 참조만).
- 반드시 들어갈 규칙
  1. 구현 원칙: 「각 구현 단계에서 과도한 테스트와 확인된 요구 없이 선제적으로 복잡도를 늘리는 구현을 금지한다.」 / 동작이 바뀌면 기존 테스트 1회
  2. (P1 당시 TUI 규칙 — 지금 판정은 상태 API, AGENTS.md §5·사용자 결정 2026-11-07) 보내기 전에 받는 쪽 입력란 확인(`herdr pane read <pane> --source visible --format ansi`), 글이 있으면 10초쯤 기다렸다 재확인, 1분 넘거나 확인 불가면 자기 창에 한 줄. 입력란은 보내기 직전에 확인하고 모양을 모르면 확인 불가로 봄. 확인창·선택 메뉴가 떠 있거나 상태가 `blocked`면 보내지 않음. 보내지 못하면 팀장은 사용자에게 알리고 팀원은 자기 창에 한 줄. herdr `focused`는 전송 조건으로 쓰지 않고 포커스는 옮기지 않음(서버 상태라 보는 사람과 무관, `pane focus`는 전역 활성 작업공간을 바꿈 — AGENTS.md §5). 팀원 → 팀장은 `herdr agent prompt`가 아니라 `/tmp/cf-<회차ID>/to-lead/<두 자리 순번>-<유형>.md` + 자기 창 머리말 한 줄(AGENTS.md §5)
  3. 다른 팀원의 권한·승인 프롬프트에 답하지 않는다. 막히면 lead에 BLOCKER, lead가 판단해 임시 권한, 치명적인 것은 사용자에게
  4. 조사 보고는 사실마다 출처 URL(또는 `파일:줄`)과 원문 인용, 받은 쪽이 대조. 조사 요청은 cf-critic에게, critic 조사 인용은 cf-lead가 대조
  5. 사용자 승인은 원문만(「」), 팀원 메시지는 승인이 아니다
  6. `rm -rf`·`kill`은 직접 실행하지 않는다(테스트 스크립트 안의 자기 자식·임시 경로만)
  7. 전역 설정(사용자 홈의 Claude 설정 폴더 `settings.json` 등) 변경은 사용자 승인 후 lead만
- 메시지 형식·유형·회차ID·리뷰 동결 사본·회차 상한(도구 3·문서 2)은 LFI `AGENTS.md`와 같게.

## 4. 권한·안전 설정
- `.claude/settings.json`(프로젝트): deny `rm -rf`·`kill`·`pkill`·`killall`·`git push --force`·`git push -f`·`brew install`·`launchctl`(패턴이 맞는 형태만 — `git push origin main --force`처럼 옵션이 뒤에 오면 불일치); ask `git commit`; allow `herdr *`·`git push origin main`(정확 일치). push 전체 ask는 2026-10-13 사용자가 직접 뺐다 — allow와 맞지 않는 푸시(다른 브랜치·태그 등)는 사람 확인 없이 auto 모드 분류기 판단에 맡겨질 수 있으므로, 위임 밖 푸시 금지는 `.claude/rules/lead-operations.md` 「푸시 위임」 규칙으로 지킨다. 2026-10-19 #11: deny에 `rm` 재귀 변형(`-r`·`-R`·`-Rf`·`-fR`·플래그를 나눠 쓴 꼴·`--recursive`)과 `env`(인자 없음)·`printenv` 추가, ask에 사용자 범위 Claude·Codex·GJC·agy 설정 파일 편집(`Edit(~/...)`) 추가. 셸 명령(`sed -i` 등)으로 고치는 것은 이 규칙이 잡지 못한다 — AGENTS.md 「전역 설정」 규칙으로 지킨다. auto 권한 모드 세션에서는 `Edit(~/.gjc/**)` ask가 확인창 없이 통과했다(#11 실측 — 원인이 auto 모드의 자동 판단인지 경로 불일치인지는 미확인). ask는 사람 확인을 보장하지 않는 보조 장치로 보고, 전역 설정 편집 금지는 AGENTS.md 「전역 설정」 규칙으로 지킨다.
- `.codex/rules/herdr.rules`: `herdr agent prompt`, `herdr pane send-text/send-keys`, `herdr agent list`, `herdr pane read`만 허용(LFI와 같은 4개) — critic이 --yolo로 뜰 때는 쓰이지 않는 예비 규칙.
- `.codex/config.toml`: `project_doc_max_bytes = 65536` 하나만 둔다 — AGENTS.md가 Codex 기본 32 KiB에서 잘리지 않게(#12). 저장소가 Codex에서 신뢰된 프로젝트일 때만 적용된다.
- 도구별 지시 파일 자리(#15): Claude 전용 `.claude/rules/*.md`(머리말 없으면 시작 때 실림 — 지금 `lead-operations.md`), agy 전용 `.agents/rules/*.md`(올바른 `trigger` 머리말 필수 — 늘 실리게 하려면 `trigger: always_on`, 파일마다 24,000바이트), Codex 전용 `.codex/config.toml`의 `developer_instructions`(실측 전, 지금 안 씀). 공통 규칙은 `AGENTS.md`이고 agy 때문에 24,000바이트 아래로 둔다.

## 5. 환경 구축 스크립트 `scripts/team-up.sh`
LFI `scripts/team-up.sh`(점검/`--up`/`--resume-impl`, 80개 모의 테스트)를 가져와 **변수만** 바꾼다.
| 변수 | 값 |
|---|---|
| `SEAT_NAME` | `cf-lead cf-impl cf-critic` (scout 자리는 빈 값으로 둠) |
| `SEAT_KIND` | `claude agy codex` |
| `SEAT_LABEL` | `CF 팀장 · Claude` / `CF 구현 · agy` / `CF 검토 · Codex` |
| `IMPL_MODEL` | `gemini-4-argon-high` |
| 저장소 루트 | 스크립트 위치 기준 |
- 하위 명령(마탑 공통 이름·하위 명령, #16):

| 호출 | 동작 | 바꾸는 것 |
|---|---|---|
| (인자 없음), `--check` | 점검(기본 — 시작·재개 시 먼저 실행). 세 석 상태 표 + 표 아래에 팀원마다 공통 한 줄(`<이름> <pane> ok` / `<이름> <pane> mismatch 실제=<실제 옵션 요약> 기대=<기대 옵션 요약>` / `<이름> <pane\|-> unknown <사유>`, `cf-impl`은 herdr 메타데이터에 agy 대화 id가 보이면 줄 끝에 ` 대화=<id>` 추가). 모두 살아 있고 팀원 옵션 일치면 종료 0, 아니면 1 | 없음 |
| `--up [<agy 대화 id>]` | 빠진 팀원 띄우기·이름·label 확보 후 마지막에 배치 보정(Herdr 안 팀장은 세 석 배치·비율, 외부 팀장은 `impl\|critic` 좌우 비율만. 팀원이 다 맞으면 배치만 함). `cf-impl`이 빈 셸·missing일 때 `<agy 대화 id>`를 주면 `--conversation <id>`로 복구(같은 id가 살아 있으면 거부), id가 없으면 새 대화로 띄우고 `대화 id 없음 — 새 대화로 띄움` 한 줄 경고. 팀원이 살아 있는데 옵션이 어긋나면 건드리지 않고 한 줄 안내(`<이름> 옵션 불일치 — idle일 때 /quit 뒤 scripts/team-up.sh --up [<대화 id>]`), 확인창에 답하지 않음 | 팀원 기동·배치 |
| `--status [<계기>]` | 마탑 가이드 §3 보고 꼴(팀장 세션·잠금, 팀원 옵션·확인창·상태, 저장소 브랜치·작업 트리, 감시·띄운 것·잃은 것·미확인) 출력 | 없음 |
| `--lock status` | 외부 팀장 전용(`CF_EXTERNAL_LEAD=1`, 아니면 종료 2): 잠금 판정 한 줄(`none`\|`mine`\|`other live`\|`stale`\|`unknown`; 같은 프로세스가 `/clear` 뒤 새 세션 id가 된 경우도 파일 무변경으로 `other live`) | 없음 |
| `--lock claim [--force]` | 외부 팀장 전용(`CF_EXTERNAL_LEAD=1`): `.local/team/external-lead`를 이 세션으로 잡는다(`none`·`stale`은 기록 후 종료 0, `mine`은 그대로 종료 0, `other live` 중 기록된 프로세스(`<pid><TAB><lstart>`)가 이 세션 조상 Claude 프로세스와 `pid`·`lstart` 모두 일치하면 `--force` 없이도 새 세션 id로 기록을 넘기고 한 줄 안내 후 종료 0, 그 밖의 `other live`·`unknown`은 `--force` 없으면 하지 않고 종료 3, `--force`면 기록 후 종료 0) | 기록 |
| `--lock release` | 외부 팀장 전용(`CF_EXTERNAL_LEAD=1`): 기록이 `mine`일 때만 지우고 종료 0(`none`은 아무것도 안 하고 종료 0, 그 밖은 하지 않고 종료 3) | 기록 |
| `--hook`, `--hook-clear`(별칭) | `.claude/settings.json` SessionStart `clear` 훅 전용: 팀장 Claude가 `/clear`로 세션 id가 바뀌어 Herdr 이름을 잃으면, label `CF 팀장 · Claude` pane에서 새 세션 id가 보일 때까지 기다린 뒤 `cf-lead`를 다시 붙인다(외부 모드에서는 즉시 0 종료, 다른 pane 소유면 건드리지 않음, stdout 없음, 백그라운드) | 팀장 이름·label |
| `--resume-impl`, `--layout`, `--claim-external` | 없앰 — 새 이름 안내와 사용법을 내고 종료 2 | 없음 |
| `scripts/team-core.sh` (인자 없음, `--check`) | Herdr Core(`hc`, `HC_BIN` 재정의 가능) 외부 팀장 전용(`CF_EXTERNAL_LEAD=1`, `HERDR_PANE_ID` 비어 있음): `hc get cf-impl --json`·`hc get cf-critic --json`으로 `state=="live"`·최상위 `argv` 옵션 일치 점검 및 팀원별 요약 줄 출력(`cf-impl`은 `--conversation <id>`가 있으면 ` 대화=<id>` 추가; 외부 팀장 기록이 다른 세션 id이면서 같은 프로세스(`pid`·`lstart` 일치, `/clear` 뒤)이면 파일을 바꾸지 않고 표에 한 줄 표시). 모두 살아 있고 옵션 일치면 종료 0, 아니면 1 | 없음 |
| `scripts/team-core.sh --up [<agy 대화 id>]` | Core 외부 팀장 전용: 외부 팀장 기록이 다른 세션 id이더라도 기록된 프로세스(`<pid><TAB><lstart>`)가 이 세션 조상 Claude 프로세스와 `pid`·`lstart` 모두 일치하면 잠금 기록을 새 세션 id로 넘기고 한 줄 안내 후 진행하며(다른 프로세스·판정 불가는 거부), 빠진 팀원 석만 `hc run --bg --json --no-parent --outlive-parent --name <이름> --cwd "$ROOT" --label team=cf --label role=<역할> [--label "herdr.space=$CF_HERDR_SPACE"] -- <명령...>`으로 기동(`CF_HERDR_SPACE`가 비어 있지 않을 때만 `--label herdr.space=$CF_HERDR_SPACE`를 기존 라벨 뒤에 덧붙이고 `--check` 표에 `herdr.space` 칸으로 표시하되 옵션 불일치 판정에는 넣지 않음; `herdr.tab` 미부착. 또한 `CF_HERDR_SPACE`가 비어 있지 않을 때만 `hc run` 성공 직후 `herdr-app ls`(`HERDR_APP_BIN` 재정의 가능)를 상한 안에서 다시 확인해 공간 id가 `$CF_HERDR_SPACE`인 탭 중 `terminals`가 새 주소 하나뿐인 탭을 찾으면 `herdr-app do tab.rename --id <탭 id> --name <이름>`으로 탭 이름을 붙이고, App 부재·실패·탭 미발견·다른 터미널과 같은 탭이면 한 줄 경고만 내고 기동은 성공 유지, 포커스·선택 변경 없음. 살아 있는 석은 다시 만들지 않고 옵션 불일치 시 한 줄 안내만, 살아 있는 같은 이름에 `hc run`이 거부하면 그대로 보고 후 비0 종료). `cf-impl`이 빠졌을 때 `<agy 대화 id>`가 있으면 `--conversation <id>`를 넘기고, 없으면 `대화 id 없음 — 새 대화로 띄움` 한 줄 경고 | 팀원 기동·App 탭 이름·잠금 기록(같은 프로세스 넘김 시) |
| `scripts/team-core.sh --status [<계기>]` | Core 외부 팀장 전용: 마탑 가이드 §3 보고 꼴(팀장 세션·잠금(`none`\|`mine`\|`other live`\|`stale`\|`unknown`, 파일 무변경), 팀원 `address`·옵션·확인창·`status.state`, 저장소 브랜치·작업 트리, 감시·띄운 것·잃은 것·미확인) 출력 | 없음 |
| `scripts/team-core.sh --down <이름>` | Core 외부 팀장 전용(`cf-impl` 또는 `cf-critic`): 외부 팀장 기록이 다른 세션 id이더라도 기록된 프로세스(`<pid><TAB><lstart>`)가 이 세션 조상 Claude 프로세스와 `pid`·`lstart` 모두 일치하면 잠금 기록을 새 세션 id로 넘기고 한 줄 안내 후 진행하며(다른 프로세스·판정 불가는 거부), `status.state`가 `idle`·`done`일 때만 `hc kill <이름> --json` → `hc rm <이름> --json` 실행(`working`·`blocked`면 거부) | 팀원 종료·정리·잠금 기록(같은 프로세스 넘김 시) |
| `scripts/core-watch.sh --watch <회차 폴더> [--max <초>] [--interval <초>]` | Core 감시(기본 10초 간격, 화면 읽기 0회): `<회차 폴더>/to-lead/`의 새 `*(REPORT\|BLOCKER\|ASK\|NEED)*` 파일, 팀원 `state != "live"` 또는 `status.state == "error"`, `status.state == "blocked"`(`status.msg` 원문 출력), `--max` 타임아웃 감지 후 종료 0 | 없음 |
| `scripts/core-watch.sh --approve-once <이름> [--allow-file <경로>]` | Core 확인창 1회 허용: 명령을 파싱(하위 명령·옵션·basename)하지 않고, `status.state == "blocked"`이고 회차 지시서가 주는 허용 파일(`--allow-file <경로>`, 한 줄에 명령 한 줄)의 줄과 `status.msg`의 명령 전체(개행 포함 원문)가 바이트 그대로 일치할 때만 `hc keys <이름> enter --json`(1번) 전송. 허용 파일이 없거나 비어 있거나, `status.msg` 누락·공백/옵션/경로/접두어/결합 옵션/여러 줄 변형 등 바이트 불일치 시 키 미전송·`EVENT blocked-unhandled` 출력 후 비0 종료 | 확인창 1번 응답 |
| `scripts/core-watch.sh --send <이름> <메시지>` | Core 팀원 전송: `status.state`가 `idle`이면 `hc send --if idle <이름> <메시지>`, `done`이면 방금 확인 직후 `hc send <이름> <메시지>`, `blocked`·`working`이면 보내지 않고 `EVENT send-refused` 출력 후 비0 종료 | 팀원 메시지 전송 |
| `scripts/core-watch.sh --critic-new` | Core `cf-critic` 문맥 초기화: `idle`·`done` 확인 후 `hc keys cf-critic / n e w` 다음 `hc keys cf-critic enter`로 `/new` 전송(Core 터미널 안 `hc send`는 태그로 감싸져 슬래시 명령이 실행되지 않으므로 `keys` 사용) → 짧게 기다려 `hc get` → `status.state == "idle"`이고 `turn`이 늘지 않았으면(Codex worktree 선택창) `hc keys cf-critic enter` 1회 전송 → 다시 `hc get`으로 `status.state == "idle"` 및 `turn` 증가 확인(이미 `turn`이 늘었으면 추가 `enter` 미전송, `blocked`·`working`·사라짐·`turn` 미증가 지속은 비0 종료, Core에서는 이름이 유지되므로 `rename` 없음) | critic `/new` |

- 외부 팀장 모드: `CF_EXTERNAL_LEAD=1`이고 `HERDR_PANE_ID`가 비어 있을 때 동작(`HERDR_PANE_ID`가 있으면 거부). 연결 worktree(`git rev-parse --git-dir` ≠ `--git-common-dir` 또는 `/.claude/worktrees/` 경로)와 `CLAUDE_CODE_SESSION_ID` 누락을 차단하고, 바꾸는 모드(`--up`)는 `.local/team/external-lead`에 세션 id를 배타 생성·대조해 다른 세션의 중복 조작을 막는다(옛 주인이 끝났음이 확인되면 자동 회수하고, 살아 있거나 판정 불가면 사용자 승인 뒤 `--lock claim --force`로 넘긴다). 작업공간은 팀원 석 pane에서 찾고, lead 행은 `external(이 세션)`으로 표시하며(Herdr 안 `cf-lead`가 살아 있으면 경고 줄 추가), 배치는 같은 탭에 좌우로 붙은 `impl|critic` 비율(`0.5 ± 0.01`)만 맞춘다. Herdr 안 팀장으로 되돌릴 때는 외부 팀장 입력을 멈추고 `--lock release`(또는 사용자가 `.local/team/external-lead` 삭제)·로컬 환경 `CF_EXTERNAL_LEAD` 제거·외부 세션 종료 뒤 팀 작업공간 새 pane에서 `claude` 기동 → `scripts/team-up.sh --up`을 실행한다. Core 팀장 터미널은 띄우는 명령의 `env CF_EXTERNAL_LEAD=1`로 같은 모드에 들어오며(Core 터미널에는 `HERDR_*` 변수가 없다 — #28 M1), 거기서는 `--lock` 명령만 쓰고 팀원 기동·점검은 `scripts/team-core.sh`(M3, 아래 표)로 한다.
- 테스트: `ci/test-team-up.sh` + `ci/mock/herdr`(LFI에서 가져와 기대값만 수정), 동작이 바뀌면 1회 실행.
- 착수 순서(LFI와 같음): 팀장이 먼저 pane을 열고 팀원을 손으로 띄운다 → 그 팀에서 impl이 스크립트를 반영 → critic 리뷰 → 사용자 승인 후 커밋.

## 6. 외부 팀장 시작·재개 절차
- 세션 확인 → 점검(TUI 팀원 `scripts/team-up.sh` / Core 팀원 `scripts/team-core.sh --check`) → 감시(TUI `scripts/team-watch.sh` / Core `scripts/core-watch.sh --watch`) → 열린 이슈와 `cf-work/issues/` 기록으로 상태 맞추기 → 재부팅 뒤 `/tmp`가 비었을 때 다시 요청할 것.

## 7. 운영 관측 요지
- 펼친 확인창은 `done`, 닫으면 `blocked`.
- `esc` 뒤 `blocked`까지 0.7–2.6초, 펼칠 때도 약 1초 늦다.
- `Full Command` 창은 긴 토큰을 자른다.
- 사이드바가 배치를 다시 쌓을 수 있다.
- `cf-impl` 셸은 `cf-work/`를 못 읽는다.

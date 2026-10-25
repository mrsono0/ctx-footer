# 05. 상세 작업계획서

원칙: 단계마다 **목적 → 선행 → 작업 → 산출물 → 완료 기준 → 검증(모의 vs 실화면) → 사용자 승인 → 담당**. 앞 단계의 완료 기준을 넘어야 다음으로 간다. 확인된 요구만 만들고, 테스트는 완료 기준만큼(동작이 바뀌면 기존 테스트 1회).

**2026-10-17부터 진행 단계는 GitHub 이슈(로드맵 #1)가 맡는다(AGENTS.md §8). 이 문서는 단계·회차의 이슈 번호 색인이며, 진행 기록은 이슈에 둔다.**

이 문서는 plan-r1(2026-10-11)로 P2 실측(docs/06)과 사용자 결정을 반영해 갱신했다. docs/02 §6의 미확인 U1–U5는 docs/06이 관측·기록했다(남은 미확인은 아래 표 및 docs/06 참조).

## 한눈에
| 단계 | 이름 | 핵심 산출물 | 사용자 승인 | 상태 |
|---|---|---|---|---|
| P0 | 프로젝트 기반 | 폴더·git·README·docs 01–05·차용 출처 | 계획 확정, 라이선스 | **완료** `b911a17` |
| P1 | 팀·환경 구축 | 팀 3석·AGENTS/CLAUDE·권한 2종·team-up.sh(배치 확인 포함)·모의 테스트 88/88 | 규칙 파일, 커밋 | **완료** `236e92c`·`5c6cb4a` |
| P2 | 스펙 확정 스파이크 | docs/06(U1–U5 실측·타입 확정·T1/D-1~D-8 판정) | 없음 | **완료** `b3ad6df` |
| P3 | 스캐폴딩 | marketplace.json·plugin/ 7종·dev-check.sh | 커밋 | **완료** `08e71d8` |
| P4 | 구현·단위 테스트 | plugin/hooks/register.ts·plugin/tests/register.test.ts | 커밋 | **완료** `13b0161` |
| P5 | 실화면 검증 | docs/07-acceptance.md(A1–A5) | 커밋 | **완료** `9b13c01` |
| P6 | 상시 적용 | GitHub 마켓플레이스 user scope 설치(M2 결정) | **전역 설정 변경** 원문 | **완료** 2026-10-11(설치 0.1.0, 기록은 이 문서 커밋) |
| — | 릴리스 | version 올림 + 태그(`v0.1.0`, M1 결정) + 푸시 | 버전 커밋·태그·푸시 원문 | **완료** `v0.1.0`(대상 커밋 `fbb8eab`) |
| 운영 | 배치 기준(team-up) | `scripts/team-up.sh` 배치 기준(팀장 위 0.6, 아래 줄 impl\|critic 0.5, ±0.01)·`--layout`·`--up`/`--resume-impl` 끝 보정·모의 테스트 185/185 | 커밋 | **완료** `36e7a49`·`868cfa4`·`5a082b2`(실화면 `--layout`·`--resume-impl` cf-lead 확인) |
| 운영 | critic exec 시험 | `scripts/critic-run.sh`·`ci/test-critic-run.sh`·`ci/mock/codex`(모의 29/29)·실제 실행 비교 3회 — 1차(문서 사본): 판정 파일·완료 이벤트·첫 줄(`APPROVE`) 일치 확인; 2차(`git clone --shared` 사본·r1 수정 전 코드): `APPROVE_WITH_CHANGES`(114초, `rc=0`)·P2(저장소 상위 경로 `-C` 허용) 자체 검출·P1(TUI는 공식 설정 문서 근거로 지적) 미검출(이유 미확인)·제외 옵션 지정 실행에서 `ci/test-critic-run.sh`의 `TMPDIR` `mktemp` 쓰기 거부(`Operation not permitted`, `rc=1`) 관측(`bash -n`은 첫 인자 `scripts/critic-run.sh`만 구문 검사했고 `ci/test-team-up.sh`는 구문 검사·실행 모두 수행되지 않음); 3차(`<회차>/tmp` 생성 + `TMPDIR=<회차>/tmp` + `--add-dir <회차>/tmp`, 같은 r1 수정 전 코드): 모델 셸 `TMPDIR` 자동 상속 및 기본 `mktemp -d` 생성 성공 확인·`ci/test-critic-run.sh` 18/18(`rc=0`) 실행 통과·`ci/test-team-up.sh` 181/185(`rc=1`, 539행 프로세스 치환 `/dev/fd/62: Operation not permitted`) 실행·판정은 `APPROVE`(146초, `rc=0`, P1·P2 모두 미검출) | 커밋(규칙 채택은 별도) | **완료** `c700098`·`a06fa55`·`0d3e6a2` |

(P7 공개 배포는 폐지 — 구조는 P3가, 첫 설치·공개는 P6이 담당하고 남은 절차만 아래 「릴리스」로 둔다.)

- clearhook-r1(2026-10-12, 팀 환경 보강): 팀장 `/clear` 뒤 Herdr `cf-lead` 이름이 풀리는 문제(gjc-herdr #12)에 `.claude/settings.json` SessionStart `clear` 훅 + `scripts/team-up.sh --hook-clear`. 사용자 원문 「응, 훅 넣어서 진행해」. 모의 테스트 101/101. 실화면 확인(팀장 pane `/clear`)·커밋은 별도.
- pushallow-r1(2026-10-13, 권한 정리): 프로젝트 `.claude/settings.json` ask `Bash(git push *)`가 auto 모드보다 우선해 위임된 `main` 푸시도 매번 확인창을 띄움 → 사용자가 직접 ask에서 빼고 allow `Bash(git push origin main)`(정확 일치)를 추가(deny 무변경). 사용자 원문 「네」. critic r1 REJECT(위임 밖 푸시도 auto 판단으로 확인 없이 갈 수 있음) → 설정은 두고 docs/04에 실제 효과를 적음(cf-lead 결정, deny 보강은 안 함).
- layout-r1(2026-10-14, 팀 환경 보강): GJCH 팀과 합의한 배치 기준을 `scripts/team-up.sh` 기능으로. 사용자 원문 「커밋 승인, 배치 작업도 진행, 덤도 진행」. 새 pane은 기준 자리에 만들고, `--up`·`--resume-impl` 끝과 `--layout`에서 팀장·impl이 같은 탭이면 보정(모양이 맞으면 비율만 resize, 다르면 임시 탭 경유 `pane move --no-focus`). critic은 같은 탭일 때만 함께, 아니면 팀장 0.6/impl 아래만. Sidebar 등 세 석 밖 pane은 옮기거나 크기를 바꾸거나 닫지 않고, 임시 탭은 남은 pane이 모두 agent 없을 때만 닫는다. 배치 실패는 기동을 되돌리지 않고 종료 코드만 비0 + 안내. 점검(인자 없음)은 경고만, `--hook-clear`는 배치를 읽지도 않는다.
- impl-agy-r1(2026-10-15, 팀 환경): 구현 담당(`cf-impl`)을 GJC에서 `agy --model gemini-4-argon-high --sandbox`로 정식 교체(`AGENTS.md`·`scripts/team-up.sh`·`ci/test-team-up.sh`·`ci/mock/herdr`·`docs/04-team-and-env.md` 반영, `--resume-impl`을 `agy --conversation <id>`로 바꾸고 GJC 전용 `/rename` 처리 제거). 사용자 원문 「2. 교체 승인」.
- agyrule-r1(2026-10-15, 팀 환경): agy 전역 `toolPermission`을 `proceed-in-sandbox`로 둔 설정과 CF·GJCH 합의 절차(확인창은 lead가 1번만 선택, 2·3번 금지, 전역 `settings.json` 변경 시 팀 간 사전 공지·순차 재기동)를 `AGENTS.md`와 `docs/04-team-and-env.md`에 반영. 사용자 원문 「규칙 반영 승인」.
- acceptedits-r1(2026-10-15, 팀 환경): 구현 agy(`cf-impl`) 기동·복구 명령에 `--mode accept-edits`를 추가해 `agy --model gemini-4-argon-high --mode accept-edits --sandbox`(복구 `agy --conversation <id> --model gemini-4-argon-high --mode accept-edits --sandbox`)로 갱신(`AGENTS.md`·`scripts/team-up.sh`·`ci/test-team-up.sh`·`docs/04-team-and-env.md`). 사용자 원문 「2. 승인」.
- closeopen-r1(2026-10-15, 문서 정리): 결정상 더 관찰하지 않기로 한 미확인 2건(U5 데스크톱 표면, U1 엔진 자체 라벨 병렬 모양)을 `docs/05`·`06`·`07`에서 **닫음**(관찰 없이 종결, 실제 모양은 관찰하지 않음)으로 정리. 사용자 원문 「닫기로 한것은 명확하게 닫기 처리를 합니다.」.
- critic-exec-r1(2026-10-15, 운영 시험): critic 리뷰를 비대화형 `codex exec` 회차 실행기(`scripts/critic-run.sh`, `-m gpt-6.1-sol -c model_reasoning_effort="high" -s workspace-write` + `/tmp`·`TMPDIR`·`writable_roots` 제외 `-C <동결 사본> --json -o <회차>/VERDICT.md`, 저장소 하위·상위 경로 `-C` 거부)로 시험. 모의 테스트 23/23(`ci/test-critic-run.sh`·`ci/mock/codex`) 및 기존 `ci/test-team-up.sh` 185/185 통과. `closeopen-r1` 동결 입력 복사본으로 실제 1회 실행 시 종료 코드 0·58초·`turn.completed`·첫 줄 `VERDICT: APPROVE`(TUI 판정 첫 줄과 일치, 입력 토큰 263,372; 단 복사한 `REQUEST.md`가 기존 `/tmp/cf-closeopen-r1-review/` 경로를 가리키고 사본에 Git 비교 기준본이 없어 전체 diff·다른 파일 무변경 독립 대조 등 TUI와 동등한 검토 범위까지는 입증하지 않음). `--search` 미지원·승인 요청 발생 시 동작·OS 쓰기 차단은 미확인으로 두고 `AGENTS.md`·`scripts/team-up.sh`는 바꾸지 않음. 사용자 원문 「3번 critic exec runner 시험 진행해」. 커밋 `c700098`.
- critic-exec-r3(2026-10-15, 운영 시험 2차): 리뷰 깊이 비교를 위해 `git clone --shared`(`ea337e3`) 사본에 `critic-exec-r1` 수정 전 4개 파일을 덮어쓰고 현재 `scripts/critic-run.sh`(`c700098`)로 1회 실행(임시 회차 폴더 `cf-critic-exec-r3-trial/`). 결과: 종료 코드 0·114초(실행기 관측)·`turn.completed`(입력 토큰 261,210, 캐시 216,320, 출력 3,353, 추론 1,723)·승인 요청 이벤트 0건·첫 줄 `VERDICT: APPROVE_WITH_CHANGES`(TUI와 동일). TUI가 찾은 2건 중 P2(저장소 상위 경로 `-C` 허용)는 읽기 전용 셸 검증까지 수행해 스스로 찾았고(`VERDICT.md:5-9`), P1(`workspace-write` 기본 `/tmp`·`writable_roots` 설정, TUI 판정에서 공식 설정 문서를 근거로 지적)은 이번 exec 판정에 없었다(미검출 이유는 미확인; 웹 접근 유무와의 인과관계는 가설). 추가 지적 없음. 또한 제외 옵션(`exclude_slash_tmp=true`·`exclude_tmpdir_env_var=true`)을 지정한 이번 실행에서 `ci/test-critic-run.sh` 실행 시 `TMPDIR`(시스템 사용자 임시 폴더)의 `mktemp` 쓰기 거부(`Operation not permitted`, `exit_code=1`)를 관측했다(`events.jsonl:17,19`; trial `VERDICT.md:15`는 두 테스트 모두 중단됐다고 적었으나 실제 로그상 `bash -n`은 첫 인자 `scripts/critic-run.sh`만 구문 검사했고 `ci/test-team-up.sh`는 구문 검사·실행 모두 수행되지 않음. `/tmp` 자체·추가 `writable_roots`·실제 저장소 쓰기 차단은 이번 시험에서 별도 검증하지 않음). 사용자 원문 「네 진행합니다」. 커밋 `a06fa55`.
- critic-exec-r5(2026-10-16, 운영 시험 3차): `scripts/critic-run.sh`가 회차 전용 `<회차>/tmp`를 만들고(저장소 하위·상위·심볼릭 링크 거부 포함) 기존 제외 옵션 3개는 유지한 채 `TMPDIR="<회차>/tmp"`와 `--add-dir "<회차>/tmp"`를 `codex exec`에 넘기도록 보강(모의 테스트 29/29·기존 `ci/test-team-up.sh` 185/185 통과). 별도 최소 관측(임시 탐색 폴더 `cf-critic-exec-r5-tmpdir-probe/`, 17초·`rc=0`)에서 명령줄 `TMPDIR` 재대입 없이 실행한 모델 셸(`/bin/zsh -lc`)이 회차 전용 `TMPDIR`(`<회차>/tmp` 실경로)를 자동 상속받고 기본 `mktemp -d`가 그 하위(`tmp.hUe1lrxYOv`)에 생성·삭제(`exit_code=0`)됨을 실측했다(`events.jsonl:8-9`). 2차와 동일한 `ea337e3` + r1 수정 전 4개 파일로 3차 비교 실행(임시 회차 폴더 `cf-critic-exec-r5-trial/`)한 결과: 종료 코드 0·146초(실행기 관측)·`turn.completed`(입력 토큰 593,068, 캐시 540,800, 출력 3,765, 추론 2,030)·승인 요청 이벤트 0건·테스트 실행 확인(`events.jsonl:19-21,27`: `ci/test-critic-run.sh` 18/18 `exit_code=0` 통과, `ci/test-team-up.sh`는 539행 프로세스 치환 `/dev/fd/62: Operation not permitted`로 181/185 `exit_code=1`). 단, 판정 첫 줄은 `VERDICT: APPROVE`(`VERDICT.md:1`)로 이번 실행에서는 P1·P2 모두 지적하지 않아(2차에서 찾았던 P2도 미검출), 동일 입력에서도 회차별 검출 편차가 있음을 관측했다. 사용자 원문 「1. 승인, 2. 진행」. 커밋 `0d3e6a2`.
- ctx7-r1(2026-10-16, 팀 규칙): GJCH 팀장 전달(사용자 요청)에 따라 구현·검토 팀원의 Context7 문서 확인 규칙을 `AGENTS.md`에 반영 — DIRECTIVE 6칸(Context7 칸), §6 「문서 확인(Context7)」, §5 agy 확인창 3번 예외(서버 `context7`의 `resolve-library-id`·`query-docs`만 영구 허용). 노출 확인(2026-10-16 cf-lead): cf-critic `/mcp` `context7: connected (2 tools)`, cf-impl agy `/mcp` `✓ context7`(같은 도구의 플러그인 서버 `wf3-code-research_context7`도 있음). `CLAUDE.md`는 참조만이라 무변경. 사용자 원문 「1. 둘다 승인, 2. 합니다. 3. 네」. 커밋 `4ed5519`.
- argv-r1(2026-10-17, 팀 환경 보강·외부 팀장 이관 0단계): `scripts/team-up.sh` 점검 모드(인자 없음)가 살아 있는 팀원 2석(`alive`·`unnamed`)의 `herdr pane process-info --pane <pane>`(`foreground_processes` 중 `name == SEAT_KIND`가 정확히 1개이고 `argv`가 있을 때만)를 `SEAT_CMD` 기대 단위와 비교해, 누락·값 다름(`↳ 옵션 불일치: 없음 …; 다름 … (복구: …)`) 또는 판정 불가(`↳ 옵션 판정 불가: <고정 사유>[ (작업 중 — 다시 점검)]`)가 있으면 표시하고 종료 코드 1을 반환하도록 보강(출력에는 기대 옵션과 고정 사유만 쓰고 실제 `argv`·`cmdline`·stderr·원문 JSON은 출력하지 않음). 모의 테스트 233/233(`/bin/bash ci/test-team-up.sh`, 스냅샷·기동형·복구형·`--이름=값`·값 다름·반복 `-c`·판정 불가 5종·작업 중 표시·`SECRET-SENTINEL-123` 미출력 포함) 및 실화면 점검(`/bin/bash scripts/team-up.sh` → `↳ 옵션` 줄 없음·`rc=0`) 확인. 사용자 원문 「1. 둘다 승인, 2. 합니다. 3. 네」, 「커밋 승인, 다음 순서대로 진행」. 커밋 `0e85265`.
- extlead-r1(2026-10-17, 팀 환경 보강·외부 팀장 이관 1–2단계 스크립트): `scripts/team-up.sh`에 외부 팀장 모드(`CF_EXTERNAL_LEAD=1`이고 `HERDR_PANE_ID` 비어 있음; `HERDR_PANE_ID`가 있으면 거부)와 `--claim-external`을 추가하고 `.gitignore`에 `.local/`을 반영. 메인 작업 트리 확인(`git rev-parse --git-dir` 실경로 == `--git-common-dir` 실경로 및 `/.claude/worktrees/` 미포함), `CLAUDE_CODE_SESSION_ID` 필수 확인, 바꾸는 모드(`--up`·`--resume-impl`·`--layout`)의 `.local/team/external-lead` 배타 생성(`set -o noclobber`)·세션 id 대조, 팀원 석 기준 작업공간 탐색, lead 행 `external(이 세션)` 표시(Herdr 안 `cf-lead` 생존·기록 불일치/없음 경고 줄), `impl|critic` 좌우 인접 시 가로 비율(`0.5 ± 0.01`) 보정을 구현. 모의 테스트 309/309(`TEAM_UP_BASH=/bin/bash /bin/bash ci/test-team-up.sh`, 임시 저장소 `git worktree add` 연결 worktree 차단 포함) 통과 및 실화면 읽기 전용 점검(`env -u HERDR_PANE_ID -u HERDR_ENV CF_EXTERNAL_LEAD=1 CLAUDE_CODE_SESSION_ID=extlead-r1-test /bin/bash scripts/team-up.sh` → `external(이 세션)`·`↳ Herdr 안 cf-lead(wN:p1)가 살아 있음…`·`↳ 외부 팀장 기록: 없음`·`rc=0`, `.local/team/external-lead` 미생성) 확인. 외부 모드의 `--up`·`--resume-impl`·`--layout`·`--claim-external` 실화면과 `/clear` 뒤 세션 id 변화는 3단계 시범에서 확인(「미확인」). 사용자 원문 「1. 둘다 승인, 2. 합니다. 3. 네」, 「커밋 승인, 다음 순서대로 진행」. 커밋 `af8c645`.
- extlead-r2(2026-10-17, 팀 규칙·외부 팀장 이관 1–2단계 규칙): GJCH 검토를 마친 팀장 초안(`DRAFT.md`, 보충 우선 B1–B9)을 `AGENTS.md`에 문구 그대로 반영하고 `docs/04-team-and-env.md` §1·§2·§5 대응 문장을 정렬 — 외부 팀장(`CF_EXTERNAL_LEAD=1`·worktree 끔·`.local/team/external-lead` 잠금·`--claim-external`), 시작·재개 시 `scripts/team-up.sh` 점검 우선, 팀원 → 팀장 보고 경로(`/tmp/cf-<회차ID>/to-lead/<두 자리 순번>-<유형>.md` + 화면 머리말 한 줄 후 idle), 포커스(`focused: true`) 대기, 확인창 zoom 펼치기(`ctrl+g`·`ctrl+o`), 이관 중 팀장 간 연락(`SendMessage`·`ListAgents`), Herdr 안 팀장으로 되돌리기 절차. `CLAUDE.md`는 참조만이라 무변경. 사용자 원문 「1. 둘다 승인, 2. 합니다. 3. 네」, 커밋 승인 「커밋 승은, 다음 작업 진행」. 커밋 `fa8244f`.
- 외부 팀장 시범 1차(2026-10-17, 읽기 전용): 데스크톱 Code 탭 세션(worktree 끔, 로컬 환경 `CF_EXTERNAL_LEAD=1`)에서 메인 작업 트리·`HERDR_PANE_ID` 빈 값·`herdr agent list` 동작(확인창 없음)·외부 모드 점검 rc=0(팀원 2석 alive, 옵션 일치, `.local/team/external-lead` 미생성)을 확인. Herdr 안 cf-lead 세션에는 `CF_EXTERNAL_LEAD`가 없음. 사용자 원문 「2차 시범 진행」.
- 외부 팀장 시범 2차·extlead-r3(2026-10-17): 사용자 원문 「2차 시범 진행」으로 데스크톱 세션이 팀원 입력을 맡고 Herdr 안 cf-lead는 읽기만 함. 첫 바꾸는 명령 `scripts/team-up.sh --layout`(rc=0, `impl|critic` 비율 0.5)에서 `.local/team/external-lead`가 그 세션 id로 생성됨. `/clear` 뒤 같은 데스크톱 세션의 `CLAUDE_CODE_SESSION_ID`가 바뀌어 점검에 `↳ 외부 팀장 기록: 다른 세션(…)`이 나옴 → 사용자 원문 「승인합니다. 이 세션에서 --claim-external 실행하고 C 진행해 주세요.」 뒤 `--claim-external`로 갱신, 재점검 rc=0. 이 회차에서 외부 팀장의 배정으로 남은 「Herdr 안 팀장」 전제 문장을 정리(AGENTS.md §5 입력란 예시·안전 절 보고 경로, docs/04 규칙 2번·`--layout` 설명, docs/05 extlead-r2 커밋 승인 인용).
- extlead-r4(2026-10-17, 외부 팀장 시범 3차 후속): 외부 모드에서 기록이 이미 있을 때 바꾸는 모드마다 stderr에 나오던 `Segmentation fault: 11` 줄(MacPorts bash 5.2.26 + `LANG` 없는 데스크톱 셸에서 noclobber 실패 문구를 만들다 서브셸이 죽음, 판정은 정상)을 없애려고 `ensure_external_lead_lock`이 기록이 없을 때만 배타 생성을 시도하게 함. 모의 테스트 309/309(`TEAM_UP_BASH=/bin/bash /bin/bash ci/test-team-up.sh`) 통과 및 실화면(데스크톱 외부 팀장 `scripts/team-up.sh --layout` → segfault 줄 없음·rc=0) 확인. 시범 3차: 외부 `--up`·`--resume-impl` 실화면, §7 되돌리기 부분 시험(Herdr 안 `--up`·`--layout` 뒤 반납) 확인 — 결과 `/tmp/cf-extlead-trial/RESULT-3.md`. 사용자 원문 「segfault 소음을 스크립트 회차로 고쳐 주세요. 초안부터 보여 주세요.」.
- extlead-r5(2026-10-17, 테스트 환경 격리): 외부 팀장 데스크톱 세션에서 `ci/test-team-up.sh`가 195/309로 실패하던 문제(Herdr 모드 시험 실행 줄이 호출한 셸의 `CF_EXTERNAL_LEAD`를 지우지 않아 외부 모드로 돎 — 스크립트 결함 아님)를 고치려고 테스트 앞부분에서 스크립트가 읽는 팀 환경변수를 모두 비움. 환경 4종(깨끗함·외부 팀장 흉내·Herdr pane+외부 변수·bash 5) 변경 전 309·195·195·195 → 변경 후 각 309/309. 사용자 원문 「정확하게 테스트가 되어야지, 수정해서 테스트 진행 합니다.」.
- extlead-r6(2026-10-17, 팀 규칙): herdr `focused`를 전송 대기 조건에서 뺌 — 사람이 보는지와 무관한 서버 상태라(사용자가 다른 작업공간에 있어도 팀원 pane이 `focused: true`) critic VERDICT 전송이 세 번 60초 대기 뒤 보류돼 회차가 멈췄고, Herdr 안 팀장 pane을 닫으면 팀원 2석 중 하나는 늘 focused라 영구 차단될 구조였음. 입력란 확인(보내기 직전, 모양 모르면 확인 불가)만 남기고, `herdr pane focus`가 서버 전역 활성 작업공간을 바꾸므로 포커스는 사용자 지시 없이 옮기지 않음. GJCH 팀장과 의논(같은 문제·같은 방향, herdr 0.9.5 API에 보는 클라이언트 정보 없음). 사용자 원문 「GJCH 팀장과 의논을 해보고 해결 방법을 모색 합니다.」, 「extlead-r6 규칙 초안을 써서 보여 주세요.」.
- extlead-r7(2026-10-17, 팀 규칙·외부 팀장 이관 4단계): 사용자 결정으로 외부 팀장(데스크톱 Code 탭 세션)을 공식 팀장으로, Herdr 안 Claude pane을 부팀장 `cf-vice`(label `CF 부팀장 · Claude`, 읽기 전용 감시·독립 재확인·초안 검토 의견, 팀원 입력·확인창 응답·바꾸는 `team-up.sh` 모드·쓰기·커밋·푸시 안 함)로 지정 — `AGENTS.md` §1 팀 표·「팀장 세션은 하나다」, §5 팀장–부팀장 연락, §7 되돌리기(부팀장 pane에서 `--up`)와 `docs/04` §1·§2를 맞춤. 근거: 시범 2·3차(`/tmp/cf-extlead-trial/RESULT-2.md`·`RESULT-3.md`)에서 부팀장 감시가 초안 빠진 점 2개와 매 회차 독립 확인을 냄. 사용자 원문 「우선 미확인 항목 확인 테스트 수정 사항 발생하면 해결까지 부팀장과 같이 진행을 하고요 공식적으로 현재 herdr 팀장을 부팀장으로 수정하고 여기를 공식 팀장으로 지정을 하고 난 후 진행을 합니다.」.
- extlead-r8(2026-10-17, 팀 규칙): §5 확인창 펼치기에서 `herdr pane zoom`을 뺌 — zoom이 그 pane으로 포커스를 옮겨 같은 §5 「포커스는 옮기지 않는다」와 어긋났고, 옛 규칙에서 critic VERDICT 전송 보류 세 번의 실제 원인이었음(「확인창 뜬 pane으로 herdr가 포커스를 옮긴다」 가설은 관측으로 기각). zoom 없이 `send-keys ctrl+g` + `pane read --source visible`, 잘리면 펼친 화면이 보일 때만 `send-text $'\e[6~'`(Page Down)를 `(a–b of N lines)`의 b=N까지 되풀이하고 응답 전 원래 확인창·1번 커서를 확인, 이 키들은 「확인창이면 보내지 않음」의 예외로 명시 — 긴 한 줄·7줄 명령 확인창에서 실측, 포커스·활성 작업공간 변화 없음(`/tmp/cf-extlead-trial/RESULT-3.md`). MCP `ctrl+o`는 미시험이라 펼쳐지지 않으면 사용자에게. 사용자 원문 「zoom 없이 확인창을 읽는 방법을 먼저 확인하고, 초안을 써서 보여 주세요.」.
- #2(2026-10-17, 팀 규칙, 로드맵 #1): GitHub 이슈로 작업을 관리하는 규칙을 `AGENTS.md` §8로 넣고, 진행 기준 문장(3·5·20·52·77·87·88·104행)을 이슈 기준으로, `cf-lead` 행에 이슈 작업·`i<번호>` 브랜치·gitignore 보관 복사를, 푸시 위임에 이슈 브랜치 ff 병합 뒤 `main` 푸시를 더함. docs/04 cf-lead 권한·docs/05 머리말 맞춤. 부트스트랩 예외로 이 이슈만 `main`에 바로 커밋. 사용자 결정 「D1 브랜치 i<번호> 사용, D2 cf-impl이 커밋, D3 요청마다 원문 승인으로 정합니다.」.
- #3(2026-10-18, 팀장 감시 도구, 로드맵 #1): 팀장 감시 스크립트(`scripts/team-watch.sh`), agy 명령 확인창 펼침 읽기 스크립트(`scripts/prompt-read.sh`), 모의 테스트(`ci/test-team-watch.sh`·`ci/mock/herdr`), 프로젝트 `.claude/settings.json` allow 2건을 추가. 회차 r1–r7과 실화면 재검증을 거쳐 확인창 구조 판정(`inspect_collapsed_prompt`, 펼친 화면 범위 줄 아래 빈 줄 허용, 짧은 명령 fail closed)을 맞춤. 커밋 `9bc1163`.
- #4(2026-10-18, 팀 규칙, 로드맵 #1 B): 작업 파일·데이터 운영 규칙(`AGENTS.md` §9, 저장소 밖 작업 뿌리 `cf-work/`), 외부 팀장 시작·재개 절차(`docs/04` §6), 운영 관측 요지(`docs/04` §7). 커밋 `efd340a`.
- #5(2026-10-18, 미확인 시험, 로드맵 #1 D): MCP 도구 확인창 `ctrl+o`는 펼쳐지지 않음(인자는 위 대화 기록 줄에서 읽음), agy 모드 안내 문구는 입력란 판정에 영향 없음, 화면 없는 Herdr 작은 탭은 미확인. 저장소 변경 없음. 후속 #8.
- #6(2026-10-18, 복귀 시험, 로드맵 #1 E): 데스크톱 `/clear`는 세션을 새 프로세스로 다시 띄운다(세션 id·프로세스·세션 간 메시지 소켓이 바뀌고 백그라운드 작업이 끝남). 외부 팀장 기록만 옛 값으로 남아 사용자 승인 뒤 `--claim-external`로 회수. D4 = (b) 자동 회수, 후속 #9. 저장소 변경 없음.
- #7(2026-10-18, 팀 운영, 로드맵 #1 G): 부팀장 `cf-vice`를 끝내고 외부 팀장 단독 운영으로 전환. D5(부팀장 없을 때 독립 재확인)를 `AGENTS.md` §7에, 부팀장 「선택」 표시를 `docs/04` §1·§2에 반영. 이 색인 줄들과 같은 커밋.
- 후속(로드맵 밖): #8 `fix:` 팀장 감시 도구의 MCP 확인창·알 수 없는 blocked 알림, #9 `feat:` 외부 팀장 기록 자동 회수.
- #8(2026-10-18, 팀장 감시 도구): `scripts/team-watch.sh`가 MCP 도구 확인창을 화면 구조로 알아보고 `EVENT impl-blocked kind=mcp`를, 알아보지 못한 blocked가 20초를 넘으면 `kind=unknown`을 낸다(명령 확인창 사건 줄은 그대로). 모의 시험 224/224, 실화면 `kind=mcp` 확인. 커밋 `093cfda`.
- #10(2026-10-18, 문서 정정): `AGENTS.md` §7 D5의 「`team-watch.sh`가 보지 않는 것」을 코드에 맞춤(외부 팀장 기록·로컬 `origin/main`은 이미 봄), `docs/04` §1 팀장 권한 칸의 옛 보관 경로를 `cf-work/`로. 이 줄과 같은 커밋.
- #9(2026-10-18, 팀 환경, D4=b): 외부 팀장 기록에 세션 Claude 프로세스의 pid·시작 시각을 더하고, 옛 주인이 끝났음이 확인되면 바꾸는 명령(`--up`·`--resume-impl`·`--layout`)이 기록을 스스로 넘긴다(살아 있음·판정 불가는 거부, 점검은 표시만). 기록 쓰기는 잠금으로 묶음. 모의 시험 402/402, 실화면: 살아 있음 거부·끝난 주인 자동 회수·옛 형식 거부 확인. 이 줄과 같은 커밋.
- #12(2026-10-18, 팀 환경): `.codex/config.toml`에 `project_doc_max_bytes = 65536`을 두어 Codex가 AGENTS.md(40 KiB)를 기본 32 KiB에서 자르지 않게 함(잘리면 「안전」·「사용자 승인」·「보고 형식」 절이 cf-critic에 실리지 않았다). `AGENTS.md` §1 규칙·권한 파일 목록에 `.codex/config.toml` 추가. 이 줄과 같은 커밋.
- #11(2026-10-19, 팀 환경): 지시로만 적힌 금지를 `.claude/settings.json`에 보강 — deny `rm` 재귀 변형·`env`·`printenv`, ask 사용자 범위 설정 파일 편집. `AGENTS.md` §6에 서브에이전트 지시 규칙 한 줄. 이 줄과 같은 커밋.
- #13(2026-10-20, 규칙 정리): `AGENTS.md`의 긴 절차·관측 이력을 문장 그대로 새 `docs/08-team-operations.md`로 옮기고 원칙과 경로만 남김(40,525 → 30,593바이트). 옮긴 문장은 바꾸지 않음(대조 스크립트로 빠짐 0 확인). 이 줄과 같은 커밋.
- #14(2026-10-20, 규칙 정리): agy가 `AGENTS.md` 앞 약 24 KB만 싣는 것(#13 실측)에 맞춰 문장은 그대로 두고 순서만 바꿈 — 안전·사용자 승인·보고 형식을 앞으로, 팀장만 쓰는 절차를 맨 끝 「팀장 운영 절차」로. 이 줄과 같은 커밋.
- #15(2026-10-20, 규칙 정리): `AGENTS.md`의 「팀장 운영 절차」를 Claude만 싣는 `.claude/rules/lead-operations.md`로 옮김(AGENTS.md를 24,000바이트 아래로), 마탑 사용자 명시 전달·구성 요청 채택 문구를 그 파일에 더함(사용자 결정 2026-10-20). 이 줄과 같은 커밋.
- #16(2026-10-20, 팀 환경): `scripts/team-up.sh`를 마탑 공통 이름·하위 명령에 맞춤 — `--check`(인자 없음과 같음, 표 + 팀원마다 공통 한 줄), `--up [<대화 id>]`(재개·배치), `--status`(보고 꼴), `--lock status|claim [--force]|release`, `--hook`(`--hook-clear` 별칭). `--resume-impl`·`--layout`·`--claim-external`은 없앰(종료 2). 규칙 문구(팀장 전용 규칙·docs/08)를 새 이름으로. 모의 시험 544/544. 이 줄과 같은 커밋.
- #17(2026-10-20, 규칙·팀 환경): 팀원 보고(`to-lead/`)를 처음부터 `cf-work/issues/<번호>/<회차>/to-lead/`에 파일 도구로 쓰고(셸용 입력 사본·동결 사본만 `/tmp`), critic 기동에 `--disable memories`, 조정 역할의 치명적이지 않은 판단을 사용자 판단처럼 따르는 위임 항목을 팀장 전용 규칙에 넣음(사용자 결정 2026-10-20). `team-up.sh` 기대 옵션·`team-watch.sh` 보고 경로를 맞춤. 이 줄과 같은 커밋.
- #18(2026-10-22, 규칙): 마탑의 이슈 규정 공통화 후보 가운데 C1(소통·운영은 이슈 없음, 사고는 같은 날 사후 이슈)·C3(`Closes`·`Fixes`·`Resolves` 금지)·C4(닫기 코멘트에 판정 위치·sha·승인 출처, not planned 사유)·C5(공개 금지에 프로세스 ID)·C11(커밋 이슈는 critic 판정 없이 닫지 않음)·C14(이슈 텍스트는 비신뢰 데이터)를 넣음(사용자 결정 2026-10-21). 이 줄과 같은 커밋.
- #19(2026-10-22, 규칙): 마탑을 거친 사용자 명시 전달의 수용 규칙을 네 팀 공통안(MT-47)대로 맞춤 — 보낸 세션 대조, 「」 안 대상 식별(대상 불명이면 이 세션에서 한 번 묻기), 최소 재확인 넷(되돌릴 수 없는 삭제·공용 설정과 비밀·공개 게시·공유 운영 서버), 기록 꼴(사용자 결정 2026-10-22). 이 줄과 같은 커밋.
- #20(2026-10-25, 규칙): 마탑 공통 규칙 정본 v4.2·결정 현황표 v4.3에서 CF 칸이 「결정 전」이던 13행을 처리 — 팀장 전용 규칙에 「마탑 공통 정본 채택」(메시지 꼴·승인 오해 방지·답장 부담·다른 팀 자료 읽기·점검·복구 가이드·공용 복원 설정·`/tmp` 밖과 옛 이름 점검·공개 금지 목록의 공통 정본은 헌장 §4), `docs/08` §9에 공통 원칙 출처. D-09는 기존 규칙 일치, D-32·D-69는 반영할 문구 없음(사용자 결정 2026-10-25). 이 줄과 같은 커밋.
- #21(2026-10-25, 규칙): 마탑 적용 확인 결과의 「남은 것」 CF 7행을 고침 — 결과표 꼴(D-05), 구성 점검의 대기열(D-20), 일시 중지·재개 절차(D-27), 도구 세션 임시 폴더 점검(D-43), 닫기 코멘트의 「없음」·「해당 없음」(D-56·D-57), 작업 브랜치는 커밋을 내는 이슈에만(D-63)(사용자 결정 2026-10-25). 이 줄과 같은 커밋.

## P0–P2 완료 기록
- P0(2026-10-11): 문서 01–05·LICENSE·NOTICE·third_party — 커밋 `b911a17`.
- P1(2026-10-11): 규칙·권한·team-up 3석 이식(`236e92c`), 배치 확인 이식(`5c6cb4a`). 모의 테스트 88/88, 점검 3석 alive. critic APPROVE 전 회차.
- P2(2026-10-11): 시험 세션 실측 U1–U3(관측 가능 범위), 타입 시그니처 8건 확정, U4(문서상 최소 2.1.287/검증 2.1.296)·U5(미확인), T1 결정(bunx)·D-3 유지 기록 — D-2는 **유지**(긴 형식)로 기록됐고, 폭 기준 전환(넓음 `ctx 53% · Xk/Yk`·좁음 `ctx 53%`)은 P2 뒤 사용자 결정 「형식 바꾸기」→「작은 화면은 ctx 53% 유지, 넓은 화면으로 변경되면 원래대로 복원」(plan-r1에서 반영). 커밋 `b3ad6df`. statusLine은 사용자 결정 「전역으로 꺼」로 이미 제거(사용자 홈의 Claude 설정 파일 백업 `settings.json.bak-20261011-164943-statusline`).

## P3. 스캐폴딩
- 목적: docs/03 §4 구조(저장소 루트 = 마켓플레이스 루트, `plugin/` 하위)를 기능 코드 없이 만든다.
- 선행: P2.
- 작업: `.claude-plugin/marketplace.json`(BRIEF 3절 값), `plugin/.claude-plugin/plugin.json`(name `ctx-footer`, version `0.1.0`, description, author, `"types"`), `plugin/hooks/hooks.json`, `plugin/types/index.d.ts`(`'ctx-footer': { context: ContextReading | null }`), `plugin/tsconfig.json`(extends 엔진 제공), 빈 `plugin/hooks/register.ts`(`register` 내보내기만), `plugin/tests/` 자리, `plugin/LICENSE`·`NOTICE` 사본, `scripts/dev-check.sh`(validate + bunx 고정 tsc + test + 금지 API 검색 — plugin/ 대상), `.gitignore`에 `plugin/.claude-plugin/types/`.
- 산출물: 위 파일들.
- 완료 기준: `claude plugin validate plugin` 통과, `scripts/dev-check.sh` 통과(단위 테스트 0개 허용), bunx tsc 고정 버전 확정·기록(M3 닫기).
- 검증: 모의(validate·tsc·test) / 실화면 없음.
- 사용자 승인: 커밋.
- 담당: impl(작성) · critic 리뷰(도구 3회차).

## P4. 구현·단위 테스트
- 목적: docs/03 §3 의사 코드(폭 기준 형식 전환)를 구현한다.
- 선행: P3.
- 작업: `plugin/hooks/register.ts`(session.start·session.measure·SessionMode, dashband 고지 주석), `plugin/tests/register.test.ts`(docs/03 §5 4가지 — toReading 있음/없음, label 형식·폭 경계(기준값-1/기준값/없음), SessionMode 훅).
- 산출물: 위 2파일.
- 완료 기준: `scripts/dev-check.sh` 통과, 금지 API 0건, 코드 100줄 이내(목표 50줄 안팎).
- 검증: 모의(단위 테스트·정적) + critic 리뷰(3회차, 고정 질문: "N1 안전을 어기는가", "요구 밖 기능이 있는가", "실패 시 엔진 기본 그림이 남는가") / 실화면은 P5.
- 사용자 승인: 커밋.
- 담당: impl(작성) · critic(판정).

## P5. 실화면 검증
- 목적: 인수 기준 A1–A5를 실제 화면으로 확인한다.
- 선행: P4.
- 작업: 시험 세션(`claude --plugin-dir ./plugin`, 새 탭)에서 하단 한 줄 확인, 값 변화 2턴 이상(압축 활용 가능), 첫 응답 전 모양(D-3). 가능하면 U1 연결자(` & `)·D-7 실패 경로 관찰 — 안 되면 미확인 유지.
- 산출물: `docs/07-acceptance.md`(화면 기록·판정, docs/06 형식 준수).
- 완료 기준: A1–A5 충족.
- 검증: 실화면(모의 없음) + critic 리뷰(문서 2회차).
- 사용자 승인: 커밋.
- 담당: impl(관찰·기록) · critic(기록 대조).

## P6. 상시 적용
- 목적: 모든 세션에서 쓴다(사용자 본인 포함 같은 경로).
- 선행: P5.
- 작업: **user scope 설치(M2 결정)** — `claude plugin install ctx-footer --marketplace mrsono0/ctx-footer` → `/reload-plugins` 또는 새 세션 → 화면 확인. statusLine 정리는 **이미 완료**(P2 기록 참조) — 새 작업 없음.
- 산출물: 설치 기록(회차 폴더), README 설치 문구(한글 — M4 결정).
- 완료 기준: 실사용 세션 하단 한 줄 `ctx N%`, 되돌리는 방법 README 문서화.
- 검증: 실화면(설치 세션에서 A1 재확인).
- 사용자 승인: **전역 설정 변경**(플러그인 설치 = 사용자 홈의 Claude 설정 폴더 기록) 원문.
- 담당: lead(전역 변경 실행·백업) · impl(기록).
- **결과(2026-10-11 20:31, 사용자 원문 「네, 커밋하고 P6 진행해」)**: cf-lead가 사용자 홈의 Claude 설정 파일(`settings.json`)을 백업(`…bak-20261011-203117-p6`)한 뒤 `claude plugin install ctx-footer --marketplace mrsono0/ctx-footer`를 실행했다.
  - 설치 출력: «Successfully added marketplace: ctx-footer (declared in user settings)», «Successfully installed plugin: ctx-footer@ctx-footer (scope: user)». 저장소는 HTTPS로 클론했다.
  - `claude plugin list`: ctx-footer@ctx-footer · 0.1.0 · user · ✔ enabled.
  - 전역 설정 변경은 두 항목뿐이다(백업과 `jq -S` diff로 확인).
    - `enabledPlugins["ctx-footer@ctx-footer"] = true`
    - `extraKnownMarketplaces["ctx-footer"]`(source github, repo `mrsono0/ctx-footer`)
  - 설치 캐시(사용자 홈의 Claude 플러그인 캐시 `ctx-footer/ctx-footer/0.1.0/`)에는 `plugin/` 내용만 들어 있다. docs·scripts·AGENTS.md는 없다. docs/03 §4의 구조와 일치한다.
  - 실화면: `--plugin-dir` 없이 새 세션을 띄웠다.
    - 첫 응답 전에는 라벨이 없다.
    - 응답 뒤 바닥줄 한 줄 오른쪽에 `ctx 5% · 54k/1000k`가 나왔다(약 150열, A1 재확인).
    - 화면 원본은 cf-lead 회차 폴더에 있다: `p6-installed-footer.ansi`, sha16 `f24f0c4a673f0052`.
  - 되돌리는 방법은 README 「되돌리기」에 적었다.

## 릴리스 (P7 흡수)
- 목적: 배포 버전을 GitHub 원격에 올린다(공개 저장소 `mrsono0/ctx-footer`, 공식 디렉터리 등록 없음).
- 선행: P5 인수 통과 뒤 `v0.1.0` 태그(M1 결정, 2026-10-11).
- 작업: `plugin/.claude-plugin/plugin.json` version 올림 → 커밋(승인) → 태그(예: `v0.1.0`) → 푸시(lead). 이후 릴리스마다 반복.
- 산출물: 버전 커밋·태그·푸시 기록(회차 폴더).
- 완료 기준: 태그가 원격에 있고 `mrsono0/ctx-footer#vX.Y.Z` 고정 설치가 동작.
- 검증: 실화면(태그 고정 설치 1회).
- 사용자 승인: 버전 커밋 · 태그·푸시 원문(M1 시점 결정 포함).
- 담당: impl(버전·태그 준비) · lead(푸시·사용자 승인).
- **결과(v0.1.0, 2026-10-11, 사용자 원문 「1·2 진행, mrsono0/ctx-footer 하면 라스트 버전이 설치되도록 옵션 추가」)**
  - 태그
    - 주석 태그 `v0.1.0`을 커밋 `fbb8eab`(docs: README 최신·버전 고정 설치 옵션)에 붙였다.
    - 그 판의 `plugin.json` version은 0.1.0이다. P3부터 0.1.0이었으므로 버전 올림 커밋은 없다.
    - 원격 주석 태그 `v0.1.0`(태그 객체 `9b52e11`)의 대상 커밋(`refs/tags/v0.1.0^{}`)은 `fbb8eab`다. `git ls-remote`로 확인했다.
  - 태그 판 구조 검사
    - `git clone --branch v0.1.0` 사본에서 `claude plugin validate`를 마켓플레이스와 plugin에 돌렸고 통과했다.
    - 훅은 session.start·session.measure·ui.render{SessionMode}다.
  - 고정 설치 검증(격리 환경, cf-lead)
    - `CLAUDE_CONFIG_DIR`과 `CLAUDE_CODE_PLUGIN_CACHE_DIR`를 임시 폴더로 두고 `claude plugin install ctx-footer --marketplace mrsono0/ctx-footer#v0.1.0`을 실행했다.
    - 출력: «Cloning … (ref: v0.1.0)», «Successfully added marketplace: ctx-footer», «Successfully installed plugin: ctx-footer@ctx-footer (scope: user)».
    - `claude plugin list`에서 0.1.0이 enabled 상태였다. 마켓플레이스 Source는 «GitHub (mrsono0/ctx-footer@v0.1.0)»다.
    - 실사용(사용자 홈의 Claude 설정 파일 `settings.json`)의 해시는 바뀌지 않았다.
    - 완료 기준 「태그가 원격에 있고 고정 설치가 동작」을 충족한다.
  - 검증 기준에서 달라진 점
    - 계획한 검증은 「실화면(태그 고정 설치 1회)」이었다. 이번에는 격리 설치에서 설치·목록까지만 확인했고, 그 설치본으로 세션 바닥줄(실화면)은 보지 않았다.
    - 실화면은 같은 0.1.0 판을 P6 설치본으로 확인한 것(위 P6 결과)으로 갈음한다.
    - 근거: `git diff 27441ff v0.1.0 -- plugin/ .claude-plugin/`은 0행이다. P6 설치 직전에 푸시한 `main`(`27441ff`)부터 태그 사이에는 문서 커밋만 있다.
    - 고정 설치본으로 실화면을 확인하는 것은 「미확인」이다.
  - 재확인(2026-10-12, cf-lead, 사용자 원문 「1」 — 선택지 1 그대로 기록 / 2 로그인해서 실화면 / 3 그대로 둠)
    - 같은 격리 방식으로 `claude plugin install ctx-footer --marketplace mrsono0/ctx-footer#v0.1.0`을 다시 실행해 성공했다. `claude plugin list`에서 0.1.0 enabled, 격리 `installed_plugins.json`의 `gitCommitSha`는 `fbb8eab`(태그 대상 커밋)다.
    - 같은 env로 띄운 `claude`(v2.1.296)는 테마 선택 뒤 «Select login method:» 화면에서 멈췄다. 사용자 결정으로 로그인하지 않고 종료했다.
    - 격리 고정 설치본과 P6 설치본(사용자 홈의 Claude 플러그인 캐시 `ctx-footer/ctx-footer/0.1.0`, 위 P6 실화면 판)의 파일 sha256 목록을 비교했다. 실행 중 생기는 잠금 표식 `.in_use/`를 빼면 8개 파일(`.claude-plugin/plugin.json`, `hooks/hooks.json`, `hooks/register.ts`, `LICENSE`, `NOTICE`, `tests/register.test.ts`, `tsconfig.json`, `types/index.d.ts`)이 바이트 동일하다.
    - 실사용(사용자 홈의 Claude 설정 파일 `settings.json`) 해시(sha16 `d11ef39578bd9008`)는 확인 전후 같다.
    - 근거는 cf-lead 회차 폴더 `pinscreen-r1`(`EVIDENCE.md`, `pin-files.sha256`, `p6-files.sha256`, `installed_plugins.json`)에 있다.
    - 고정 설치 경로로 불러온 세션의 바닥줄은 여전히 「미확인」이다.

## 미결정·미확인 (닫는 방법 포함)
| 항목 | 내용 | 닫는 방법 |
|---|---|---|
| M1 | **결정**: 첫 릴리스는 P5 인수 뒤 `v0.1.0` 태그 | 사용자 원문 「1–3 진행, M1·M2·M4(한글로) 권장대로」(2026-10-11). 태그·푸시 승인은 릴리스 시 별도 원문 |
| M2 | **결정**: P6 설치는 GitHub 마켓플레이스 **user scope** 설치 | 같은 원문. 전역 설정 변경 승인은 설치 시 별도 원문 |
| M3 | **닫음**: bunx 고정 TypeScript `7.0.2`(npm 배포 2026-07-08, 안정판) | `scripts/dev-check.sh`와 같은 값. P3에서 bunx 동작 확인(2026-10-11) |
| M4 | **결정**: README 한글 | 같은 원문(공개 저장소) |
| M5 | **닫음**: 폭 기준 전환값 `WIDE_COLUMNS = 96` | P5(docs/07) — 가장 긴 모드 힌트(accept edits)에서 최대 라벨 22칸 한 줄 최소 폭 94(계산) + 여유 2, 96·95 경계 실측 |
| U1 연결자 | **닫음**(연결 모양): `modes` 항목 사이 ` & `, 같은 흐린 색, 오른쪽 끝 | docs/07 「남은 관찰 정리」 U1(2026-10-14) — 사본 계측 라벨로 관찰. 엔진 자체 라벨(`memory paused`·`account memory: …`) 병렬 모양도 **닫음**(2026-10-15, 관찰 없이 종결 — 사용자 원문 「닫기로 한것은 명확하게 닫기 처리를 합니다.」. 띄우는 조건 미발견, 전역 설정 변경 시도 안 함) — 실제 모양은 관찰하지 않았다 |
| U5 데스크톱 | **닫음**(2026-10-15, 관찰 없이 종결 — 사용자 원문 「닫기로 한것은 명확하게 닫기 처리를 합니다.」. 앞선 결정 2026-10-14 「2. 건너띔」): 데스크톱 표면 잘림 모양 — 실제 모양은 관찰하지 않았다 | 앱 2.19675.0 있음(2026-10-14). GUI라 터미널에서 관찰 불가 → 앞선 결정 사용자 원문 「2. 건너띔」(2026-10-14)에 이어 사용자 원문 「닫기로 한것은 명확하게 닫기 처리를 합니다.」(2026-10-15)로 관찰 없이 종결(docs/07 U5) |
| D-7 실패 경로 | **닫음**: 그리기 훅 throw → 엔진이 건너뛰고 기본 그림, 알림 1건, 세션 정상 | docs/07 「남은 관찰 정리」 D-7(2026-10-14, 사본 의도 실패 시험) |
| U3 이벤트 시점 | **닫음**(이번 시험 세션 1회): 첫 응답 전 빈 context measure 누적 1회, 관측한 응답 3회마다 +1, 수동 `/compact` 진행 중·완료 뒤·30초 뒤까지 증가 없음(다음 응답 뒤 +1) | docs/07 「남은 관찰 정리」 U3(2026-10-14, 사본 이벤트 계측) |

## 위험과 대응
| 위험 | 대응 |
|---|---|
| 좁은 터미널에서 라벨이 다음 줄로 넘어감 | **폭 기준 형식 전환으로 대응**(`ctx 53% · Xk/Yk` ↔ `ctx 53%`, 사용자 결정). 기준값 96 확정·폭별 모양 실측(docs/07) — P2에서 8자 라벨 `ctx test`도 약 67열에서 줄바꿈됐으므로(docs/06 U1) 전환만으로 두 줄을 완전히 막는다고 보장하지 않는다 |
| 엔진 업데이트로 props·이벤트 변경 | D-1(엔진 그림 유지)로 영향 최소화, `claude plugin validate`를 업데이트 때 재실행 |
| 압축 직후 이전 퍼센트 표시 | D-3 유지로 수용(사용자 결정 「2. 권장」) — 오해 소지 낮고 조치 없음 |
| 팀 운영 비용이 작업보다 큼 | 상주 3석, 조사는 cf-critic이 겸함. 남은 단계는 짧게 |
| 차용 라이선스 누락 | plugin/LICENSE·NOTICE 사본(P3), critic 고정 질문 |

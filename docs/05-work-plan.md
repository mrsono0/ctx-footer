# 05. 상세 작업계획서

원칙: 단계마다 **목적 → 선행 → 작업 → 산출물 → 완료 기준 → 검증(모의 vs 실화면) → 사용자 승인 → 담당**. 앞 단계의 완료 기준을 넘어야 다음으로 간다. 확인된 요구만 만들고, 테스트는 완료 기준만큼(동작이 바뀌면 기존 테스트 1회).

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

(P7 공개 배포는 폐지 — 구조는 P3가, 첫 설치·공개는 P6이 담당하고 남은 절차만 아래 「릴리스」로 둔다.)

- clearhook-r1(2026-10-12, 팀 환경 보강): 팀장 `/clear` 뒤 Herdr `cf-lead` 이름이 풀리는 문제(gjc-herdr #12)에 `.claude/settings.json` SessionStart `clear` 훅 + `scripts/team-up.sh --hook-clear`. 사용자 원문 「응, 훅 넣어서 진행해」. 모의 테스트 101/101. 실화면 확인(팀장 pane `/clear`)·커밋은 별도.
- pushallow-r1(2026-10-13, 권한 정리): 프로젝트 `.claude/settings.json` ask `Bash(git push *)`가 auto 모드보다 우선해 위임된 `main` 푸시도 매번 확인창을 띄움 → 사용자가 직접 ask에서 빼고 allow `Bash(git push origin main)`(정확 일치)를 추가(deny 무변경). 사용자 원문 「네」. critic r1 REJECT(위임 밖 푸시도 auto 판단으로 확인 없이 갈 수 있음) → 설정은 두고 docs/04에 실제 효과를 적음(cf-lead 결정, deny 보강은 안 함).
- layout-r1(2026-10-14, 팀 환경 보강): GJCH 팀과 합의한 배치 기준을 `scripts/team-up.sh` 기능으로. 사용자 원문 「커밋 승인, 배치 작업도 진행, 덤도 진행」. 새 pane은 기준 자리에 만들고, `--up`·`--resume-impl` 끝과 `--layout`에서 팀장·impl이 같은 탭이면 보정(모양이 맞으면 비율만 resize, 다르면 임시 탭 경유 `pane move --no-focus`). critic은 같은 탭일 때만 함께, 아니면 팀장 0.6/impl 아래만. Sidebar 등 세 석 밖 pane은 옮기거나 크기를 바꾸거나 닫지 않고, 임시 탭은 남은 pane이 모두 agent 없을 때만 닫는다. 배치 실패는 기동을 되돌리지 않고 종료 코드만 비0 + 안내. 점검(인자 없음)은 경고만, `--hook-clear`는 배치를 읽지도 않는다.
- impl-agy-r1(2026-10-15, 팀 환경): 구현 담당(`cf-impl`)을 GJC에서 `agy --model gemini-4-argon-high --sandbox`로 정식 교체(`AGENTS.md`·`scripts/team-up.sh`·`ci/test-team-up.sh`·`ci/mock/herdr`·`docs/04-team-and-env.md` 반영, `--resume-impl`을 `agy --conversation <id>`로 바꾸고 GJC 전용 `/rename` 처리 제거). 사용자 원문 「2. 교체 승인」.
- agyrule-r1(2026-10-15, 팀 환경): agy 전역 `toolPermission`을 `proceed-in-sandbox`로 둔 설정과 CF·GJCH 합의 절차(확인창은 lead가 1번만 선택, 2·3번 금지, 전역 `settings.json` 변경 시 팀 간 사전 공지·순차 재기동)를 `AGENTS.md`와 `docs/04-team-and-env.md`에 반영. 사용자 원문 「규칙 반영 승인」.
- acceptedits-r1(2026-10-15, 팀 환경): 구현 agy(`cf-impl`) 기동·복구 명령에 `--mode accept-edits`를 추가해 `agy --model gemini-4-argon-high --mode accept-edits --sandbox`(복구 `agy --conversation <id> --model gemini-4-argon-high --mode accept-edits --sandbox`)로 갱신(`AGENTS.md`·`scripts/team-up.sh`·`ci/test-team-up.sh`·`docs/04-team-and-env.md`). 사용자 원문 「2. 승인」.

## P0–P2 완료 기록
- P0(2026-10-11): 문서 01–05·LICENSE·NOTICE·third_party — 커밋 `b911a17`.
- P1(2026-10-11): 규칙·권한·team-up 3석 이식(`236e92c`), 배치 확인 이식(`5c6cb4a`). 모의 테스트 88/88, 점검 3석 alive. critic APPROVE 전 회차.
- P2(2026-10-11): 시험 세션 실측 U1–U3(관측 가능 범위), 타입 시그니처 8건 확정, U4(문서상 최소 2.1.287/검증 2.1.296)·U5(미확인), T1 결정(bunx)·D-3 유지 기록 — D-2는 **유지**(긴 형식)로 기록됐고, 폭 기준 전환(넓음 `ctx 53% · Xk/Yk`·좁음 `ctx 53%`)은 P2 뒤 사용자 결정 「형식 바꾸기」→「작은 화면은 ctx 53% 유지, 넓은 화면으로 변경되면 원래대로 복원」(plan-r1에서 반영). 커밋 `b3ad6df`. statusLine은 사용자 결정 「전역으로 꺼」로 이미 제거(백업 `~/.claude/settings.json.bak-20261011-164943-statusline`).

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
- 사용자 승인: **전역 설정 변경**(플러그인 설치 = `~/.claude` 기록) 원문.
- 담당: lead(전역 변경 실행·백업) · impl(기록).
- **결과(2026-10-11 20:31, 사용자 원문 「네, 커밋하고 P6 진행해」)**: cf-lead가 `~/.claude/settings.json`을 백업(`…bak-20261011-203117-p6`)한 뒤 `claude plugin install ctx-footer --marketplace mrsono0/ctx-footer`를 실행했다.
  - 설치 출력: «Successfully added marketplace: ctx-footer (declared in user settings)», «Successfully installed plugin: ctx-footer@ctx-footer (scope: user)». 저장소는 HTTPS로 클론했다.
  - `claude plugin list`: ctx-footer@ctx-footer · 0.1.0 · user · ✔ enabled.
  - 전역 설정 변경은 두 항목뿐이다(백업과 `jq -S` diff로 확인).
    - `enabledPlugins["ctx-footer@ctx-footer"] = true`
    - `extraKnownMarketplaces["ctx-footer"]`(source github, repo `mrsono0/ctx-footer`)
  - 설치 캐시(`~/.claude/plugins/cache/ctx-footer/ctx-footer/0.1.0/`)에는 `plugin/` 내용만 들어 있다. docs·scripts·AGENTS.md는 없다. docs/03 §4의 구조와 일치한다.
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
    - 실사용 `~/.claude/settings.json`의 해시는 바뀌지 않았다.
    - 완료 기준 「태그가 원격에 있고 고정 설치가 동작」을 충족한다.
  - 검증 기준에서 달라진 점
    - 계획한 검증은 「실화면(태그 고정 설치 1회)」이었다. 이번에는 격리 설치에서 설치·목록까지만 확인했고, 그 설치본으로 세션 바닥줄(실화면)은 보지 않았다.
    - 실화면은 같은 0.1.0 판을 P6 설치본으로 확인한 것(위 P6 결과)으로 갈음한다.
    - 근거: `git diff 27441ff v0.1.0 -- plugin/ .claude-plugin/`은 0행이다. P6 설치 직전에 푸시한 `main`(`27441ff`)부터 태그 사이에는 문서 커밋만 있다.
    - 고정 설치본으로 실화면을 확인하는 것은 「미확인」이다.
  - 재확인(2026-10-12, cf-lead, 사용자 원문 「1」 — 선택지 1 그대로 기록 / 2 로그인해서 실화면 / 3 그대로 둠)
    - 같은 격리 방식으로 `claude plugin install ctx-footer --marketplace mrsono0/ctx-footer#v0.1.0`을 다시 실행해 성공했다. `claude plugin list`에서 0.1.0 enabled, 격리 `installed_plugins.json`의 `gitCommitSha`는 `fbb8eab`(태그 대상 커밋)다.
    - 같은 env로 띄운 `claude`(v2.1.296)는 테마 선택 뒤 «Select login method:» 화면에서 멈췄다. 사용자 결정으로 로그인하지 않고 종료했다.
    - 격리 고정 설치본과 P6 설치본(`~/.claude/plugins/cache/ctx-footer/ctx-footer/0.1.0`, 위 P6 실화면 판)의 파일 sha256 목록을 비교했다. 실행 중 생기는 잠금 표식 `.in_use/`를 빼면 8개 파일(`.claude-plugin/plugin.json`, `hooks/hooks.json`, `hooks/register.ts`, `LICENSE`, `NOTICE`, `tests/register.test.ts`, `tsconfig.json`, `types/index.d.ts`)이 바이트 동일하다.
    - 실사용 `~/.claude/settings.json` 해시(sha16 `d11ef39578bd9008`)는 확인 전후 같다.
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
| U1 연결자 | **닫음**(연결 모양): `modes` 항목 사이 ` & `, 같은 흐린 색, 오른쪽 끝 | docs/07 「남은 관찰 정리」 U1(2026-10-14) — 사본 계측 라벨로 관찰. 엔진 라벨(`memory paused`·`account memory: …`)은 띄우는 조건을 못 찾아 미확인(전역 설정 변경 시도 안 함) |
| U5 데스크톱 | **유지**(사용자 결정으로 건너뜀, 미확인): 데스크톱 표면 잘림 모양 | 앱 2.19675.0 있음(2026-10-14). GUI라 터미널에서 관찰 불가 → 사용자 원문 「2. 건너띔」(2026-10-14)으로 화면 확인 안 함(docs/07 U5) |
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

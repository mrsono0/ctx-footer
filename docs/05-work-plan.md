# 05. 상세 작업계획서

원칙: 단계마다 **목적 → 선행 → 작업 → 산출물 → 완료 기준 → 검증(모의 vs 실화면) → 사용자 승인 → 담당**. 앞 단계의 완료 기준을 넘어야 다음으로 간다. 확인된 요구만 만들고, 테스트는 완료 기준만큼(동작이 바뀌면 기존 테스트 1회).

이 문서는 plan-r1(2026-10-11)로 P2 실측(docs/06)과 사용자 결정을 반영해 갱신했다. docs/02 §6의 미확인 U1–U5는 docs/06이 관측·기록했다(남은 미확인은 아래 표 및 docs/06 참조).

## 한눈에
| 단계 | 이름 | 핵심 산출물 | 사용자 승인 | 상태 |
|---|---|---|---|---|
| P0 | 프로젝트 기반 | 폴더·git·README·docs 01–05·차용 출처 | 계획 확정, 라이선스 | **완료** `b911a17` |
| P1 | 팀·환경 구축 | 팀 3석·AGENTS/CLAUDE·권한 2종·team-up.sh(배치 확인 포함)·모의 테스트 88/88 | 규칙 파일, 커밋 | **완료** `236e92c`·`5c6cb4a` |
| P2 | 스펙 확정 스파이크 | docs/06(U1–U5 실측·타입 확정·T1/D-1~D-8 판정) | 없음 | **완료** `b3ad6df` |
| P3 | 스캐폴딩 | marketplace.json·plugin/ 7종·dev-check.sh | 커밋 | 대기 |
| P4 | 구현·단위 테스트 | plugin/hooks/register.ts·plugin/tests/register.test.ts | 커밋 | 대기 |
| P5 | 실화면 검증 | docs/07-acceptance.md(A1–A5) | 커밋 | 대기 |
| P6 | 상시 적용 | GitHub 마켓플레이스 user scope 설치(M2 결정) | **전역 설정 변경** 원문 | 대기 |
| — | 릴리스 | version 올림 + 태그(`v0.1.0`, M1 결정) + 푸시 | 버전 커밋·태그·푸시 원문 | 대기 |

(P7 공개 배포는 폐지 — 구조는 P3가, 첫 설치·공개는 P6이 담당하고 남은 절차만 아래 「릴리스」로 둔다.)

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

## 릴리스 (P7 흡수)
- 목적: 배포 버전을 GitHub 원격에 올린다(공개 저장소 `mrsono0/ctx-footer`, 공식 디렉터리 등록 없음).
- 선행: P5 인수 통과 뒤 `v0.1.0` 태그(M1 결정, 2026-10-11).
- 작업: `plugin/.claude-plugin/plugin.json` version 올림 → 커밋(승인) → 태그(예: `v0.1.0`) → 푸시(lead). 이후 릴리스마다 반복.
- 산출물: 버전 커밋·태그·푸시 기록(회차 폴더).
- 완료 기준: 태그가 원격에 있고 `mrsono0/ctx-footer#vX.Y.Z` 고정 설치가 동작.
- 검증: 실화면(태그 고정 설치 1회).
- 사용자 승인: 버전 커밋 · 태그·푸시 원문(M1 시점 결정 포함).
- 담당: impl(버전·태그 준비) · lead(푸시·사용자 승인).

## 미결정·미확인 (닫는 방법 포함)
| 항목 | 내용 | 닫는 방법 |
|---|---|---|
| M1 | **결정**: 첫 릴리스는 P5 인수 뒤 `v0.1.0` 태그 | 사용자 원문 「1–3 진행, M1·M2·M4(한글로) 권장대로」(2026-10-11). 태그·푸시 승인은 릴리스 시 별도 원문 |
| M2 | **결정**: P6 설치는 GitHub 마켓플레이스 **user scope** 설치 | 같은 원문. 전역 설정 변경 승인은 설치 시 별도 원문 |
| M3 | **닫음**: bunx 고정 TypeScript `7.0.2`(npm 배포 2026-07-08, 안정판) | `scripts/dev-check.sh`와 같은 값. P3에서 bunx 동작 확인(2026-10-11) |
| M4 | **결정**: README 한글 | 같은 원문(공개 저장소) |
| M5 | 폭 기준 전환값 `WIDE_COLUMNS`(출발 100) | P5 실측으로 확정(사용자 확인) |
| U1 연결자 | `modes` 라벨 간 ` & ` 실화면 | P5에서 다른 모드 라벨 활성화 시 관찰, 불가 시 유지 |
| U5 데스크톱 | 데스크톱 표면 잘림 모양 | 데스크톱 앱 확보 시 실측(없으면 유지) |
| D-7 실패 경로 | 훅 실패 시 엔진 기본 그림 | P5에서 의도 실패 시험(선택) 또는 유지 |
| U3 이벤트 시점 | `session.measure` 발생 시점(compact 직후/첫 응답)·빈 context 수신 | P5에서 가능하면 관찰, 없으면 유지(docs/06 미확인 4) |

## 위험과 대응
| 위험 | 대응 |
|---|---|
| 좁은 터미널에서 라벨이 다음 줄로 넘어감 | **폭 기준 형식 전환으로 대응**(`ctx 53% · Xk/Yk` ↔ `ctx 53%`, 사용자 결정). 기준값(M5)·실제 모양은 P5 실측 — P2에서 8자 라벨 `ctx test`도 약 67열에서 줄바꿈됐으므로(docs/06 U1) 전환만으로 두 줄을 완전히 막는다고 보장하지 않는다 |
| 엔진 업데이트로 props·이벤트 변경 | D-1(엔진 그림 유지)로 영향 최소화, `claude plugin validate`를 업데이트 때 재실행 |
| 압축 직후 이전 퍼센트 표시 | D-3 유지로 수용(사용자 결정 「2. 권장」) — 오해 소지 낮고 조치 없음 |
| 팀 운영 비용이 작업보다 큼 | 상주 3석, 조사는 cf-critic이 겸함. 남은 단계는 짧게 |
| 차용 라이선스 누락 | plugin/LICENSE·NOTICE 사본(P3), critic 고정 질문 |

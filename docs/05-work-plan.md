# 05. 상세 작업계획서

원칙: 단계마다 **목적 → 선행 → 작업 → 산출물 → 완료 기준 → 검증 → 승인**. 앞 단계의 완료 기준을 넘어야 다음으로 간다. 확인된 요구만 만들고, 테스트는 완료 기준만큼(동작이 바뀌면 기존 테스트 1회).

## 한눈에
| 단계 | 이름 | 핵심 산출물 | 사용자 승인 |
|---|---|---|---|
| P0 | 프로젝트 기반 | 폴더·git·README·docs 01–05·차용 출처 | 계획 확정, 라이선스 |
| P1 | 팀·환경 구축 | herdr 작업공간·팀 3석·AGENTS/CLAUDE·권한 파일·team-up.sh·모의 테스트 | 규칙 파일, 커밋 |
| P2 | 스펙 확정 스파이크 | 미확인 U1–U5 실측 기록, 확정 타입 | 없음(읽기·시험 세션만) |
| P3 | 스캐폴딩 | plugin.json·hooks.json·types·tsconfig·dev-check.sh | 커밋 |
| P4 | 구현·단위 테스트 | register.ts·register.test.ts | 커밋 |
| P5 | 실화면 검증 | A1–A3 관찰 기록 | 없음 |
| P6 | 상시 적용 | 전역 로드 설정, statusLine 정리 | **전역 설정 변경** |
| P7 | (선택) 공개 배포 | GitHub 저장소·marketplace.json | 저장소 생성·푸시 |

## P0. 프로젝트 기반 — 진행 중
- 목적: 계획과 근거를 한곳에 둔다.
- 작업: `/Users/mrsono0/LectureForgeProjects/ctx-footer` 생성, `git init`(main), `.gitignore`·`.gitattributes`, README, docs 01–05, `third_party/dashband/`(LICENSE·SOURCE.md·.ref 사본, 커밋 28496787).
- 라이선스: MIT 확정(사용자 원문 「네, MIT로 확정하고 커밋한 뒤 팀 띄워」). `LICENSE`, `NOTICE`(dashband 고지).
- 완료 기준: 문서 5개가 서로 모순 없고, 사용자가 계획을 확정.
- 승인: 「계획 확정」, 라이선스, 첫 커밋.

## P1. 팀·환경 구축
- 목적: 이 프로젝트 전용 herdr 팀을 띄우고 규칙·권한·기동 스크립트를 갖춘다.
- 선행: P0 확정.
- 작업 (순서대로)
  1. 사용자가 herdr에 작업공간 `ctx-footer`를 만들고 첫 pane에서 `claude`(cf-lead) 실행 — 또는 LFI 팀장이 `herdr workspace create` + `herdr pane run`으로 대신(사용자 승인 후)
  2. cf-lead가 아래 줄 3칸 중 2칸에 `gjc --mpreset glm53-gemini-codex56`, `codex … -s read-only -a on-request`를 띄우고 `herdr agent rename`으로 `cf-impl`·`cf-critic`
  3. cf-lead 초안 → cf-impl 반영: `AGENTS.md`, `CLAUDE.md`, `.claude/settings.json`, `.codex/rules/herdr.rules`(04 문서 §3·§4) → cf-critic 리뷰(규칙 3회차)
  4. cf-impl: LFI `scripts/team-up.sh`·`ci/test-team-up.sh`·`ci/mock/herdr` 이식, 변수만 교체(04 §5) → 모의 테스트 1회 → cf-critic 리뷰
  5. critic 재시작 후 `.codex/rules` 로드 확인(LFI에서 쓴 방법: `herdr agent list`·`pane read`가 프롬프트 없이 실행)
- 산출물: 위 파일들, 팀 3석 alive.
- 완료 기준: `scripts/team-up.sh` 점검 모드가 3석 alive·조치 없음, 모의 테스트 전부 통과, critic APPROVE.
- 승인: 규칙 파일 변경, 커밋(·푸시는 저장소 생기면).

## P2. 스펙 확정 스파이크
- 목적: 02 문서 미확인 U1–U5를 실측으로 닫고 타입을 확정한다.
- 선행: P1.
- 작업
  1. 최소 mod(라벨 고정 문자열 `ctx test`를 `modes`에 더하기만) 를 임시 폴더에 두고 **시험 세션**(`claude --plugin-dir <임시 폴더>`, 새 herdr pane)에서 로드 — 실사용 세션·전역 설정은 건드리지 않는다
  2. 화면을 `herdr pane read --source visible`로 기록: U1(붙는 위치·연결자·잘림), U2(`modes` 빈 경우)
  3. 값 연결 후: U3(압축 직후·첫 응답 전), 몇 턴 관찰
  4. 깔린 `.claude-plugin/types/claude-code/index.d.ts`로 `SessionMode`·`SessionContextUsage`·`session.measure` 시그니처 확정, U4 최소 버전 판단
  5. (가능하면) 데스크톱 앱 U5 — 안 되면 「미확인」으로 남김
- 산출물: `docs/06-spike-results.md`(관측 사실 / 근거(화면·파일:줄) / 미확인).
- 완료 기준: U1–U3 닫힘, D-1~D-3 유지 또는 근거 있는 수정안.
- 검증: cf-critic가 기록과 원문 대조. 시험 세션 종료·임시 폴더는 스크립트 정리(직접 rm -rf 금지 — 사용자에게 정리 요청 또는 `trap` 스크립트).

## P3. 스캐폴딩
- 목적: 03 문서 §4 구조를 만든다(기능 코드 없이).
- 작업: `.claude-plugin/plugin.json`(name `ctx-footer`, version `0.1.0`, description, `"types"`), `hooks/hooks.json`, `types/index.d.ts`(PluginState 계약·ContextReading), `tsconfig.json`, 빈 `hooks/register.ts`(`register` 내보내기만), `scripts/dev-check.sh`(validate + tsc + test + 금지 API 검색), `LICENSE`·`NOTICE`.
- 완료 기준: `claude plugin validate .` 통과, `scripts/dev-check.sh` 통과(테스트 0개 허용).
- 승인: 커밋.

## P4. 구현·단위 테스트
- 목적: 03 §3 의사 코드를 구현한다.
- 작업: `register.ts`(session.start·session.measure·SessionMode, dashband 고지 주석), `register.test.ts`(03 §5의 3가지).
- 완료 기준: `scripts/dev-check.sh` 통과, 금지 API 0건, 코드 100줄 이내(목표 50줄 안팎).
- 검증: cf-critic 리뷰(도구 3회차) — 고정 질문: "N1 안전을 어기는가", "요구 밖 기능이 있는가", "실패 시 엔진 기본 그림이 남는가".
- 승인: 커밋.

## P5. 실화면 검증
- 목적: 인수 기준 A1–A3을 실제 화면으로 확인.
- 작업: 시험 세션에서 `--plugin-dir`로 로드, statusLine을 끈 상태(시험 세션 한정 설정 또는 `--settings`)로 하단 한 줄 확인, 2턴 이상 값 변화, 첫 응답 전 모양.
- 산출물: `docs/07-acceptance.md`(화면 기록·판정).
- 완료 기준: A1–A5 충족.

## P6. 상시 적용 (사용자 승인 필수)
- 목적: 모든 세션에서 쓰고, 커스텀 statusLine을 정리해 하단을 한 줄로.
- 선택지(사용자 결정): ① `~/.claude/settings.json` `env.CLAUDE_CODE_PLUGIN_DIRS`에 폴더 경로 ② 로컬 마켓플레이스(`claude plugin marketplace add <folder>` + `claude plugin install`) — ①이 단순, ②는 `/plugin`으로 켜고 끄기 쉬움.
- 작업: 백업 → 적용 → `/reload-plugins` 또는 새 세션 → 화면 확인 → `statusLine` 제거(백업) → 확인.
- 완료 기준: 실사용 세션 하단 한 줄, 되돌리는 방법 문서화(README).
- 승인: 「전역 설정 변경」 원문.

## P7. (선택) 공개 배포
- 사용자가 요청할 때만. GitHub 저장소 생성(공개 여부 결정)·`marketplace.json`·README 설치 줄·첫 푸시.

## 위험과 대응
| 위험 | 대응 |
|---|---|
| `SessionMode` 라벨이 좁은 터미널에서 잘림 | P2에서 관찰, 형식을 `ctx 53%`로 줄이는 옵션 |
| 엔진 업데이트로 props·이벤트 변경 | D-1(엔진 그림 유지)로 영향 최소화, `claude plugin validate`를 업데이트 때 재실행 |
| 압축 직후 값 공백 | D-3(라벨 생략) |
| 팀 운영 비용이 작업보다 큼 | 상주 3석, 조사는 cf-critic이 겸함. P1을 짧게 |
| 차용 라이선스 누락 | P3에서 NOTICE·주석, critic 고정 질문 |

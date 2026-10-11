# 03. 설계

## 1. 구조
```
session.start ──► $.session.usage() ──┐
session.measure(e.context) ───────────┼─► update(ctx atom) ─► (redraw)
                                      │
ui.render {component:'SessionMode'} ──┴─ read(ctx atom) ─► next({...e, props:{modes:[...modes, label]}})
```
- 이벤트 2개(값 갱신) + 그리기 훅 1개. 타이머·파일·프로세스·네트워크 없음.

## 2. 결정
| ID | 결정 | 근거·대안 |
|---|---|---|
| D-1 | **엔진 그림 유지**: `modes`에 라벨 문자열을 더해 `next`로 넘긴다(색 없음, 엔진의 흐린 글씨) | 가장 작은 변경, 엔진 모양 변화에 강함. 대안: dashband처럼 자기 트리로 색 표시 — 사용자가 색을 원하면 P6에서 옵션으로 |
| D-2 | 라벨 형식 **폭 기준 전환**: `columns ≥ 기준값`(출발 100, M5)이면 `ctx 53% · 531k/1000k`, 미만 또는 viewport 없음이면 `ctx 53%` | 변경(2026-10-11, 사용자 원문 「작은 화면은 ctx 53% 유지, 넓은 화면으로 변경되면 원래대로 복원」). 폭은 그리기 훅의 `e.viewport?.columns`(타입 [T 9751] `viewport?`, [T 10398–10403] `columns` «Cells across», [T 9748] 폭 변화 시 재그리기 — 타이머·폭 감시 이벤트 불필요). 관측 근거 docs/06 U1 — 관측 라벨 `ctx test`(8자)도 약 67열에서 줄바꿈. 기준값·실제 모양은 P5 실측 |
| D-3 | 값이 없을 때(첫 응답 전) 라벨을 **붙이지 않는다** | **유지**(사용자 결정 「2. 권장」, 2026-10-11). docs/06 U3 관측 — `/compact` 뒤 다음 응답 전까지 이전 표시가 유지되며 이를 허용한다(압축 시 atom 초기화 이벤트는 추가하지 않음) |
| D-4 | 상태: `atom({ plugin: 'ctx-footer', key: 'context' }, null)` 하나(값 `ContextReading \| null`) | `ContextReading = { percent: number; tokens: number \| null; window: number }` — 폭 전환에 토큰·창 필요(D-2). 값 없음 판정은 `percent == null`. 계약 `types/index.d.ts` |
| D-5 | 표면: `e.surface`가 `terminal`·`desktop`일 때만(엔진이 그 둘에만 raise) | 추가 분기 불필요, 방어적으로 그 외는 `next(e)` |
| D-6 | 설정(userConfig) 없음 | 미니멀. 형식·색 옵션은 요구가 확인되면 |
| D-7 | 실패 시 `next(e)`로 엔진 기본 그림 | N4 |
| D-8 | 차용 코드 파일 머리에 dashband MIT 고지 주석 | N5 |

## 3. 모듈 의사 코드 (`plugin/hooks/register.ts`)
```ts
import { atom, read, update } from 'claude-code'
import type { Register, SessionContextUsage } from 'claude-code'
// Portions adapted from dashband (MIT, (c) 2026 Egon Leitner): usage reading pattern, SessionMode hook shape.

type ContextReading = { percent: number; tokens: number | null; window: number }

const WIDE_COLUMNS = 100 // 폭 기준값 — 출발값, P5 실측으로 확정(미결정 M5)
const ctx = atom({ plugin: 'ctx-footer', key: 'context' } as const, null)

export const toReading = (c: SessionContextUsage): ContextReading | null =>
  c.percent == null ? null : { percent: c.percent, tokens: c.tokens ?? null, window: c.window }

export const label = (r: ContextReading, columns: number | null): string => {
  const pct = `ctx ${r.percent}%`
  if (columns === null || columns < WIDE_COLUMNS || r.tokens === null) return pct
  return `${pct} · ${Math.round(r.tokens / 1000)}k/${Math.round(r.window / 1000)}k`
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const { context } = await $.session.usage()
    await update($, ctx, () => toReading(context))
    return next(e)
  })
  on('session.measure', async ($, e, next) => {
    await update($, ctx, () => toReading(e.context))
    return next(e)
  })
  on('ui.render', { component: 'SessionMode' }, async ($, e, next) => {
    const r = await read($, ctx)
    if (r === null) return next(e)
    const columns = e.viewport?.columns ?? null
    return next({ ...e, props: { ...e.props, modes: [...e.props.modes, label(r, columns)] } })
  })
}
```
- 값 없음 판정은 `percent == null`(D-3). 토큰이 없으면(percent는 있음) 넓은 화면에서도 짧은 형식.
- 폭은 그리기 훅의 `e.viewport?.columns`로만 읽는다 — 폭 감시 타이머·이벤트 없음([T 9748] 폭 변화 시 엔진이 다시 그린다).
- `.tsx` 불필요(JSX 없음) → `register.ts`. D-1을 색 트리로 바꾸면 `.tsx`.
- 시그니처는 docs/06에서 깔린 타입으로 확정(파일:줄 기록). 구조는 P2 시험 코드와 같고 폭 전환만 추가.

## 4. 스캐폴딩 (배포 구성 확정 — BRIEF plan-r1 3절, 근거 cf-critic dist-r1·cf-lead 대조 완료)
```
ctx-footer/                        # 저장소 루트 = 마켓플레이스 루트
├─ .claude-plugin/
│  └─ marketplace.json             # name "ctx-footer", owner { name "mrsono0" }, plugins [{ name "ctx-footer", source "./plugin", description }]
├─ plugin/                         # 설치 때 캐시로 복사되는 것은 이 폴더뿐
│  ├─ .claude-plugin/plugin.json   # name ctx-footer, version 0.1.0, description, author, "types": "./types/index.d.ts"
│  ├─ hooks/hooks.json             # { "modules": ["./register.ts"] }
│  ├─ hooks/register.ts            # 모듈(§3 의사 코드)
│  ├─ types/index.d.ts             # PluginState 계약: 'ctx-footer': { context: ContextReading | null } (D-4)
│  ├─ tests/register.test.ts       # claude plugin test (엔진 tsconfig include: hooks/types/tests)
│  ├─ tsconfig.json                # extends ./.claude-plugin/types/tsconfig.json (엔진 제공)
│  └─ LICENSE, NOTICE
├─ scripts/
│  ├─ team-up.sh                   # herdr 팀 기동·복구(04 문서)
│  └─ dev-check.sh                 # validate + tsc + test + 금지 API 검사 — plugin/ 대상
├─ ci/                             # team-up 모의 테스트(모의 herdr)
├─ docs/                           # 01~06
├─ third_party/dashband/           # 차용 출처 사본(.ref, LICENSE, SOURCE.md) — 로드 대상 아님
├─ AGENTS.md / CLAUDE.md           # 팀 규칙(04 문서)
└─ README.md / LICENSE / NOTICE
```
- `plugin/.claude-plugin/types/`는 엔진이 쓰는 파일이라 `.gitignore`.
- "no Node.js, bundler, or build step" — 빌드 단계 없음(공식 근거, 대조 완료).

## 5. 테스트 설계 (요구만큼)
- 단위(`plugin/tests/register.test.ts`, `claude plugin test plugin`): ① `toReading` — percent 있음/없음(없음 → null), tokens 없으면 `tokens: null` ② `label` 형식·폭 경계 — `columns` 기준값-1(짧은 형식)/기준값(긴 형식)/없음(짧은 형식), `tokens: null`이면 긴 폭에서도 짧은 형식 ③ SessionMode 훅 — 값 없음이면 `modes` 그대로, 값 있음이면 끝에 라벨 하나, 기존 `modes` 순서 보존.
- 정적(`scripts/dev-check.sh`, plugin/ 대상): `claude plugin validate`, `bunx` 고정 tsc(T1 — 버전은 P3에서 확정, docs/06 결정 T1), 금지 API 검색(`\$\.(process|fs|net|store)|session\.(send|append|authorize)|fetch\(`) 0건.
- 실화면(P5): `--plugin-dir ./plugin`로 띄워 A1~A3 관찰, 화면 기록은 `herdr pane read`.

## 6. 설치·배포 (F7)
- 개발: `claude --plugin-dir ./plugin`(그 세션만). dev-check는 `plugin/` 대상.
- 상시 설치(P6, 사용자 원문 승인 = 전역 설정 변경): `claude plugin install ctx-footer --marketplace mrsono0/ctx-footer`(v2.1.292+) 또는 `/plugin marketplace add mrsono0/ctx-footer` → `/plugin install ctx-footer@ctx-footer`. 태그 고정 `mrsono0/ctx-footer#v0.1.0`. statusLine 정리는 이미 완료(2026-10-11, 사용자 결정 「전역으로 꺼」, 백업 `~/.claude/settings.json.bak-20261011-164943-statusline`).
- 릴리스: `plugin.json` version 올림 + git 태그(한 곳에만 버전 존재). 첫 태그 시점은 미결정 M1. 공식 마켓플레이스 디렉터리 등록은 안 한다.

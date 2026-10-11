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
| D-2 | 라벨 형식 `ctx 53% · 531k/1000k` | statusLine에서 쓰던 형식 유지. k는 `Math.round(tokens/1000)`, 창은 `window/1000` |
| D-3 | 값이 없을 때(첫 응답 전·압축 직후) 라벨을 **붙이지 않는다** | 빈 값을 0%로 오해하지 않게. 대안 `ctx …` |
| D-4 | 상태: `atom({ plugin: 'ctx-footer', key: 'context' }, null)` 하나 | 계약 `types/index.d.ts`: `'ctx-footer': { context: ContextReading | null }` |
| D-5 | 표면: `e.surface`가 `terminal`·`desktop`일 때만(엔진이 그 둘에만 raise) | 추가 분기 불필요, 방어적으로 그 외는 `next(e)` |
| D-6 | 설정(userConfig) 없음 | 미니멀. 형식·색 옵션은 요구가 확인되면 |
| D-7 | 실패 시 `next(e)`로 엔진 기본 그림 | N4 |
| D-8 | 차용 코드 파일 머리에 dashband MIT 고지 주석 | N5 |

## 3. 모듈 의사 코드 (`hooks/register.ts`)
```ts
import { atom, read, update } from 'claude-code'
import type { Register, SessionContextUsage } from 'claude-code'
import type { ContextReading } from '../types'
// Portions adapted from dashband (MIT, (c) 2026 Egon Leitner): usage reading pattern, SessionMode hook shape.

const ctx = atom({ plugin: 'ctx-footer', key: 'context' } as const, null)

export const toReading = (c: SessionContextUsage): ContextReading | null =>
  c.percent == null || c.tokens == null ? null : { percent: c.percent, tokens: c.tokens, window: c.window }

export const label = (r: ContextReading): string =>
  `ctx ${r.percent}% · ${Math.round(r.tokens / 1000)}k/${Math.round(r.window / 1000)}k`

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
    return next({ ...e, props: { ...e.props, modes: [...e.props.modes, label(r)] } })
  })
}
```
- `.tsx` 불필요(JSX 없음) → `register.ts`. D-1을 색 트리로 바꾸면 `.tsx`.
- 정확한 타입 이름·시그니처는 P2에서 깔린 타입(`.claude-plugin/types/`)으로 확정.

## 4. 스캐폴딩
```
ctx-footer/
├─ .claude-plugin/
│  ├─ plugin.json            # name ctx-footer, version, description, "types": "./types/index.d.ts"
│  └─ marketplace.json       # (P7, 사용자 요청 시) 로컬/공개 마켓플레이스
├─ hooks/
│  ├─ hooks.json             # { "modules": ["./register.ts"] }
│  ├─ register.ts            # 모듈(위 의사 코드)
│  └─ register.test.ts       # claude plugin test
├─ types/index.d.ts          # PluginState 계약 + ContextReading
├─ tsconfig.json             # 깔린 타입의 tsconfig를 extends (dashband와 같은 방식)
├─ third_party/dashband/     # 차용 출처 사본(.ref, LICENSE, SOURCE.md) — 로드 대상 아님
├─ scripts/
│  ├─ team-up.sh             # herdr 팀 기동·복구(04 문서)
│  └─ dev-check.sh           # validate + tsc + test + 금지 API 검색 한 번에
├─ ci/                       # team-up 모의 테스트(모의 herdr)
├─ docs/                     # 01~05
├─ AGENTS.md / CLAUDE.md     # 팀 규칙(04 문서)
├─ README.md / LICENSE / NOTICE
```
- `.claude-plugin/types/`는 엔진이 쓰는 파일이라 `.gitignore`.

## 5. 테스트 설계 (요구만큼)
- 단위(`claude plugin test`): ① `toReading` — percent·tokens 있음/없음 ② `label` 형식(반올림 포함) ③ SessionMode 훅 — 값 없음이면 `modes` 그대로, 값 있음이면 끝에 라벨 하나, 기존 `modes` 순서 보존.
- 정적: `claude plugin validate`, `tsc -p .`, 금지 API 검색(`\$\.(process|fs|net|store)|session\.(send|append|authorize)|fetch\(`) 0건.
- 실화면(P5): `--plugin-dir`로 띄워 A1~A3 관찰, 화면 캡처는 `herdr pane read`.

## 6. 설치·배포
- 개발: `claude --plugin-dir /Users/mrsono0/LectureForgeProjects/ctx-footer`
- 상시(P6, 사용자 승인): `~/.claude/settings.json` `env.CLAUDE_CODE_PLUGIN_DIRS`에 폴더 추가 **또는** 로컬 마켓플레이스(`claude plugin marketplace add <folder>` + install) → 그 뒤 커스텀 `statusLine` 제거.
- 공개(P7, 요청 시): GitHub 저장소 + `.claude-plugin/marketplace.json`, README에 `/plugin install ctx-footer --marketplace <owner>/<repo>`.

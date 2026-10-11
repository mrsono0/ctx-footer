# 02. 스펙 분석

근거 표기: [T] = Claude Code 2.1.296 번들 타입 정의 `plugin-authoring/types/claude-code.d.ts`(세션이 쓴 사본, 줄 번호), [D] = 공식 문서 URL, [B] = dashband 원본(`third_party/dashband/*.ref`, 커밋 28496787). 확인 못 한 것은 「미확인」.

## 1. 그릴 자리: `SessionMode`
- [D] https://code.claude.com/docs/en/plugins/mods/interface — "`InfoNotice`, `SessionMode`, `PromptHint` | Status lines under the logo, the mode labels in the footer, and the hint line under the prompt"
- [T 10197–10211] "The dim mode labels at the right of the prompt footer (`focus`, `memory paused`), joined by ` & `. One instance. A hook adds a mode by rewriting `modes`, removes one by filtering, or draws its own tree. Raised on the terminal and desktop surfaces only." props: `modes: readonly string[]` ("empty when there are none").
- 결론: 바닥줄 **오른쪽** 모드 라벨 자리. `modes`에 문자열 하나를 더하면 엔진이 자기 방식(흐린 글씨, ` & ` 연결)으로 그린다 → 엔진 그림을 그대로 쓰는 가장 작은 변경.
- [D] interface 문서 "Change a detail": `return next({ ...e, props: { ...e.props, ... } })` 패턴.
- 비교: [B 294–340] dashband는 `modes`를 앞에 두고 자기 색 트리(`Box`/`Text`)를 그린다(엔진 그림 대체). 색을 쓰려면 이 방식이 필요하다.

## 2. 값: `$.session.usage()`와 `session.measure`
- [T 10958–] `SessionContextUsage`: `tokens?`(마지막 응답 입력 토큰, statusLine `total_input_tokens`), `window`(창 크기, `context_window_size`), `percent?`(0–100 정수, `used_percentage`). "absent until the first response of the live window: a fresh session, or one just compacted".
- [T 4415–4425] `session.measure`: "Fires when the engine measures the session and a unit moved: after each main-thread turn … pushed, not polled". 입력에 `context`(breakdown 없음).
- [T 2845] 예: `const { context } = await $.session.usage()`.
- [B 148–152, 220–257] dashband: `session.start`에서 `$.session.usage()`로 첫 값, `session.measure`에서 갱신, `atom`+`update`로 저장해 그리기에서 `read`.

## 3. 상태와 다시 그리기
- 스킬 안내(plugin-authoring SKILL.md): `atom(ref, initial)`, 그리기에서 `read($, atom)`, 다른 이벤트에서 `update($, atom, fn)` — "the write redraws the readers; each value declared in the contract". `$.state` 값을 쓰는 mod는 `types/index.d.ts`에 `interface PluginState { '<mod>': {...} }` 선언, `plugin.json`에 `"types": "./types/index.d.ts"`.
- 예제: `examples/band.tsx`, `band-state.d.ts`(같은 폴더).

## 4. 플러그인 구성·개발·설치
- 스킬 안내: `.claude-plugin/plugin.json`(`name`, `version`, `description`), `hooks/hooks.json`(`{ "modules": ["./register.tsx"] }`), `hooks/register.tsx`(`export const register: Register = (on, options) => {...}`).
- 개발 로드 [skill reference "Developing one"]: `claude --plugin-dir <folder>`(그 세션만), 또는 `~/.claude/settings.json`의 `env.CLAUDE_CODE_PLUGIN_DIRS`(모든 세션). 대화형 세션은 폴더를 감시해 저장 시 다시 로드.
- 설치형: `claude plugin marketplace add <folder>` + 상대 경로 `source`면 그 폴더에서 직접 읽고 `/reload-plugins`로 갱신.
- 검사: `claude plugin validate <folder>`, 타입 검사 `tsc -p <folder>`(타입이 깔린 뒤), `*.test.ts` + `claude plugin test <folder>`.
- 실패: 훅이 실패하면 건너뛰고 체인 계속(기본 바닥줄 유지). `claude --debug`에 기록.

## 5. dashband 차용 범위 [B]
| 차용 | dashband 위치 | 이유 |
|---|---|---|
| `session.start`에서 `$.session.usage()` 첫 읽기 | register 220–232 | 세션 시작 직후 값 |
| `session.measure`에서 갱신 | register 252–257 | 엔진이 미는 갱신(폴링 불필요) |
| `atom`/`read`/`update` 패턴 | register 30–33 | 값이 바뀌면 다시 그림 |
| `SessionMode` 훅 골격 | register 294–340 | 바닥줄 자리 |
| `contextColor`(≥90 red, ≥75 주황, 그 외 green) | model 81–82 | 색 트리 방식을 고를 때만 |
| `toUsage`의 context 부분 | register 66–74 | `percent`/`tokens` 추출 |

차용하지 않음: 캐시 TTL·전사 파일 읽기(`$.process.run` sh/tail), `$.fs` 추적 로그, 공유 한도(`$.store`), 15초 타이머, 토스트, `AbovePrompt` 밴드, 사용 한도 표시.

## 6. 미확인 (구현 단계 P2에서 실측으로 닫는다)
- U1 `modes`에 더한 라벨이 실제로 오른쪽 끝에 ` & `로 붙는지, 너비가 좁을 때 잘리는 규칙
- U2 `modes`가 비었을 때도 `SessionMode`가 raise되는지(우리 라벨만 있을 때 표시 여부)
- U3 `session.measure`가 압축(compact) 직후에도 오는지, 값이 비는 구간의 모양
- U4 최소 요구 Claude Code 버전(dashband README는 "2.1.287 or later", 우리 기능 집합 기준 재확인)
- U5 데스크톱 앱 표면의 모양(dashband README: 앱은 footer 항목을 짧게 자른다)

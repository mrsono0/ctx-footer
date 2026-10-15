# 06. P2 스파이크 결과 — U1–U5 실측·타입 확정

날짜 2026-10-11. 환경: Claude Code 2.1.296(macOS, herdr 터미널). 시험 폴더 `/tmp/cf-spike.jpcwTK`(플러그인 `ctx-footer-spike` 0.0.0), 시험 세션 = herdr 새 탭 wN:t2의 pane wN:p5(`claude --plugin-dir /tmp/cf-spike.jpcwTK`, cwd = 시험 폴더). `claude plugin validate` 통과(경고: author 미기입 1건).

근거 표기: `[S 파일 sha16]` = 화면 원본(`herdr pane read --source visible --format ansi`, 회차 폴더 `/tmp/cf-spike-r1.2xwxM1/`), `[T 줄]` = 깔린 타입 `/tmp/cf-spike.jpcwTK/.claude-plugin/types/claude-code/index.d.ts`(엔진이 시험 세션 로드 시 생성), 원본 인용은 `«…»`.

## U1 — 라벨 위치·연결자·잘림

**관측 사실**
- statusLine이 있을 때(16:45경 전역 statusLine on): 라벨 `ctx test`는 **statusLine(`◔ 0% · 0k/1000k`) 줄의 오른쪽 끝**에 그려진다. `-- INSERT --` 줄에는 붙지 않는다. `[S u1-before-first-response.ansi bb0c78ce, u1-after-first-response.ansi f52116ec]`
- statusLine이 없을 때(사용자 결정 「전역으로 꺼」, 16:49 — cf-lead가 `~/.claude/settings.json`의 statusLine 키 제거, 백업 `~/.claude/settings.json.bak-20261011-164943-statusline`): 라벨은 **`-- INSERT -- ⏵⏵ auto mode on …` 모드 줄의 오른쪽 끝**이고 바닥줄은 한 줄로 유지된다(README 목업 위치). `[S u1-nostatusline-plain.ansi 828c7090]`
- 색: 엔진의 흐린 회색(ANSI `38;2;102;102;102`)으로, 같은 줄의 다른 바닥줄 텍스트와 같다. `[S u1-before-first-response.ansi 원본]`
- 좁은 폭(약 67열·44열): **라벨 본문은 잘리지 않고 별도 줄로 줄바꿈된다(우측 정렬)**. 모드 줄의 엔진 힌트(`· ← for agents`)가 먼저 `…`로 잘린다. `[S u1-nostatusline-narrow.ansi 2ed061d7, u1-nostatusline-narrow2.ansi 72e16053, u1-narrow2.ansi 30a1b16b]`
- shift+tab 모드 순환(auto → accept edits)은 `⏵⏵ accept edits on`으로 **INSERT 줄 표현이 바뀔 뿐** `modes` 항목이 추가되지 않는다 — 우리 라벨과의 연결을 관찰할 수 없었다. `[S u1-mode-cycle.ansi 072d525c]`

**근거(타입)**: [T 10197–10205] «The dim mode labels at the right of the prompt footer (`focus`, `memory paused`), joined by ` & `. One instance. … Raised on the terminal and desktop surfaces only.», [T 10206–10211] `SessionMode: { modes: readonly string[] }` «The labels the footer shows, in order; empty when there are none.»

**미확인**: 연결자 ` & `의 실화면 모습(다른 `modes` 라벨—`focus`, `memory paused` 등—을 활성화하는 방법을 찾지 못함).

## U2 — `modes`가 비어도 raise되는가

**관측 사실**: 첫 응답 전·다른 모드 라벨이 전혀 없는 상태에서도 우리 라벨 `ctx test`가 단독으로 표시된다 → **SessionMode는 `modes`가 비어도 raise된다(예)**. `[S u1-before-first-response.ansi bb0c78ce]` — [T 10208–10210] «empty when there are none»와 모순 없음(빈 배열도 이벤트는 온다).

## U3 — 압축 직후·값 없는 구간·값 갱신

**관측 사실**(S2: 실제 `$.session.usage()` 연결 코드, register.ts sha16 `a98c0d3d`)
- 값 없을 때(첫 응답 전): **라벨 없음** — D-3 그대로. `[S s2-after-save-reload.ansi c649b2a3]`
- 첫 응답 뒤: `ctx 5% · 45k/1000k` 표시(README 목업 형식과 동일). `[S s2-first-value.ansi 24c6e654]`
- 아주 작은 대화(숫자 Q&A 연속 2–3턴): **표시는 `45k` 그대로**였다(원시 토큰 변화량은 계측하지 못함 — 가설: 반올림 아래 증가). `[S s2-second-value.ansi 67ce3e14, s2-third-value-b.ansi a4fb1c41]`
- `/compact` 직후·다음 응답 전 캡처: **라벨이 사라지지 않고 이전 표시(5% · 45k)를 유지**했다(관측은 표시 행동까지 — atom 보존·이벤트 미수신 여부는 가설). `[S u3-compact-immediate.ansi fadf00e4]`
- `/compact` 뒤 첫 응답 후 캡처: 표시가 `ctx 4% · 38k/1000k`로 갱신됐다. `[S u3-after-compact-response.ansi 806fd056]`
- 저장 시 재로드: register.ts 저장 직후(약 8초 내 캡처) 재시작 없이 라벨 반영이 바뀌었다(S1 고정 라벨 소멸 → S2 코드 동작) — 대화형 세션의 플러그인 폴더 감시 확인. `[S s2-after-save-reload.ansi vs u1-nostatusline-plain.ansi]`

**결론**(표시 행동 관측 범위): docs/02 U3의 관측 가능한 부분은 닫힘 — 관측된 표시 전이는 «첫 응답 전 없음 → 45k → compact 후 캡처에서 45k 유지 → 다음 응답 후 38k». 라벨이 공백이 되는 구간은 관측되지 않았다(이전 표시 유지). `session.measure`의 발생 시점(compact 직후인지 첫 응답에만 오는지)과 빈 context 수신 여부는 이 계측으로 알 수 없다 — **미확인**(가설: compact 뒤 첫 응답에 온다). 타입 근거 [T 10954–10956] «`tokens` and `percent` are the last API response's input side against the model's window, absent until the first response of the live window: a fresh session, or one just compacted, until its next response.»는 `$.session.usage()` 응답에 대한 것이며, 우리 atom이 값을 지우는 시점과 다르다.

## U4 — 최소 요구 버전

**결론**: 문서상 최소 **2.1.287** / 검증 환경 **2.1.296**(실측). 기능집합별 최초 버전은 자료 없음.

**관측 사실**: 이 세션에서 `ui.render SessionMode`·`atom/read/update`·`$.session.usage`·`session.start/measure`가 Claude Code **2.1.296**에서 동작함(위 U1–U3). 최소 버전의 하한은 실측하지 못했다.

**조사 결과**(cf-critic ANSWER spike-r1, 인용 5건 cf-lead 원문 대조 완료 2026-10-11):
- 공식 문서 요구: https://code.claude.com/docs/en/plugins/mods/create — «Use Claude Code v2.1.287 or later.»
- 공식 변경 기록: https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md#21287 — «Added Claude Mods: plugins may now modify deeper behavior».
- 기능집합별 최초 버전: **자료 없음** — reference 문서(https://code.claude.com/docs/en/plugins/mods/reference)에 해당 API들이 있으나 각 API 최초 버전은 명시하지 않는다. 전체 기능집합이 2.1.287에서 검증됐다고 쓰지 않는다.
- dashband 작성자 주장(참고, 공식 보증 아님): https://github.com/EgonLeitner/dashband/blob/28496787/README.md#requirements — «Claude Code with mod support (2.1.287 or later)»; 같은 행은 CLI 2.1.289·Desktop 앱 2.31226에서 시험했다고 적는다.

**미확인**: 우리 기능집합 전체가 동작하는 실제 최소 버전(하한 실측 없음).

## U5 — 데스크톱 앱 표면

**결론**: **미확인**(공식 잘림 규칙 자료 없음; dashband 작성자 관측만 있음).

**관측 사실**: 없음(데스크톱 앱이 이 기계에 없어 관측 불가).

**조사 결과**(cf-critic ANSWER, cf-lead 원문 대조 완료):
- 공식 문서의 잘림 규칙·문자수·ellipsis 근거: **자료 없음**.
- 표면 지원 근거(잘림 근거 아님): 공식 타입 — 깔린 타입 `/tmp/cf-spike.jpcwTK/.claude-plugin/types/claude-code/index.d.ts` 1행 «Written by Claude Code 2.1.296.», [T 10199–10204] «Raised on the terminal and desktop surfaces only.»(GitHub 공개 사본은 2.1.277 생성본이라 깔린 타입을 우선한다).
- dashband 작성자 관측(참고): https://github.com/EgonLeitner/dashband/blob/28496787/README.md#what-it-shows — «The Desktop app cuts a footer item short, so there cache and context appear in the status line, …».

**미확인**: 데스크톱 표면에서 우리 `modes` 문자열의 잘림 한계·실제 모양.

## 타입 시그니처 확정 (깔린 index.d.ts, 15,990줄)

- `Register` [T 9309]: `export type Register = (on: On, options: PluginOptions) => unknown;`
- `SessionMode` props [T 10206–10211]: `SessionMode: { modes: readonly string[]; }` («empty when there are none»)
- 컴포넌트 이름 [T 9368]: `RenderComponent`에 `'SessionMode'` 포함.
- `SessionContextUsage` [T 10958–10983]: `tokens?: number`(«Input tokens the last response was answered over … the status line's `total_input_tokens`»), `window: number`(`context_window_size`), `percent?: number`(0–100, `used_percentage`), `breakdown?: SessionContextBreakdown`(«present only when the call passed `breakdown`»).
- `session.measure` [T 4420–4422]: 이벤트 이름 `'session.measure': SessionMeasureInput`. 입력 [T 11096–11110]: `context: SessionContextUsage` + `rateLimits`(«The same figures the op reads, without `context.breakdown`»).
- `atom` [T 14709]: `export const atom: AtomFunction` — 시그니처 [T 714–715]: `<P extends keyof PluginState & string, K extends keyof PluginState[P] & string>(ref: StateName<P,K> & Readonly<Pick<StateAddress,'id'>>, initial: StateValue<P,K>): Atom<StateValue<P,K>>`. 예시 [T 712]: `const count = atom({ plugin: "counter", key: "count" } as const, 0)`
- `read` [T 14734]: `export const read: ReadFunction` — [T 9292–9293]: `<T>($: StateDollar, source: Atom<T>): Promise<T>`; «Made while a `ui.render` hook draws, it subscribes the drawing» [T 9286].
- `update` [T 14743]: `export const update: UpdateFunction` — [T 14593–14594]: `<T>($: StateDollar, target: Atom<T>, change: (value: T) => T): Promise<T>`.
- 엔진 제공 tsconfig: `/tmp/cf-spike.jpcwTK/.claude-plugin/types/tsconfig.json`(sha16 `75aed92a`) — `noEmit`, include hooks/types/tests. 원문은 회차 폴더 사본 참조.

## 결정 T1 — 타입 검사용 tsc 확보 방법 (**결정**)

- 사실: 이 기계에 tsc 없음(bun·node·npm 있음). 엔진이 `.claude-plugin/types/tsconfig.json`을 제공한다.
- 사용자 원문 승인 「권장안대로 bunx로 해」(2026-10-11): **package.json 없이 `scripts/dev-check.sh`에서 버전 고정 `bunx` tsc**(예: `bunx --bun -p typescript@<고정 버전> tsc -p .`).
- 고정 버전 값과 정확한 bunx 문법은 P3에서 확인해 확정한다(지금 설치·실행하지 않음). docs/03 반영도 P3 몫.

## 결정 D-1~D-8 유지 여부

| ID | 판정 | 근거 |
|---|---|---|
| D-1 엔진 그림 유지 | **유지** | 흐린 회색·줄바꿈 모두 엔진 그림으로 관측(U1) |
| D-2 라벨 형식 | **유지** | `ctx 5% · 45k/1000k` 실측(U3) |
| D-3 값 없으면 라벨 생략 | **전제 수정 필요(관측 근거)** | 첫 응답 전 생략은 그대로. 그러나 «압축 직후»에는 라벨이 공백이 되지 않고 **이전 값 유지**(U3). 수정안(선택): compact 시점에 atom을 null로 초기화하는 이벤트 추가 — 다만 확인된 요구 없으므로 P4 전에 lead·사용자 결정. docs/03은 고치지 않음 |
| D-4 atom 1개 | **유지** | 실측 동작으로 충분 |
| D-5 표면 분기 | **유지** | 터미널 관측; 데스크톱(U5)은 **닫음**(2026-10-15, 관찰 없이 종결 — 사용자 원문 「닫기로 한것은 명확하게 닫기 처리를 합니다.」, 앞선 결정 2026-10-14 「2. 건너띔」) — 실제 모양은 관찰하지 않았다(docs/07 U5) |
| D-6 userConfig 없음 | **유지** | — |
| D-7 실패 시 next(e) | **유지(관측 2026-10-14)** | 그리기 훅 throw 시 엔진이 기본 그림 — docs/07 「남은 관찰 정리」 D-7 |
| D-8 dashband 고지 | **유지** | 시험 register.ts 머리 주석으로 실제 확인 |

## 미확인 목록

1. U1 연결자 ` & ` 실화면(다른 `modes` 라벨 활성화 방법 미발견) → **닫음 2026-10-14**(연결 모양, 사본 계측 라벨로 관찰, docs/07 U1); 엔진 자체 라벨(`memory paused`·`account memory: …`)과 나란히 선 모양도 **닫음**(2026-10-15, 관찰 없이 종결 — 사용자 원문 「닫기로 한것은 명확하게 닫기 처리를 합니다.」. 띄우는 조건 미발견, 전역 설정 변경 시도 안 함) — 실제 모양은 관찰하지 않았다
2. U4 기능집합의 실제 하한(문서상 최소 2.1.287·검증 환경 2.1.296으로 기록 — 기능별 최초 버전 자료 없음, 인용 대조 완료)
3. U5 데스크톱 표면의 실제 잘림 모양(앱 부재 — 공식 근거 자료 없음, dashband 작성자 관측만) → **닫음**(2026-10-15, 관찰 없이 종결 — 사용자 원문 「닫기로 한것은 명확하게 닫기 처리를 합니다.」. 2026-10-14 앱 있음 확인, 앞선 결정 사용자 원문 「2. 건너띔」으로 화면 확인 안 함 — docs/07 U5) — 실제 모양은 관찰하지 않았다
4. U3의 `session.measure` 발생 시점(compact 직후인지 첫 응답에만 오는지)·빈 context 수신 여부 — 표시 전이만 관측됨(이벤트 계측 없음. 가설: compact 뒤 첫 응답에 온다) → **닫음 2026-10-14**(이벤트 계측, docs/07 U3)
5. D-7 실패 경로(훅 실패 시 엔진 기본 그림 — 관측 안 함) → **닫음 2026-10-14**(docs/07 D-7)
6. 세션 한정 statusLine 끄기 문법(`--settings '{"statusLine":null}'`은 무효 — Settings Error 대화상자 `[S u1-no-statusline.ansi abf26dbb]`; 전역은 lead가 직접 제거하여 해결)

## 정리 상태

시험 세션(wN:p5)은 `/exit` 완료(`[S test-session-exit.ansi 288ec899]` — `claude --resume e8f4a187…` 안내 후 셸 프롬프트). 탭 wN:t2·시험 폴더·회차 폴더는 유지(정리는 cf-lead). 저장소 변경은 이 문서 1개뿐.

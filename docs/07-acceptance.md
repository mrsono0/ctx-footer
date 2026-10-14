# 07. P5 실화면 검증 — 인수 기준 A1–A5·폭 기준값 M5

날짜 2026-10-11. 환경: Claude Code 2.1.296(macOS, herdr 터미널), 전역 statusLine 없음.

시험 세션은 3회이고, 모두 herdr wN 새 탭에서 cwd = 저장소로 `claude --plugin-dir ./plugin`을 실행했다.

|세션|pane|`WIDE_COLUMNS`|한 일|
|---|---|---|---|
|1차(r1)|탭 wN:t5, pane wN:pF|100(P4 커밋 `13b0161`)|A1–A3, 폭 단계 측정|
|2차(r2)|pane wN:pJ|93(p5-r1 첫 정정값)|93/92 경계, 권한 모드 4종|
|3차(r3)|탭 wN:t7, pane wN:pN|**96**(확정값)|96/95 경계, 권한 모드 4종, resize 출력 보존|

시험 세션에는 도구를 쓰지 않는 글쓰기 질문만 보냈다(「도구 쓰지 말고 … 수필 N단어로 써 줘」).

**근거 표기**
- 형식은 `[S 파일 sha16 · 폭]`이다.
- 화면 원본은 `herdr pane read --source visible --format ansi`로 받았다.
- 저장 위치: r1은 `/tmp/cf-p5-r1.captures/`, r2는 `/tmp/cf-p5-r2.captures/`, r3은 `/tmp/cf-p5-r3.captures/`.
- r3은 resize할 때마다 herdr 출력을 `<이름>.resize.json`으로 같이 저장했다.

**폭 표기.** 이 문서의 폭은 화면 원본에서 가장 긴 가로 구분선(`─`)의 길이다.

관측 사실
- 바닥줄에 라벨이 붙은 원본에서는 구분선 길이 = 바닥줄 텍스트 줄 길이 + 2였다.
  - 라벨이 없는 원본(첫 응답 전 등)에는 이 관계를 적용할 수 없다. 바닥줄이 힌트에서 끝나기 때문이다.
- r3에서는 구분선 길이 = herdr pane rect 폭 − 2였다. 저장한 resize 출력 6건 모두 그랬다.

  |rect 폭|구분선|원본|
  |---|---|---|
  |55|53|`[S r3-s1.resize.json 396b9399b3b0dbe3]` `[S r3-s1.ansi a27a660cdad30fb4 · 53]`|
  |89|87|`[S r3-s2.resize.json 68943fdc8e101f0a]` `[S r3-s2.ansi 45d4201ebec45b89 · 87]`|
  |95|93|`[S r3-s3.resize.json 6d0dd52a8df90074]` `[S r3-s3.ansi 9c93ade36f69d2c9 · 93]`|
  |97|95|`[S r3-s4.resize.json 5bad50b6931d49fe]` `[S r3-s4.ansi 6cedf42256c4fb89 · 95]`|
  |98|96|`[S r3-s5.resize.json 2b77b2b812e3a82f]` `[S r3-s5.ansi d22aa2f94c5310c7 · 96]`|
  |97|95|`[S r3-s6.resize.json 5bad50b6931d49fe]` `[S r3-s6.ansi 8acb72a813311606 · 95]`|

  - r1·r2의 rect 폭은 저장하지 않았다(미확인 6).
- 형식은 구분선 길이에서 바뀌었다.
  - r1: 99 짧음 / 100 긴 형식
  - r2: 92 짧음 / 93 긴 형식
  - r3: 95 짧음 / 96 긴 형식
  - 세 번 모두 바뀐 위치가 그때의 `WIDE_COLUMNS`와 같다.

가설
- 엔진이 훅에 주는 `e.viewport.columns`는 구분선 길이와 같다.
- 근거는 위 전환 위치뿐이다. `columns` 값을 직접 출력하지는 않았다.

## A1 — 넓은 화면 긴 형식·한 줄, 폭에 따른 전환

**판정: 충족**

**관측 사실**
- 폭 151에서 바닥줄은 한 줄이다: `-- INSERT -- ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents … ctx 5% · 53k/1000k`. `[S a1-wide-first-response-b.ansi 7d7d0a198eb80568 · 151]`
- 폭을 바꾸면 다시 시작하지 않아도 형식이 저절로 바뀐다.
  - r1, `WIDE_COLUMNS = 100`
    - 99 → `ctx 5%`. `[S m5-step6.ansi 60f3802d0a6e3824 · 99]`
    - 100 → `ctx 5% · 49k/1000k`. `[S m5-step18.ansi 4f3d7c412fa89dc4 · 100]`
    - 101 → 긴 형식. `[S m5-step7.ansi 539a6a749afc5060 · 101]`
    - 102 → 긴 형식. `[S m5-step5.ansi f84376fe6fd34daa · 102]`
    - 107 → 긴 형식. `[S m5-step4.ansi 892c342262e3b29e · 107]`
  - r2, `WIDE_COLUMNS = 93`, auto 모드
    - 92 → `ctx 5%`. `[S r2-s3.ansi b5aed4d9d451f873 · 92]`
    - 93 → `ctx 5% · 54k/1000k`, 한 줄. `[S r2-s4.ansi 4537f9b73ff9b86f · 93]`
  - r3, `WIDE_COLUMNS = 96`, auto 모드
    - 95 → `ctx 5%`. 확대할 때와 축소할 때 모두 그랬다. `[S r3-s4.ansi 6cedf42256c4fb89 · 95]` `[S r3-s6.ansi 8acb72a813311606 · 95]`
    - 96 → `ctx 5% · 54k/1000k`, 한 줄. `[S r3-s5.ansi d22aa2f94c5310c7 · 96]`
    - 150 → 긴 형식. `[S r3-wide-first.ansi 75906897843033c9 · 150]`
- 짧은 형식도 폭이 더 좁으면 바닥줄이 두 줄이 된다(엔진 줄바꿈, D-1).
  - 한 줄이었던 폭은 75·77이다. `[S m5-step14.ansi 05519fb9b6436750 · 75]` `[S m5-step11.ansi 5c9bf2fc665addbc · 77]`
  - 라벨이 다음 줄로 넘어간 폭은 72·70·67·63·53·44다. `[S m5-step15.ansi 8e12d605f2fafc4d · 72]` `[S m5-step13.ansi b24edb9fe9d3bff7 · 70]` `[S r2-split.ansi acb3221e5261af1b · 67]` `[S m5-step12.ansi 690eae8991bee455 · 63]` `[S r3-s1.ansi a27a660cdad30fb4 · 53]` `[S m5-step1.ansi acbec72c047394f3 · 44]`

## A2 — 턴마다 값 변화, 압축 뒤 감소

**판정: 충족**

**관측 사실**(폭 151, auto 모드)
- 1턴 뒤 `ctx 5% · 53k/1000k`. `[S a1-wide-first-response-b.ansi 7d7d0a198eb80568]`
- 2턴 뒤 `ctx 6% · 57k/1000k`. `[S a2-second-turn.ansi ba64943813669fd6]`
- 3턴 뒤 `ctx 6% · 60k/1000k`. `[S a2-third-turn.ansi 4db6386f6801d382]`
- `/compact`이 진행 중일 때(`Compacting conversation…`가 보이는 동안)는 이전 값 `ctx 6% · 60k/1000k`가 그대로 보인다. `[S a2-compact-immediate.ansi a7ab452d20aca020]` 압축이 끝난 뒤 첫 응답 전 상태는 캡처하지 않았다(미확인 7).
- 압축 뒤 첫 응답이 끝나자 `ctx 5% · 49k/1000k`로 줄었다. `[S a2-after-compact-response.ansi 325ca8dc3b6f607f]`

## A3 — 값이 없을 때(첫 응답 전) 라벨 없음

**판정: 충족**

**관측 사실**
- 첫 응답 전 바닥줄은 `-- INSERT -- ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents`이고 `ctx` 라벨이 없다(D-3). `[S a3-before-first-response.ansi fe4427d08a888c47 · 150]`
- 첫 질문 직후(응답 중) 캡처에도 라벨이 없다. `[S a1-wide-first-response.ansi 21a89b27d3d1db79 · 151]`
- 2차 세션도 첫 응답 전에는 라벨이 없었다. 화면으로만 확인했고 원본은 저장하지 않았다.

## A4 — validate·타입 검사·plugin test 통과 / A5 — 금지 API 0건

**판정: 충족**

`WIDE_COLUMNS = 96` 반영본에서 `bash scripts/dev-check.sh`가 exit 0으로 끝났다. `[S /tmp/cf-p5-r3.captures/dev-check.txt 3e067eb8f94942b7]`
- validate 2개(마켓플레이스·plugin) ✔
- tsc@7.0.2 오류 없음
- `claude plugin test`: 8 pass / 0 fail
- 금지 API 0건

## M5 — 폭 기준값 확정: `WIDE_COLUMNS = 96`

**규칙**(배정서 p5): 긴 형식이 한 줄에 들어가는 최소 폭을 쓰고, 여유가 없으면 +2.

**측정**(화면 원본의 여백을 읽은 관측)
- 바닥줄 텍스트는 들여쓰기 2칸으로 시작한다.
- 엔진 힌트 `… · ← for agents`가 끝나는 칸은 권한 모드마다 다르다.

  |모드|힌트 끝 칸|폭 93 원본|폭 96 원본|
  |---|---|---|---|
  |manual(`⏸ manual mode on`)|46|`[S r2-mode1.ansi 952dd5e68453df46]`|`[S r3-mode1.ansi 73c8167b67f97cd0]`|
  |plan(`⏸ plan mode on (shift+tab to cycle)`)|65|`[S r2-mode3.ansi 5ed41fce75869130]`|`[S r3-mode3.ansi b41d508a30f80d36]`|
  |auto(`⏵⏵ auto mode on (shift+tab to cycle)`)|66|`[S r2-mode4.ansi 7efa22379eb647fb]`|`[S r3-mode4.ansi b12821fa347c7351]`|
  |accept edits(`⏵⏵ accept edits on (shift+tab to cycle)`)|**69**|`[S r2-mode2.ansi 1907053168226f99]`|`[S r3-mode2.ansi 9a9f9341b06a94bf]`|

- 라벨은 오른쪽 끝에 붙고 힌트와 최소 1칸 떨어진다.
  - 75에서는 `ctx 5%`(6칸) 앞 빈칸이 1이었고, 72에서는 라벨이 다음 줄로 넘어갔다. `[S m5-step14.ansi 05519fb9b6436750 · 75]` `[S m5-step15.ansi 8e12d605f2fafc4d · 72]`
- 여기서 얻는 식: 한 줄에 드는 최소 폭 = 힌트 끝 칸 + 1 + 라벨 길이 + 2.
  - auto 모드 짧은 형식으로 계산하면 75이고, 75 한 줄 / 72 줄바꿈 관측과 어긋나지 않는다.
  - 73·74는 측정하지 못했다.

**계산**(관측 아님)
- 최대 라벨은 1000k 창에서 `ctx 100% · 1000k/1000k`, 22칸이다.
- 이 라벨이 한 줄에 드는 최소 폭은 모드별로 다음과 같다.
  - manual 71
  - plan 90
  - auto 91
  - accept edits **94**
- 94는 여유가 없는 최소값이다. 여유 2를 더해 **96**으로 정했다(critic p5-r1 판정 3).
- 첫 정정값 93은 auto 모드만 기준으로 삼았다. 그래서 accept edits 모드에서 22칸 라벨이 넘친다(계산). 예: `ctx 100% · 1000k/1000k`.

**실측 확인**(r3, `WIDE_COLUMNS = 96`)
- 96: 긴 형식이 한 줄로 나왔다. 라벨은 관측 라벨 `ctx 5% · 54k/1000k`(18칸)다.

  |모드|빈칸|22칸 라벨로 바꿨을 때 계산상 빈칸|
  |---|---|---|
  |manual|30|26|
  |plan|11|7|
  |auto|10|6|
  |accept edits|7|3|

- 95: 짧은 형식이다. `[S r3-s4.ansi 6cedf42256c4fb89 · 95]` `[S r3-s6.ansi 8acb72a813311606 · 95]`
- r2(`WIDE_COLUMNS = 93`)의 87·91은 93 미만이라 짧은 형식이었다. `[S r2-s1.ansi 1079cef0df347b68 · 87]` `[S r2-s2.ansi 30ea2ba3a74ab56f · 91]`
- 최대 라벨(22칸) 자체는 실측하지 않았다. 91·94·96은 계산값이다(미확인 2).

## 미확인

1. **엔진 `e.viewport.columns`의 실제 값.** 구분선 길이와 같다는 것은 전환 위치에서 추론했을 뿐이고, 값을 직접 출력하지는 않았다.
2. **최대 라벨(22칸)이 실제로 한 줄에 드는지.** 22칸 라벨을 만들려면 토큰이 1000k여야 해서 실측하지 않았다. 1000k가 아닌 window도 측정하지 않았다.
3. ~~**U1 연결자 ` & `.**~~ **닫음(2026-10-14)** — 아래 「남은 관찰 정리」 U1. 엔진 자체 라벨과 나란히 선 모양은 여전히 미확인이다.
4. ~~**D-7 실패 경로.**~~ **닫음(2026-10-14)** — 아래 「남은 관찰 정리」 D-7.
5. **짧은 형식 한 줄 최소 폭의 정확한 값.** 75는 한 줄이었고 72는 줄바꿈이었다. 73·74는 측정하지 못했다.
6. **r1·r2의 rect 폭.** resize 출력을 저장하지 않았다. r1·r2의 폭 수치는 모두 구분선 길이다. rect − 2 관계의 근거는 r3의 6건뿐이다.
7. ~~**압축 완료 뒤 첫 응답 전 표시.**~~ **닫음(2026-10-14)** — 아래 「남은 관찰 정리」 U3. 압축이 끝난 뒤에도, 30초를 더 기다려도 이전 표시가 그대로였다.

## 남은 관찰 정리 (2026-10-14, open-items-r1)

사용자 원문 「1, 2」(cf-lead 제안 2번 "계획서에 「유지」로 남은 관찰 항목 처리"). docs/05 남은 항목 표의 U1·U5·D-7·U3을 정리한다.

**환경**
- Claude Code **2.1.299**(P5는 2.1.296), herdr 터미널.
- 시험 세션은 1회다. herdr wN 새 탭 `wN:tD`(label `open-items 시험`)의 pane `wN:pY`(rect 폭 153)에서 cwd = 저장소로 띄웠다.
  - 명령: `claude --plugin-dir /tmp/cf-open-probe.h7lFAI/probe --settings '{"enabledPlugins":{"ctx-footer@ctx-footer":false}}'`.
  - `--settings`는 설치된 user scope ctx-footer 0.1.0을 이 세션에서만 끈다. 전역 설정 파일에는 쓰지 않았다. 화면에는 사본 라벨만 나왔다(ctx 라벨 1개).
- 시험 플러그인은 저장소 밖 사본 `cf-open-probe`다. 저장소 `plugin/`은 바꾸지 않았다.
  - 저장소 `register.ts`에 계측만 더했다. atom 하나가 이벤트 수를 센다(`s` = `session.start`, `m` = `session.measure`, `e` = `percent`가 없는 measure, `c` = `session.compact`).
  - 그 수를 두 번째 `modes` 항목 `probe sN mN eN cN`로 그린다. `[S register-probe-a.ts 4432ce33ffd292e3]`
  - `claude plugin validate` 통과. 금지 API(N1) 검색 0건.
- 화면 원본 저장 위치는 `/tmp/cf-open-probe.h7lFAI/captures/`(해시 목록 `SHA256SUMS`)다. 근거 표기는 이 문서 앞의 `[S 파일 sha16 · 폭]`을 따른다.
- 프롬프트는 도구를 쓰지 않는 글쓰기 질문만 보냈다.

### U1 — ` & ` 연결 모양

**결론: 닫음**(연결 모양). 엔진 자체 라벨과 나란히 선 모양만 미확인으로 남긴다.

**관측 사실**
- 엔진이 스스로 만드는 `modes` 항목의 후보는 메모리 관련 문구다.
  - 근거는 설치본 2.1.299 실행 파일의 목록 구성 코드다. 위치는 `/opt/homebrew/Caskroom/claude-code@latest/2.1.299/claude`, 바이트 오프셋 225938716 근처다. `[S u1-engine-modes-2.1.299.txt 777a536c83ca5fbc]`
  - 그 코드의 원문: «`lr=Jn?["memory paused"]:[...[],...Dn==="read_only"?["account memory: read-only"]:Dn==="off"?["account memory: off"]:[]]`».
  - 즉 이 분기가 내는 항목은 `memory paused`, `account memory: read-only`, `account memory: off` 중 하나다. `Dn`은 같은 조각의 `accountMemoryMarker(…)`에서 온다.
  - 타입의 예시 `focus`([T 10198–10199])는 이 버전의 이 코드 조각에는 없다. 검색한 범위는 이 조각뿐이다.
  - `Jn`·`Dn`이 켜지는 조건과, 세션 한정으로 재현하는 방법은 미확인이다. 이 조각에는 그 정의가 없다. 전역 설정을 바꾸는 시도는 하지 않았다(배정서 금지).
- 대신 사본이 `modes`에 항목 두 개를 넣었다. 우리 라벨과 계측 라벨이다.
  - 엔진은 두 항목을 ` & `(공백·`&`·공백)로 잇는다. 항목 순서는 배열 순서와 같고, 줄 오른쪽 끝에 붙는다.
  - 예: `ctx 6% · 55k/1000k & probe s1 m2 e1 c0`. `[S u3-1-after-first-response.ansi 226341c8494e06f8 · 150]`
  - 연결자와 두 라벨은 한 덩어리로, 같은 흐린 색(`38;2;153;153;153`)이다. 같은 원본의 SGR을 확인했다.
  - 우리 라벨이 없을 때(첫 응답 전)는 계측 라벨만 단독으로 나왔고 연결자도 없었다. `[S u3-0-before-first-response.ansi 67f92212a3eadc8b · 150]`

**미확인**
- 엔진 라벨(`memory paused` 등)과 우리 라벨이 나란히 있을 때의 실화면. 그 라벨을 띄우는 방법을 확인하지 못했다.
- 연결된 긴 라벨이 좁은 폭에서 줄바꿈되는 모양.

### D-7 — 훅 실패 시 엔진 기본 그림

**결론: 닫음.** 그리기 훅이 throw하면 엔진이 그 훅을 건너뛰고 기본 그림을 그린다. 세션은 계속 동작한다. 저장소 코드는 바꿀 것이 없다. D-7의 "엔진 기본 그림"은 `try`/`catch` 없이 엔진이 보장한다.

**관측 사실**
- 같은 세션에서 사본 `register.ts`를 바꿔 저장했다. `SessionMode` 그리기 훅이 항상 `throw new Error('cf-open-probe D-7 intentional render failure')` 한다. 바꾼 `register.ts`의 sha16은 `e5e56fe76646274d`다(`probe-d7.sha256`).
  - 폴더 감시로 다시 읽혔고, 재시작은 하지 않았다.
- 대화창에 엔진 알림이 남았다: «`cf-open-probe: ui.render hook skipped: threw Error: cf-open-probe D-7 intentional render failure`», «`cf-open-probe: reloaded (4 hooks: …)`».
- 바닥줄은 엔진 기본 그림이다: `-- INSERT -- ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents`. 사본 라벨은 없고, 빈 줄이나 깨진 그림도 없다. `[S d7-1-render-throw-reload.ansi c68d31a16bfa6c3c · 151]`
- 그 뒤 한 턴을 더 진행했다.
  - 응답은 정상이고, 바닥줄은 같은 기본 그림이었다.
  - 알림은 화면에 1건만 있었다. `[S d7-2-after-turn.ansi aa9c3827e6bda9b3 · 151]`

**근거(타입, 2.1.296 생성본 `plugin/.claude-plugin/types/claude-code/index.d.ts`)**
- [T 3982–3983] «An invalid tree, or a throw while drawn, draws the engine's; `--plugin-dir` is told.»
- [T 3943–3945] «a hook that fails (throws, overruns its budget: HookBudget, answers a wrong shape) is skipped: the hooks beneath and core run in its place, … the failure is reported by name.»

**미확인**
- 설치본(`--plugin-dir`가 아닌 user scope)에서도 실패 알림이 뜨는지. 타입은 «`--plugin-dir` is told»라고만 적는다.
- 다른 훅(`session.measure` 등)이 실패하는 경우. 그리기 훅만 시험했다.

### U3 — `session.measure` 발생 시점·빈 context 수신

**결론: 닫음**(이번 시험 세션 1회의 관찰 범위). 계측은 누적 횟수만 남기고 이벤트 시각은 남기지 않는다.
- 이번 세션에서는 첫 응답 전 캐처에 이미 measure 누적 1회가 있었다. 그 1회는 빈 context(`percent` 없음)였다(`m1 e1`).
- 관측한 응답 3회마다 measure 누적 수가 1씩 늘었다.
- 수동 `/compact`에서는 진행 중·완료 직후·그 뒤 30초 캐처까지 `m3 e1`이 그대로였다. 다음 응답 뒤에 `m4 e1`이 됐다.
- 압축 뒤에는 빈 context가 오지 않았다. 그동안 이전 표시가 남았다(D-3으로 수용한 동작과 같다).

**관측 사실**(폭 150–151, auto 모드)

|시점|바닥줄 라벨|원본|
|---|---|---|
|첫 응답 전|`probe s1 m1 e1 c0`(ctx 라벨 없음)|`[S u3-0-before-first-response.ansi 67f92212a3eadc8b · 150]`|
|1턴 뒤|`ctx 6% · 55k/1000k & probe s1 m2 e1 c0`|`[S u3-1-after-first-response.ansi 226341c8494e06f8 · 150]`|
|2턴 뒤|`ctx 6% · 57k/1000k & probe s1 m3 e1 c0`|`[S u3-2-after-second-response.ansi efc5ae05ee866755 · 151]`|
|`/compact` 진행 중(`Compacting conversation…`)|`ctx 6% · 57k/1000k & probe s1 m3 e1 c1`|`[S u3-3-compacting.ansi 645f9f1fc843348f · 151]`|
|압축 완료 직후(`Compacted`), 다음 응답 전|`ctx 6% · 57k/1000k & probe s1 m3 e1 c1`|`[S u3-4-after-compact-before-response.ansi 082f71a2547b0ae8 · 151]`|
|그 뒤 30초|같음(원본 바이트도 같음)|`[S u3-5-after-compact-wait30s.ansi 082f71a2547b0ae8 · 151]`|
|압축 뒤 첫 응답 뒤|`ctx 5% · 49k/1000k & probe s1 m4 e1 c1`|`[S u3-6-after-compact-response.ansi c01747127f41b7f2 · 151]`|

- 압축 진행 중 캐처 시점(`Compacting conversation… (2s)`)에는 compact 수가 이미 `c1`이었다.
- `e`(빈 context)는 세션 시작 때의 1회뿐이고, 압축 뒤에는 늘지 않았다.
- 저장소 코드의 `toReading`은 이 빈 measure를 `null`로 바꾼다. 그래서 첫 응답 전에는 ctx 라벨이 없다(A3·D-3과 일치).

**근거(타입)**: [T 4412–4413] «Fires when the engine measures the session and a unit moved: after each main-thread turn, and when a rate-limit window moves a whole point.»

**가설**: 시작 때의 빈 measure는 rate-limit 창이 움직여서 온 것이다(타입 문구의 두 번째 경우). `e.rateLimits`는 계측하지 않았다.

**미확인**
- 각 이벤트가 정확히 언제 호출됐는지. 누적 수만 캐처 시점에 봤다. 예를 들어 `session.compact`가 압축 시작 순간에 왔는지는 모른다.
- 다른 세션에서의 횟수. 시작 때 빈 measure가 항상 1회 오는지, 타입이 말하는 rate-limit 변화로 measure가 더 오는지.
- 자동 압축(문턱값)에서도 같은지. 수동 `/compact`만 시험했다.
- `/clear`·resume 뒤의 시점.

### U5 — 데스크톱 앱 표면

**결론: 사용자 결정으로 건너뜀(원문 「2. 건너띔」, 2026-10-14), 미확인 유지.**

**관측 사실**
- 2026-10-14 이 기계에 `/Applications/Claude.app`(`CFBundleShortVersionString` 2.19675.0)이 있다. docs/06 U5의 「앱 없음」은 더 이상 맞지 않는다.
- 데스크톱 표면은 GUI다. 이 팀의 관찰 수단인 `herdr pane read`로는 볼 수 없다.
  - 배정서대로 GUI 조작은 하지 않고 cf-lead에 `ASK`했다.
  - cf-lead가 사용자에게 스크린샷을 요청했고, 사용자는 「2. 건너띔」으로 화면 확인을 하지 않기로 했다(2026-10-14).

**미확인**
- 데스크톱 표면에서 우리 라벨의 잘림·위치.
- user scope 설치본이 데스크톱에서도 로드되는지.

### 정리
- 시험 세션을 `/exit`로 끝냈다. `[S test-session-exit.ansi aa09bb4448edd618]`
- 탭 `wN:tD` 닫기는 cf-lead에 요청한다.
- 저장소 변경은 문서뿐이다(이 문서, docs/05 표, docs/06 해당 행).

## 정리 상태

- 시험 세션 3개를 모두 `/exit`로 끝냈다. `[S test-session-exit.ansi a887b39701e8bd28]` `[S r2-exit.ansi 4cab91bd0be7d476]` `[S r3-exit.ansi 966a2c6bfb4ae570]`
- 탭·분할 pane 정리는 cf-lead가 한다.
- 저장소 변경(커밋 없음):
  - `plugin/hooks/register.ts` — WIDE_COLUMNS 한 줄과 그 주석
  - `docs/03-design.md` — D-2·§3의 M5 문구
  - `docs/05-work-plan.md` — M5 행
  - 이 문서(새로)

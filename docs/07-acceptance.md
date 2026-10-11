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
3. **U1 연결자 ` & `.** 다른 `modes` 라벨이 생기지 않아 관찰하지 못했다. shift+tab 모드 전환은 INSERT 줄의 힌트 문구만 바꾸고 `modes` 항목을 늘리지 않는다.
4. **D-7 실패 경로.** 훅이 실패할 때 엔진 기본 그림이 남는지는 관측하지 않았다(실패를 억지로 만들지 않음).
5. **짧은 형식 한 줄 최소 폭의 정확한 값.** 75는 한 줄이었고 72는 줄바꿈이었다. 73·74는 측정하지 못했다.
6. **r1·r2의 rect 폭.** resize 출력을 저장하지 않았다. r1·r2의 폭 수치는 모두 구분선 길이다. rect − 2 관계의 근거는 r3의 6건뿐이다.
7. **압축 완료 뒤 첫 응답 전 표시.** `a2-compact-immediate`는 압축 진행 중 화면이고, `a2-after-compact-response`는 다음 응답이 끝난 뒤 화면이다. 그 사이 상태는 P5에서 다시 캡처하지 않았다(docs/06 U3에서는 이전 표시가 유지되는 것을 관측했다).

## 정리 상태

- 시험 세션 3개를 모두 `/exit`로 끝냈다. `[S test-session-exit.ansi a887b39701e8bd28]` `[S r2-exit.ansi 4cab91bd0be7d476]` `[S r3-exit.ansi 966a2c6bfb4ae570]`
- 탭·분할 pane 정리는 cf-lead가 한다.
- 저장소 변경(커밋 없음):
  - `plugin/hooks/register.ts` — WIDE_COLUMNS 한 줄과 그 주석
  - `docs/03-design.md` — D-2·§3의 M5 문구
  - `docs/05-work-plan.md` — M5 행
  - 이 문서(새로)

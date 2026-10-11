#!/usr/bin/env bash
# scripts/team-up.sh 단위 테스트. ci/mock/herdr(모의)만 부르며 실제 Herdr에는 닿지 않는다.
#   ci/test-team-up.sh                    기본 bash로 실행
#   TEAM_UP_BASH=/bin/bash ci/test-team-up.sh   다른 bash(예: macOS 3.2)로 스크립트 실행
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/scripts/team-up.sh"
MOCK_DIR="$ROOT/ci/mock"
TEAM_UP_BASH="${TEAM_UP_BASH:-bash}"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cf-team-up-test.XXXXXX")" || exit 1
cleanup() { [ -n "$TMP" ] && [ -d "$TMP" ] && rm -rf -- "$TMP"; }
trap cleanup EXIT

export PATH="$MOCK_DIR:$PATH"
if [ "$(command -v herdr)" != "$MOCK_DIR/herdr" ]; then
	echo "FATAL: herdr가 모의($MOCK_DIR/herdr)가 아니다: $(command -v herdr)" >&2
	exit 1
fi

STATE="$TMP/state.json"
LOG="$TMP/calls.log"
T=$'\t'
PASS=0
FAIL=0
CASE=""

IMPL_SID="01a126cd-0000-4000-8000-000000000001"
LEAD="wN:p1|wN|CF 팀장 · Claude|claude|cf-lead|$ROOT"
IMPL="wN:p3|wN|CF 구현 · GJC|gjc|cf-impl|$ROOT|$IMPL_SID"
CRITIC="wN:p4|wN|CF 검토 · Codex|codex|cf-critic|$ROOT"

# pane 명세: id|작업공간|label|agent|이름|cwd|gjc 세션 id|배치 y 재정의(모의 layout용)
mkstate() {
	python3 - "$@" >"$STATE" <<'PY'
import sys, json
panes = []
for s in sys.argv[1:]:
    pid, ws, label, agent, name, cwd, sid, ly = (s.split("|") + [""] * 8)[:8]
    p = {"pane_id": pid, "workspace_id": ws, "cwd": cwd, "foreground_cwd": cwd}
    if label: p["label"] = label
    if agent: p.update(agent=agent, agent_status="idle")
    if name: p["name"] = name
    if sid: p["tokens"] = {"gjc_herdr_session_id": sid}
    if ly: p["ly"] = int(ly)
    panes.append(p)
json.dump({"panes": panes, "next": 1}, sys.stdout, ensure_ascii=False)
PY
}

# 저장소 안, Herdr pane wN:p1(팀장)에서 실행한다고 가정
run() {
	: >"$LOG"
	OUT="$(cd "$ROOT" && env -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID \
		HERDR_ENV=1 HERDR_PANE_ID=wN:p1 MOCK_HERDR_STATE="$STATE" MOCK_HERDR_LOG="$LOG" \
		CF_RETRIES=3 CF_RETRY_SLEEP=0 "$TEAM_UP_BASH" "$SCRIPT" "$@" 2>&1)"
	RC=$?
}

# 읽기 전용이 아닌 호출 줄
mutations() { grep -vE "^(pane${T}(list|get|layout)|agent${T}(list|get))(${T}|\$)" "$LOG"; }
count() { grep -cF -- "$1" "$LOG"; }
field() { # pane_id dotted.field
	python3 -c 'import sys,json
d=next((p for p in json.load(open(sys.argv[1]))["panes"] if p["pane_id"]==sys.argv[2]),{})
for k in sys.argv[3].split("."): d=d.get(k) if isinstance(d,dict) else None
print("" if d is None else d)' "$STATE" "$1" "$2"
}
order() { # 작업공간 wN에서 팀장 외 pane 순서(배치 순서)
	python3 -c 'import sys,json
print(" ".join(p["pane_id"] for p in json.load(open(sys.argv[1]))["panes"] if p["workspace_id"]=="wN" and p["pane_id"]!="wN:p1"))' "$STATE"
}
pane_named() { # name → pane id
	python3 -c 'import sys,json
print(next((p["pane_id"] for p in json.load(open(sys.argv[1]))["panes"] if p.get("name")==sys.argv[2]),""))' "$STATE" "$1"
}

check() { # 설명, 명령...
	local desc=$1
	shift
	if "$@"; then
		PASS=$((PASS + 1))
	else
		FAIL=$((FAIL + 1))
		echo "FAIL [$CASE] $desc" >&2
		echo "  --- 출력" >&2
		printf '%s\n' "$OUT" | sed 's/^/  | /' >&2
		echo "  --- 호출" >&2
		sed 's/^/  > /' "$LOG" >&2
	fi
}
eq() { [ "$1" = "$2" ] || { echo "  기대 '$2' / 실제 '$1'" >&2; return 1; }; }
no_mutations() { [ -z "$(mutations)" ]; }
has() { local s; for s in "$@"; do case "$OUT" in *"$s"*) ;; *) return 1 ;; esac; done; }
line_matches() { printf '%s\n' "$OUT" | grep -E "$1" >/dev/null; }

# ---------------------------------------------------------------------------
CASE="점검: 모두 살아 있음"
mkstate "$LEAD" "$IMPL" "$CRITIC"
run
check "종료 코드 0" eq "$RC" 0
check "변경 명령 없음" no_mutations
check "세 이름 출력" has cf-lead cf-impl cf-critic
check "alive 표시" has "alive(idle)"

CASE="점검: critic 없음"
mkstate "$LEAD" "$IMPL"
run
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "critic 생성 예정 표시" line_matches "^critic .*missing .*생성"

CASE="점검: 빈 상태"
mkstate "wN:p1|wN||claude||$ROOT"
run
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations

CASE="점검: 배치 정상 — 경고 없음"
mkstate "$LEAD" "$IMPL" "$CRITIC"
run
check "종료 코드 0" eq "$RC" 0
check "변경 명령 없음" no_mutations
check "배치 경고 없음" eq "$(printf '%s\n' "$OUT" | grep -c '배치가 기준')" 0

CASE="점검: 배치 어긋남 — 경고만"
mkstate "$LEAD" "$IMPL" "wN:p4|wN|CF 검토 · Codex|codex|cf-critic|$ROOT||30"
run
check "종료 코드 0(경고가 rc에 영향 없음)" eq "$RC" 0
check "변경 명령 없음" no_mutations
check "배치 경고 출력" line_matches "배치가 기준.*critic y=30"
check "고치는 순서 안내" has "herdr pane move"

CASE="점검: 팀원 줄이 팀장 하단보다 위(팀장 옆) — 경고"
mkstate "$LEAD" "wN:p3|wN|CF 구현 · GJC|gjc|cf-impl|$ROOT||10" "wN:p4|wN|CF 검토 · Codex|codex|cf-critic|$ROOT||10"
run
check "종료 코드 0" eq "$RC" 0
check "변경 명령 없음" no_mutations
check "팀장 하단 기준 경고" line_matches "팀장 하단\(y=20\) 아래가 아님: y=10"

# ---------------------------------------------------------------------------
CASE="--up: 모두 살아 있음"
mkstate "$LEAD" "$IMPL" "$CRITIC"
run --up
check "종료 코드 0" eq "$RC" 0
check "변경 명령 없음(생성·rename 없음)" no_mutations
check "배치 그대로" eq "$(order)" "wN:p3 wN:p4"

CASE="--up: critic만 없음"
mkstate "$LEAD" "$IMPL"
run --up
new="$(pane_named cf-critic)"
check "종료 코드 0" eq "$RC" 0
check "split 1회" eq "$(count "pane${T}split")" 1
check "impl 오른쪽으로 split" eq "$(count "pane${T}split${T}wN:p3${T}--direction${T}right${T}--ratio${T}0.500")" 1
check "run 1회" eq "$(count "pane${T}run")" 1
check "critic 실행 명령" eq "$(field "$new" command)" "cd $ROOT && codex --search --yolo -m gpt-6.1-sol -c model_reasoning_effort=\"high\""
check "critic label" eq "$(field "$new" label)" "CF 검토 · Codex"
check "배치 impl|critic" eq "$(order)" "wN:p3 $new"
check "다른 석 rename 없음" eq "$(grep -cE "^agent${T}rename${T}(wN:p1|wN:p3)${T}" "$LOG")" 0
check "send-text 없음(critic은 GJC 아님)" eq "$(count "send-text")" 0

CASE="--up: 팀원 모두 없음(새 기동)"
mkstate "wN:p1|wN||claude||$ROOT"
run --up
i="$(pane_named cf-impl)"
c="$(pane_named cf-critic)"
check "종료 코드 0" eq "$RC" 0
check "팀장 이름 확보" eq "$(field wN:p1 name)" cf-lead
check "팀장 label" eq "$(field wN:p1 label)" "CF 팀장 · Claude"
check "split 2회" eq "$(count "pane${T}split")" 2
check "impl은 팀장 아래(0.62)" eq "$(field "$i" split_from) $(field "$i" split_direction) $(field "$i" split_ratio)" "wN:p1 down 0.62"
check "critic은 impl 오른쪽(1/2)" eq "$(field "$c" split_from) $(field "$c" split_direction) $(field "$c" split_ratio)" "$i right 0.500"
check "배치 impl|critic" eq "$(order)" "$i $c"
check "impl 실행 명령" eq "$(field "$i" command)" "cd $ROOT && gjc --mpreset opus5-codex56-pro"
check "critic 실행 명령" eq "$(field "$c" command)" "cd $ROOT && codex --search --yolo -m gpt-6.1-sol -c model_reasoning_effort=\"high\""
check "GJC 세션 /rename" eq "$(field "$i" tokens.gjc_herdr_session)" "CF 구현 · GJC"
check "/rename은 GJC 한 석에만" eq "$(count "send-text")" 1
check "배치 확인 layout 호출(secure_lead 뒤에도)" eq "$(count "pane${T}layout")" 1

CASE="--up: 두 번째 실행은 멱등"
run --up
check "종료 코드 0" eq "$RC" 0
check "변경 명령 없음" no_mutations

CASE="--up: 남은 빈 셸 pane 재사용"
mkstate "$LEAD" "wN:p3|wN|CF 구현 · GJC|||$ROOT" "$CRITIC"
run --up
check "종료 코드 0" eq "$RC" 0
check "split 없음" eq "$(count "pane${T}split")" 0
check "빈 셸에서 실행" eq "$(count "pane${T}run${T}wN:p3${T}")" 1
check "이름 확보" eq "$(pane_named cf-impl)" wN:p3
check "배치 그대로" eq "$(order)" "wN:p3 wN:p4"

CASE="--up: label 일치 agent가 이름만 잃음"
mkstate "$LEAD" "wN:p3|wN|CF 구현 · GJC|gjc||$ROOT|$IMPL_SID" "$CRITIC"
run --up
check "종료 코드 0" eq "$RC" 0
check "split·run 없음" eq "$(grep -cE "^pane${T}(split|run)${T}" "$LOG")" 0
check "이름만 부여" eq "$(pane_named cf-impl)" wN:p3

CASE="--up: impl만 없음(오른쪽 이웃 기준 + swap)"
mkstate "$LEAD" "$CRITIC"
run --up
i="$(pane_named cf-impl)"
check "종료 코드 0" eq "$RC" 0
check "critic 오른쪽 split" eq "$(field "$i" split_from) $(field "$i" split_direction)" "wN:p4 right"
check "swap 1회" eq "$(count "pane${T}swap")" 1
check "배치 impl|critic" eq "$(order)" "$i wN:p4"

# ---------------------------------------------------------------------------
CASE="--up: 다른 pane이 cf-critic 이름 사용"
mkstate "$LEAD" "$IMPL" "wG:p1|wG|other|codex|cf-critic|/tmp/other-project"
run --up
check "종료 코드 1" eq "$RC" 1
check "cf-critic rename 없음" eq "$(grep -cE "^agent${T}rename${T}.*${T}cf-critic\$" "$LOG")" 0
check "critic 생성 없음" eq "$(grep -cE "^pane${T}(split|run)${T}" "$LOG")" 0
check "다른 pane 이름 유지" eq "$(field wG:p1 name)" cf-critic
check "충돌 보고" has "cf-critic"

CASE="--up: 다른 pane이 cf-lead 이름 사용"
mkstate "wN:p1|wN||claude||$ROOT" "wG:p1|wG|other|claude|cf-lead|/tmp/other-project"
run --up
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "다른 pane 이름 유지" eq "$(field wG:p1 name)" cf-lead

CASE="점검: 다른 pane이 이름 사용"
mkstate "$LEAD" "$IMPL" "wG:p1|wG|other|codex|cf-critic|/tmp/other-project"
run
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "conflict 표시" line_matches "^critic .*conflict"

# ---------------------------------------------------------------------------
CASE="--resume-impl: impl 없음 → 복구"
RESUME_SID="01a126cd-1111-4000-8000-0000000000aa"
mkstate "$LEAD" "$CRITIC"
run --resume-impl "$RESUME_SID"
i="$(pane_named cf-impl)"
check "종료 코드 0" eq "$RC" 0
check "resume 명령" eq "$(field "$i" command)" "cd $ROOT && gjc --resume $RESUME_SID --mpreset opus5-codex56-pro"
check "run 1회(impl만)" eq "$(count "pane${T}run")" 1
check "배치 impl|critic" eq "$(order)" "$i wN:p4"
check "GJC 세션 /rename" eq "$(field "$i" tokens.gjc_herdr_session)" "CF 구현 · GJC"

CASE="--resume-impl: 같은 id가 다른 pane에 살아 있음"
mkstate "$LEAD" "$CRITIC" "wG:p5|wG|x|gjc||/tmp/other-project|$RESUME_SID"
run --resume-impl "${RESUME_SID:0:13}"
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "거부 사유" has "wG:p5"

CASE="--resume-impl: 구현 GJC가 이미 살아 있음"
mkstate "$LEAD" "$IMPL" "$CRITIC"
run --resume-impl "$RESUME_SID"
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations

CASE="--resume-impl: id 형식 거부"
mkstate "$LEAD" "$CRITIC"
run --resume-impl 'abc; touch /tmp/x'
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations

CASE="인자 오류"
run --bogus
check "종료 코드 2" eq "$RC" 2
check "herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0

# ---------------------------------------------------------------------------
CASE="Herdr 밖"
mkstate "$LEAD" "$CRITIC"
: >"$LOG"
OUT="$(cd "$ROOT" && env -u HERDR_ENV -u HERDR_PANE_ID MOCK_HERDR_STATE="$STATE" MOCK_HERDR_LOG="$LOG" \
	"$TEAM_UP_BASH" "$SCRIPT" --up 2>&1)"
RC=$?
check "종료 코드 1" eq "$RC" 1
check "herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0

CASE="저장소 밖 cwd"
: >"$LOG"
OUT="$(cd "$TMP" && env HERDR_ENV=1 HERDR_PANE_ID=wN:p1 MOCK_HERDR_STATE="$STATE" MOCK_HERDR_LOG="$LOG" \
	"$TEAM_UP_BASH" "$SCRIPT" --up 2>&1)"
RC=$?
check "종료 코드 1" eq "$RC" 1
check "herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0

CASE="현재 pane cwd가 저장소 밖"
mkstate "wN:p1|wN||claude||/tmp/other-project"
run --up
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations

# shellcheck disable=SC2016
echo "team-up 테스트: 통과 $PASS / 전체 $((PASS + FAIL)) (bash: $("$TEAM_UP_BASH" -c 'echo $BASH_VERSION'))"
[ "$FAIL" = 0 ]

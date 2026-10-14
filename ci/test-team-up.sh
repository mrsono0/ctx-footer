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
IMPL="wN:p3|wN|CF 구현 · agy|agy|cf-impl|$ROOT|$IMPL_SID"
CRITIC="wN:p4|wN|CF 검토 · Codex|codex|cf-critic|$ROOT"

# pane 명세: id|작업공간|label|agent|이름|cwd|세션 id(agent_session.value)|탭(기본 <작업공간>:t1)
# 탭 배치는 모의가 pane 순서로 만든다(첫 pane 위 0.6, 나머지 아래 한 줄). 다른 배치는 settree로 준다.
mkstate() {
	python3 - "$@" >"$STATE" <<'PY'
import sys, json
panes = []
for s in sys.argv[1:]:
    pid, ws, label, agent, name, cwd, sid, tab = (s.split("|") + [""] * 8)[:8]
    p = {"pane_id": pid, "workspace_id": ws, "tab_id": tab or ws + ":t1", "cwd": cwd, "foreground_cwd": cwd}
    if label: p["label"] = label
    if agent: p.update(agent=agent, agent_status="idle")
    if name: p["name"] = name
    if sid: p["agent_session"] = {"value": sid}
    panes.append(p)
json.dump({"panes": panes, "next": 1}, sys.stdout, ensure_ascii=False)
PY
}

# 모의 상태 키 설정: setstate 키 JSON값 (예: settree는 tabs.<탭>, fail, auto_sidebar)
setstate() {
	python3 -c 'import sys,json
st=json.load(open(sys.argv[1]))
d=st
ks=sys.argv[2].split(".")
for k in ks[:-1]: d=d.setdefault(k,{})
d[ks[-1]]=json.loads(sys.argv[3])
json.dump(st,open(sys.argv[1],"w"),ensure_ascii=False)' "$STATE" "$1" "$2"
}
# 탭 배치 트리: 잎 "pane_id", 분할 "d(ratio,첫,둘)" — d는 down|right
settree() { # 탭 식
	setstate "tabs.$1" "$(python3 -c 'import sys,json,re
s=sys.argv[1]; i=0
def node():
    global i
    m=re.compile(r"(down|right)\(([0-9.]+),").match(s,i)
    if m:
        i=m.end(); a=node(); i+=1; b=node(); i+=1
        return {"d":m.group(1),"r":float(m.group(2)),"a":a,"b":b}
    m=re.compile(r"[^,()]+").match(s,i); i=m.end()
    return {"p":m.group(0)}
print(json.dumps(node()))' "$2")"
}
shape() { # 탭 → settree와 같은 식(비율은 소수 둘째 자리)
	python3 -c 'import sys,json
st=json.load(open(sys.argv[1]))
def f(n): return n["p"] if "p" in n else "%s(%.2f,%s,%s)" % (n["d"],n["r"],f(n["a"]),f(n["b"]))
t=st.get("tabs",{}).get(sys.argv[2])
print(f(t) if t else "")' "$STATE" "$1"
}
tabs_of() { # 작업공간 → 탭 목록(정렬)
	python3 -c 'import sys,json
print(" ".join(sorted({p["tab_id"] for p in json.load(open(sys.argv[1]))["panes"] if p["workspace_id"]==sys.argv[2]})))' "$STATE" "$1"
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
check "배치 경고 없음" eq "$(printf '%s\n' "$OUT" | grep -c '배치')" 0

CASE="점검: 배치 어긋남(critic이 따로 한 줄) — 경고만"
mkstate "$LEAD" "$IMPL" "$CRITIC"
settree wN:t1 "down(0.6,wN:p1,down(0.5,wN:p3,wN:p4))"
run
check "종료 코드 0(경고가 rc에 영향 없음)" eq "$RC" 0
check "변경 명령 없음" no_mutations
check "배치 경고 출력" has "배치가 기준"
check "--layout 안내" has "scripts/team-up.sh --layout"

CASE="점검: 팀원이 팀장 옆 — 경고만"
mkstate "$LEAD" "$IMPL" "$CRITIC"
settree wN:t1 "right(0.5,wN:p1,right(0.5,wN:p3,wN:p4))"
run
check "종료 코드 0" eq "$RC" 0
check "변경 명령 없음" no_mutations
check "배치 경고 출력" has "배치가 기준"

CASE="점검: 비율만 다름 — 경고만"
mkstate "$LEAD" "$IMPL" "$CRITIC"
settree wN:t1 "down(0.7,wN:p1,right(0.4,wN:p3,wN:p4))"
run
check "종료 코드 0" eq "$RC" 0
check "변경 명령 없음" no_mutations
check "비율 경고" has "팀장/아래 0.7, impl/critic 0.4"

CASE="점검: 허용 오차 안(±0.01) — 경고 없음"
mkstate "$LEAD" "$IMPL" "$CRITIC"
settree wN:t1 "down(0.61,wN:p1,right(0.49,wN:p3,wN:p4))"
run
check "종료 코드 0" eq "$RC" 0
check "배치 경고 없음" eq "$(printf '%s\n' "$OUT" | grep -c '배치')" 0

CASE="점검: impl이 다른 탭 — 경고만"
mkstate "$LEAD" "wN:p3|wN|CF 구현 · agy|agy|cf-impl|$ROOT|$IMPL_SID|wN:t2" "$CRITIC"
run
check "종료 코드 0" eq "$RC" 0
check "변경 명령 없음" no_mutations
check "다른 탭 경고" has "cf-impl(wN:p3)이 팀장과 다른 탭"

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
check "critic 실행 명령" eq "$(field "$new" command)" "cd $ROOT && codex --search --yolo --disable worktrees -m gpt-6.1-sol -c model_reasoning_effort=\"high\""
check "critic label" eq "$(field "$new" label)" "CF 검토 · Codex"
check "배치 impl|critic" eq "$(order)" "wN:p3 $new"
check "다른 석 rename 없음" eq "$(grep -cE "^agent${T}rename${T}(wN:p1|wN:p3)${T}" "$LOG")" 0

CASE="--up: 팀원 모두 없음(새 기동)"
mkstate "wN:p1|wN||claude||$ROOT"
run --up
i="$(pane_named cf-impl)"
c="$(pane_named cf-critic)"
check "종료 코드 0" eq "$RC" 0
check "팀장 이름 확보" eq "$(field wN:p1 name)" cf-lead
check "팀장 label" eq "$(field wN:p1 label)" "CF 팀장 · Claude"
check "split 2회" eq "$(count "pane${T}split")" 2
check "impl은 팀장 아래(0.6)" eq "$(field "$i" split_from) $(field "$i" split_direction) $(field "$i" split_ratio)" "wN:p1 down 0.6"
check "critic은 impl 오른쪽(1/2)" eq "$(field "$c" split_from) $(field "$c" split_direction) $(field "$c" split_ratio)" "$i right 0.500"
check "배치 impl|critic" eq "$(order)" "$i $c"
check "impl 실행 명령" eq "$(field "$i" command)" "cd $ROOT && agy --model gemini-4-argon-high --sandbox"
check "impl label" eq "$(field "$i" label)" "CF 구현 · agy"
check "critic 실행 명령" eq "$(field "$c" command)" "cd $ROOT && codex --search --yolo --disable worktrees -m gpt-6.1-sol -c model_reasoning_effort=\"high\""
check "send-text 없음" eq "$(count "send-text")" 0
check "배치 확인 layout 호출(secure_lead 뒤에도)" eq "$(count "pane${T}layout")" 1
check "새 pane은 처음부터 기준 자리(move·resize 없음)" eq "$(grep -cE "^pane${T}(move|resize)${T}" "$LOG")" 0
check "배치 기준" eq "$(shape wN:t1)" "down(0.60,wN:p1,right(0.50,$i,$c))"

CASE="--up: 두 번째 실행은 멱등"
run --up
check "종료 코드 0" eq "$RC" 0
check "변경 명령 없음" no_mutations

CASE="--up: 남은 빈 셸 pane 재사용"
mkstate "$LEAD" "wN:p3|wN|CF 구현 · agy|||$ROOT" "$CRITIC"
run --up
check "종료 코드 0" eq "$RC" 0
check "split 없음" eq "$(count "pane${T}split")" 0
check "빈 셸에서 실행" eq "$(count "pane${T}run${T}wN:p3${T}")" 1
check "이름 확보" eq "$(pane_named cf-impl)" wN:p3
check "배치 그대로" eq "$(order)" "wN:p3 wN:p4"

CASE="--up: label 일치 agent가 이름만 잃음"
mkstate "$LEAD" "wN:p3|wN|CF 구현 · agy|agy||$ROOT|$IMPL_SID" "$CRITIC"
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

# --- 배치 기준: 팀장 위 0.6, 아래 줄 impl|critic 0.5 (±0.01) ---------------
SIDE="wN:pW|wN|Sidebar|||$ROOT"
TARGET="down(0.60,wN:p1,right(0.50,wN:p3,wN:p4))"
MISSHAPEN="right(0.8,right(0.5,wN:p1,down(0.5,wN:p3,wN:p4)),wN:pW)"

CASE="--layout: 이미 기준"
mkstate "$LEAD" "$IMPL" "$CRITIC"
run --layout
check "종료 코드 0" eq "$RC" 0
check "변경 명령 없음" no_mutations

CASE="--layout: 모양은 맞고 비율만 다름 → resize만"
mkstate "$LEAD" "$IMPL" "$CRITIC"
settree wN:t1 "down(0.7,wN:p1,right(0.4,wN:p3,wN:p4))"
run --layout
check "종료 코드 0" eq "$RC" 0
check "move 없음" eq "$(count "pane${T}move")" 0
check "resize 2회" eq "$(count "pane${T}resize")" 2
check "배치 기준" eq "$(shape wN:t1)" "$TARGET"

CASE="--layout: 모양 다름 → 임시 탭 경유, Sidebar 보존"
mkstate "$LEAD" "$IMPL" "$CRITIC" "$SIDE"
settree wN:t1 "$MISSHAPEN"
setstate auto_sidebar true
run --layout
check "종료 코드 0" eq "$RC" 0
check "배치 기준(Sidebar 자리·비율 그대로)" eq "$(shape wN:t1)" "right(0.80,$TARGET,wN:pW)"
check "move는 --no-focus" eq "$(grep -E "^pane${T}move${T}" "$LOG" | grep -cv -- "--no-focus")" 0
check "Sidebar에 변경 명령 없음" eq "$(mutations | grep -c "wN:pW")" 0
check "swap 없음" eq "$(count "pane${T}swap")" 0
check "agent 없는 임시 탭만 닫음(2개)" eq "$(count "tab${T}close")" 2
check "남은 탭은 팀장 탭뿐" eq "$(tabs_of wN)" "wN:t1"

CASE="--layout: 팀 석 사이에 Sidebar가 끼어 있음 → 옮기지 않고 비0"
mkstate "$LEAD" "$IMPL" "$CRITIC" "$SIDE"
settree wN:t1 "down(0.5,wN:p1,down(0.5,wN:pW,right(0.5,wN:p3,wN:p4)))"
run --layout
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "배치 그대로(Sidebar 크기 유지)" eq "$(shape wN:t1)" "down(0.50,wN:p1,down(0.50,wN:pW,right(0.50,wN:p3,wN:p4)))"
check "안내" has "다른 pane이 섞여 있어 옮기지 않음"

CASE="--layout: 석 묶음 상자 밖이어도 같은 분할에 섞인 pane → 옮기지 않음"
mkstate "$LEAD" "$IMPL" "wN:pX|wN|x|||$ROOT" "wN:pY|wN|y|||$ROOT"
settree wN:t1 "down(0.5,right(0.5,wN:p1,wN:pX),right(0.5,wN:p3,wN:pY))"
run --layout
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations

CASE="--up: 모양 다름 + 섞인 pane → 옮기지 않고 비0, 점검은 경고만"
mkstate "$LEAD" "$IMPL" "$CRITIC" "$SIDE"
settree wN:t1 "down(0.5,wN:p1,down(0.5,wN:pW,right(0.5,wN:p3,wN:p4)))"
run --up
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
run
check "점검 종료 코드 0" eq "$RC" 0
check "점검 경고" has "다른 pane이 섞여 있음"

CASE="--layout: 임시 탭에 agent pane이 남으면 닫지 않음"
mkstate "$LEAD" "$IMPL" "$CRITIC" "$SIDE"
settree wN:t1 "$MISSHAPEN"
setstate auto_sidebar true
setstate auto_pane_agent '"claude"'
run --layout
check "종료 코드 0" eq "$RC" 0
check "배치 기준" eq "$(shape wN:t1)" "right(0.80,$TARGET,wN:pW)"
check "tab close 없음" eq "$(count "tab${T}close")" 0
check "남김 안내" has "임시 탭" "닫지 않고 둠"

CASE="--layout: critic이 다른 탭 → 팀장·impl만"
mkstate "$LEAD" "$IMPL" "wN:p4|wN|CF 검토 · Codex|codex|cf-critic|$ROOT||wN:t2"
settree wN:t1 "right(0.5,wN:p1,wN:p3)"
run --layout
check "종료 코드 0" eq "$RC" 0
check "팀장 0.6 / impl 아래" eq "$(shape wN:t1)" "down(0.60,wN:p1,wN:p3)"
check "critic에 변경 명령 없음" eq "$(mutations | grep -c "wN:p4")" 0
check "critic 탭 그대로" eq "$(shape wN:t2)" "wN:p4"
check "안내" has "cf-critic(wN:p4)이 다른 탭"

CASE="--layout: critic 없음 → 팀장·impl 비율만"
mkstate "$LEAD" "$IMPL"
settree wN:t1 "down(0.7,wN:p1,wN:p3)"
run --layout
check "종료 코드 0" eq "$RC" 0
check "resize 1회" eq "$(count "pane${T}resize")" 1
check "팀장 0.6 / impl 아래" eq "$(shape wN:t1)" "down(0.60,wN:p1,wN:p3)"

CASE="--layout: impl이 다른 탭 → 옮기지 않고 비0"
mkstate "$LEAD" "wN:p3|wN|CF 구현 · agy|agy|cf-impl|$ROOT|$IMPL_SID|wN:t2" "$CRITIC"
run --layout
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "안내" has "다른 탭에 있어 옮기지 않음"

CASE="--layout: cf-lead가 이 pane이 아님"
mkstate "wN:p1|wN||claude||$ROOT" "$IMPL" "$CRITIC"
settree wN:t1 "$MISSHAPEN"
run --layout
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations

CASE="--layout: move 실패 → 비0 + 안내"
mkstate "$LEAD" "$IMPL" "$CRITIC" "$SIDE"
settree wN:t1 "$MISSHAPEN"
setstate fail '["move"]'
run --layout
check "종료 코드 1" eq "$RC" 1
check "배치 그대로" eq "$(shape wN:t1)" "right(0.80,right(0.50,wN:p1,down(0.50,wN:p3,wN:p4)),wN:pW)"
check "안내" has "임시 탭으로 옮긴 것을 확인하지 못함"

CASE="--layout: 늦은 Sidebar 생성 경쟁 → 임시 탭 안정 대기 후 되돌림"
mkstate "$LEAD" "$IMPL" "$CRITIC" "$SIDE"
settree wN:t1 "$MISSHAPEN"
setstate late_sidebar true
run --layout
check "종료 코드 0" eq "$RC" 0
check "배치 기준(늦은 Sidebar가 원래 탭에 끼어들지 않음)" eq "$(shape wN:t1)" "right(0.80,$TARGET,wN:pW)"
check "agent 없는 임시 탭만 닫음(2개)" eq "$(count "tab${T}close")" 2
check "남은 탭은 팀장 탭뿐" eq "$(tabs_of wN)" "wN:t1"

CASE="--layout: 임시 탭 대기 조회 실패 → 되돌리고 보정 시도 + 최종 비0"
mkstate "$LEAD" "$IMPL" "$CRITIC"
settree wN:t1 "down(0.7,wN:p1,down(0.5,wN:p3,wN:p4))"
setstate auto_sidebar true
setstate fail_once '["wait_list"]'
run --layout
check "종료 코드 1(대기 실패로 비0 유지)" eq "$RC" 1
check "되돌리고 비율 보정까지 완료" eq "$(shape wN:t1)" "$TARGET"
check "대기 실패 안내" has "pane 목록 안정 대기 실패"

CASE="--layout: 첫 정상 목록 뒤 대기 조회 시간 초과 → 되돌리고 보정 시도 + 최종 비0"
mkstate "$LEAD" "$IMPL" "$CRITIC"
settree wN:t1 "down(0.7,wN:p1,down(0.5,wN:p3,wN:p4))"
setstate auto_sidebar true
setstate fail_once '["wait_timeout"]'
run --layout
check "종료 코드 1(시간 초과로 비0 유지)" eq "$RC" 1
check "되돌리고 비율 보정까지 완료" eq "$(shape wN:t1)" "$TARGET"
check "대기 실패 안내" has "pane 목록 안정 대기 실패" "이동 단계에서 오류가 있었음"

CASE="--layout: 첫 move 실패 뒤에도 나머지 이동·비율 보정 시도 + 최종 비0"
mkstate "$LEAD" "$IMPL" "$CRITIC"
settree wN:t1 "down(0.7,wN:p1,down(0.5,wN:p3,wN:p4))"
setstate auto_sidebar true
setstate fail_once '["move"]'
run --layout
check "종료 코드 1(이동 실패로 비0 유지)" eq "$RC" 1
check "비율 resize 시도(1회)" eq "$(count "pane${T}resize")" 1
check "나머지 이동·비율 보정으로 배치 기준 도달" eq "$(shape wN:t1)" "$TARGET"
check "이동 오류 안내" has "이동 단계에서 오류가 있었음"

CASE="--up: 모두 살아 있지만 모양 다름 → 끝에서 보정"
mkstate "$LEAD" "$IMPL" "$CRITIC" "$SIDE"
settree wN:t1 "$MISSHAPEN"
run --up
check "종료 코드 0" eq "$RC" 0
check "생성·실행 없음" eq "$(grep -cE "^pane${T}(split|run)${T}" "$LOG")" 0
check "배치 기준" eq "$(shape wN:t1)" "right(0.80,$TARGET,wN:pW)"

CASE="--up: critic 기동 뒤 resize 실패 → 기동은 유지, 비0 + 안내"
mkstate "$LEAD" "$IMPL"
settree wN:t1 "down(0.7,wN:p1,wN:p3)"
setstate fail '["resize"]'
run --up
c="$(pane_named cf-critic)"
check "종료 코드 1" eq "$RC" 1
check "critic 기동·이름 확보" eq "$(field "$c" agent)" codex
check "안내" has "scripts/team-up.sh --layout"

CASE="--resume-impl: 끝에서 비율 보정"
mkstate "$LEAD" "$CRITIC"
settree wN:t1 "down(0.7,wN:p1,wN:p4)"
run --resume-impl "01a126cd-2222-4000-8000-0000000000bb"
i="$(pane_named cf-impl)"
check "종료 코드 0" eq "$RC" 0
check "배치 기준" eq "$(shape wN:t1)" "down(0.60,wN:p1,right(0.50,$i,wN:p4))"

# ---------------------------------------------------------------------------
CASE="--up: 다른 pane이 cf-critic 이름 사용"
mkstate "$LEAD" "$IMPL" "wG:p1|wG|other|codex|cf-critic|/tmp/other-project"
run --up
check "종료 코드 1" eq "$RC" 1
check "cf-critic rename 없음" eq "$(grep -cE "^agent${T}rename${T}.*${T}cf-critic\$" "$LOG")" 0
check "critic 생성 없음" eq "$(grep -cE "^pane${T}(split|run)${T}" "$LOG")" 0
check "다른 pane 이름 유지" eq "$(field wG:p1 name)" cf-critic
check "충돌 보고" has "cf-critic"

CASE="--up: cf-impl을 다른 종류 agent(GJC)가 사용 → conflict(건드리지 않음)"
mkstate "$LEAD" "wN:p3|wN|CF 구현 · GJC|gjc|cf-impl|$ROOT|$IMPL_SID" "$CRITIC"
run --up
check "종료 코드 1" eq "$RC" 1
check "cf-impl rename 없음" eq "$(grep -cE "^agent${T}rename${T}.*${T}cf-impl\$" "$LOG")" 0
check "impl 생성·실행 없음" eq "$(grep -cE "^pane${T}(split|run)${T}" "$LOG")" 0
check "GJC pane 이름·종류 유지" eq "$(field wN:p3 name)|$(field wN:p3 agent)" "cf-impl|gjc"
check "충돌 보고" has "cf-impl" "다른 종류 agent(gjc)가 이름 사용"

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
check "resume 명령" eq "$(field "$i" command)" "cd $ROOT && agy --conversation $RESUME_SID --model gemini-4-argon-high --sandbox"
check "run 1회(impl만)" eq "$(count "pane${T}run")" 1
check "배치 impl|critic" eq "$(order)" "$i wN:p4"
check "impl label" eq "$(field "$i" label)" "CF 구현 · agy"

CASE="--resume-impl: 같은 id가 다른 pane에 살아 있음"
mkstate "$LEAD" "$CRITIC" "wG:p5|wG|x|agy||/tmp/other-project|$RESUME_SID"
run --resume-impl "${RESUME_SID:0:13}"
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "거부 사유" has "wG:p5"

CASE="--resume-impl: 구현 agy가 이미 살아 있음"
mkstate "$LEAD" "$IMPL" "$CRITIC"
run --resume-impl "$RESUME_SID"
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "거부 사유" has "구현 agy가 이미 wN:p3 에 살아 있다"

CASE="--resume-impl: cf-impl을 GJC가 사용 → conflict 거부"
mkstate "$LEAD" "wN:p3|wN|CF 구현 · GJC|gjc|cf-impl|$ROOT|$IMPL_SID" "$CRITIC"
run --resume-impl "$RESUME_SID"
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "충돌 사유" has "cf-impl" "다른 종류 agent(gjc)가 이름 사용"

CASE="--resume-impl: id 형식 거부"
mkstate "$LEAD" "$CRITIC"
run --resume-impl 'abc; touch /tmp/x'
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations

# ---------------------------------------------------------------------------
LEAD_SID="42c09ae2-0000-4000-8000-000000000001"
LEAD_CLEARED="wN:p1|wN|CF 팀장 · Claude|claude||$ROOT|$LEAD_SID"
# 백그라운드 작업 종료 표식: 작업은 fd 9를 물려받는다. 마지막 보유자가 끝나면 EOF → HOOK_DONE 생성
HOOK_DONE="$TMP/hook.done"
hook_exited() { # 최대 10초
	local i
	for i in $(seq 100); do
		[ -e "$HOOK_DONE" ] && return 0
		sleep 0.1
	done
	return 1
}

CASE="--hook-clear: clear → 이름 확보"
mkstate "$LEAD_CLEARED" "$IMPL" "$CRITIC"
run --hook-clear <<<"{\"session_id\":\"$LEAD_SID\",\"source\":\"clear\"}" 9> >(cat >/dev/null; : >"$HOOK_DONE")
check "종료 코드 0" eq "$RC" 0
check "출력 없음" eq "$OUT" ""
if ! hook_exited; then
	echo "FATAL [$CASE] 백그라운드 작업이 10초 안에 끝나지 않음; 다음 케이스 오염을 막기 위해 중단" >&2
	exit 1
fi
check "팀장 이름 확보" eq "$(pane_named cf-lead)" wN:p1
check "다른 변경 없음" eq "$(mutations)" "agent${T}rename${T}wN:p1${T}cf-lead"
check "배치 읽기·변경 없음" eq "$(count "pane${T}layout")" 0

CASE="--hook-clear: source가 clear 아님"
mkstate "$LEAD_CLEARED"
run --hook-clear <<<"{\"session_id\":\"$LEAD_SID\",\"source\":\"startup\"}"
check "종료 코드 0" eq "$RC" 0
check "출력 없음" eq "$OUT" ""
check "herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0

CASE="--hook-clear 작업: label 불일치"
mkstate "wN:p1|wN|다른 시험|claude||$ROOT|$LEAD_SID"
run --hook-clear "$LEAD_SID"
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "이름 없음" eq "$(pane_named cf-lead)" ""

CASE="--hook-clear 작업: 다른 pane이 cf-lead 사용"
mkstate "$LEAD_CLEARED" "wG:p1|wG|other|claude|cf-lead|/tmp/other-project"
run --hook-clear "$LEAD_SID"
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "다른 pane 이름 유지" eq "$(field wG:p1 name)" cf-lead

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

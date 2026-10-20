#!/usr/bin/env bash
# scripts/team-up.sh 단위 테스트. ci/mock/herdr(모의)만 부르며 실제 Herdr에는 닿지 않는다.
#   ci/test-team-up.sh                    기본 bash로 실행
#   TEAM_UP_BASH=/bin/bash ci/test-team-up.sh   다른 bash(예: macOS 3.2)로 스크립트 실행
set -u
# 호출한 셸의 팀 환경(외부 팀장 데스크톱 세션의 CF_EXTERNAL_LEAD·CLAUDE_CODE_SESSION_ID, Herdr pane의 HERDR_*)이
# 시험에 새지 않게 스크립트가 읽는 변수를 모두 비운다. 각 시험은 필요한 값만 env로 넣는다(extlead-r5).
unset CF_EXTERNAL_LEAD CLAUDE_CODE_SESSION_ID CF_RETRIES CF_RETRY_SLEEP HERDR_ENV HERDR_PANE_ID HERDR_WORKSPACE_ID HERDR_TAB_ID

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/scripts/team-up.sh"
MOCK_DIR="$ROOT/ci/mock"
TEAM_UP_BASH="${TEAM_UP_BASH:-bash}"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cf-team-up-test.XXXXXX")" || exit 1
cleanup() { [ -n "$TMP" ] && [ -d "$TMP" ] && rm -rf -- "$TMP"; }
trap cleanup EXIT

mkdir -p "$TMP/bin"
cp "$MOCK_DIR/ps" "$TMP/bin/ps"
chmod +x "$TMP/bin/ps"
export PATH="$TMP/bin:$MOCK_DIR:$PATH"
if [ "$(command -v herdr)" != "$MOCK_DIR/herdr" ]; then
	echo "FATAL: herdr가 모의($MOCK_DIR/herdr)가 아니다: $(command -v herdr)" >&2
	exit 1
fi
if [ "$(command -v ps)" != "$TMP/bin/ps" ]; then
	echo "FATAL: ps가 모의($TMP/bin/ps)가 아니다: $(command -v ps)" >&2
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
mutations() { grep -vE "^(pane${T}(list|get|layout|process-info)|agent${T}(list|get))(${T}|\$)" "$LOG"; }
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
not_has() { local s; for s in "$@"; do case "$OUT" in *"$s"*) echo "  출력에 없어야 할 '$s' 포함" >&2; return 1 ;; esac; done; }
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
check "--up 안내" has "scripts/team-up.sh --up"

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

# --- 점검: 팀원 실행 옵션 비교 (argv-r1) -------------------------------------
CASE="점검 옵션 ①⑦: 두 석 모두 일치(기동형) + 자식 MCP 비밀 값 미출력"
mkstate "$LEAD" "$IMPL" "$CRITIC"
setstate "process_info.wN:p3" '{"foreground_processes":[{"pid":101,"name":"agy","argv":["agy","--model","gemini-4-argon-high","--mode","accept-edits","--sandbox"]},{"pid":202,"name":"node","argv":["node","context7-mcp","--api-key","SECRET-SENTINEL-123"],"cmdline":"node context7-mcp --api-key SECRET-SENTINEL-123"},{"pid":203,"name":"notebooklm-mcp"}]}'
run
check "종료 코드 0" eq "$RC" 0
check "변경 명령 없음" no_mutations
check "팀원 2석만 process-info 호출" eq "$(count "pane${T}process-info")" 2
check "옵션 줄 없음" not_has "↳ 옵션"
check "비밀 값 미출력" not_has "SECRET-SENTINEL-123"
check "공통 한 줄 cf-impl ok + 대화 id" has "cf-impl wN:p3 ok 대화=$IMPL_SID"
check "공통 한 줄 cf-critic ok" has "cf-critic wN:p4 ok"

CASE="점검 옵션 스냅샷(B): SEAT_CMD 기대 단위 목록 고정"
mkstate "$LEAD" "$IMPL" "$CRITIC"
setstate "process_info.wN:p3" '{"foreground_processes":[{"pid":101,"name":"agy","argv":["agy"]}]}'
setstate "process_info.wN:p4" '{"foreground_processes":[{"pid":102,"name":"codex","argv":["codex"]}]}'
run
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "cf-impl 기대 단위 스냅샷" has "        ↳ 옵션 불일치: 없음 --model gemini-4-argon-high, --mode accept-edits, --sandbox (복구: idle·비포커스 확인 → /quit → scripts/team-up.sh --up <id>)"
check "cf-critic 기대 단위 스냅샷" has "        ↳ 옵션 불일치: 없음 --search, --yolo, --disable worktrees, -m gpt-6.1-sol, -c model_reasoning_effort=high (복구: idle·비포커스 확인 → /quit → scripts/team-up.sh --up)"
check "공통 한 줄 cf-impl mismatch" has "cf-impl wN:p3 mismatch 실제=없음 기대=--model gemini-4-argon-high --mode accept-edits --sandbox 대화=$IMPL_SID"
check "공통 한 줄 cf-critic mismatch" has "cf-critic wN:p4 mismatch 실제=없음 기대=--search --yolo --disable worktrees -m gpt-6.1-sol -c model_reasoning_effort=high"

CASE="점검 옵션 ②⑦: agy 복구형(--conversation만) → 불일치 + 비밀 미출력"
mkstate "$LEAD" "$IMPL" "$CRITIC"
setstate "process_info.wN:p3" '{"foreground_processes":[{"pid":101,"name":"agy","argv":["agy","--conversation","SECRET-SENTINEL-123"]},{"pid":202,"name":"node","argv":["node","context7-mcp","--api-key","SECRET-SENTINEL-123"]}]}'
run
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "agy 옵션 불일치 표시" has "        ↳ 옵션 불일치: 없음 --model gemini-4-argon-high, --mode accept-edits, --sandbox (복구: idle·비포커스 확인 → /quit → scripts/team-up.sh --up <id>)"
check "옵션 줄 1개(impl만)" eq "$(printf '%s\n' "$OUT" | grep -c '↳ 옵션')" 1
check "비밀 값 미출력" not_has "SECRET-SENTINEL-123"

CASE="점검 옵션 ③: agy 복구형 + 전체 옵션(순서 무관) → 일치"
mkstate "$LEAD" "$IMPL" "$CRITIC"
setstate "process_info.wN:p3" "{\"foreground_processes\":[{\"pid\":101,\"name\":\"agy\",\"argv\":[\"agy\",\"--conversation\",\"$IMPL_SID\",\"--sandbox\",\"--mode\",\"accept-edits\",\"--model\",\"gemini-4-argon-high\"]}]}"
run
check "종료 코드 0" eq "$RC" 0
check "변경 명령 없음" no_mutations
check "옵션 줄 없음" not_has "↳ 옵션"

CASE="점검 옵션 ④: codex resume만 → 불일치"
mkstate "$LEAD" "$IMPL" "$CRITIC"
setstate "process_info.wN:p4" '{"foreground_processes":[{"pid":102,"name":"codex","argv":["codex","resume","01a14527-0000-7000-8000-000000000001"]}]}'
run
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "codex 옵션 불일치 표시" has "        ↳ 옵션 불일치: 없음 --search, --yolo, --disable worktrees, -m gpt-6.1-sol, -c model_reasoning_effort=high (복구: idle·비포커스 확인 → /quit → scripts/team-up.sh --up)"
check "옵션 줄 1개(critic만)" eq "$(printf '%s\n' "$OUT" | grep -c '↳ 옵션')" 1

CASE="점검 옵션 ⑤: --model=값 꼴 정규화 → 일치"
mkstate "$LEAD" "$IMPL" "$CRITIC"
setstate "process_info.wN:p3" '{"foreground_processes":[{"pid":101,"name":"agy","argv":["agy","--model=gemini-4-argon-high","--mode=accept-edits","--sandbox"]}]}'
run
check "종료 코드 0" eq "$RC" 0
check "변경 명령 없음" no_mutations
check "옵션 줄 없음" not_has "↳ 옵션"

CASE="점검 옵션 C: 값 다름 구분(없음 + 다름 동시) 및 실제 값 미출력"
mkstate "$LEAD" "$IMPL" "$CRITIC"
setstate "process_info.wN:p3" '{"foreground_processes":[{"pid":101,"name":"agy","argv":["agy","--model","SECRET-SENTINEL-123","--mode","accept-edits"]}]}'
run
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "없음·다름 한 줄 표시" has "        ↳ 옵션 불일치: 없음 --sandbox; 다름 --model(기대 gemini-4-argon-high) (복구: idle·비포커스 확인 → /quit → scripts/team-up.sh --up <id>)"
check "공통 한 줄 실제·기대 요약" has "cf-impl wN:p3 mismatch 실제=--model=<다름> --mode accept-edits 기대=--model gemini-4-argon-high --mode accept-edits --sandbox 대화=$IMPL_SID"
check "실제 값 미출력" not_has "SECRET-SENTINEL-123"

CASE="점검 옵션 E1: 반복 깃발(-c other=1 -c model_reasoning_effort=high) → 일치"
mkstate "$LEAD" "$IMPL" "$CRITIC"
setstate "process_info.wN:p4" '{"foreground_processes":[{"pid":102,"name":"codex","argv":["codex","--search","--yolo","--disable","worktrees","-m","gpt-6.1-sol","-c","other=1","-c","model_reasoning_effort=high"]}]}'
run
check "종료 코드 0" eq "$RC" 0
check "옵션 줄 없음" not_has "↳ 옵션"

CASE="점검 옵션 E2: 반복 깃발(-c model_reasoning_effort=low -c other=high) → 불일치"
mkstate "$LEAD" "$IMPL" "$CRITIC"
setstate "process_info.wN:p4" '{"foreground_processes":[{"pid":102,"name":"codex","argv":["codex","--search","--yolo","--disable","worktrees","-m","gpt-6.1-sol","-c","model_reasoning_effort=low","-c","other=high"]}]}'
run
check "종료 코드 1" eq "$RC" 1
check "불일치 표시" has "        ↳ 옵션 불일치: 다름 -c(기대 model_reasoning_effort=high) (복구: idle·비포커스 확인 → /quit → scripts/team-up.sh --up)"

CASE="점검 옵션 ⑥-1: agent 프로세스 0개 → 판정 불가"
mkstate "$LEAD" "$IMPL" "$CRITIC"
setstate "process_info.wN:p3" '{"foreground_processes":[{"pid":202,"name":"node","argv":["node","context7-mcp","--api-key","SECRET-SENTINEL-123"]}]}'
run
check "종료 코드 1" eq "$RC" 1
check "0개 판정 불가" has "        ↳ 옵션 판정 불가: agent 프로세스 0개"
check "공통 한 줄 unknown 사유" has "cf-impl wN:p3 unknown agent 프로세스 0개 대화=$IMPL_SID"
check "idle이면 작업 중 문구 없음" not_has "작업 중"
check "비밀 값 미출력" not_has "SECRET-SENTINEL-123"

CASE="점검 옵션 ⑥-2·A: agent 프로세스 2개 이상 + working 상태 → 판정 불가(작업 중 표시)"
mkstate "$LEAD" "$IMPL" "$CRITIC"
python3 -c 'import sys,json
st=json.load(open(sys.argv[1]))
for p in st["panes"]:
    if p["pane_id"]=="wN:p3": p["agent_status"]="working"
json.dump(st,open(sys.argv[1],"w"),ensure_ascii=False)' "$STATE"
setstate "process_info.wN:p3" '{"foreground_processes":[{"pid":101,"name":"agy","argv":["agy","SECRET-SENTINEL-123"]},{"pid":105,"name":"agy","argv":["agy","SECRET-SENTINEL-123"]}]}'
run
check "종료 코드 1" eq "$RC" 1
check "2개 이상 + 작업 중 표시" has "        ↳ 옵션 판정 불가: agent 프로세스 2개 이상 (작업 중 — 다시 점검)"
check "비밀 값 미출력" not_has "SECRET-SENTINEL-123"

CASE="점검 옵션 ⑥-3: argv 없음 → 판정 불가"
mkstate "$LEAD" "$IMPL" "$CRITIC"
setstate "process_info.wN:p3" '{"foreground_processes":[{"pid":101,"name":"agy","cmdline":"agy SECRET-SENTINEL-123"}]}'
run
check "종료 코드 1" eq "$RC" 1
check "argv 없음 판정 불가" has "        ↳ 옵션 판정 불가: argv 없음"
check "비밀 값 미출력" not_has "SECRET-SENTINEL-123"

CASE="점검 옵션 ⑥-4·D: process-info 실패 + stderr 비밀 미출력"
mkstate "$LEAD" "$IMPL" "$CRITIC"
setstate process_info_fail '["wN:p3"]'
setstate process_info_stderr '"herdr error: SECRET-SENTINEL-123"'
run
check "종료 코드 1" eq "$RC" 1
check "process-info 실패 판정 불가" has "        ↳ 옵션 판정 불가: process-info 실패"
check "stderr 비밀 미출력" not_has "SECRET-SENTINEL-123"

CASE="점검 옵션 ⑥-5·D: JSON 오류 + 원문 비밀 미출력"
mkstate "$LEAD" "$IMPL" "$CRITIC"
setstate "process_info_raw.wN:p4" '"invalid json SECRET-SENTINEL-123"'
run
check "종료 코드 1" eq "$RC" 1
check "JSON 오류 판정 불가" has "        ↳ 옵션 판정 불가: JSON 오류"
check "원문 비밀 미출력" not_has "SECRET-SENTINEL-123"

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
check "impl 실행 명령" eq "$(field "$i" command)" "cd $ROOT && agy --model gemini-4-argon-high --mode accept-edits --sandbox"
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

CASE="--up: 남은 빈 셸 pane 재사용 (대화 id 없음 경고)"
mkstate "$LEAD" "wN:p3|wN|CF 구현 · agy|||$ROOT" "$CRITIC"
run --up
check "종료 코드 0" eq "$RC" 0
check "split 없음" eq "$(count "pane${T}split")" 0
check "빈 셸에서 실행" eq "$(count "pane${T}run${T}wN:p3${T}")" 1
check "대화 id 없음 경고" has "대화 id 없음 — 새 대화로 띄움"
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

CASE="--up(배치): 이미 기준"
mkstate "$LEAD" "$IMPL" "$CRITIC"
run --up
check "종료 코드 0" eq "$RC" 0
check "변경 명령 없음" no_mutations

CASE="--up(배치): 모양은 맞고 비율만 다름 → resize만"
mkstate "$LEAD" "$IMPL" "$CRITIC"
settree wN:t1 "down(0.7,wN:p1,right(0.4,wN:p3,wN:p4))"
run --up
check "종료 코드 0" eq "$RC" 0
check "move 없음" eq "$(count "pane${T}move")" 0
check "resize 2회" eq "$(count "pane${T}resize")" 2
check "배치 기준" eq "$(shape wN:t1)" "$TARGET"

CASE="--up(배치): 모양 다름 → 임시 탭 경유, Sidebar 보존"
mkstate "$LEAD" "$IMPL" "$CRITIC" "$SIDE"
settree wN:t1 "$MISSHAPEN"
setstate auto_sidebar true
run --up
check "종료 코드 0" eq "$RC" 0
check "배치 기준(Sidebar 자리·비율 그대로)" eq "$(shape wN:t1)" "right(0.80,$TARGET,wN:pW)"
check "move는 --no-focus" eq "$(grep -E "^pane${T}move${T}" "$LOG" | grep -cv -- "--no-focus")" 0
check "Sidebar에 변경 명령 없음" eq "$(mutations | grep -c "wN:pW")" 0
check "swap 없음" eq "$(count "pane${T}swap")" 0
check "agent 없는 임시 탭만 닫음(2개)" eq "$(count "tab${T}close")" 2
check "남은 탭은 팀장 탭뿐" eq "$(tabs_of wN)" "wN:t1"

CASE="--up(배치): 팀 석 사이에 Sidebar가 끼어 있음 → 옮기지 않고 비0"
mkstate "$LEAD" "$IMPL" "$CRITIC" "$SIDE"
settree wN:t1 "down(0.5,wN:p1,down(0.5,wN:pW,right(0.5,wN:p3,wN:p4)))"
run --up
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "배치 그대로(Sidebar 크기 유지)" eq "$(shape wN:t1)" "down(0.50,wN:p1,down(0.50,wN:pW,right(0.50,wN:p3,wN:p4)))"
check "안내" has "다른 pane이 섞여 있어 옮기지 않음"

CASE="--up(배치): 석 묶음 상자 밖이어도 같은 분할에 섞인 pane → 옮기지 않음"
mkstate "$LEAD" "$IMPL" "wN:p4|wN|CF 검토 · Codex|codex|cf-critic|$ROOT||wN:t2" "wN:pX|wN|x|||$ROOT" "wN:pY|wN|y|||$ROOT"
settree wN:t1 "down(0.5,right(0.5,wN:p1,wN:pX),right(0.5,wN:p3,wN:pY))"
run --up
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

CASE="--up(배치): 임시 탭에 agent pane이 남으면 닫지 않음"
mkstate "$LEAD" "$IMPL" "$CRITIC" "$SIDE"
settree wN:t1 "$MISSHAPEN"
setstate auto_sidebar true
setstate auto_pane_agent '"claude"'
run --up
check "종료 코드 0" eq "$RC" 0
check "배치 기준" eq "$(shape wN:t1)" "right(0.80,$TARGET,wN:pW)"
check "tab close 없음" eq "$(count "tab${T}close")" 0
check "남김 안내" has "임시 탭" "닫지 않고 둠"

CASE="--up(배치): critic이 다른 탭 → 팀장·impl만"
mkstate "$LEAD" "$IMPL" "wN:p4|wN|CF 검토 · Codex|codex|cf-critic|$ROOT||wN:t2"
settree wN:t1 "right(0.5,wN:p1,wN:p3)"
run --up
check "종료 코드 0" eq "$RC" 0
check "팀장 0.6 / impl 아래" eq "$(shape wN:t1)" "down(0.60,wN:p1,wN:p3)"
check "critic에 변경 명령 없음" eq "$(mutations | grep -c "wN:p4")" 0
check "critic 탭 그대로" eq "$(shape wN:t2)" "wN:p4"
check "안내" has "cf-critic(wN:p4)이 다른 탭"

CASE="--up(배치): critic이 다른 탭이고 비율만 다름 → 팀장·impl 비율만"
mkstate "$LEAD" "$IMPL" "wN:p4|wN|CF 검토 · Codex|codex|cf-critic|$ROOT||wN:t2"
settree wN:t1 "down(0.7,wN:p1,wN:p3)"
run --up
check "종료 코드 0" eq "$RC" 0
check "resize 1회" eq "$(count "pane${T}resize")" 1
check "팀장 0.6 / impl 아래" eq "$(shape wN:t1)" "down(0.60,wN:p1,wN:p3)"

CASE="--up(배치): impl이 다른 탭 → 옮기지 않고 비0"
mkstate "$LEAD" "wN:p3|wN|CF 구현 · agy|agy|cf-impl|$ROOT|$IMPL_SID|wN:t2" "$CRITIC"
run --up
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "안내" has "다른 탭에 있어 옮기지 않음"

CASE="--up(배치): cf-lead를 다른 pane이 소유 → 옮기지 않고 비0"
mkstate "wN:p1|wN||claude||$ROOT" "wG:p1|wG|other|claude|cf-lead|/tmp/other-project" "$IMPL" "$CRITIC"
settree wN:t1 "$MISSHAPEN"
run --up
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations

CASE="--up(배치): move 실패 → 비0 + 안내"
mkstate "$LEAD" "$IMPL" "$CRITIC" "$SIDE"
settree wN:t1 "$MISSHAPEN"
setstate fail '["move"]'
run --up
check "종료 코드 1" eq "$RC" 1
check "배치 그대로" eq "$(shape wN:t1)" "right(0.80,right(0.50,wN:p1,down(0.50,wN:p3,wN:p4)),wN:pW)"
check "안내" has "임시 탭으로 옮긴 것을 확인하지 못함"

CASE="--up(배치): 늦은 Sidebar 생성 경쟁 → 임시 탭 안정 대기 후 되돌림"
mkstate "$LEAD" "$IMPL" "$CRITIC" "$SIDE"
settree wN:t1 "$MISSHAPEN"
setstate late_sidebar true
run --up
check "종료 코드 0" eq "$RC" 0
check "배치 기준(늦은 Sidebar가 원래 탭에 끼어들지 않음)" eq "$(shape wN:t1)" "right(0.80,$TARGET,wN:pW)"
check "agent 없는 임시 탭만 닫음(2개)" eq "$(count "tab${T}close")" 2
check "남은 탭은 팀장 탭뿐" eq "$(tabs_of wN)" "wN:t1"

CASE="--up(배치): 임시 탭 대기 조회 실패 → 되돌리고 보정 시도 + 최종 비0"
mkstate "$LEAD" "$IMPL" "$CRITIC"
settree wN:t1 "down(0.7,wN:p1,down(0.5,wN:p3,wN:p4))"
setstate auto_sidebar true
setstate fail_once '["wait_list"]'
run --up
check "종료 코드 1(대기 실패로 비0 유지)" eq "$RC" 1
check "되돌리고 비율 보정까지 완료" eq "$(shape wN:t1)" "$TARGET"
check "대기 실패 안내" has "pane 목록 안정 대기 실패"

CASE="--up(배치): 첫 정상 목록 뒤 대기 조회 시간 초과 → 되돌리고 보정 시도 + 최종 비0"
mkstate "$LEAD" "$IMPL" "$CRITIC"
settree wN:t1 "down(0.7,wN:p1,down(0.5,wN:p3,wN:p4))"
setstate auto_sidebar true
setstate fail_once '["wait_timeout"]'
run --up
check "종료 코드 1(시간 초과로 비0 유지)" eq "$RC" 1
check "되돌리고 비율 보정까지 완료" eq "$(shape wN:t1)" "$TARGET"
check "대기 실패 안내" has "pane 목록 안정 대기 실패" "이동 단계에서 오류가 있었음"

CASE="--up(배치): 첫 move 실패 뒤에도 나머지 이동·비율 보정 시도 + 최종 비0"
mkstate "$LEAD" "$IMPL" "$CRITIC"
settree wN:t1 "down(0.7,wN:p1,down(0.5,wN:p3,wN:p4))"
setstate auto_sidebar true
setstate fail_once '["move"]'
run --up
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
check "안내" has "scripts/team-up.sh --up"

CASE="--up <id>: 끝에서 비율 보정"
mkstate "$LEAD" "$CRITIC"
settree wN:t1 "down(0.7,wN:p1,wN:p4)"
run --up "01a126cd-2222-4000-8000-0000000000bb"
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
CASE="--up <id>: impl 없음 → 복구"
RESUME_SID="01a126cd-1111-4000-8000-0000000000aa"
mkstate "$LEAD" "$CRITIC"
run --up "$RESUME_SID"
i="$(pane_named cf-impl)"
check "종료 코드 0" eq "$RC" 0
check "resume 명령" eq "$(field "$i" command)" "cd $ROOT && agy --conversation $RESUME_SID --model gemini-4-argon-high --mode accept-edits --sandbox"
check "run 1회(impl만)" eq "$(count "pane${T}run")" 1
check "배치 impl|critic" eq "$(order)" "$i wN:p4"
check "impl label" eq "$(field "$i" label)" "CF 구현 · agy"

CASE="--up <id>: 같은 id가 다른 pane에 살아 있음"
mkstate "$LEAD" "$CRITIC" "wG:p5|wG|x|agy||/tmp/other-project|$RESUME_SID"
run --up "${RESUME_SID:0:13}"
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "거부 사유" has "wG:p5"

CASE="--up <id>: 구현 agy가 이미 살아 있음"
mkstate "$LEAD" "$IMPL" "$CRITIC"
run --up "$RESUME_SID"
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "거부 사유" has "구현 agy가 이미 wN:p3 에 살아 있다"

CASE="--up <id>: cf-impl을 GJC가 사용 → conflict 거부"
mkstate "$LEAD" "wN:p3|wN|CF 구현 · GJC|gjc|cf-impl|$ROOT|$IMPL_SID" "$CRITIC"
run --up "$RESUME_SID"
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "충돌 사유" has "cf-impl" "다른 종류 agent(gjc)가 이름 사용"

CASE="--up <id>: id 형식 거부"
mkstate "$LEAD" "$CRITIC"
run --up 'abc; touch /tmp/x'
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
OUT="$(cd "$ROOT" && env -u HERDR_ENV -u HERDR_PANE_ID -u CF_EXTERNAL_LEAD MOCK_HERDR_STATE="$STATE" MOCK_HERDR_LOG="$LOG" \
	"$TEAM_UP_BASH" "$SCRIPT" --up 2>&1)"
RC=$?
check "종료 코드 1" eq "$RC" 1
check "Herdr 밖 안내" has "Herdr pane 안이 아니다; 아무것도 하지 않음"
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

# ---------------------------------------------------------------------------
# 외부 팀장 모드 (CF_EXTERNAL_LEAD=1 + HERDR_PANE_ID 비어 있음)
# 실제 저장소의 .local/team/external-lead를 건드리지 않도록 임시 메인 git 저장소(WT_MAIN)에서 실행한다.
EXT_SID="a1b2c3d4-0000-4000-8000-000000000001"
OTHER_EXT_SID="deadbeef-9999-4000-8000-000000000002"
WT_MAIN="$TMP/wt-main"
WT_LINKED="$TMP/wt-linked"
mkdir -p "$WT_MAIN/scripts" "$WT_MAIN/.claude/worktrees/w1"
cp "$SCRIPT" "$WT_MAIN/scripts/team-up.sh"
chmod +x "$WT_MAIN/scripts/team-up.sh"
(
	cd "$WT_MAIN" &&
		HOME="$TMP" XDG_CONFIG_HOME="$TMP" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git init -q &&
		HOME="$TMP" XDG_CONFIG_HOME="$TMP" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init &&
		HOME="$TMP" XDG_CONFIG_HOME="$TMP" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git worktree add -q "$WT_LINKED" -b linked
)
mkdir -p "$WT_LINKED/scripts"
cp "$SCRIPT" "$WT_LINKED/scripts/team-up.sh"
chmod +x "$WT_LINKED/scripts/team-up.sh"
EXT_ROOT="$(cd "$WT_MAIN" && pwd -P)"
EXT_SCRIPT="$EXT_ROOT/scripts/team-up.sh"
EXT_LOCK="$EXT_ROOT/.local/team/external-lead"
EXT_LEAD="wN:p1|wN|CF 팀장 · Claude|claude|cf-lead|$EXT_ROOT"
EXT_LEAD_CLEARED="wN:p1|wN|CF 팀장 · Claude|claude||$EXT_ROOT|$LEAD_SID"
EXT_IMPL="wN:p3|wN|CF 구현 · agy|agy|cf-impl|$EXT_ROOT|$IMPL_SID"
EXT_CRITIC="wN:p4|wN|CF 검토 · Codex|codex|cf-critic|$EXT_ROOT"

run_ext() {
	: >"$LOG"
	OUT="$(cd "$EXT_ROOT" && env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID \
		CF_EXTERNAL_LEAD=1 CLAUDE_CODE_SESSION_ID="$EXT_SID" \
		MOCK_HERDR_STATE="$STATE" MOCK_HERDR_LOG="$LOG" \
		CF_RETRIES=3 CF_RETRY_SLEEP=0 "$TEAM_UP_BASH" "$EXT_SCRIPT" "$@" 2>&1)"
	RC=$?
}

CASE="외부 모드 ①: CF_EXTERNAL_LEAD=1 + HERDR_PANE_ID 있음 → die·무변경"
mkstate "$EXT_LEAD" "$EXT_IMPL" "$EXT_CRITIC"
: >"$LOG"
OUT="$(cd "$EXT_ROOT" && env HERDR_ENV=1 HERDR_PANE_ID=wN:p1 CF_EXTERNAL_LEAD=1 CLAUDE_CODE_SESSION_ID="$EXT_SID" \
	MOCK_HERDR_STATE="$STATE" MOCK_HERDR_LOG="$LOG" "$TEAM_UP_BASH" "$EXT_SCRIPT" 2>&1)"
RC=$?
check "종료 코드 1" eq "$RC" 1
check "거부 문구" has "Herdr pane 안 세션에서는 CF_EXTERNAL_LEAD를 쓰지 않는다; 아무것도 하지 않음"
check "herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0

CASE="외부 모드: CLAUDE_CODE_SESSION_ID 없음 → die"
mkstate "$EXT_IMPL" "$EXT_CRITIC"
: >"$LOG"
OUT="$(cd "$EXT_ROOT" && env -u HERDR_ENV -u HERDR_PANE_ID -u CLAUDE_CODE_SESSION_ID CF_EXTERNAL_LEAD=1 \
	MOCK_HERDR_STATE="$STATE" MOCK_HERDR_LOG="$LOG" "$TEAM_UP_BASH" "$EXT_SCRIPT" 2>&1)"
RC=$?
check "종료 코드 1" eq "$RC" 1
check "거부 문구" has "CLAUDE_CODE_SESSION_ID가 없다; 외부 팀장 세션을 확인할 수 없음"
check "herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0

CASE="외부 모드 ③: 팀원 2석 alive + 기록 없음 → 점검 rc 0, external(이 세션), 파일 무생성"
rm -f "$EXT_LOCK"
mkstate "$EXT_IMPL" "$EXT_CRITIC"
run_ext
check "종료 코드 0" eq "$RC" 0
check "변경 명령 없음" no_mutations
check "현재 pane 외부" has "현재 pane 외부"
check "lead 행 external(이 세션)" line_matches "^lead +cf-lead +- +claude +external\(이 세션\) +- +유지\$"
check "기록 없음 경고 줄" has "↳ 외부 팀장 기록: 없음"
check "배치 경고 없음" eq "$(printf '%s\n' "$OUT" | grep -c '배치')" 0
check "기록 파일 생성 안 됨" test ! -e "$EXT_LOCK"

CASE="외부 모드 (§8.3): HERDR_ENV=1인데 HERDR_PANE_ID만 없음 + CF_EXTERNAL_LEAD=1 → 외부 모드로 동작"
mkstate "$EXT_IMPL" "$EXT_CRITIC"
: >"$LOG"
OUT="$(cd "$EXT_ROOT" && env -u HERDR_PANE_ID HERDR_ENV=1 CF_EXTERNAL_LEAD=1 CLAUDE_CODE_SESSION_ID="$EXT_SID" \
	MOCK_HERDR_STATE="$STATE" MOCK_HERDR_LOG="$LOG" "$TEAM_UP_BASH" "$EXT_SCRIPT" 2>&1)"
RC=$?
check "종료 코드 0" eq "$RC" 0
check "변경 명령 없음" no_mutations
check "external(이 세션)" has "external(이 세션)"

CASE="외부 모드 ④: 팀원 pane 0개 → die(0개 문구)"
mkstate "wN:p9|wN|일반 셸|||/tmp/other-project"
run_ext
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "0개 문구" has "CF 팀원 pane을 찾지 못했다; Herdr에서 작업공간과 label 「CF 구현 · agy」 빈 셸 pane을 먼저 만든다"

CASE="외부 모드 ⑤: 팀원 pane이 두 작업공간 → die"
mkstate "w1:p3|w1|CF 구현 · agy|agy|cf-impl|$EXT_ROOT|$IMPL_SID" "w2:p4|w2|CF 검토 · Codex|codex|cf-critic|$EXT_ROOT"
run_ext
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "여러 작업공간 문구" has "CF 팀원 pane이 여러 작업공간에 있다: w1, w2; 아무것도 하지 않음"

CASE="외부 모드 ⑥: Herdr 안 cf-lead 살아 있음 → 경고 줄·rc 0·건드리지 않음"
mkstate "$EXT_LEAD" "$EXT_IMPL" "$EXT_CRITIC"
run_ext
check "종료 코드 0" eq "$RC" 0
check "변경 명령 없음" no_mutations
check "Herdr 안 cf-lead 경고 줄" has "↳ Herdr 안 cf-lead(wN:p1)가 살아 있음 — 이관 중이면 한쪽만 팀원에게 입력한다"
check "cf-lead 이름 그대로" eq "$(pane_named cf-lead)" wN:p1

SELF_LOCK_EXPECTED="$(printf '%s\n42500\tSun Oct 18 15:36:35 2026' "$EXT_SID")"

CASE="외부 모드 ⑦ + §8.1: --up critic 없음 + 첫 기록 생성 → impl 옆 새 pane·이름 확보"
rm -f "$EXT_LOCK"
mkstate "$EXT_IMPL"
run_ext --up
c="$(pane_named cf-critic)"
check "종료 코드 0" eq "$RC" 0
check "기록 파일 생성" test -f "$EXT_LOCK"
check "기록된 2줄 형식(세션 id + claude pid·lstart) 일치" eq "$(cat "$EXT_LOCK")" "$SELF_LOCK_EXPECTED"
check "cf-lead rename 없음" eq "$(grep -cE "^agent${T}rename${T}.*${T}cf-lead\$" "$LOG")" 0
check "critic 새 pane을 impl 오른쪽에 분할" eq "$(field "$c" split_from)|$(field "$c" split_direction)" "wN:p3|right"
check "critic 기동·이름 확보" eq "$(field "$c" agent)|$(field "$c" label)" "codex|CF 검토 · Codex"
check "배치 impl|critic 0.50" eq "$(shape wN:t1)" "right(0.50,wN:p3,$c)"

CASE="외부 모드 (§8.3): 같은 세션 id 기록됨 → 점검 경고 없음·--up 통과"
mkstate "$EXT_IMPL" "$EXT_CRITIC"
run_ext
check "점검 종료 코드 0" eq "$RC" 0
check "기록 경고 없음" not_has "외부 팀장 기록:"
run_ext --up
check "--up 종료 코드 0" eq "$RC" 0
check "변경 명령 없음" no_mutations

CASE="외부 모드 (#9 ④ 옛 형식 / 판정 불가): 둘째 줄 없는 옛 1줄 기록 및 꼴 틀린 2줄 기록 → 점검 판정 불가(파일 무변경) · 바꾸는 모드 거부"
printf '%s\n' "$OTHER_EXT_SID" >|"$EXT_LOCK"
mkstate "$EXT_IMPL" "$EXT_CRITIC"
run_ext
check "점검 종료 코드 0" eq "$RC" 0
check "점검 변경 명령 없음" no_mutations
check "다른 세션 경고 줄 + 판정 불가" has "↳ 외부 팀장 기록: 다른 세션(deadbeef…) — 판정 불가"
check "기록 파일 내용 유지" eq "$(cat "$EXT_LOCK")" "$OTHER_EXT_SID"
run_ext --up
check "--up 종료 코드 1" eq "$RC" 1
check "herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0
check "기록 불일치 die 문구(§8.1+§9.2)" has \
	"다른 세션(deadbeef…)이 외부 팀장으로 기록돼 있다; 사용자 승인 뒤 이 세션에서 CF_EXTERNAL_LEAD=1 scripts/team-up.sh --lock claim --force (같은 외부 팀장이 /clear·새 대화 뒤라 세션 id가 바뀐 경우도 사용자 확인 후 --lock claim --force)"
check "기록 파일 내용 여전히 유지" eq "$(cat "$EXT_LOCK")" "$OTHER_EXT_SID"

BAD_LOCK="$(printf '%s\nnotapid\tSun Oct 18 12:00:00 2026' "$OTHER_EXT_SID")"
printf '%s\n' "$BAD_LOCK" >|"$EXT_LOCK"
run_ext
check "꼴 틀린 2줄 점검 종료 코드 0" eq "$RC" 0
check "꼴 틀린 2줄 점검 판정 불가" has "↳ 외부 팀장 기록: 다른 세션(deadbeef…) — 판정 불가"
check "꼴 틀린 2줄 점검 기록 무변경" eq "$(cat "$EXT_LOCK")" "$BAD_LOCK"
run_ext --up
check "꼴 틀린 2줄 --up 거부" eq "$RC" 1
check "꼴 틀린 2줄 herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0
check "꼴 틀린 2줄 기록 무변경" eq "$(cat "$EXT_LOCK")" "$BAD_LOCK"

for bad_ts in "not-a-start-time" "Sun Oct 18 14:00:69 2026" "Sun Oct 18 14:00:60 2026" "Sun Feb 30 14:00:00 2026"; do
	BAD_LSTART_LOCK="$(printf '%s\n6000\t%s' "$OTHER_EXT_SID" "$bad_ts")"
	printf '%s\n' "$BAD_LSTART_LOCK" >|"$EXT_LOCK"
	mkstate "$EXT_IMPL" "$EXT_CRITIC"
	setstate "ps_procs" '{"6000": {"ppid": 1, "comm": "/Users/mock/.local/bin/claude", "lstart": "Sun Oct 18 14:00:00 2026"}}'
	run_ext
	check "살아 있는 pid + 꼴 틀린 lstart($bad_ts) 점검 종료 코드 0" eq "$RC" 0
	check "살아 있는 pid + 꼴 틀린 lstart($bad_ts) 점검 판정 불가" has "↳ 외부 팀장 기록: 다른 세션(deadbeef…) — 판정 불가"
	check "살아 있는 pid + 꼴 틀린 lstart($bad_ts) 점검 기록 무변경" eq "$(cat "$EXT_LOCK")" "$BAD_LSTART_LOCK"
	run_ext --up
	check "살아 있는 pid + 꼴 틀린 lstart($bad_ts) --up 거부(rc 1)" eq "$RC" 1
	check "살아 있는 pid + 꼴 틀린 lstart($bad_ts) --up herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0
	check "살아 있는 pid + 꼴 틀린 lstart($bad_ts) --up 기록 무변경" eq "$(cat "$EXT_LOCK")" "$BAD_LSTART_LOCK"
	run_ext --up "$RESUME_SID"
	check "살아 있는 pid + 꼴 틀린 lstart($bad_ts) --up <id> 거부(rc 1)" eq "$RC" 1
	check "살아 있는 pid + 꼴 틀린 lstart($bad_ts) --up <id> 기록 무변경" eq "$(cat "$EXT_LOCK")" "$BAD_LSTART_LOCK"
done

CASE="외부 모드 (#9 ① 살아 있음 → 거부): 다른 세션 pid·시작 시각 모두 일치 → 점검 살아 있음(파일 무변경) · 바꾸는 모드 거부"
ALIVE_LOCK="$(printf '%s\n6000\tSun Oct 18 14:00:00 2026' "$OTHER_EXT_SID")"
printf '%s\n' "$ALIVE_LOCK" >|"$EXT_LOCK"
mkstate "$EXT_IMPL" "$EXT_CRITIC"
setstate "ps_procs" '{"6000": {"ppid": 1, "comm": "/Users/mock/.local/bin/claude", "lstart": "Sun Oct 18 14:00:00 2026"}}'
run_ext
check "살아 있음 점검 종료 코드 0" eq "$RC" 0
check "살아 있음 점검 변경 명령 없음" no_mutations
check "살아 있음 점검 표시" has "↳ 외부 팀장 기록: 다른 세션(deadbeef…) — 옛 주인 살아 있음"
check "살아 있음 점검 기록 무변경" eq "$(cat "$EXT_LOCK")" "$ALIVE_LOCK"
for m_arg in "--up" "--up $RESUME_SID"; do
	# shellcheck disable=SC2086
	run_ext $m_arg
	check "살아 있음 $m_arg 거부(rc 1)" eq "$RC" 1
	check "살아 있음 $m_arg herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0
	check "살아 있음 $m_arg die 문구" has "다른 세션(deadbeef…)이 외부 팀장으로 기록돼 있다; 사용자 승인 뒤 이 세션에서 CF_EXTERNAL_LEAD=1 scripts/team-up.sh --lock claim --force"
	check "살아 있음 $m_arg 기록 무변경" eq "$(cat "$EXT_LOCK")" "$ALIVE_LOCK"
done

CASE="외부 모드 (#9 ② pid 없음 → 회수): 기록 pid가 사라짐 → 점검은 무변경 표시 · 바꾸는 명령에서 자동 회수"
GONE_PID_LOCK="$(printf '%s\n7777\tSun Oct 18 12:00:00 2026' "$OTHER_EXT_SID")"
printf '%s\n' "$GONE_PID_LOCK" >|"$EXT_LOCK"
mkstate "$EXT_IMPL" "$EXT_CRITIC"
run_ext
check "pid 없음 점검 종료 코드 0" eq "$RC" 0
check "pid 없음 점검 변경 명령 없음" no_mutations
check "pid 없음 점검 표시" has "↳ 외부 팀장 기록: 다른 세션(deadbeef…) — 옛 주인 종료됨 — 바꾸는 명령 때 자동 회수"
check "pid 없음 점검은 기록을 쓰지 않음" eq "$(cat "$EXT_LOCK")" "$GONE_PID_LOCK"
run_ext --up
check "pid 없음 --up 종료 코드 0" eq "$RC" 0
check "pid 없음 자동 회수 안내 문구" has "외부 팀장 기록 자동 회수: 옛 세션(deadbeef…) 종료 확인"
check "pid 없음 새 세션 2줄 기록으로 갱신" eq "$(cat "$EXT_LOCK")" "$SELF_LOCK_EXPECTED"

CASE="외부 모드 (#9 ②-경합 및 중간 종료 정리: 동시 회수 시 한쪽만 성공·중간 종료 시 잠금 자동 정리)"
EXT_SID_B="b2c3d4e5-1111-4000-8000-000000000003"
printf '%s\n' "$GONE_PID_LOCK" >|"$EXT_LOCK"
mkstate "$EXT_IMPL" "$EXT_CRITIC"
setstate "ps_procs" '{"43500": {"ppid": 1, "comm": "/Users/mock/.local/bin/claude", "lstart": "Sun Oct 18 15:36:36 2026"}}'
mkdir "$EXT_LOCK.lock"
(
	cd "$EXT_ROOT" && env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID \
		CF_EXTERNAL_LEAD=1 CLAUDE_CODE_SESSION_ID="$EXT_SID" \
		MOCK_HERDR_STATE="$STATE" MOCK_HERDR_LOG="$TMP/race-a.log" \
		CF_RETRIES=3 CF_RETRY_SLEEP=0 "$TEAM_UP_BASH" "$EXT_SCRIPT" --up >"$TMP/race-a.out" 2>&1
	echo "$?" >"$TMP/race-a.rc"
) &
pid_a=$!
(
	cd "$EXT_ROOT" && env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID \
		CF_EXTERNAL_LEAD=1 CLAUDE_CODE_SESSION_ID="$EXT_SID_B" MOCK_PS_SELF_PPID=43500 \
		MOCK_HERDR_STATE="$STATE" MOCK_HERDR_LOG="$TMP/race-b.log" \
		CF_RETRIES=3 CF_RETRY_SLEEP=0 "$TEAM_UP_BASH" "$EXT_SCRIPT" --up >"$TMP/race-b.out" 2>&1
	echo "$?" >"$TMP/race-b.rc"
) &
pid_b=$!
sleep 0.2
rmdir "$EXT_LOCK.lock"
wait "$pid_a" "$pid_b"
rc_a="$(cat "$TMP/race-a.rc")"
rc_b="$(cat "$TMP/race-b.rc")"
check "동시 회수 중 정확히 한 세션만 성공(rc 합 = 1)" eq "$((rc_a + rc_b))" 1
if [ "$rc_a" = 0 ]; then
	check "A 성공 시 기록은 A" eq "$(cat "$EXT_LOCK")" "$SELF_LOCK_EXPECTED"
	check "B 거부 문구" grep -q "다른 세션(a1b2c3d4…)이 외부 팀장으로 기록돼 있다" "$TMP/race-b.out"
else
	check "B 성공 시 기록은 B" eq "$(cat "$EXT_LOCK")" "$(printf '%s\n43500\tSun Oct 18 15:36:36 2026' "$EXT_SID_B")"
	check "A 거부 문구" grep -q "다른 세션(b2c3d4e5…)이 외부 팀장으로 기록돼 있다" "$TMP/race-a.out"
fi

"$TEAM_UP_BASH" -c '
	ROOT="$1"
	EXT_LEAD_FILE="$ROOT/.local/team/external-lead"
	EXT_LEAD_LOCK_DIR="$ROOT/.local/team/external-lead.lock"
	EXT_LEAD_LOCK_HELD=0
	warn() { echo "team-up: $*" >&2; }
	die() { warn "$*"; exit 1; }
	eval "$(sed -n "/^acquire_ext_lead_lock()/,/^}/p; /^release_ext_lead_lock()/,/^}/p" "$2")"
	acquire_ext_lead_lock
	exit 42
' _ "$EXT_ROOT" "$EXT_SCRIPT"
holder_rc=$?
check "잠금 보유 중 조기 종료(exit 42) 시 종료 코드 보존" eq "$holder_rc" 42
check "잠금 보유 중 조기 종료 뒤 잠금 디렉터리 자동 정리됨" test ! -e "$EXT_LOCK.lock"
printf '%s\n' "$GONE_PID_LOCK" >|"$EXT_LOCK"
run_ext --up
check "조기 종료 정리 뒤 다음 실행(--up) 정상 회수 성공" eq "$RC" 0

CASE="외부 모드 (#9 ③ 시작 시각 다름 → 회수): 기록 pid는 존재하나 lstart가 다름 → 점검은 무변경 표시 · 바꾸는 명령에서 자동 회수"
DIFF_LSTART_LOCK="$(printf '%s\n6000\tSun Oct 18 12:00:00 2026' "$OTHER_EXT_SID")"
printf '%s\n' "$DIFF_LSTART_LOCK" >|"$EXT_LOCK"
mkstate "$EXT_IMPL" "$EXT_CRITIC"
setstate "ps_procs" '{"6000": {"ppid": 1, "comm": "/Users/mock/.local/bin/claude", "lstart": "Sun Oct 18 14:00:00 2026"}}'
run_ext
check "시작 시각 다름 점검 종료 코드 0" eq "$RC" 0
check "시작 시각 다름 점검 변경 명령 없음" no_mutations
check "시작 시각 다름 점검 표시" has "↳ 외부 팀장 기록: 다른 세션(deadbeef…) — 옛 주인 종료됨 — 바꾸는 명령 때 자동 회수"
check "시작 시각 다름 점검은 기록을 쓰지 않음" eq "$(cat "$EXT_LOCK")" "$DIFF_LSTART_LOCK"
run_ext --up
check "시작 시각 다름 --up 종료 코드 0" eq "$RC" 0
check "시작 시각 다름 자동 회수 안내 문구" has "외부 팀장 기록 자동 회수: 옛 세션(deadbeef…) 종료 확인"
check "시작 시각 다름 새 세션 2줄 기록으로 갱신" eq "$(cat "$EXT_LOCK")" "$SELF_LOCK_EXPECTED"

CASE="외부 모드 (#9 ⑤ ps 실패·조상 없음 → 거부): ps 오류 또는 소문자 claude 조상 없음 → 점검 판정 불가 · 바꾸는 모드 거부"
printf '%s\n' "$GONE_PID_LOCK" >|"$EXT_LOCK"
mkstate "$EXT_IMPL" "$EXT_CRITIC"
setstate "ps_fail" "true"
run_ext
check "ps 실패 점검 종료 코드 0" eq "$RC" 0
check "ps 실패 점검 판정 불가" has "↳ 외부 팀장 기록: 다른 세션(deadbeef…) — 판정 불가"
check "ps 실패 점검 기록 무변경" eq "$(cat "$EXT_LOCK")" "$GONE_PID_LOCK"
run_ext --up
check "ps 실패 --up 거부(rc 1)" eq "$RC" 1
check "ps 실패 herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0
check "ps 실패 --lock claim --force 안내" has "--lock claim --force"
check "ps 실패 기록 무변경" eq "$(cat "$EXT_LOCK")" "$GONE_PID_LOCK"

mkstate "$EXT_IMPL" "$EXT_CRITIC"
setstate "ps_fail_pids" '["7777"]'
run_ext
check "기록 pid ps 실패 점검 판정 불가" has "↳ 외부 팀장 기록: 다른 세션(deadbeef…) — 판정 불가"
run_ext --up
check "기록 pid ps 실패 --up 거부(rc 1)" eq "$RC" 1
check "기록 pid ps 실패 herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0
check "기록 pid ps 실패 기록 무변경" eq "$(cat "$EXT_LOCK")" "$GONE_PID_LOCK"

mkstate "$EXT_IMPL" "$EXT_CRITIC"
setstate "ps_no_ancestor" "true"
run_ext
check "조상 없음 점검 종료 코드 0" eq "$RC" 0
check "조상 없음 점검 판정 불가" has "↳ 외부 팀장 기록: 다른 세션(deadbeef…) — 판정 불가"
check "조상 없음 점검 기록 무변경" eq "$(cat "$EXT_LOCK")" "$GONE_PID_LOCK"
run_ext --up
check "조상 없음 --up 거부(rc 1)" eq "$RC" 1
check "조상 없음 herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0
check "조상 없음 --lock claim --force 안내" has "--lock claim --force"
check "조상 없음 기록 무변경" eq "$(cat "$EXT_LOCK")" "$GONE_PID_LOCK"

CASE="외부 모드 (§8.1, §8.3): --lock claim --force 덮어쓰기 및 비외부 모드 거부"
mkstate "$EXT_IMPL" "$EXT_CRITIC"
printf '%s\n' "$OTHER_EXT_SID" >|"$EXT_LOCK"
: >"$LOG"
OUT="$(cd "$EXT_ROOT" && env HERDR_ENV=1 HERDR_PANE_ID=wN:p1 MOCK_HERDR_STATE="$STATE" MOCK_HERDR_LOG="$LOG" \
	"$TEAM_UP_BASH" "$EXT_SCRIPT" --lock claim --force 2>&1)"
RC=$?
check "Herdr 안 모드에서 --lock 거부(종료 2)" eq "$RC" 2
check "기록 파일 덮어쓰지 않음" eq "$(cat "$EXT_LOCK")" "$OTHER_EXT_SID"
run_ext --lock claim --force
check "--lock claim --force 종료 코드 0" eq "$RC" 0
check "herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0
check "새 세션 2줄 기록으로 덮어써짐" eq "$(cat "$EXT_LOCK")" "$SELF_LOCK_EXPECTED"
run_ext --up
check "덮어쓴 뒤 --up 통과" eq "$RC" 0

CASE="외부 모드 ⑦: --up impl·critic 둘 다 없음 → die·파일 무생성"
rm -f "$EXT_LOCK"
mkstate "$EXT_LEAD"
run_ext --up
check "종료 코드 1" eq "$RC" 1
check "변경 명령 없음" no_mutations
check "0개 문구" has "CF 팀원 pane을 찾지 못했다; Herdr에서 작업공간과 label 「CF 구현 · agy」 빈 셸 pane을 먼저 만든다"
check "실패 시 기록 파일 생성 안 됨" test ! -e "$EXT_LOCK"

CASE="외부 모드: --up <id> critic만 있을 때 왼쪽 자리에 복구"
mkstate "$EXT_CRITIC"
run_ext --up "$RESUME_SID"
i="$(pane_named cf-impl)"
check "종료 코드 0" eq "$RC" 0
check "cf-lead rename 없음" eq "$(grep -cE "^agent${T}rename${T}.*${T}cf-lead\$" "$LOG")" 0
check "배치 impl|critic 0.50" eq "$(shape wN:t1)" "right(0.50,$i,wN:p4)"

CASE="외부 모드 ⑧: --up 좌우 붙음 + 비율 다름 → 비율만 맞춤(팀장 pane 무변경)"
mkstate "$EXT_LEAD" "$EXT_IMPL" "$EXT_CRITIC"
settree wN:t1 "down(0.7,wN:p1,right(0.35,wN:p3,wN:p4))"
run_ext --up
check "종료 코드 0" eq "$RC" 0
check "pane move/close 없음" eq "$(grep -cE "^(pane${T}move|tab${T}close)${T}" "$LOG")" 0
check "팀장 비율(0.70)은 그대로 두고 impl/critic 비율만 0.50" eq "$(shape wN:t1)" "down(0.70,wN:p1,right(0.50,wN:p3,wN:p4))"

CASE="외부 모드 ⑧: --up(배치) 다른 탭 / 섞인 모양 / 한 석 충돌 → 무이동·rc 1"
mkstate "$EXT_IMPL" "wN:p4|wN|CF 검토 · Codex|codex|cf-critic|$EXT_ROOT||wN:t2"
run_ext --up
check "다른 탭 종료 코드 1" eq "$RC" 1
check "다른 탭 변경 없음" no_mutations
mkstate "$EXT_IMPL" "$EXT_CRITIC"
settree wN:t1 "down(0.5,wN:p3,wN:p4)"
run_ext --up
check "위아래 배치 종료 코드 1" eq "$RC" 1
check "위아래 배치 변경 없음" no_mutations
mkstate "$EXT_IMPL" "wN:p4|wN|other|codex|cf-critic|/tmp/other-project"
run_ext --up
check "한 석만 가용(critic 충돌) 종료 코드 1" eq "$RC" 1
check "한 석만 가용 변경 없음" no_mutations

CASE="외부 모드 ⑨: --hook-clear 및 --hook 별칭 → 0·무출력·herdr 호출 없음"
mkstate "$EXT_LEAD_CLEARED" "$EXT_IMPL" "$EXT_CRITIC"
run_ext --hook-clear <<<"{\"session_id\":\"$LEAD_SID\",\"source\":\"clear\"}"
check "--hook-clear 종료 코드 0" eq "$RC" 0
check "--hook-clear 출력 없음" eq "$OUT" ""
check "--hook-clear herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0
run_ext --hook <<<"{\"session_id\":\"$LEAD_SID\",\"source\":\"clear\"}"
check "--hook 종료 코드 0" eq "$RC" 0
check "--hook 출력 없음" eq "$OUT" ""
check "--hook herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0

CASE="외부 모드 (§9.1): git worktree add 연결 worktree 및 .claude/worktrees 거절"
mkstate "$EXT_IMPL" "$EXT_CRITIC"
: >"$LOG"
OUT="$(cd "$WT_LINKED" && env -u HERDR_ENV -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 CLAUDE_CODE_SESSION_ID="$EXT_SID" \
	MOCK_HERDR_STATE="$STATE" MOCK_HERDR_LOG="$LOG" "$TEAM_UP_BASH" "$WT_LINKED/scripts/team-up.sh" 2>&1)"
RC=$?
check "연결 worktree 종료 코드 1" eq "$RC" 1
check "연결 worktree 거절 문구" has "데스크톱 세션의 worktree 옵션을 끄고 저장소 폴더에서 새 세션을 연다"
check "연결 worktree herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0

: >"$LOG"
OUT="$(cd "$EXT_ROOT/.claude/worktrees/w1" && env -u HERDR_ENV -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 CLAUDE_CODE_SESSION_ID="$EXT_SID" \
	MOCK_HERDR_STATE="$STATE" MOCK_HERDR_LOG="$LOG" "$TEAM_UP_BASH" "$EXT_SCRIPT" 2>&1)"
RC=$?
check ".claude/worktrees 하위 종료 코드 1" eq "$RC" 1
check ".claude/worktrees 거절 문구" has "데스크톱 세션의 worktree 옵션을 끄고 저장소 폴더에서 새 세션을 연다"
check ".claude/worktrees herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0

# ---------------------------------------------------------------------------
# #16 추가 시험: 새 하위 명령(--check, --up [<id>], --status, --lock, --hook), 없앤 이름, 안전 계약
CASE="#16: --check와 인자 없음 출력·종료 코드 일치 + 공통 한 줄(ok / unknown)"
mkstate "$LEAD" "$IMPL" "$CRITIC"
run
OUT_NOARG="$OUT"
RC_NOARG="$RC"
run --check
check "--check 종료 코드 0" eq "$RC" 0
check "인자 없음과 --check 출력 동일" eq "$OUT" "$OUT_NOARG"
check "인자 없음과 --check 종료 코드 동일" eq "$RC" "$RC_NOARG"
check "표 아래 cf-impl ok + 대화=<id>" line_matches "^cf-impl wN:p3 ok 대화=$IMPL_SID\$"
check "표 아래 cf-critic ok" line_matches "^cf-critic wN:p4 ok\$"

mkstate "$LEAD" "wN:p3|wN|CF 구현 · agy|||$ROOT"
run --check
check "빈 셸 + missing 점검 종료 코드 1" eq "$RC" 1
check "빈 셸 공통 한 줄" line_matches "^cf-impl wN:p3 unknown 빈 셸\$"
check "missing 공통 한 줄" line_matches "^cf-critic - unknown 없음\$"

mkstate "$LEAD" "wN:p3|wN|CF 구현 · agy|agy||$ROOT|$IMPL_SID" "$CRITIC"
run --check
check "unnamed 점검 종료 코드 1" eq "$RC" 1
check "unnamed 공통 한 줄" line_matches "^cf-impl wN:p3 unknown 이름 미확보\(unnamed\) 대화=$IMPL_SID\$"

CASE="#16: 없앤 이름(--resume-impl, --layout, --claim-external) → 사용법 + 새 이름 안내 + 종료 2 + 무변경"
mkstate "$LEAD" "$IMPL" "$CRITIC"
run --resume-impl "$RESUME_SID"
check "--resume-impl 종료 코드 2" eq "$RC" 2
check "--resume-impl 새 이름 안내" has "--resume-impl은 없앴다" "scripts/team-up.sh --up <agy 대화 id>"
check "--resume-impl herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0

run --layout
check "--layout 종료 코드 2" eq "$RC" 2
check "--layout 새 이름 안내" has "--layout은 없앴다" "scripts/team-up.sh --up"
check "--layout herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0

run --claim-external
check "--claim-external 종료 코드 2" eq "$RC" 2
check "--claim-external 새 이름 안내" has "--claim-external은 없앴다" "scripts/team-up.sh --lock claim [--force]"
check "--claim-external herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0

CASE="#16: --hook 별칭(Herdr 안 clear → cf-lead 이름 확보)"
rm -f "$HOOK_DONE"
mkstate "$LEAD_CLEARED" "$IMPL" "$CRITIC"
run --hook <<<"{\"session_id\":\"$LEAD_SID\",\"source\":\"clear\"}" 9> >(cat >/dev/null; : >"$HOOK_DONE")
check "--hook 종료 코드 0" eq "$RC" 0
check "--hook 출력 없음" eq "$OUT" ""
if ! hook_exited; then
	echo "FATAL [$CASE] 백그라운드 작업이 10초 안에 끝나지 않음" >&2
	exit 1
fi
check "--hook 팀장 이름 확보" eq "$(pane_named cf-lead)" wN:p1
check "--hook 다른 변경 없음" eq "$(mutations)" "agent${T}rename${T}wN:p1${T}cf-lead"

CASE="#16: --up <id> 빈 셸에서 대화 복구 vs --up(id 없음) 새 대화 경고"
mkstate "$LEAD" "wN:p3|wN|CF 구현 · agy|||$ROOT" "$CRITIC"
run --up "$RESUME_SID"
check "빈 셸 + id 종료 코드 0" eq "$RC" 0
check "빈 셸 + id split 없음" eq "$(count "pane${T}split")" 0
check "빈 셸 + id --conversation 기동" eq "$(field wN:p3 command)" "cd $ROOT && agy --conversation $RESUME_SID --model gemini-4-argon-high --mode accept-edits --sandbox"
check "빈 셸 + id는 대화 id 없음 경고 안 냄" not_has "대화 id 없음 — 새 대화로 띄움"

CASE="#16: --up 살아 있는 팀원 옵션 불일치 → 건드리지 않고 한 줄 알림 + 확인창 미응답 + 배치 보정"
mkstate "$LEAD" "$IMPL" "$CRITIC"
settree wN:t1 "down(0.7,wN:p1,right(0.4,wN:p3,wN:p4))"
python3 -c 'import sys,json
st=json.load(open(sys.argv[1]))
for p in st["panes"]:
    if p["pane_id"]=="wN:p3": p["agent_status"]="blocked"
json.dump(st,open(sys.argv[1],"w"),ensure_ascii=False)' "$STATE"
setstate "process_info.wN:p3" '{"foreground_processes":[{"pid":101,"name":"agy","argv":["agy"]}]}'
setstate "process_info.wN:p4" '{"foreground_processes":[{"pid":102,"name":"codex","argv":["codex"]}]}'
run --up
check "--up 옵션 불일치 시 종료 코드 0(배치 보정 성공)" eq "$RC" 0
check "살아 있는 팀원 재실행·분할 없음" eq "$(grep -cE "^pane${T}(split|run)${T}" "$LOG")" 0
check "확인창에 답하지 않음(send-text/send-keys 없음)" eq "$(grep -cE "^pane${T}(send-text|send-keys)${T}" "$LOG")" 0
check "cf-impl 옵션 불일치 한 줄 안내(대화 id 포함)" has "cf-impl 옵션 불일치 — idle일 때 /quit 뒤 scripts/team-up.sh --up $IMPL_SID"
check "cf-critic 옵션 불일치 한 줄 안내(id 없음)" has "cf-critic 옵션 불일치 — idle일 때 /quit 뒤 scripts/team-up.sh --up"
check "마지막에 배치 비율 보정 수행" eq "$(shape wN:t1)" "$TARGET"

CASE="#16: --lock 표 5상태(none, mine, other live, stale, unknown) × status/claim/claim --force/release"
# 0) 비외부 모드에서 --lock 호출 → 종료 2
for sub in "status" "claim" "claim --force" "release"; do
	# shellcheck disable=SC2086
	run --lock $sub
	check "Herdr 안에서 --lock $sub 종료 코드 2" eq "$RC" 2
	check "Herdr 안에서 --lock $sub herdr 호출 없음" eq "$(wc -l <"$LOG" | tr -d ' ')" 0
done

# 1) 기록 없음(none)
rm -f "$EXT_LOCK"
mkstate "$EXT_IMPL" "$EXT_CRITIC"
run_ext --lock status
check "none: status 종료 0" eq "$RC" 0
check "none: status 출력" eq "$OUT" "none"
check "none: status 뒤에도 파일 없음" test ! -e "$EXT_LOCK"
run_ext --lock release
check "none: release 종료 0" eq "$RC" 0
check "none: release 뒤에도 파일 없음" test ! -e "$EXT_LOCK"
run_ext --lock claim
check "none: claim 종료 0" eq "$RC" 0
check "none: claim이 이 세션으로 기록" eq "$(cat "$EXT_LOCK")" "$SELF_LOCK_EXPECTED"
rm -f "$EXT_LOCK"
run_ext --lock claim --force
check "none: claim --force 종료 0" eq "$RC" 0
check "none: claim --force가 이 세션으로 기록" eq "$(cat "$EXT_LOCK")" "$SELF_LOCK_EXPECTED"

# 2) 이 세션(mine)
run_ext --lock status
check "mine: status 종료 0" eq "$RC" 0
check "mine: status 출력" eq "$OUT" "mine"
run_ext --lock claim
check "mine: claim 종료 0" eq "$RC" 0
check "mine: claim 그대로 유지" eq "$(cat "$EXT_LOCK")" "$SELF_LOCK_EXPECTED"
run_ext --lock claim --force
check "mine: claim --force 종료 0" eq "$RC" 0
check "mine: claim --force 그대로 유지" eq "$(cat "$EXT_LOCK")" "$SELF_LOCK_EXPECTED"
run_ext --lock release
check "mine: release 종료 0" eq "$RC" 0
check "mine: release가 기록 지움" test ! -e "$EXT_LOCK"

# 3) 다른 세션·옛 주인 살아 있음(other live)
printf '%s\n' "$ALIVE_LOCK" >|"$EXT_LOCK"
setstate "ps_procs" '{"6000": {"ppid": 1, "comm": "/Users/mock/.local/bin/claude", "lstart": "Sun Oct 18 14:00:00 2026"}}'
run_ext --lock status
check "other live: status 종료 0" eq "$RC" 0
check "other live: status 출력" eq "$OUT" "other live"
check "other live: status 기록 무변경" eq "$(cat "$EXT_LOCK")" "$ALIVE_LOCK"
run_ext --lock claim
check "other live: claim 종료 3" eq "$RC" 3
check "other live: claim 기록 무변경" eq "$(cat "$EXT_LOCK")" "$ALIVE_LOCK"
run_ext --lock release
check "other live: release 종료 3" eq "$RC" 3
check "other live: release 기록 무변경" eq "$(cat "$EXT_LOCK")" "$ALIVE_LOCK"
run_ext --lock claim --force
check "other live: claim --force 종료 0" eq "$RC" 0
check "other live: claim --force 이 세션으로 기록" eq "$(cat "$EXT_LOCK")" "$SELF_LOCK_EXPECTED"

# 4) 다른 세션·옛 주인 끝남(stale)
printf '%s\n' "$GONE_PID_LOCK" >|"$EXT_LOCK"
run_ext --lock status
check "stale: status 종료 0" eq "$RC" 0
check "stale: status 출력" eq "$OUT" "stale"
check "stale: status 기록 무변경" eq "$(cat "$EXT_LOCK")" "$GONE_PID_LOCK"
run_ext --lock release
check "stale: release 종료 3" eq "$RC" 3
check "stale: release 기록 무변경" eq "$(cat "$EXT_LOCK")" "$GONE_PID_LOCK"
run_ext --lock claim
check "stale: claim 종료 0(자동 회수와 같음)" eq "$RC" 0
check "stale: claim 이 세션으로 기록" eq "$(cat "$EXT_LOCK")" "$SELF_LOCK_EXPECTED"
printf '%s\n' "$GONE_PID_LOCK" >|"$EXT_LOCK"
run_ext --lock claim --force
check "stale: claim --force 종료 0" eq "$RC" 0
check "stale: claim --force 이 세션으로 기록" eq "$(cat "$EXT_LOCK")" "$SELF_LOCK_EXPECTED"

# 5) 판정 불가(unknown — 옛 1줄 형식)
printf '%s\n' "$OTHER_EXT_SID" >|"$EXT_LOCK"
run_ext --lock status
check "unknown: status 종료 0" eq "$RC" 0
check "unknown: status 출력" eq "$OUT" "unknown"
check "unknown: status 기록 무변경" eq "$(cat "$EXT_LOCK")" "$OTHER_EXT_SID"
run_ext --lock claim
check "unknown: claim 종료 3" eq "$RC" 3
check "unknown: claim 기록 무변경" eq "$(cat "$EXT_LOCK")" "$OTHER_EXT_SID"
run_ext --lock release
check "unknown: release 종료 3" eq "$RC" 3
check "unknown: release 기록 무변경" eq "$(cat "$EXT_LOCK")" "$OTHER_EXT_SID"
run_ext --lock claim --force
check "unknown: claim --force 종료 0" eq "$RC" 0
check "unknown: claim --force 이 세션으로 기록" eq "$(cat "$EXT_LOCK")" "$SELF_LOCK_EXPECTED"

CASE="#16: --status 출력 꼴(마탑 가이드 §3)"
printf '%s\n' "$SELF_LOCK_EXPECTED" >|"$EXT_LOCK"
mkstate "$EXT_IMPL" "$EXT_CRITIC"
run_ext --status
check "외부 --status 종료 코드 0" eq "$RC" 0
check "외부 --status 변경 명령 없음" no_mutations
check "외부 --status 머리말(계기 미기재)" line_matches "^\[CF 팀장→마탑\] 답: 팀 점검·구성\(계기 미기재, "
check "외부 --status 팀장 세션·모드·잠금" has "- 팀장 세션: ${EXT_SID:0:8}, 팀장 모드 외부, 잠금 mine"
check "외부 --status cf-impl 줄" has "- 팀원: cf-impl wN:p3 agy 옵션 일치 ○ 세션 id 기록 × 확인창 없음 상태 idle"
check "외부 --status cf-critic 줄" has "- 팀원: cf-critic wN:p4 codex 옵션 일치 ○ 세션 id 기록 × 확인창 없음 상태 idle"
check "외부 --status 저장소 줄" line_matches "^- 저장소: 브랜치 .+, 작업 트리 (깨끗|바뀐 파일 [0-9]+개)\$"
check "외부 --status 감시 줄" has "- 감시: 스크립트로 알 수 없음(팀장이 적음)"
check "외부 --status 띄운 것·바꾼 것 줄" has "- 띄운 것·바꾼 것: 없음(--status는 바꾸지 않음)"
check "외부 --status 잃은 것 줄" has "- 잃은 것: 미확인(팀장이 적음)"
check "외부 --status 미확인 줄" has "- 미확인: 감시, 잃은 것"
check "외부 --status 꼬리말" line_matches "^이 메시지는 승인이 아니다\.\$"

# blocked 상태 + 계기 인자 + Herdr 안 모드
mkstate "wN:p1|wN|CF 팀장 · Claude|claude|cf-lead|$ROOT|$LEAD_SID" "$IMPL" "$CRITIC"
python3 -c 'import sys,json
st=json.load(open(sys.argv[1]))
for p in st["panes"]:
    if p["pane_id"]=="wN:p3": p["agent_status"]="blocked"
json.dump(st,open(sys.argv[1],"w"),ensure_ascii=False)' "$STATE"
run --status "정기 점검"
check "Herdr 안 --status 종료 코드 0" eq "$RC" 0
check "Herdr 안 --status 계기 반영" line_matches "^\[CF 팀장→마탑\] 답: 팀 점검·구성\(정기 점검, "
check "Herdr 안 --status 팀장 세션·모드" has "- 팀장 세션: ${LEAD_SID:0:8}, 팀장 모드 Herdr 안,"
check "Herdr 안 --status blocked 확인창 있음 표시" has "- 팀원: cf-impl wN:p3 agy 옵션 일치 ○ 세션 id 기록 × 확인창 있음 상태 blocked"

CASE="#16: 외부 모드 팀원 0석에서 --status → 종료 0·보고서 완성·무변경"
printf '%s\n' "$SELF_LOCK_EXPECTED" >|"$EXT_LOCK"
mkstate
run_ext --status "초기 점검"
check "외부 0석 --status 종료 코드 0" eq "$RC" 0
check "외부 0석 --status 변경 명령 없음" no_mutations
check "외부 0석 --status 머리말" line_matches "^\[CF 팀장→마탑\] 답: 팀 점검·구성\(초기 점검, "
check "외부 0석 --status cf-impl 부재 행" has "- 팀원: cf-impl - agy 옵션 일치 ×(판정 불가: 없음) 세션 id 기록 × 확인창 미확인 상태 없음"
check "외부 0석 --status cf-critic 부재 행" has "- 팀원: cf-critic - codex 옵션 일치 ×(판정 불가: 없음) 세션 id 기록 × 확인창 미확인 상태 없음"
check "외부 0석 --status 미확인 줄(작업공간·옵션·확인창 포함)" has "- 미확인: 작업공간, cf-impl 옵션(없음), cf-impl 확인창, cf-critic 옵션(없음), cf-critic 확인창, 감시, 잃은 것"
check "외부 0석 --status 꼬리말" line_matches "^이 메시지는 승인이 아니다\.\$"

CASE="#16: 안전 계약 — 읽기 전용 셋(--check, --status, --lock status)이 저장소·기록·팀원·배치를 아무것도 바꾸지 않음"
(
	cd "$EXT_ROOT" &&
		printf 'unchanged content\n' >tracked.txt &&
		HOME="$TMP" XDG_CONFIG_HOME="$TMP" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git add tracked.txt &&
		HOME="$TMP" XDG_CONFIG_HOME="$TMP" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -c user.name=t -c user.email=t@t commit -q -m tracked &&
		touch -t 202001010000 tracked.txt
)
printf '%s\n' "$GONE_PID_LOCK" >|"$EXT_LOCK"
mkstate "$EXT_LEAD" "$EXT_IMPL" "$EXT_CRITIC"
settree wN:t1 "down(0.7,wN:p1,right(0.35,wN:p3,wN:p4))"
STATE_BEFORE="$(shasum -a 256 "$STATE" | cut -d' ' -f1)"
LOCK_BEFORE="$(shasum -a 256 "$EXT_LOCK" | cut -d' ' -f1)"
INDEX_BEFORE="$(shasum -a 256 "$EXT_ROOT/.git/index" | cut -d' ' -f1)"
REPO_BEFORE="$(cd "$EXT_ROOT" && HOME="$TMP" XDG_CONFIG_HOME="$TMP" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_OPTIONAL_LOCKS=0 git --no-optional-locks status --porcelain)"
for ro_args in "" "--check" "--status" "--lock status"; do
	# shellcheck disable=SC2086
	run_ext $ro_args
	check "안전 계약($ro_args): 종료 코드 0" eq "$RC" 0
	check "안전 계약($ro_args): herdr 변경 호출 0건" no_mutations
	check "안전 계약($ro_args): Herdr 상태(팀원·배치) 불변" eq "$(shasum -a 256 "$STATE" | cut -d' ' -f1)" "$STATE_BEFORE"
	check "안전 계약($ro_args): 외부 팀장 기록 불변" eq "$(shasum -a 256 "$EXT_LOCK" | cut -d' ' -f1)" "$LOCK_BEFORE"
	check "안전 계약($ro_args): 잠금 디렉터리 잔류 없음" test ! -e "$EXT_LOCK.lock"
	check "안전 계약($ro_args): Git 인덱스(.git/index) 바이트 불변" eq "$(shasum -a 256 "$EXT_ROOT/.git/index" | cut -d' ' -f1)" "$INDEX_BEFORE"
	check "안전 계약($ro_args): 저장소 작업 트리 불변" eq \
		"$(cd "$EXT_ROOT" && HOME="$TMP" XDG_CONFIG_HOME="$TMP" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_OPTIONAL_LOCKS=0 git --no-optional-locks status --porcelain)" \
		"$REPO_BEFORE"
done

# shellcheck disable=SC2016
echo "team-up 테스트: 통과 $PASS / 전체 $((PASS + FAIL)) (bash: $("$TEAM_UP_BASH" -c 'echo $BASH_VERSION'))"
[ "$FAIL" = 0 ]

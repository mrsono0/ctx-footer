#!/usr/bin/env bash
# ctx-footer 팀(팀장 1 + 팀원 2) 기동·복구. Herdr pane 안, 이 저장소 안에서만 동작한다.
#   scripts/team-up.sh                      점검만: 세 석의 pane·agent·상태 표 출력(변경 없음)
#                                           종료 코드 0 = 세 석 모두 살아 있음, 1 = 아니거나 오류
#   scripts/team-up.sh --up                 이 pane을 cf-lead로 확보하고 없는 팀원만 띄운다
#   scripts/team-up.sh --resume-impl <id>   구현 GJC를 `gjc --resume <id> --mpreset …`로 복구한다
#   scripts/team-up.sh --layout             팀장 pane에서: 기존 세 석을 배치 기준(팀장 위 0.6, 아래 줄 impl|critic 반반)으로 맞춘다
#   scripts/team-up.sh --hook-clear         SessionStart(clear) 훅 전용: 팀장 pane에 cf-lead 이름을 다시 붙인다
# 다른 pane이 쓰는 이름은 건드리지 않는다. 살아 있는 팀원은 재생성하지 않는다.
# 남은 빈 셸 pane(같은 작업공간·label 일치·agent 없음·저장소 cwd)은 새로 만들지 않고 재사용한다.
set -u

# --- 팀 정의: AGENTS.md 「팀」 표와 일치시킨다 (인덱스 0 = 팀장, 1..2 = 아래 줄 왼쪽부터) ---
# 상주 scout가 필요해지면 4석째 cf-scout(GJC kimi3)를 이 표에 추가한다(docs/04 §1 — 지금은 자리만 비워 둠).
IMPL_PRESET="opus5-codex56-pro"
SEAT_ROLE=(lead impl critic)
SEAT_NAME=(cf-lead cf-impl cf-critic)
SEAT_KIND=(claude gjc codex) # Herdr가 감지하는 agent 종류
SEAT_LABEL=("CF 팀장 · Claude" "CF 구현 · GJC" "CF 검토 · Codex")
SEAT_CMD=(
	"" # 팀장은 사람이 이 pane에서 띄운다. 스크립트는 팀장을 실행하지 않는다.
	"gjc --mpreset $IMPL_PRESET"
	'codex --search --yolo --disable worktrees -m gpt-6.1-sol -c model_reasoning_effort="high"'
)
LEAD_RATIO=0.6                       # 배치 기준: 팀장(위) pane이 차지하는 세로 비율
ROW_RATIO=0.5                        # 배치 기준: 아래 줄 impl(왼쪽) 몫. 비율 허용 오차는 ±0.01
TEMP_TAB_WAIT=2.5                    # 임시 탭 pane 목록 안정 대기 상한(초)
RETRIES="${CF_RETRIES:-30}"         # 감지·보고 지연 대기 횟수
RETRY_SLEEP="${CF_RETRY_SLEEP:-2}"  # 대기 간격(초) → 기본 최대 약 60초

usage() {
	sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}
warn() { echo "team-up: $*" >&2; }
die() { warn "$*"; exit 1; }

mode=check
resume_id=""
hook_sid=""
case "${1:-}" in
"") ;;
--up) mode=up ;;
--layout) mode=layout ;;
--resume-impl)
	mode=resume
	resume_id="${2:-}"
	[ -n "$resume_id" ] || usage
	shift
	;;
--hook-clear)
	mode=hook
	hook_sid="${2:-}" # 비었으면 훅 진입점(stdin), 있으면 백그라운드 작업
	[ -z "$hook_sid" ] || shift
	;;
*) usage ;;
esac
[ "$#" -le 1 ] || usage

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# --- 훅 진입점: stdin JSON의 source가 clear이고 session_id가 있을 때만 백그라운드 작업을 띄운다 ---
# 무엇이든 실패하면 조용히 0. stdout에 쓰지 않는다(SessionStart stdout은 대화 문맥에 들어간다).
if [ "$mode" = hook ] && [ -z "$hook_sid" ]; then
	[ -t 0 ] && exit 0
	command -v python3 >/dev/null || exit 0
	hook_sid="$(python3 -c 'import json,os,select,sys,time
deadline=time.monotonic()+2
raw=bytearray()
try:
    while True:
        remaining=deadline-time.monotonic()
        if remaining<=0 or not select.select([sys.stdin],[],[],remaining)[0]: sys.exit(0)
        chunk=os.read(sys.stdin.fileno(),65536)
        if not chunk: break
        raw.extend(chunk)
    v=json.loads(raw)
    sid=v.get("session_id") if isinstance(v,dict) and v.get("source")=="clear" else None
    if isinstance(sid,str) and sid.strip(): print(sid.strip())
except (OSError, ValueError): pass' 2>/dev/null)"
	[ -n "$hook_sid" ] || exit 0
	nohup "$BASH" "$0" --hook-clear "$hook_sid" </dev/null >/dev/null 2>&1 &
	exit 0
fi

# --- 가드: Herdr pane 안, 이 저장소 안에서만 ---
[ "${HERDR_ENV:-}" = 1 ] && [ -n "${HERDR_PANE_ID:-}" ] || die "Herdr pane 안이 아니다; 아무것도 하지 않음"
under_root() { case "${1%/}/" in "$ROOT"/*) return 0 ;; esac; return 1; }
under_root "$(pwd -P)" || die "현재 디렉터리가 $ROOT 밖이다; 아무것도 하지 않음"
command -v herdr >/dev/null || die "herdr 명령이 없다"
command -v python3 >/dev/null || die "python3 명령이 없다"

jget() {
	python3 -c 'import sys,json
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
for k in sys.argv[1].split("."): d=d.get(k) if isinstance(d,dict) else None
print("" if d is None else d)' "$1"
}

retry() {
	local i=0
	until "$@"; do
		i=$((i + 1))
		[ "$i" -ge "$RETRIES" ] && return 1
		sleep "$RETRY_SLEEP"
	done
}

self_json="$(herdr pane get "$HERDR_PANE_ID" 2>/dev/null)" || die "현재 pane $HERDR_PANE_ID 를 읽지 못했다"
self_cwd="$(printf '%s' "$self_json" | jget result.pane.foreground_cwd)"
[ -n "$self_cwd" ] || self_cwd="$(printf '%s' "$self_json" | jget result.pane.cwd)"
under_root "$self_cwd" || die "pane $HERDR_PANE_ID 의 cwd($self_cwd)가 $ROOT 밖이다; 아무것도 하지 않음"
WS="$(printf '%s' "$self_json" | jget result.pane.workspace_id)"
[ -n "$WS" ] || die "현재 pane의 작업공간을 알 수 없다"

# --- 석 분류 ---
# 상태: alive(이름 확보·agent 실행 중) / unnamed(label·종류 일치 agent가 이름 없이 실행 중)
#       shell(재사용할 빈 셸 pane) / missing(없음) / conflict(다른 pane이 이름 사용 → 건드리지 않음)
# shellcheck disable=SC2016
PY_CLASSIFY='import sys,os,json
root,ws,label,kind=sys.argv[1:5]
def load(s,*path):
    try: d=json.loads(s)
    except Exception: return None
    for k in path: d=d.get(k) if isinstance(d,dict) else None
    return d
panes=load(os.environ.get("PANES_JSON",""),"result","panes") or []
owner=load(os.environ.get("OWNER_JSON",""),"result","agent")
def inroot(p): return ((p.get("foreground_cwd") or p.get("cwd") or "").rstrip("/")+"/").startswith(root+"/")
def out(status,p,note=""):
    p=p or {}
    print("\x1f".join([status,p.get("pane_id") or "","1" if p.get("workspace_id")==ws else "0",
        p.get("agent") or "",p.get("agent_status") or "",p.get("label") or "",note]))
    sys.exit(0)
if owner and owner.get("pane_id"):
    p=dict(owner); p.update(next((x for x in panes if x.get("pane_id")==owner["pane_id"]),{}))
    if not inroot(p): out("conflict",p,"저장소 밖 pane이 이름 사용")
    if p.get("agent") and p.get("agent")!=kind: out("conflict",p,"다른 종류 agent("+p["agent"]+")가 이름 사용")
    if p.get("agent"): out("alive",p)
    if p.get("workspace_id")==ws: out("shell",p)
    out("conflict",p,"다른 작업공간 pane이 이름 사용")
cand=[p for p in panes if p.get("workspace_id")==ws and p.get("label")==label and inroot(p)]
for p in cand:
    if p.get("agent")==kind: out("unnamed",p)
for p in cand:
    if not p.get("agent"): out("shell",p)
out("missing",None)'

S_STATUS=()
S_PANE=()
S_INWS=()
S_AGENT=()
S_ASTATUS=()
S_LABEL=()
S_NOTE=()
PANES_JSON=""

classify_all() {
	local i owner_json out
	PANES_JSON="$(herdr pane list 2>/dev/null)" || die "herdr pane list 실패"
	for i in 0 1 2; do
		owner_json="$(herdr agent get "${SEAT_NAME[$i]}" 2>/dev/null)" || owner_json=""
		out="$(PANES_JSON="$PANES_JSON" OWNER_JSON="$owner_json" python3 -c "$PY_CLASSIFY" \
			"$ROOT" "$WS" "${SEAT_LABEL[$i]}" "${SEAT_KIND[$i]}")" || die "상태 분류 실패: ${SEAT_NAME[$i]}"
		IFS=$'\x1f' read -r "S_STATUS[i]" "S_PANE[i]" "S_INWS[i]" "S_AGENT[i]" "S_ASTATUS[i]" "S_LABEL[i]" "S_NOTE[i]" <<<"$out"
	done
}

action_of() { # idx
	local i=$1
	if [ "$i" = 0 ]; then
		case "${S_STATUS[0]}" in
		alive) [ "${S_PANE[0]}" = "$HERDR_PANE_ID" ] && echo "유지" || echo "--up 거부(다른 pane 소유)" ;;
		conflict) echo "--up 거부(충돌)" ;;
		*) echo "이 pane($HERDR_PANE_ID) 확보" ;;
		esac
		return
	fi
	case "${S_STATUS[$i]}" in
	alive) echo "유지" ;;
	unnamed) echo "이름 부여" ;;
	shell) echo "빈 셸 재사용" ;;
	missing) echo "생성" ;;
	conflict) echo "건너뜀(충돌)" ;;
	esac
}

print_table() {
	local i st
	echo "team-up 점검 — 저장소 $ROOT · 작업공간 $WS · 현재 pane $HERDR_PANE_ID"
	printf '%-7s %-11s %-7s %-7s %-17s %-20s %s\n' 석 이름 pane agent 상태 label "--up 조치"
	for i in 0 1 2; do
		st="${S_STATUS[$i]}"
		[ -n "${S_ASTATUS[$i]}" ] && st="$st(${S_ASTATUS[$i]})"
		printf '%-7s %-11s %-7s %-7s %-17s %-20s %s\n' "${SEAT_ROLE[$i]}" "${SEAT_NAME[$i]}" \
			"${S_PANE[$i]:--}" "${S_AGENT[$i]:--}" "$st" "${S_LABEL[$i]:--}" "$(action_of "$i")"
		[ -z "${S_NOTE[$i]}" ] || echo "        ↳ ${S_NOTE[$i]}"
	done
}

all_alive() {
	local i
	[ "${S_STATUS[0]}" = alive ] || return 1
	for i in 1 2; do [ "${S_STATUS[$i]}" = alive ] || return 1; done
}

# 이름이 비었거나 이 pane 소유일 때만 rename (다른 pane이 쓰면 2를 돌려주고 건드리지 않음)
claim_name() { # pane name
	local owner
	owner="$(herdr agent get "$2" 2>/dev/null | jget result.agent.pane_id)"
	if [ -z "$owner" ]; then
		herdr agent rename "$1" "$2" >/dev/null 2>&1
	elif [ "$owner" = "$1" ]; then
		return 0
	else
		return 2
	fi
}

retry_claim() { # pane name — 다른 pane 소유(2)면 즉시 중단
	local i=0 rc
	while :; do
		claim_name "$1" "$2"
		rc=$?
		[ "$rc" = 0 ] && return 0
		[ "$rc" = 2 ] && return 2
		i=$((i + 1))
		[ "$i" -ge "$RETRIES" ] && return 1
		sleep "$RETRY_SLEEP"
	done
}

pane_field() { herdr pane get "$1" 2>/dev/null | jget "result.pane.$2"; }
pane_has_agent() { [ "$(pane_field "$1" agent)" = "$2" ]; }

ensure_label() { # pane label
	[ "$(pane_field "$1" label)" = "$2" ] || herdr pane rename "$1" "$2" >/dev/null 2>&1
}

# 사이드바는 GJC 세션 이름을 보인다. GJC가 idle이고 세션 id token이 발행된 뒤에만 /rename을 입력한다.
gjc_ready() {
	herdr pane get "$1" 2>/dev/null | python3 -c 'import sys,json
p=json.load(sys.stdin)["result"]["pane"]
sys.exit(0 if p.get("agent_status")=="idle" and (p.get("tokens") or {}).get("gjc_herdr_session_id") else 1)' 2>/dev/null
}
gjc_named() { [ "$(pane_field "$1" tokens.gjc_herdr_session)" = "$2" ]; }
gjc_rename_session() { # pane label
	if ! retry gjc_ready "$1"; then
		warn "$1: GJC가 입력 준비되지 않음; GJC 입력창에서 /rename $2 를 직접 입력"
		return 1
	fi
	gjc_named "$1" "$2" && return 0
	herdr pane send-text "$1" "/rename $2" >/dev/null 2>&1
	herdr pane send-keys "$1" enter >/dev/null 2>&1
	if retry gjc_named "$1" "$2"; then
		echo "$1: GJC 세션 이름 '$2'"
	else
		warn "$1: /rename을 입력했지만 세션 이름 token이 바뀌지 않음; GJC 입력창 확인 필요"
		return 1
	fi
}

split_pane() { # target direction ratio → NEW_PANE
	NEW_PANE="$(herdr pane split "$1" --direction "$2" --ratio "$3" --cwd "$ROOT" --no-focus 2>/dev/null |
		jget result.pane.pane_id)"
	[ -n "$NEW_PANE" ] || { warn "pane split 실패($1 $2)"; return 1; }
}

usable_anchor() { # idx — 이 작업공간에 pane이 있는 석
	case "${S_STATUS[$1]}" in alive | unnamed | shell | spawned) [ "${S_INWS[$1]}" = 1 ] ;; *) return 1 ;; esac
}

# 배치 이동 단계 실패(기동 실패와 별도). 이동 단계의 비0은 마지막 배치·비율 보정이 모양을 고쳐도 그대로 둔다.
layout_status=0

# 없는 석의 pane을 아래 줄 순서(impl | critic)에 맞춰 만든다 → NEW_PANE
place_new() { # idx
	local i=$1 j k run ratio
	for ((j = i - 1; j >= 1; j--)); do
		if usable_anchor "$j"; then
			# 왼쪽 이웃 영역을 그 이웃 + 뒤이어 생성될 석들이 같은 폭으로 나눠 갖도록 첫 pane 비율을 정한다
			run=0
			for ((k = i; k <= 2; k++)); do
				[ "${S_STATUS[$k]}" = missing ] || break
				run=$((run + 1))
			done
			ratio="$(awk -v n="$run" 'BEGIN { printf "%.3f", 1 / (1 + n) }')"
			split_pane "${S_PANE[$j]}" right "$ratio"
			return
		fi
	done
	for ((j = i + 1; j <= 2; j++)); do
		if usable_anchor "$j"; then
			# 오른쪽 이웃만 있으면 그 오른쪽에 만든 뒤 자리를 맞바꿔 왼쪽에 둔다
			split_pane "${S_PANE[$j]}" right 0.5 || return 1
			herdr pane swap --source-pane "$NEW_PANE" --target-pane "${S_PANE[$j]}" >/dev/null 2>&1 || {
				layout_status=1
				warn "pane swap 실패($NEW_PANE ↔ ${S_PANE[$j]}); 순서가 어긋남"
			}
			return 0
		fi
	done
	split_pane "$HERDR_PANE_ID" down "$LEAD_RATIO"
}

# 팀원 한 석을 맞춘다. 살아 있으면 손대지 않고, 충돌이면 건너뛴다.
ensure_member() { # idx command
	local i=$1 cmd=$2 name="${SEAT_NAME[$1]}" label="${SEAT_LABEL[$1]}" kind="${SEAT_KIND[$1]}" pane rc
	case "${S_STATUS[$i]}" in
	alive)
		echo "$name: 살아 있음(${S_PANE[$i]}); 그대로 둠"
		return 0
		;;
	conflict)
		warn "$name: ${S_NOTE[$i]} (${S_PANE[$i]}); 건너뜀"
		return 1
		;;
	unnamed)
		pane="${S_PANE[$i]}"
		retry_claim "$pane" "$name" || { warn "$name: $pane 에 이름을 확보하지 못함"; return 1; }
		ensure_label "$pane" "$label"
		echo "$name: 실행 중인 $pane 에 이름 부여"
		[ "$kind" = gjc ] && gjc_rename_session "$pane" "$label"
		return 0
		;;
	shell)
		pane="${S_PANE[$i]}"
		echo "$name: 빈 셸 $pane 재사용"
		;;
	missing)
		place_new "$i" || return 1
		pane="$NEW_PANE"
		S_PANE[i]="$pane"
		S_INWS[i]=1
		echo "$name: 새 pane $pane"
		;;
	esac
	S_STATUS[i]=spawned
	ensure_label "$pane" "$label"
	herdr pane run "$pane" "cd $(printf '%q' "$ROOT") && $cmd" >/dev/null 2>&1 ||
		{ warn "$name: $pane 에서 실행 실패"; return 1; }
	retry pane_has_agent "$pane" "$kind" || { warn "$name: $pane 에서 $kind 가 감지되지 않음"; return 1; }
	retry_claim "$pane" "$name"
	rc=$?
	[ "$rc" = 0 ] || { warn "$name: $pane 에 이름을 확보하지 못함(rc=$rc)"; return 1; }
	echo "$name: $pane 에서 실행 · 이름 확보"
	[ "$kind" = gjc ] && gjc_rename_session "$pane" "$label"
	return 0
}

secure_lead() {
	case "${S_STATUS[0]}" in
	alive | conflict | shell)
		[ "${S_PANE[0]}" = "$HERDR_PANE_ID" ] ||
			die "cf-lead 이름을 ${S_PANE[0]} 가 쓰고 있다; 아무것도 바꾸지 않음"
		;;
	esac
	retry_claim "$HERDR_PANE_ID" "${SEAT_NAME[0]}" || die "이 pane을 cf-lead로 확보하지 못함"
	ensure_label "$HERDR_PANE_ID" "${SEAT_LABEL[0]}"
	S_STATUS[0]=alive
	S_PANE[0]="$HERDR_PANE_ID"
	S_INWS[0]=1 # 이 pane 자신 — 작업공간 안. 배치 확인 가드가 남아 있음(secure_lead 뒤 누락 방지)
}

# /clear 뒤 백그라운드 작업: 팀장 label pane에서, Herdr가 새 세션 id를 볼 때까지 기다렸다가 이름을 다시 붙인다.
# 옛 세션을 보고 있을 때 rename하면 뒤이어 지워질 수 있어서 기다린다. 다른 pane이 cf-lead를 쓰면 건드리지 않는다.
lead_session_is() { # session_id
	pane_has_agent "$HERDR_PANE_ID" "${SEAT_KIND[0]}" &&
		[ "$(pane_field "$HERDR_PANE_ID" agent_session.value)" = "$1" ]
}
hook_clear() {
	[ "$(printf '%s' "$self_json" | jget result.pane.label)" = "${SEAT_LABEL[0]}" ] ||
		die "현재 pane label이 '${SEAT_LABEL[0]}'이 아니다; 아무것도 하지 않음"
	retry lead_session_is "$hook_sid" || die "Herdr가 세션 $hook_sid 를 보지 못함; 아무것도 하지 않음"
	retry_claim "$HERDR_PANE_ID" "${SEAT_NAME[0]}" || die "이 pane을 cf-lead로 확보하지 못함"
	ensure_label "$HERDR_PANE_ID" "${SEAT_LABEL[0]}"
}

# 같은 GJC 세션 id(접두어 포함)가 어느 pane에든 살아 있으면 그 pane id를 출력
# shellcheck disable=SC2016
session_alive_in() { # id
	PANES_JSON="$PANES_JSON" python3 -c 'import sys,os,json
sid=sys.argv[1]
try: panes=json.loads(os.environ["PANES_JSON"])["result"]["panes"]
except Exception: sys.exit(0)
for p in panes:
    if not p.get("agent"): continue
    ids=[(p.get("tokens") or {}).get("gjc_herdr_session_id"),(p.get("agent_session") or {}).get("value")]
    if any(x and (x.startswith(sid) or sid.startswith(x)) for x in ids):
        print(p["pane_id"]); break' "$1"
}

# --- 배치: 기준은 팀장 위(LEAD_RATIO), 아래 줄 왼쪽부터 impl|critic(ROW_RATIO), 비율 허용 오차 ±0.01 ---
# 같은 탭 안 pane move는 same_tab으로 무시되므로 임시 탭을 거친다. pane swap은 focus를 옮기므로 재배치에 쓰지 않고,
# 모든 move는 --no-focus. 세 석 밖의 pane(Sidebar 등)은 옮기거나 크기를 바꾸거나 닫지 않는다.

# 팀장 탭의 배치 상태 → "상태 critic포함 아래비율 줄비율 탭" (layout을 읽지 못하면 빈 값)
#   상태: ok(기준 모양) / move(모양이 다름, 옮겨도 됨) / mixed(모양이 다르고 세 석 밖 pane이 섞여 있음)
#         / away(impl이 팀장 탭에 없음)
#   move 조건: 세 석이 한 분할 영역을 빈틈없이 채운다(그 영역 안에 다른 pane 없음). 그래야 석을 빼고 되돌려도
#   영역 밖 pane(Sidebar 등)의 자리·크기가 바뀌지 않는다. 아니면 mixed — 옮기지 않는다.
#   critic포함: critic pane이 팀장 탭에 있으면 1(그때만 critic까지 본다), 아니면 0 — 팀장·impl만 맞춘다
# shellcheck disable=SC2016
layout_state() { # lead impl [critic]
	herdr pane layout --pane "$1" 2>/dev/null | python3 -c 'import sys,json
lead,impl,critic=sys.argv[1:4]
try:
    l=json.load(sys.stdin)["result"]["layout"]
    r={p["pane_id"]:p["rect"] for p in l["panes"]}
    splits=l.get("splits") or []
    tab=l.get("tab_id") or "-"
except Exception: sys.exit(0)
def box(q): return (q["x"],q["y"],q["width"],q["height"])
def ratio(d,b):
    for s in splits:
        if s.get("direction")==d and box(s["rect"])==b: return s["ratio"]
if lead not in r: sys.exit(0)
if impl not in r: print("away 0 - - "+tab); sys.exit(0)
crit=1 if critic and critic in r else 0
L,M=box(r[lead]),box(r[impl])
C=box(r[critic]) if crit else None
ok=M[0]==L[0] and M[1]==L[1]+L[3]
if ok and C: ok=C[0]==M[0]+M[2] and C[1]==M[1] and C[3]==M[3] and M[2]+C[2]==L[2]
elif ok: ok=M[2]==L[2]
down=ratio("down",(L[0],L[1],L[2],L[3]+M[3])) if ok else None
right=ratio("right",(M[0],M[1],M[2]+C[2],M[3])) if ok and C else None
if down is None or (C and right is None):
    seats=[b for b in (L,M,C) if b]
    x0,y0=min(b[0] for b in seats),min(b[1] for b in seats)
    x1,y1=max(b[0]+b[2] for b in seats),max(b[1]+b[3] for b in seats)
    tiled=sum(b[2]*b[3] for b in seats)==(x1-x0)*(y1-y0) and any(box(s["rect"])==(x0,y0,x1-x0,y1-y0) for s in splits)
    print("%s %d - - %s" % ("move" if tiled else "mixed",crit,tab))
else: print("ok %d %s %s %s" % (crit,down,right if C else "-",tab))' "$1" "$2" "${3:-}"
}

ratios_ok() { # 아래비율 줄비율("-"이면 보지 않음)
	python3 -c 'import sys
d,r,lr,rr=sys.argv[1:5]
ok=lambda a,b: abs(float(a)-float(b))<=0.01+1e-9
sys.exit(0 if ok(d,lr) and (r=="-" or ok(r,rr)) else 1)' "$1" "$2" "$LEAD_RATIO" "$ROW_RATIO"
}

# split 비율을 target으로. 늘릴 때는 첫 pane을 경계 쪽으로, 줄일 때는 둘째 pane을 경계 쪽으로 resize(amount = 비율 차).
# 반환: 0 손댈 것 없음, 1 resize 실패, 3 resize함
set_ratio() { # current target first grow_dir second shrink_dir
	local d
	d="$(python3 -c 'import sys; d=float(sys.argv[2])-float(sys.argv[1]); print("" if abs(d)<0.005 else "%+.4f" % d)' "$1" "$2")" ||
		return 1
	case "$d" in
	"") return 0 ;;
	+*) herdr pane resize --pane "$3" --direction "$4" --amount "${d#+}" >/dev/null 2>&1 || return 1 ;;
	*) herdr pane resize --pane "$5" --direction "$6" --amount "${d#-}" >/dev/null 2>&1 || return 1 ;;
	esac
	return 3
}

# 기준 모양에서 비율만 맞추고, resize했으면 다시 읽어 확인한다. 상태는 layout_state 출력(호출자가 읽은 것).
# 반환: 0 기준 확인, 1 resize 실패·미도달, 2 기준 모양이 아님(layout 읽기 실패 포함)
fit_ratios() { # lead impl critic 상태...
	local lead=$1 impl=$2 critic=$3 fail=0 touched=0 rc
	shift 3
	[ "${1:-}" = ok ] || return 2
	set_ratio "$3" "$LEAD_RATIO" "$lead" down "$impl" up
	rc=$?
	case $rc in 1) fail=1 ;; 3) touched=1 ;; esac
	if [ "$2" = 1 ]; then
		set_ratio "$4" "$ROW_RATIO" "$impl" right "$critic" left
		rc=$?
		case $rc in 1) fail=1 ;; 3) touched=1 ;; esac
	fi
	if [ "$touched" = 1 ]; then
		# shellcheck disable=SC2046
		set -- $(layout_state "$lead" "$impl" "$critic")
		[ "${1:-}" = ok ] || { warn "resize 중 배치가 바뀌어 기준 모양이 아님"; return 1; }
	fi
	ratios_ok "$3" "$4" || fail=1
	[ "$fail" = 0 ] || warn "비율 미도달 또는 resize 실패: 팀장/아래 $3$([ "$4" = - ] || echo ", impl/critic $4") (기준 $LEAD_RATIO$([ "$4" = - ] || echo "/$ROW_RATIO") ±0.01)"
	return "$fail"
}

# 스크립트가 만든 임시 탭은 남은 pane이 모두 agent 없는 pane(사용자 설정이 자동으로 만든 Sidebar 등)일 때만 닫는다.
close_temp_tab() { # tab
	local left
	left="$(herdr pane list 2>/dev/null | python3 -c 'import sys,json
try: panes=json.load(sys.stdin)["result"]["panes"]
except Exception: print("unknown"); sys.exit(0)
ps=[p for p in panes if p.get("tab_id")==sys.argv[1]]
print("agent" if any(p.get("agent") for p in ps) else "ok" if ps else "gone")' "$1")"
	case "$left" in
	ok) herdr tab close "$1" >/dev/null 2>&1 || warn "임시 탭 $1 을 닫지 못함; herdr tab close $1" ;;
	gone) ;;
	*) warn "임시 탭 $1 을 닫지 않고 둠(agent pane이 있거나 목록을 읽지 못함)" ;;
	esac
}

# 새 탭에는 사용자 설정이 agent 없는 Sidebar pane을 비동기로 만들 수 있다.
# 즉시 되돌리면 원래 탭에 Sidebar가 끼어드는 경쟁이 생길 수 있으므로, 임시 탭의 pane 수가 늘어
# 0.3초 동안 변하지 않을 때까지(또는 상한까지) 기다린다. 상한 안에 늘지 않으면(Sidebar 없음) 그대로 진행한다.
# 반환: 0 안정됨 또는 정상 목록으로 상한 만료, 1 목록 조회 실패(시간 초과 포함) 또는 상한 안에 정상 목록을 한 번도 못 받음
wait_temp_tab() { # tab
	python3 -c 'import json,subprocess,sys,time
tab,cap=sys.argv[1],float(sys.argv[2])
end=time.monotonic()+cap; last=None; changed=0.0
while True:
    left=end-time.monotonic()
    if left<=0: break
    if last is not None and left<0.15:
        time.sleep(left)
        break
    try: r=subprocess.run(["herdr","pane","list"],capture_output=True,text=True,timeout=left)
    except Exception: sys.exit(1)
    if r.returncode!=0: sys.exit(1)
    try:
        panes=json.loads(r.stdout)["result"]["panes"]
        if not isinstance(panes,list): sys.exit(1)
        n=sum(1 for p in panes if p.get("tab_id")==tab)
    except Exception: sys.exit(1)
    now=time.monotonic()
    if n<1: last=None
    elif n!=last: last,changed=n,now
    if n>=2 and now-changed>=0.3: sys.exit(0)
    left=end-now
    if left<=0: break
    time.sleep(min(0.1,left))
sys.exit(0 if last is not None else 1)' "$1" "$TEMP_TAB_WAIT"
}

# pane을 임시 탭으로 뺐다가, 임시 탭 pane 목록이 안정될 때까지 기다린 뒤 tab의 target 옆으로 되돌린다.
move_via_temp_tab() { # pane tab target split ratio
	local tmp wait_ok=1
	tmp="$(herdr pane move "$1" --new-tab --no-focus 2>/dev/null | jget result.move_result.created_tab.tab_id)"
	[ -n "$tmp" ] || { warn "$1 을 임시 탭으로 옮긴 것을 확인하지 못함; herdr tab list 확인"; return 1; }
	# 대기 중 목록 조회가 실패해도 pane은 원래 탭으로 되돌리되, 실패(비0)는 유지한다.
	wait_temp_tab "$tmp" || {
		wait_ok=0
		warn "임시 탭 $tmp 의 pane 목록 안정 대기 실패; $1 은 $2 로 되돌림"
	}
	if [ "$(herdr pane move "$1" --tab "$2" --target-pane "$3" --split "$4" --ratio "$5" --no-focus 2>/dev/null |
		jget result.move_result.changed)" != True ]; then
		warn "$1 을 임시 탭 $tmp 에서 $2 로 되돌리지 못함; 직접 옮긴다(herdr pane move $1 --tab $2 --target-pane $3 --split $4)"
		return 1
	fi
	close_temp_tab "$tmp"
	[ "$wait_ok" = 1 ]
}

# 배치 대상 pane → L_IMPL, L_CRITIC(이 작업공간에 pane이 있는 석만, 없으면 빈 값)
layout_seats() {
	L_IMPL=""
	L_CRITIC=""
	usable_anchor 1 && L_IMPL="${S_PANE[1]}"
	usable_anchor 2 && L_CRITIC="${S_PANE[2]}"
	[ -n "${S_PANE[0]}" ] && [ "${S_INWS[0]}" = 1 ] && [ -n "$L_IMPL" ]
}

# 팀장(이 pane)·impl이 같은 탭이면 기준으로 맞춘다. critic은 같은 탭일 때만 함께 맞춘다.
# 반환: 0 맞춤, 1 실패(안내 출력), 4 해당 없음(impl이 다른 탭 — 옮기지 않음)
apply_layout() {
	local lead=$HERDR_PANE_ID impl=$L_IMPL critic=$L_CRITIC tab state
	state="$(layout_state "$lead" "$impl" "$critic")"
	# shellcheck disable=SC2086
	set -- $state
	case "${1:-}" in
	"")
		warn "배치: 팀장 탭 layout을 읽지 못함; 아무것도 옮기지 않음"
		return 1
		;;
	away)
		warn "배치: cf-impl($impl)이 팀장($lead)과 다른 탭에 있어 옮기지 않음; 같은 탭으로 옮긴 뒤 scripts/team-up.sh --layout"
		return 4
		;;
	mixed)
		warn "배치: 팀 석 사이에 다른 pane이 섞여 있어 옮기지 않음(옮기면 그 pane 크기가 바뀜); 직접 정리한 뒤 scripts/team-up.sh --layout"
		return 1
		;;
	move)
		tab=$5
		move_via_temp_tab "$impl" "$tab" "$lead" down "$LEAD_RATIO" || layout_status=1
		if [ "$2" = 1 ] && [ "$(pane_field "$impl" tab_id)" = "$tab" ]; then
			move_via_temp_tab "$critic" "$tab" "$impl" right "$ROW_RATIO" || layout_status=1
		fi
		state="$(layout_state "$lead" "$impl" "$critic")"
		;;
	esac
	[ "$2" = 1 ] || critic=""
	[ -n "$critic" ] || [ -z "$L_CRITIC" ] || warn "배치: cf-critic($L_CRITIC)이 다른 탭에 있어 팀장·impl만 맞춤"
	# shellcheck disable=SC2086
	fit_ratios "$lead" "$impl" "$critic" $state
	case $? in
	0)
		if [ "$layout_status" != 0 ]; then
			warn "배치: 이동 단계에서 오류가 있었음; herdr pane layout 확인 뒤 scripts/team-up.sh --layout"
			return 1
		fi
		echo "배치: 팀장 $lead 위($LEAD_RATIO), 아래 impl $impl${critic:+ | critic $critic($ROW_RATIO)}"
		return 0
		;;
	2) warn "배치: 기준 모양이 되지 않음; herdr pane layout 확인 뒤 scripts/team-up.sh --layout" ;;
	*) warn "배치: 자리는 맞지만 비율이 기준이 아님; herdr pane layout 확인 뒤 scripts/team-up.sh --layout" ;;
	esac
	return 1
}

# --up·--resume-impl 끝: 배치 실패는 기동 결과를 되돌리지 않고 종료 코드만 비0으로 만든다.
finish_layout() {
	local rc
	layout_seats || return "$layout_status"
	apply_layout
	rc=$?
	[ "$rc" != 1 ] && [ "$layout_status" = 0 ]
}

# 점검(읽기 전용): 기준과 다르면 경고만 낸다. 종료 코드에 영향 없음.
check_layout() {
	local lead="${S_PANE[0]}" fix="고치려면 팀장 pane에서 scripts/team-up.sh --layout"
	layout_seats || return 0
	# shellcheck disable=SC2046
	set -- $(layout_state "$lead" "$L_IMPL" "$L_CRITIC")
	case "${1:-}" in
	ok)
		[ "$2" = 1 ] || [ -z "$L_CRITIC" ] || warn "배치: cf-critic($L_CRITIC)이 팀장과 다른 탭에 있음"
		ratios_ok "$3" "$4" && return 0
		warn "배치 비율이 기준과 다름: 팀장/아래 $3$([ "$4" = - ] || echo ", impl/critic $4") (기준 $LEAD_RATIO$([ "$4" = - ] || echo "/$ROW_RATIO") ±0.01)"
		;;
	move) warn "배치가 기준(팀장 위, 아래 줄 왼쪽부터 impl|critic)과 다름" ;;
	mixed)
		fix="다른 pane을 팀 석 영역 밖으로 직접 옮긴 뒤 scripts/team-up.sh --layout"
		warn "배치가 기준과 다르고 팀 석 사이에 다른 pane이 섞여 있음"
		;;
	away) fix="cf-impl을 팀장 탭으로 옮긴 뒤 scripts/team-up.sh --layout"; warn "배치: cf-impl($L_IMPL)이 팀장과 다른 탭에 있음" ;;
	*) return 0 ;;
	esac
	warn "$fix"
	return 0
}

if [ "$mode" = hook ]; then
	hook_clear
	exit
fi

classify_all

case "$mode" in
check)
	print_table
	check_layout
	all_alive
	exit
	;;
up)
	secure_lead
	fail=0
	for i in 1 2; do ensure_member "$i" "${SEAT_CMD[$i]}" || fail=1; done
	finish_layout || fail=1
	exit "$fail"
	;;
layout)
	[ "${S_STATUS[0]}" = alive ] && [ "${S_PANE[0]}" = "$HERDR_PANE_ID" ] ||
		die "--layout: cf-lead가 이 pane($HERDR_PANE_ID)이 아니다; 아무것도 옮기지 않음"
	layout_seats || die "--layout: 이 작업공간에 cf-impl pane이 없다; 아무것도 옮기지 않음(scripts/team-up.sh --up)"
	apply_layout || exit 1
	exit 0
	;;
resume)
	case "$resume_id" in *[!0-9A-Fa-f-]*) die "세션 id 형식이 아니다: $resume_id" ;; esac
	[ "${#resume_id}" -ge 8 ] || die "세션 id가 너무 짧다(8자 이상): $resume_id"
	other="$(session_alive_in "$resume_id")"
	[ -z "$other" ] || die "세션 $resume_id 가 이미 $other 에 살아 있다; 복구하지 않음"
	case "${S_STATUS[1]}" in
	alive | unnamed) die "구현 GJC가 이미 ${S_PANE[1]} 에 살아 있다; 복구하지 않음" ;;
	conflict) die "cf-impl: ${S_NOTE[1]} (${S_PANE[1]}); 복구하지 않음" ;;
	esac
	secure_lead
	fail=0
	ensure_member 1 "gjc --resume $resume_id --mpreset $IMPL_PRESET" || fail=1
	finish_layout || fail=1
	exit "$fail"
	;;
esac

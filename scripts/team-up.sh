#!/usr/bin/env bash
# ctx-footer 팀(팀장 1 + 팀원 2) 기동·복구. Herdr pane 안, 이 저장소 안에서만 동작한다.
#   scripts/team-up.sh                      점검만: 세 석의 pane·agent·상태 표 출력(변경 없음)
#                                           종료 코드 0 = 세 석 모두 살아 있음, 1 = 아니거나 오류
#   scripts/team-up.sh --up                 이 pane을 cf-lead로 확보하고 없는 팀원만 띄운다
#   scripts/team-up.sh --resume-impl <id>   구현 GJC를 `gjc --resume <id> --mpreset …`로 복구한다
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
	'codex --search --yolo -m gpt-6.1-sol -c model_reasoning_effort="high"'
)
LEAD_RATIO=0.62                      # 팀장(위) pane이 차지하는 세로 비율
RETRIES="${CF_RETRIES:-30}"         # 감지·보고 지연 대기 횟수
RETRY_SLEEP="${CF_RETRY_SLEEP:-2}"  # 대기 간격(초) → 기본 최대 약 60초

usage() {
	sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}
warn() { echo "team-up: $*" >&2; }
die() { warn "$*"; exit 1; }

mode=check
resume_id=""
case "${1:-}" in
"") ;;
--up) mode=up ;;
--resume-impl)
	mode=resume
	resume_id="${2:-}"
	[ -n "$resume_id" ] || usage
	shift
	;;
*) usage ;;
esac
[ "$#" -le 1 ] || usage

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

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
			herdr pane swap --source-pane "$NEW_PANE" --target-pane "${S_PANE[$j]}" >/dev/null 2>&1 ||
				warn "pane swap 실패($NEW_PANE ↔ ${S_PANE[$j]}); 순서가 어긋남"
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

# --- 배치 확인(점검·--up 끝, 읽기 전용): 팀원 석이 팀장 아래 같은 줄, 왼쪽부터 impl|critic ---
# 어긋나도 경고만 낸다(자동 재배치 없음). 팀장·팀원 석 pane을 모르거나 다른 작업공간에 있으면 건너뛴다.
check_layout() {
	local lead="${S_PANE[0]}" i detail
	[ -n "$lead" ] && [ "${S_INWS[0]}" = 1 ] || return 0
	for i in 1 2; do
		[ -n "${S_PANE[$i]}" ] && [ "${S_INWS[$i]}" = 1 ] || return 0
	done
	detail="$(herdr pane layout --pane "$lead" 2>/dev/null | python3 -c '
import sys, json
try:
    panes = json.load(sys.stdin)["result"]["layout"]["panes"]
except Exception:
    sys.exit(0)
r = {p.get("pane_id"): p.get("rect") or {} for p in panes}
lead, impl, critic = sys.argv[1:4]
if not all(r.get(x) for x in (lead, impl, critic)):
    sys.exit(0)
ys = [r[x]["y"] for x in (impl, critic)]
xs = [r[x]["x"] for x in (impl, critic)]
if len(set(ys)) != 1:
    print("팀원 줄 y 불일치: " + ", ".join("%s y=%s" % (n, y) for n, y in zip(("impl", "critic"), ys)))
elif not xs[0] < xs[1]:
    print("좌우 순서가 impl|critic 아님: x=" + ",".join(str(x) for x in xs))
elif ys[0] < r[lead]["y"] + r[lead].get("height", 0):
    print("팀원 줄이 팀장 하단(y=%s) 아래가 아님: y=%s" % (r[lead]["y"] + r[lead].get("height", 0), ys[0]))
' "$lead" "${S_PANE[1]}" "${S_PANE[2]}")" || true
	[ -z "$detail" ] && return 0
	warn "배치가 기준(팀장 아래 한 줄, 왼쪽부터 impl|critic)과 다름: $detail"
	warn "고치는 순서: herdr pane move <pane> --new-tab → herdr pane move <pane> --tab <tab> --split right --target-pane <왼쪽 이웃> → 필요 시 herdr pane swap · 남은 빈 탭은 herdr tab close"
	return 0
}

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
	check_layout
	exit "$fail"
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
	ensure_member 1 "gjc --resume $resume_id --mpreset $IMPL_PRESET"
	exit
	;;
esac

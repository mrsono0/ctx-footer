#!/usr/bin/env bash
# ctx-footer Herdr Core(hc) 외부 팀장 전용 팀원 점검·기동·정리 스크립트.
#   CF_EXTERNAL_LEAD=1 scripts/team-core.sh                    점검(기본, --check와 같음)
#   CF_EXTERNAL_LEAD=1 scripts/team-core.sh --check            점검(읽기 전용)
#   CF_EXTERNAL_LEAD=1 scripts/team-core.sh --up [<대화 id>]   빠진 팀원 기동(살아 있는 석 불변)
#   CF_EXTERNAL_LEAD=1 scripts/team-core.sh --status [<계기>]  마탑 가이드 §3 보고 꼴 출력
#   CF_EXTERNAL_LEAD=1 scripts/team-core.sh --down <이름>      팀원(idle·done) 종료 및 정리
set -u

HC_BIN="${HC_BIN:-hc}"
IMPL_MODEL="gemini-4-argon-high"

SEAT_ROLE=(lead impl critic)
SEAT_NAME=(cf-lead cf-impl cf-critic)
SEAT_KIND=(claude agy codex)
SEAT_CMD=(
	""
	"agy --model $IMPL_MODEL --mode accept-edits --sandbox"
	'codex --search --yolo --disable worktrees --disable memories -m gpt-6.1-sol -c model_reasoning_effort="high"'
)

die() { echo "team-core: $*" >&2; exit 1; }
warn() { echo "team-core: $*" >&2; }
usage() {
	cat >&2 <<'EOF'
사용법: CF_EXTERNAL_LEAD=1 scripts/team-core.sh [--check | --up [<agy 대화 id>] | --status [<계기>] | --down <cf-impl|cf-critic>]
EOF
	exit 2
}

mode=check
resume_id=""
status_trigger="점검"
down_target=""

case "${1:-}" in
"" | --check)
	[ "$#" -le 1 ] || usage
	mode=check
	;;
--up)
	mode=up
	if [ "$#" -eq 2 ]; then
		resume_id="${2:-}"
		[ -n "$resume_id" ] || usage
	elif [ "$#" -gt 2 ]; then
		usage
	fi
	;;
--status)
	mode=status
	if [ "$#" -eq 2 ]; then
		status_trigger="${2:-}"
		[ -n "$status_trigger" ] || usage
		case "$status_trigger" in -*) usage ;; esac
	elif [ "$#" -gt 2 ]; then
		usage
	fi
	;;
--down)
	mode=down
	[ "$#" -eq 2 ] || usage
	down_target="${2:-}"
	case "$down_target" in
	cf-impl | cf-critic) ;;
	*)
		warn "--down 대상은 cf-impl 또는 cf-critic만 허용된다: $down_target"
		usage
		;;
	esac
	;;
-h | --help)
	cat <<'EOF'
사용법: CF_EXTERNAL_LEAD=1 scripts/team-core.sh [--check | --up [<agy 대화 id>] | --status [<계기>] | --down <cf-impl|cf-critic>]
EOF
	exit 0
	;;
*)
	usage
	;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
EXT_LEAD_FILE="$ROOT/.local/team/external-lead"

# --- 전제 검사: CF_EXTERNAL_LEAD=1, HERDR_PANE_ID 비어 있음, 저장소 안, worktree 제외, CLAUDE_CODE_SESSION_ID, hc/python3 ---
if [ "${CF_EXTERNAL_LEAD:-}" != 1 ]; then
	warn "team-core.sh는 외부 팀장 모드(CF_EXTERNAL_LEAD=1) 전용이다; 아무것도 하지 않음"
	exit 2
fi
[ -z "${HERDR_PANE_ID:-}" ] || die "Herdr pane 안 세션에서는 team-core.sh를 쓰지 않는다; 아무것도 하지 않음"
[ -n "${CLAUDE_CODE_SESSION_ID:-}" ] || die "외부 팀장 모드에서는 CLAUDE_CODE_SESSION_ID가 필요하다; 아무것도 하지 않음"

under_root() { case "${1%/}/" in "$ROOT"/*) return 0 ;; esac; return 1; }
under_root "$(pwd -P)" || die "현재 디렉터리가 $ROOT 밖이다; 아무것도 하지 않음"

WT_ERR="데스크톱 세션의 worktree 옵션을 끄고 저장소 폴더에서 새 세션을 연다"
case "$ROOT/$(pwd -P)/" in */.claude/worktrees/*) die "$WT_ERR" ;; esac
git_dir="$(cd "$ROOT" && d="$(HOME=/dev/null XDG_CONFIG_HOME=/dev/null GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_OPTIONAL_LOCKS=0 git --no-optional-locks -C "$ROOT" rev-parse --git-dir 2>/dev/null)" && [ -n "$d" ] && cd "$d" && pwd -P)" || die "$WT_ERR"
git_common_dir="$(cd "$ROOT" && d="$(HOME=/dev/null XDG_CONFIG_HOME=/dev/null GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_OPTIONAL_LOCKS=0 git --no-optional-locks -C "$ROOT" rev-parse --git-common-dir 2>/dev/null)" && [ -n "$d" ] && cd "$d" && pwd -P)" || die "$WT_ERR"
[ "$git_dir" = "$git_common_dir" ] || die "$WT_ERR"

command -v "$HC_BIN" >/dev/null 2>&1 || die "hc 명령($HC_BIN)이 없다"
command -v python3 >/dev/null 2>&1 || die "python3 명령이 없다"

read_ext_lead_id() {
	local id=""
	[ -f "$EXT_LEAD_FILE" ] && IFS= read -r id <"$EXT_LEAD_FILE" || true
	printf '%s' "$id"
}

ext_lock_state() {
	local rec_id
	[ -e "$EXT_LEAD_FILE" ] || { printf 'none'; return 0; }
	rec_id="$(read_ext_lead_id)"
	[ -n "$rec_id" ] || { printf 'unknown'; return 0; }
	if [ "$rec_id" = "$CLAUDE_CODE_SESSION_ID" ]; then
		printf 'mine'
	else
		printf 'other live'
	fi
}

check_ext_lead_owner_for_mutation() {
	local rec_id
	rec_id="$(read_ext_lead_id)"
	if [ -n "$rec_id" ] && [ "$rec_id" != "$CLAUDE_CODE_SESSION_ID" ]; then
		die "다른 세션(${rec_id:0:8}…)이 외부 팀장으로 기록돼 있다; 사용자 승인 뒤 CF_EXTERNAL_LEAD=1 scripts/team-up.sh --lock claim --force"
	fi
}

# --- hc get <이름> --json 파싱 및 SEAT_CMD 옵션 대조 ---
# 출력(단위 구분자 \x1f):
#   t_state \x1f address \x1f app \x1f s_state \x1f turn \x1f conv_id \x1f opt_state \x1f opt_note \x1f opt_act \x1f opt_exp \x1f opt_reason \x1f space_s \x1f _
# shellcheck disable=SC2016
PY_INSPECT_CORE='import json, os, shlex, sys

kind, seat_cmd, recover, rc = sys.argv[1:5]
raw = os.environ.get("HC_JSON", "")

words = shlex.split(seat_cmd)[1:]
units = []
k = 0
while k < len(words):
    if words[k].startswith("-") and k + 1 < len(words) and not words[k + 1].startswith("-"):
        units.append((words[k], words[k + 1]))
        k += 2
    else:
        units.append((words[k],))
        k += 1
exp_summary = " ".join(" ".join(u) for u in units)

def emit(t_state, addr, app, s_state, turn_s, conv_id, opt_state, opt_note, opt_act, opt_exp, opt_reason, space_s="없음"):
    print("\x1f".join([t_state, addr, app, s_state, turn_s, conv_id, opt_state, opt_note, opt_act, opt_exp, opt_reason, space_s, "_"]))
    sys.exit(0 if (t_state == "live" and opt_state == "ok") else 1)

if rc != "0" or not raw.strip():
    emit("missing", "-", "-", "", "-", "", "unknown", "", "", exp_summary, "없음")

try:
    d = json.loads(raw)
except Exception:
    emit("missing", "-", "-", "", "-", "", "unknown", "옵션 판정 불가: JSON 오류", "", exp_summary, "JSON 오류")

if not isinstance(d, dict):
    emit("missing", "-", "-", "", "-", "", "unknown", "옵션 판정 불가: JSON 오류", "", exp_summary, "JSON 오류")

t_state = str(d.get("state") or "missing")
addr = str(d.get("address") or "-")
st_obj = d.get("status") if isinstance(d.get("status"), dict) else {}
app = str(st_obj.get("app") or "-")
s_state = str(st_obj.get("state") or "")
turn_val = d.get("turn")
turn_s = str(turn_val) if isinstance(turn_val, int) else "-"
labels_obj = d.get("labels") if isinstance(d.get("labels"), dict) else {}
raw_space = labels_obj.get("herdr.space")
if isinstance(raw_space, str) and raw_space != "":
    space_s = raw_space.replace("\x1f", " ").replace("\n", " ").replace("\r", " ")
else:
    space_s = "없음"

argv = d.get("argv")
conv_id = ""
if isinstance(argv, list):
    for idx in range(1, len(argv)):
        w = argv[idx]
        if not isinstance(w, str):
            continue
        if w == "--conversation" and idx + 1 < len(argv) and isinstance(argv[idx + 1], str) and not argv[idx + 1].startswith("-"):
            conv_id = argv[idx + 1]
            break
        if w.startswith("--conversation="):
            conv_id = w.split("=", 1)[1]
            break

if t_state != "live":
    emit(t_state, addr, app, s_state, turn_s, conv_id, "unknown", "", "", exp_summary, "종료됨(" + t_state + ")", space_s)

if not isinstance(argv, list) or len(argv) < 1 or any(not isinstance(x, str) for x in argv):
    emit(t_state, addr, app, s_state, turn_s, conv_id, "unknown", "옵션 판정 불가: argv 없음", "", exp_summary, "argv 없음", space_s)

bin_name = os.path.basename(argv[0])
act = []
for w in argv[1:]:
    if w.startswith("--") and "=" in w:
        act.extend(w.split("=", 1))
    elif w.startswith("model_reasoning_effort=") and len(w) > len("model_reasoning_effort=") + 1:
        val = w.split("=", 1)[1]
        if (val.startswith("\"") and val.endswith("\"")) or (val.startswith("\x27") and val.endswith("\x27")):
            val = val[1:-1]
        act.append("model_reasoning_effort=" + val)
    else:
        act.append(w)

missing = []
diff_val = []
act_parts = []
if bin_name != kind:
    diff_val.append("실행파일(기대 %s)" % kind)
exp_pairs = {u for u in units if len(u) == 2}
for u in units:
    if len(u) == 1:
        if u[0] in act:
            act_parts.append(u[0])
        else:
            missing.append(u[0])
    else:
        flag, val = u
        if any(act[j] == flag and act[j + 1] == val for j in range(len(act) - 1)):
            act_parts.append("%s %s" % (flag, val))
            continue
        if any(act[j] == flag and not act[j + 1].startswith("-") and (act[j], act[j + 1]) not in exp_pairs for j in range(len(act) - 1)):
            diff_val.append("%s(기대 %s)" % (flag, val))
            act_parts.append("%s=<다름>" % flag)
        else:
            missing.append("%s %s" % (flag, val))

if not missing and not diff_val:
    emit(t_state, addr, app, s_state, turn_s, conv_id, "ok", "", exp_summary, exp_summary, "", space_s)

parts = []
if missing:
    parts.append("없음 " + ", ".join(missing))
if diff_val:
    parts.append("다름 " + ", ".join(diff_val))
diff_str = "; ".join(parts)
act_summary = " ".join(act_parts) if act_parts else "없음"
emit(t_state, addr, app, s_state, turn_s, conv_id, "mismatch", "옵션 불일치: " + diff_str + " (" + recover + ")", act_summary, exp_summary, diff_str, space_s)
'

S_STATUS=()
S_ADDR=()
S_APP=()
S_ASTATUS=()
S_TURN=()
S_SID=()
S_OPT_STATE=()
S_OPT_NOTE=()
S_OPT_ACT=()
S_OPT_EXP=()
S_OPT_REASON=()
S_SPACE=()
opts_ok=1

inspect_all() {
	local i raw rc recover out
	local f_st f_addr f_app f_ast f_turn f_sid f_ost f_onote f_oact f_oexp f_oreason f_space _
	opts_ok=1
	S_STATUS[0]="external"
	S_ADDR[0]="-"
	S_APP[0]="${SEAT_KIND[0]}"
	S_ASTATUS[0]="이 세션"
	S_TURN[0]="-"
	S_SID[0]="$CLAUDE_CODE_SESSION_ID"
	S_OPT_STATE[0]="ok"
	S_OPT_NOTE[0]=""
	S_SPACE[0]="-"
	rec_id="$(read_ext_lead_id)"
	if [ -z "$rec_id" ]; then
		S_OPT_NOTE[0]="외부 팀장 기록: 없음"
	elif [ "$rec_id" != "$CLAUDE_CODE_SESSION_ID" ]; then
		S_OPT_NOTE[0]="외부 팀장 기록: 다른 세션(${rec_id:0:8}…)"
	fi

	for i in 1 2; do
		if [ "$i" = 1 ]; then
			recover="복구: idle 확인 → scripts/team-core.sh --down cf-impl → scripts/team-core.sh --up <id>"
		else
			recover="복구: idle 확인 → scripts/team-core.sh --down cf-critic → scripts/team-core.sh --up"
		fi
		raw="$("$HC_BIN" get "${SEAT_NAME[$i]}" --json 2>/dev/null)"
		rc=$?
		if ! out="$(HC_JSON="$raw" python3 -c "$PY_INSPECT_CORE" "${SEAT_KIND[$i]}" "${SEAT_CMD[$i]}" "$recover" "$rc")"; then
			opts_ok=0
		fi
		IFS=$'\x1f' read -r f_st f_addr f_app f_ast f_turn f_sid f_ost f_onote f_oact f_oexp f_oreason f_space _ <<<"$out"
		S_STATUS[i]="$f_st"
		S_ADDR[i]="$f_addr"
		S_APP[i]="$f_app"
		S_ASTATUS[i]="$f_ast"
		S_TURN[i]="$f_turn"
		S_SID[i]="$f_sid"
		S_OPT_STATE[i]="$f_ost"
		S_OPT_NOTE[i]="$f_onote"
		S_OPT_ACT[i]="$f_oact"
		S_OPT_EXP[i]="$f_oexp"
		S_OPT_REASON[i]="$f_oreason"
		S_SPACE[i]="${f_space:-없음}"
	done
}

action_of() {
	local i=$1
	if [ "$i" = 0 ]; then
		echo "유지"
		return
	fi
	case "${S_STATUS[$i]}" in
	live) echo "유지" ;;
	*) echo "생성" ;;
	esac
}

print_table() {
	local i st
	echo "team-core 점검 — 저장소 $ROOT · 모드 Core(외부 팀장)"
	printf '%-7s %-11s %-7s %-7s %-17s %-7s %-12s %s\n' 석 이름 address agent 상태 turn herdr.space "--up 조치"
	for i in 0 1 2; do
		st="${S_STATUS[$i]}"
		[ -n "${S_ASTATUS[$i]}" ] && st="$st(${S_ASTATUS[$i]})"
		printf '%-7s %-11s %-7s %-7s %-17s %-7s %-12s %s\n' \
			"${SEAT_ROLE[$i]}" "${SEAT_NAME[$i]}" "${S_ADDR[$i]:--}" "${S_APP[$i]:--}" "$st" "${S_TURN[$i]:--}" "${S_SPACE[$i]:-없음}" "$(action_of "$i")"
		[ -z "${S_OPT_NOTE[$i]:-}" ] || echo "        ↳ ${S_OPT_NOTE[$i]}"
	done
}

print_check_summary() {
	local i addr tail
	for i in 1 2; do
		addr="${S_ADDR[$i]:--}"
		tail=""
		if [ "$i" = 1 ] && [ -n "${S_SID[1]:-}" ]; then
			tail=" 대화=${S_SID[1]}"
		fi
		case "${S_OPT_STATE[$i]:-unknown}" in
		ok)
			echo "${SEAT_NAME[$i]} $addr ok$tail"
			;;
		mismatch)
			echo "${SEAT_NAME[$i]} $addr mismatch 실제=${S_OPT_ACT[$i]} 기대=${S_OPT_EXP[$i]}$tail"
			;;
		*)
			echo "${SEAT_NAME[$i]} $addr unknown ${S_OPT_REASON[$i]:-판정 불가}$tail"
			;;
		esac
	done
}

print_status() {
	local now_ts lead_sid_short lock_st i name addr kind opt_field sid_field dialog_field st_field
	local branch wt_out wt_n wt_desc unv_str="" item
	local -a unv_items=()
	now_ts="$(date '+%Y-%m-%d %H:%M:%S%z')"
	lock_st="$(ext_lock_state)"
	lead_sid_short="${CLAUDE_CODE_SESSION_ID:0:8}"
	[ "$lock_st" != unknown ] || unv_items+=("잠금(unknown)")
	echo "[CF 팀장→마탑] 답: 팀 점검·구성($status_trigger, $now_ts)"
	echo "- 팀장 세션: $lead_sid_short, 팀장 모드 외부(Core), 잠금 $lock_st"
	for i in 1 2; do
		name="${SEAT_NAME[$i]}"
		addr="${S_ADDR[$i]:--}"
		kind="${SEAT_KIND[$i]}"
		case "${S_OPT_STATE[$i]:-unknown}" in
		ok) opt_field="○" ;;
		mismatch) opt_field="×(${S_OPT_REASON[$i]})" ;;
		*)
			opt_field="×(판정 불가: ${S_OPT_REASON[$i]:-미확인})"
			unv_items+=("$name 옵션(${S_OPT_REASON[$i]:-미확인})")
			;;
		esac
		if [ "$i" = 1 ] && [ -n "${S_SID[1]:-}" ]; then
			sid_field="○"
		else
			sid_field="×"
		fi
		if [ "${S_STATUS[$i]}" = live ]; then
			st_field="${S_ASTATUS[$i]:-없음}"
			case "$st_field" in
			blocked) dialog_field="있음" ;;
			idle | done | working) dialog_field="없음" ;;
			*)
				dialog_field="미확인"
				unv_items+=("$name 확인창")
				;;
			esac
		else
			st_field="없음"
			dialog_field="미확인"
			unv_items+=("$name 확인창")
		fi
		echo "- 팀원: $name $addr $kind 옵션 일치 $opt_field 세션 id 기록 $sid_field 확인창 $dialog_field 상태 $st_field"
	done
	branch="$(HOME=/dev/null XDG_CONFIG_HOME=/dev/null GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_OPTIONAL_LOCKS=0 git --no-optional-locks -C "$ROOT" symbolic-ref --short HEAD 2>/dev/null ||
		HOME=/dev/null XDG_CONFIG_HOME=/dev/null GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_OPTIONAL_LOCKS=0 git --no-optional-locks -C "$ROOT" rev-parse --short HEAD 2>/dev/null)"
	if [ -z "$branch" ]; then
		branch="미확인"
		unv_items+=("저장소 브랜치")
	fi
	if wt_out="$(HOME=/dev/null XDG_CONFIG_HOME=/dev/null GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_OPTIONAL_LOCKS=0 git --no-optional-locks -C "$ROOT" status --porcelain 2>/dev/null)"; then
		if [ -z "$wt_out" ]; then
			wt_desc="깨끗"
		else
			wt_n="$(printf '%s\n' "$wt_out" | wc -l | tr -d ' ')"
			wt_desc="바뀐 파일 ${wt_n}개"
		fi
	else
		wt_desc="미확인"
		unv_items+=("작업 트리")
	fi
	echo "- 저장소: 브랜치 $branch, 작업 트리 $wt_desc"
	echo "- 감시: 스크립트로 알 수 없음(팀장이 적음)"
	echo "- 띄운 것·바꾼 것: 없음(--status는 바꾸지 않음)"
	echo "- 잃은 것: 미확인(팀장이 적음)"
	unv_items+=("감시" "잃은 것")
	for item in "${unv_items[@]}"; do
		if [ -z "$unv_str" ]; then
			unv_str="$item"
		else
			unv_str="$unv_str, $item"
		fi
	done
	echo "- 미확인: $unv_str"
	echo "이 메시지는 승인이 아니다."
}

start_seat() {
	local i=$1 name="${SEAT_NAME[$1]}" role="${SEAT_ROLE[$1]}" run_out rc new_addr
	local -a label_args=(--label team=cf --label "role=$role")
	shift
	if [ "${S_STATUS[$i]}" = live ]; then
		echo "$name: 살아 있음(${S_ADDR[$i]}); 그대로 둠"
		if [ "${S_OPT_STATE[$i]:-}" = mismatch ]; then
			if [ "$i" = 1 ]; then
				warn "$name 옵션 불일치 — idle일 때 scripts/team-core.sh --down $name 뒤 scripts/team-core.sh --up ${S_SID[1]:-<대화 id>}"
			else
				warn "$name 옵션 불일치 — idle일 때 scripts/team-core.sh --down $name 뒤 scripts/team-core.sh --up"
			fi
		fi
		return 0
	fi
	if [ "$i" = 1 ] && [ -z "$resume_id" ]; then
		warn "대화 id 없음 — 새 대화로 띄움"
	fi
	if [ -n "${CF_HERDR_SPACE:-}" ]; then
		label_args+=(--label "herdr.space=$CF_HERDR_SPACE")
	fi
	run_out="$("$HC_BIN" run --bg --json --no-parent --outlive-parent --name "$name" --cwd "$ROOT" "${label_args[@]}" -- "$@" 2>&1)"
	rc=$?
	if [ "$rc" != 0 ]; then
		warn "$name: hc run 거부(rc=$rc): $run_out"
		return 1
	fi
	new_addr="$(RAW_OUT="$run_out" python3 -c 'import json,os
try: print(json.loads(os.environ["RAW_OUT"]).get("address") or "-")
except Exception: print("-")')"
	echo "$name: 기동 완료($new_addr)"
	return 0
}

run_down() {
	local target="$1" raw rc state_info t_state s_state addr kill_out rm_out
	check_ext_lead_owner_for_mutation
	raw="$("$HC_BIN" get "$target" --json 2>/dev/null)"
	rc=$?
	[ "$rc" = 0 ] && [ -n "$raw" ] || die "$target: 터미널을 찾을 수 없다; 내리지 않음"
	state_info="$(RAW_JSON="$raw" python3 -c 'import json,os
try:
    d=json.loads(os.environ["RAW_JSON"])
    st=d.get("status") if isinstance(d.get("status"),dict) else {}
    print("%s\t%s\t%s" % (d.get("state") or "-", st.get("state") or "-", d.get("address") or "-"))
except Exception:
    print("error\terror\t-")')"
	IFS=$'\t' read -r t_state s_state addr <<<"$state_info"
	[ "$t_state" = live ] || die "$target: 살아 있지 않다(state=$t_state); 내리지 않음"
	case "$s_state" in
	idle | done) ;;
	*)
		die "$target: 현재 상태가 '$s_state'이다(idle·done일 때만 가능); 내리지 않음"
		;;
	esac
	kill_out="$("$HC_BIN" kill "$target" --json 2>&1)" || die "$target: hc kill 실패: $kill_out"
	rm_out="$("$HC_BIN" rm "$target" --json 2>&1)" || die "$target: hc rm 실패: $rm_out"
	echo "$target: 종료 및 정리 완료($addr)"
}

case "$mode" in
check)
	inspect_all
	print_table
	print_check_summary
	[ "${S_STATUS[1]}" = live ] && [ "${S_STATUS[2]}" = live ] && [ "$opts_ok" = 1 ]
	exit
	;;
status)
	inspect_all
	print_status
	exit 0
	;;
down)
	run_down "$down_target"
	exit 0
	;;
up)
	if [ -n "$resume_id" ]; then
		case "$resume_id" in *[!0-9A-Fa-f-]*) die "세션 id 형식이 아니다: $resume_id" ;; esac
		[ "${#resume_id}" -ge 8 ] || die "세션 id가 너무 짧다(8자 이상): $resume_id"
	fi
	check_ext_lead_owner_for_mutation
	inspect_all
	fail=0
	if [ -n "$resume_id" ]; then
		start_seat 1 agy --conversation "$resume_id" --model "$IMPL_MODEL" --mode accept-edits --sandbox || fail=1
	else
		start_seat 1 agy --model "$IMPL_MODEL" --mode accept-edits --sandbox || fail=1
	fi
	start_seat 2 codex --search --yolo --disable worktrees --disable memories -m gpt-6.1-sol -c 'model_reasoning_effort="high"' || fail=1
	exit "$fail"
	;;
esac

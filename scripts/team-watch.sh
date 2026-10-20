#!/usr/bin/env bash
# scripts/team-watch.sh
# 외부 팀장 전용 읽기 전용 감시 도구.
# 키 전송·rename·저장소/임시 파일 쓰기를 일절 하지 않는다(유일한 예외는 시작 시 자기 mktemp 사본 생성 후 exec이며 종료 시 trap으로 삭제).
set -u

SELF_COPY_PATH=""
PRESET_ROOT=""
PRESET_HASH=""

usage() {
	echo "사용법: scripts/team-watch.sh [general|round <회차ID> <허용 파일 정규식>] [초] [--duration <초>] [--minutes <분>] [--interval <초>] [--critic-grace <초>] [--verdict-timeout <초>]" >&2
	exit 2
}

MODE="general"
ROUND_ID=""
ISSUE_NUM=""
ROUND_SUB=""
ALLOW_REGEX=""
DURATION=3600
INTERVAL=5
CRITIC_GRACE=60
VERDICT_TIMEOUT=150
UNKNOWN_BLOCKED_SEC="${UNKNOWN_BLOCKED_SEC:-20}"

orig_args=("$@")
if [ "$#" -gt 0 ]; then
	case "$1" in
	general)
		MODE="general"
		shift
		;;
	round)
		MODE="round"
		[ "$#" -ge 3 ] || usage
		ROUND_ID="$2"
		ALLOW_REGEX="$3"
		shift 3
		case "${ROUND_ID}" in
		i[0-9]*-?*)
			ISSUE_NUM="${ROUND_ID#i}"
			ISSUE_NUM="${ISSUE_NUM%%-*}"
			ROUND_SUB="${ROUND_ID#*-}"
			case "${ISSUE_NUM}" in '' | *[!0-9]*) usage ;; esac
			case "${ROUND_SUB}" in '' | -* | .* | *..* | *[!A-Za-z0-9._-]*) usage ;; esac
			;;
		*)
			usage
			;;
		esac
		[ -n "${ALLOW_REGEX}" ] || usage
		;;
	-h | --help)
		usage
		;;
	--*)
		MODE="general"
		;;
	*)
		usage
		;;
	esac
fi

while [ "$#" -gt 0 ]; do
	case "$1" in
	--duration)
		[ "$#" -ge 2 ] || usage
		DURATION="$2"
		shift 2
		;;
	--minutes)
		[ "$#" -ge 2 ] || usage
		case "$2" in '' | *[!0-9]*) usage ;; esac
		DURATION=$(($2 * 60))
		shift 2
		;;
	--interval)
		[ "$#" -ge 2 ] || usage
		INTERVAL="$2"
		shift 2
		;;
	--critic-grace)
		[ "$#" -ge 2 ] || usage
		CRITIC_GRACE="$2"
		shift 2
		;;
	--verdict-timeout)
		[ "$#" -ge 2 ] || usage
		VERDICT_TIMEOUT="$2"
		shift 2
		;;
	*)
		case "$1" in
		'' | *[!0-9]*) usage ;;
		*)
			DURATION="$1"
			shift
			;;
		esac
		;;
	esac
done

for num_val in "${DURATION}" "${INTERVAL}" "${CRITIC_GRACE}" "${VERDICT_TIMEOUT}" "${UNKNOWN_BLOCKED_SEC}"; do
	case "${num_val}" in
	'' | *[!0-9]*) usage ;;
	esac
done

# 시작 시 자기 자신을 mktemp 사본으로 복사해 exec한다(저장소 파일이 브랜치 전환·병합으로 바뀌어도 실행 중인 감시 보호).
if [ -z "${SELF_COPY_PATH}" ]; then
	orig_script="${BASH_SOURCE[0]}"
	orig_root="$(cd "$(dirname "${orig_script}")/.." && pwd -P)" || exit 1
	orig_hash="$(HOME=/dev/null XDG_CONFIG_HOME=/dev/null GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "${orig_root}" --no-optional-locks hash-object "${orig_script}" 2>/dev/null)" || true
	if [ -z "${orig_hash}" ]; then
		orig_hash="$(shasum -a 256 "${orig_script}" | cut -d' ' -f1)"
	fi
	tmp_self="$(mktemp "${TMPDIR:-/tmp}/cf-team-watch-self.XXXXXX")" || exit 1
	ORIG_SCRIPT="${orig_script}" TMP_SELF="${tmp_self}" ORIG_ROOT="${orig_root}" ORIG_HASH="${orig_hash}" python3 -c '
import os, shlex
src = os.environ["ORIG_SCRIPT"]
dst = os.environ["TMP_SELF"]
with open(src, "r", encoding="utf-8") as f:
    text = f.read()
text = text.replace("SELF_COPY_PATH=\"\"", "SELF_COPY_PATH=" + shlex.quote(dst), 1)
text = text.replace("PRESET_ROOT=\"\"", "PRESET_ROOT=" + shlex.quote(os.environ["ORIG_ROOT"]), 1)
text = text.replace("PRESET_HASH=\"\"", "PRESET_HASH=" + shlex.quote(os.environ["ORIG_HASH"]), 1)
with open(dst, "w", encoding="utf-8") as f:
    f.write(text)
os.chmod(dst, 0o700)
' || {
		rm -f -- "${tmp_self}"
		exit 1
	}
	if [ "${#orig_args[@]}" -gt 0 ]; then
		exec "${BASH:-/bin/bash}" "${tmp_self}" "${orig_args[@]}"
	else
		exec "${BASH:-/bin/bash}" "${tmp_self}"
	fi
fi

cleanup_self() {
	if [ -n "${SELF_COPY_PATH}" ] && [ -f "${SELF_COPY_PATH}" ]; then
		rm -f -- "${SELF_COPY_PATH}"
	fi
}
trap cleanup_self EXIT
trap 'exit 0' INT TERM HUP

ROOT="${PRESET_ROOT}"
TOOL_HASH="${PRESET_HASH}"
WORK_ROOT="${CF_WORK_ROOT:-}"
if [ -z "${WORK_ROOT}" ]; then
	WORK_ROOT="$(cd "${ROOT}/.." && pwd -P)/cf-work"
fi
WORK_ROOT="${WORK_ROOT%/}"

git_ro() {
	HOME=/dev/null XDG_CONFIG_HOME=/dev/null GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
		git -C "${ROOT}" --no-optional-locks "$@"
}

read_head() {
	git_ro rev-parse --short HEAD 2>/dev/null || printf 'unknown\n'
}

read_refs_sig() {
	local sym="" refs=""
	sym="$(git_ro symbolic-ref -q --short HEAD 2>/dev/null || printf 'DETACHED')"
	refs="$(git_ro for-each-ref --format='%(refname:short) %(objectname:short)' refs/heads 2>/dev/null || true)"
	printf '%s\n%s\n' "${sym}" "${refs}" | shasum -a 256 | cut -c1-16
}

read_origin_main() {
	git_ro rev-parse --verify -q --short refs/remotes/origin/main 2>/dev/null ||
		git_ro rev-parse --verify -q --short origin/main 2>/dev/null ||
		printf 'none\n'
}

read_ext_lead_sig() {
	local f="${ROOT}/.local/team/external-lead"
	if [ -f "${f}" ]; then
		shasum -a 256 "${f}" | cut -c1-16
	else
		printf 'none\n'
	fi
}

# agent 이름 → "pane_id\tsession_id\tstatus"
snap_agent() {
	local name="$1" raw=""
	raw="$(herdr agent get "${name}" 2>/dev/null)" || raw=""
	RAW_JSON="${raw}" python3 -c '
import json, os
raw = os.environ["RAW_JSON"]
try:
    a = json.loads(raw)["result"]["agent"]
    pid = a.get("pane_id") or "-"
    sid = (a.get("agent_session") or {}).get("value") or "-"
    st = a.get("agent_status") or "-"
    print(f"{pid}\t{sid}\t{st}")
except Exception:
    print("-\t-\tmissing")
'
}

# pane_id의 현재 agent 종류·세션(이름 풀림 시 확인용) → "agent\tsession_id"
snap_pane_agent() {
	local target_pid="$1" raw=""
	raw="$(herdr pane list 2>/dev/null)" || raw=""
	RAW_JSON="${raw}" TARGET_PID="${target_pid}" python3 -c '
import json, os
raw = os.environ["RAW_JSON"]
pid = os.environ["TARGET_PID"]
try:
    panes = json.loads(raw)["result"]["panes"]
    for p in panes:
        if p.get("pane_id") == pid:
            ag = p.get("agent") or "-"
            sid = (p.get("agent_session") or {}).get("value") or "-"
            print(f"{ag}\t{sid}")
            break
    else:
        print("-\t-")
except Exception:
    print("-\t-")
'
}

# 확인창 포커스 기록: herdr pane layout --pane <pane>의 focused_pane_id·zoomed 및 workspace list
layout_focus_info() {
	local pid="$1" raw_lay="" raw_ws=""
	raw_lay="$(herdr pane layout --pane "${pid}" 2>/dev/null)" || raw_lay=""
	raw_ws="$(herdr workspace list 2>/dev/null)" || raw_ws=""
	RAW_LAY="${raw_lay}" RAW_WS="${raw_ws}" python3 -c '
import json, os
fp = "-"
zm = "false"
ws = "-"
try:
    l = json.loads(os.environ["RAW_LAY"])["result"]["layout"]
    fp = l.get("focused_pane_id") or "-"
    zm = "true" if l.get("zoomed") else "false"
except Exception:
    pass
try:
    wss = json.loads(os.environ["RAW_WS"])["result"]["workspaces"]
    focused_ws = [w.get("workspace_id") for w in wss if w.get("focused") and w.get("workspace_id")]
    if focused_ws:
        ws = ",".join(focused_ws)
except Exception:
    pass
print(f"focused_pane_id={fp} zoomed={zm} active_workspace={ws}")
'
}

# 화면 분석: 확인창 구조(명령 확인창 cmd / MCP 확인창 mcp) 여부 및 agy 하단 6줄 실행 중("● [시각] ... running") 표시 여부
analyze_screen() {
	local scr="$1"
	SCR="${scr}" python3 -c '
import os, re

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
INPUT_SEP_RE = re.compile(r"^\s*[\u2500\u2501\u2550\-]{3,}\s*$")
MCP_HINT_RE = re.compile(r"^\s*\u2191/\u2193\s+Navigate\s*\u00b7\s*tab\s+Amend\s*$")
MCP_OPT_PATTERNS = [
    re.compile(r"^\s*(?:[>❯]\s*)?1\.\s+Yes,\s*allow tool call\s*$"),
    re.compile(r"^\s*(?:[>❯]\s*)?2\.\s+Yes,\s*and always allow tool\b"),
    re.compile(r"^\s*(?:[>❯]\s*)?3\.\s+Yes,\s*and always allow tool\b"),
    re.compile(r"^\s*(?:[>❯]\s*)?4\.\s+No,\s*deny tool call\s*$"),
    re.compile(r"^\s*(?:[>❯]\s*)?5\.\s+No,\s*and always deny tool\b"),
    re.compile(r"^\s*(?:[>❯]\s*)?6\.\s+No,\s*and always deny tool\b"),
]

def inspect_collapsed_prompt(scr):
    raw_lines = scr.splitlines()
    ne = [(idx, l) for idx, l in enumerate(raw_lines) if l.strip()]
    if len(ne) < 6:
        return (False, False)
    if "ctrl+g edit/expand command" in ne[-1][1] and not re.match(r"^\s*[>❯]", ne[-1][1]):
        hint_pos = len(ne) - 1
    elif (
        len(ne) >= 7
        and re.search(r"^\s*esc to cancel\b|accept-edits|shift\+tab", ne[-1][1])
        and not INPUT_SEP_RE.match(ne[-1][1])
        and not re.match(r"^\s*[>❯]", ne[-1][1])
        and "ctrl+g edit/expand command" in ne[-2][1]
        and not re.match(r"^\s*[>❯]", ne[-2][1])
    ):
        hint_pos = len(ne) - 2
    else:
        return (False, False)
    cancel_pos = hint_pos - 1
    if not re.match(r"^\s*(?:[>❯]\s*)?4\.\s+No,\s*cancel\b", ne[cancel_pos][1]):
        return (False, False)
    yes_pos = None
    for pos in range(cancel_pos - 1, 0, -1):
        if re.match(r"^\s*(?:[>❯]\s*)?1\.\s+Yes\b", ne[pos][1]):
            yes_pos = pos
            break
    if yes_pos is None or ne[yes_pos - 1][1].strip() != "Run this command?":
        return (False, False)
    q_pos = yes_pos - 1
    mid_menu = [ne[p][1] for p in range(yes_pos + 1, cancel_pos)]
    opt2_idxs = [i for i, l in enumerate(mid_menu) if re.match(r"^\s*(?:[>❯]\s*)?2\.\s+", l)]
    opt3_idxs = [i for i, l in enumerate(mid_menu) if re.match(r"^\s*(?:[>❯]\s*)?3\.\s+", l)]
    if opt2_idxs != [0] or len(opt3_idxs) != 1 or opt3_idxs[0] < 1:
        return (False, False)
    if any(
        re.match(r"^\s*(?:[>❯]\s*)?[14]\.\s+", l) or l.strip() == "Run this command?"
        for l in mid_menu
    ):
        return (False, False)
    menu_lines = [ne[p][1] for p in range(yes_pos, cancel_pos + 1)]
    cursor_lines = [l for l in menu_lines if re.match(r"^\s*[>❯]", l)]
    if len(cursor_lines) != 1 or not re.match(r"^\s*[>❯]\s*[1-4]\.\s+", cursor_lines[0]):
        return (False, False)
    q_raw = ne[q_pos][0]
    for r_i in range(q_raw, len(raw_lines) - 1):
        if INPUT_SEP_RE.match(raw_lines[r_i]) and re.match(r"^\s*[>❯](\s.*)?$", raw_lines[r_i + 1]):
            return (False, False)
    for p in range(q_pos, len(ne) - 1):
        if INPUT_SEP_RE.match(ne[p][1]) and re.match(r"^\s*[>❯](\s.*)?$", ne[p + 1][1]):
            return (False, False)
    for p in range(q_pos, hint_pos + 1):
        if re.match(r"^\s*[>❯]\s*$", ne[p][1]):
            return (False, False)
    cursor_on_1 = bool(re.match(r"^\s*[>❯]\s*1\.\s+Yes\b", ne[yes_pos][1]))
    return (True, cursor_on_1)

def inspect_mcp_prompt(scr):
    clean_scr = ANSI_RE.sub("", scr)
    raw_lines = clean_scr.splitlines()
    ne = [(idx, l) for idx, l in enumerate(raw_lines) if l.strip()]
    if len(ne) < 8:
        return False
    if MCP_HINT_RE.match(ne[-1][1]):
        hint_pos = len(ne) - 1
    elif (
        len(ne) >= 9
        and re.search(r"^\s*esc to cancel\b|accept-edits|shift\+tab", ne[-1][1])
        and not INPUT_SEP_RE.match(ne[-1][1])
        and not re.match(r"^\s*[>❯]", ne[-1][1])
        and MCP_HINT_RE.match(ne[-2][1])
    ):
        hint_pos = len(ne) - 2
        if ne[-1][0] - ne[hint_pos][0] > 2:
            return False
    else:
        return False
    yes_pos = None
    for pos in range(hint_pos - 1, 0, -1):
        if MCP_OPT_PATTERNS[0].match(ne[pos][1]):
            yes_pos = pos
            break
    if yes_pos is None or ne[yes_pos - 1][1].strip() != "Allow calling this tool?":
        return False
    q_pos = yes_pos - 1
    menu_lines = [ne[p][1] for p in range(yes_pos, hint_pos)]
    opt_positions = []
    for pat in MCP_OPT_PATTERNS:
        matches = [i for i, l in enumerate(menu_lines) if pat.match(l)]
        if len(matches) != 1:
            return False
        opt_positions.append(matches[0])
    if (
        opt_positions[0] != 0
        or opt_positions[1] != 1
        or opt_positions[4] != opt_positions[3] + 1
        or opt_positions != sorted(opt_positions)
    ):
        return False
    bounds = opt_positions + [len(menu_lines)]
    expected_suffixes = {
        1: "in this conversation",
        2: "(Persist to settings.json)",
        4: "in this conversation",
        5: "(Persist to settings.json)",
    }
    for idx_opt, suffix in expected_suffixes.items():
        joined = " ".join(s.strip() for s in menu_lines[bounds[idx_opt]:bounds[idx_opt + 1]])
        if not joined.endswith(suffix):
            return False
    opt_pos_set = set(opt_positions)
    for i, l in enumerate(menu_lines):
        if i not in opt_pos_set:
            if (
                re.match(r"^\s*[>❯]", l)
                or re.match(r"^\s*(?:[>❯]\s*)?\d+\.\s+", l)
                or l.strip() in ("Allow calling this tool?", "Run this command?")
                or INPUT_SEP_RE.match(l)
            ):
                return False
    cursor_lines = [l for l in menu_lines if re.match(r"^\s*[>❯]", l)]
    if len(cursor_lines) != 1 or not re.match(r"^\s*[>❯]\s*[1-6]\.\s+", cursor_lines[0]):
        return False
    q_raw = ne[q_pos][0]
    last_menu_raw = ne[hint_pos - 1][0]
    if any(not raw_lines[r_i].strip() for r_i in range(q_raw, last_menu_raw + 1)):
        return False
    if ne[hint_pos][0] - last_menu_raw > 2:
        return False
    for r_i in range(q_raw, len(raw_lines) - 1):
        if INPUT_SEP_RE.match(raw_lines[r_i]) and re.match(r"^\s*[>❯](\s.*)?$", raw_lines[r_i + 1]):
            return False
    for p in range(q_pos, len(ne) - 1):
        if INPUT_SEP_RE.match(ne[p][1]) and re.match(r"^\s*[>❯](\s.*)?$", ne[p + 1][1]):
            return False
    for p in range(q_pos, hint_pos + 1):
        if re.match(r"^\s*[>❯]\s*$", ne[p][1]):
            return False
    return True

scr = os.environ["SCR"]
lines = scr.splitlines()
if inspect_collapsed_prompt(scr)[0]:
    prompt_kind = "cmd"
elif inspect_mcp_prompt(scr):
    prompt_kind = "mcp"
else:
    prompt_kind = "0"
tail_lines = "\n".join(lines[-6:])
has_running = "1" if re.search(r"\u25cf \[[0-9:]+\].*running", tail_lines) else "0"
has_new = "1" if re.search(r"(?i)(100%\s+(context\s+)?left|/new)", scr) else "0"
print(f"{prompt_kind}\t{has_running}\t{has_new}")
'
}

list_to_lead() {
	local d="${WORK_ROOT}/issues/${ISSUE_NUM}/${ROUND_SUB}/to-lead"
	if [ -d "${d}" ]; then
		D_PATH="${d}" python3 -c '
import os
d = os.environ["D_PATH"]
try:
    for name in sorted(os.listdir(d)):
        if not name.startswith("."):
            print(name)
except Exception:
    pass
'
	fi
}

find_latest_verdict() {
	ROUND_ID="${ROUND_ID}" python3 -c '
import glob, os
rid = os.environ["ROUND_ID"]
patterns = [
    f"/tmp/cf-{rid}-review*/VERDICT*.md",
    f"/tmp/cf-{rid}-review*/*/VERDICT*.md",
]
best_path = ""
best_mtime = 0
for pat in patterns:
    for path in glob.glob(pat):
        if os.path.isfile(path):
            try:
                mt = int(os.path.getmtime(path))
            except Exception:
                continue
            if mt >= best_mtime:
                best_mtime = mt
                best_path = path
if best_path:
    print(f"{best_path}\t{best_mtime}")
else:
    print("\t0")
'
}

check_out_of_scope() {
	git_ro status --porcelain=v1 -z --untracked-files=all 2>/dev/null | ALLOW_REGEX="${ALLOW_REGEX}" python3 -c '
import os, re, sys
raw = sys.stdin.buffer.read().decode("utf-8", errors="replace")
allow_re = re.compile(os.environ["ALLOW_REGEX"])
entries = raw.split("\0")
i = 0
while i < len(entries):
    item = entries[i]
    if not item or len(item) < 4:
        i += 1
        continue
    xy = item[:2]
    path = item[3:]
    if "R" in xy or "C" in xy:
        if not allow_re.fullmatch(path):
            print(path)
            break
        i += 1
        if i < len(entries) and entries[i]:
            orig_path = entries[i]
            if not allow_re.fullmatch(orig_path):
                print(orig_path)
                break
    else:
        if not allow_re.fullmatch(path):
            print(path)
            break
    i += 1
'
}

# --- 초기 기준선(baseline) 기록 ---
init_ts="$(date +%s)"
critic_grace_start=0
unknown_blocked_start=0

base_head="$(read_head)"
base_refs="$(read_refs_sig)"
base_origin="$(read_origin_main)"
base_rec="$(read_ext_lead_sig)"

IFS=$'\t' read -r base_ip base_is base_ist <<<"$(snap_agent cf-impl)"
IFS=$'\t' read -r base_cp base_cs base_cst <<<"$(snap_agent cf-critic)"

was_impl_busy=0
if [ "${base_ist}" = "working" ]; then
	was_impl_busy=1
elif [ "${base_ip}" != "-" ] && { [ "${base_ist}" = "idle" ] || [ "${base_ist}" = "done" ]; }; then
	init_scr="$(herdr pane read "${base_ip}" --source visible 2>/dev/null)" || init_scr=""
	IFS=$'\t' read -r _ init_running _ <<<"$(analyze_screen "${init_scr}")"
	if [ "${init_running}" = "1" ]; then
		was_impl_busy=1
	fi
fi

base_to_lead=""
v_seen=""
if [ "${MODE}" = "round" ]; then
	base_to_lead="$(list_to_lead)"
	IFS=$'\t' read -r init_vp init_vm <<<"$(find_latest_verdict)"
	if [ -n "${init_vp}" ] && [ $((init_ts - init_vm)) -ge "${VERDICT_TIMEOUT}" ]; then
		v_seen="${init_vp}:${init_vm}"
	fi
fi

start_ts="$(date +%s)"
deadline=$((start_ts + DURATION))

# 첫 줄: 기준선 기록 완료 후 도구 판(git hash-object 값) 출력
printf 'team-watch version=%s mode=%s\n' "${TOOL_HASH}" "${MODE}"

while :; do
	now="$(date +%s)"

	IFS=$'\t' read -r ip is ist <<<"$(snap_agent cf-impl)"
	IFS=$'\t' read -r cp cs cst <<<"$(snap_agent cf-critic)"

	impl_scr=""
	impl_prompt="0"
	impl_running="0"
	if [ "${ip}" != "-" ]; then
		impl_scr="$(herdr pane read "${ip}" --source visible 2>/dev/null)" || impl_scr=""
		IFS=$'\t' read -r impl_prompt impl_running _ <<<"$(analyze_screen "${impl_scr}")"
	fi

	critic_scr=""
	critic_new_screen="0"
	if [ "${cp}" != "-" ]; then
		critic_scr="$(herdr pane read "${cp}" --source visible 2>/dev/null)" || critic_scr=""
		IFS=$'\t' read -r _ _ critic_new_screen <<<"$(analyze_screen "${critic_scr}")"
	elif [ "${base_cp}" != "-" ]; then
		critic_scr="$(herdr pane read "${base_cp}" --source visible 2>/dev/null)" || critic_scr=""
		IFS=$'\t' read -r _ _ critic_new_screen <<<"$(analyze_screen "${critic_scr}")"
	fi

	# 1. 확인창 감지 (cf-impl: 명령 확인창·MCP 확인창·알 수 없는 blocked 20초 초과 / cf-critic: blocked)
	if [ "${ist}" = "blocked" ]; then
		if [ "${impl_prompt}" = "cmd" ]; then
			f_info="$(layout_focus_info "${ip}")"
			printf 'EVENT impl-blocked pane=%s status=%s %s\n' "${ip}" "${ist}" "${f_info}"
			exit 0
		elif [ "${impl_prompt}" = "mcp" ]; then
			f_info="$(layout_focus_info "${ip}")"
			printf 'EVENT impl-blocked kind=mcp pane=%s status=%s %s\n' "${ip}" "${ist}" "${f_info}"
			exit 0
		else
			if [ "${unknown_blocked_start}" -eq 0 ]; then
				unknown_blocked_start="${now}"
			fi
			if [ $((now - unknown_blocked_start)) -gt "${UNKNOWN_BLOCKED_SEC}" ]; then
				f_info="$(layout_focus_info "${ip}")"
				printf 'EVENT impl-blocked kind=unknown pane=%s status=%s %s\n' "${ip}" "${ist}" "${f_info}"
				exit 0
			fi
		fi
	else
		unknown_blocked_start=0
	fi
	if [ "${cst}" = "blocked" ]; then
		target_cp="${cp}"
		[ "${target_cp}" != "-" ] || target_cp="${base_cp}"
		f_info="$(layout_focus_info "${target_cp}")"
		printf 'EVENT critic-blocked pane=%s status=%s %s\n' "${target_cp}" "${cst}" "${f_info}"
		exit 0
	fi

	# 2. 팀원 이름 풀림 (critic /new 직후에는 유예 시간 동안 대기)
	if [ "${ist}" = "missing" ]; then
		printf 'EVENT impl-name-missing\n'
		exit 0
	fi
	if [ "${cst}" = "missing" ]; then
		if [ "${base_cp}" != "-" ]; then
			IFS=$'\t' read -r p_ag _ <<<"$(snap_pane_agent "${base_cp}")"
			if [ "${p_ag}" = "codex" ]; then
				if [ "${critic_grace_start}" -eq 0 ]; then
					critic_grace_start="${now}"
				fi
				if [ $((now - critic_grace_start)) -ge "${CRITIC_GRACE}" ]; then
					printf 'EVENT critic-name-missing pane=%s\n' "${base_cp}"
					exit 0
				fi
			else
				printf 'EVENT critic-name-missing pane=%s\n' "${base_cp}"
				exit 0
			fi
		else
			printf 'EVENT critic-name-missing\n'
			exit 0
		fi
	else
		if [ "${critic_grace_start}" -gt 0 ] && [ "${cp}" = "${base_cp}" ]; then
			base_cs="${cs}"
			critic_grace_start=0
		fi
	fi

	# 3. 팀원 pane·세션 바뀜 (critic /new 유예에 따른 동일 pane 새 세션은 제외)
	if [ "${base_ip}" != "-" ] && [ "${ip}" != "${base_ip}" ]; then
		printf 'EVENT impl-changed was=%s/%s now=%s/%s\n' "${base_ip}" "${base_is}" "${ip}" "${is}"
		exit 0
	fi
	if [ "${base_is}" != "-" ] && [ "${is}" != "-" ] && [ "${is}" != "${base_is}" ]; then
		printf 'EVENT impl-changed was=%s/%s now=%s/%s\n' "${base_ip}" "${base_is}" "${ip}" "${is}"
		exit 0
	fi
	if [ "${cst}" != "missing" ]; then
		if [ "${base_cp}" != "-" ] && [ "${cp}" != "${base_cp}" ]; then
			printf 'EVENT critic-changed was=%s/%s now=%s/%s\n' "${base_cp}" "${base_cs}" "${cp}" "${cs}"
			exit 0
		fi
		if [ "${base_cs}" != "-" ] && [ "${cs}" != "-" ] && [ "${cs}" != "${base_cs}" ]; then
			if [ "${cp}" = "${base_cp}" ] && [ "${critic_new_screen}" = "1" ]; then
				base_cs="${cs}"
			else
				printf 'EVENT critic-changed was=%s/%s now=%s/%s\n' "${base_cp}" "${base_cs}" "${cp}" "${cs}"
				exit 0
			fi
		fi
	fi

	# 4. HEAD·refs/heads·origin/main·external-lead 해시 변화
	cur_head="$(read_head)"
	if [ "${cur_head}" != "${base_head}" ]; then
		printf 'EVENT head-changed %s→%s\n' "${base_head}" "${cur_head}"
		exit 0
	fi
	cur_refs="$(read_refs_sig)"
	if [ "${cur_refs}" != "${base_refs}" ]; then
		printf 'EVENT refs-heads-changed %s→%s\n' "${base_refs}" "${cur_refs}"
		exit 0
	fi
	cur_origin="$(read_origin_main)"
	if [ "${cur_origin}" != "${base_origin}" ]; then
		printf 'EVENT origin-main-changed %s→%s\n' "${base_origin}" "${cur_origin}"
		exit 0
	fi
	cur_rec="$(read_ext_lead_sig)"
	if [ "${cur_rec}" != "${base_rec}" ]; then
		printf 'EVENT external-lead-changed %s→%s\n' "${base_rec}" "${cur_rec}"
		exit 0
	fi

	# 5. round 모드 전용 감시 (허용 파일 밖 변경, to-lead 새 파일, VERDICT 후 150초 정체)
	if [ "${MODE}" = "round" ]; then
		bad_file="$(check_out_of_scope)"
		if [ -n "${bad_file}" ]; then
			printf 'EVENT out-of-scope file=%s\n' "${bad_file}"
			exit 0
		fi
		cur_to_lead="$(list_to_lead)"
		new_tl_file="$(BASE_TL="${base_to_lead}" CUR_TL="${cur_to_lead}" python3 -c '
import os
base_set = set(x for x in os.environ["BASE_TL"].splitlines() if x)
for name in os.environ["CUR_TL"].splitlines():
    if name and name not in base_set:
        print(name)
        break
')"
		if [ -n "${new_tl_file}" ]; then
			printf 'EVENT to-lead file=%s\n' "${new_tl_file}"
			exit 0
		fi
		IFS=$'\t' read -r v_path v_mtime <<<"$(find_latest_verdict)"
		if [ -n "${v_path}" ]; then
			v_key="${v_path}:${v_mtime}"
			if [ "${ist}" = "working" ] || [ "${impl_running}" = "1" ]; then
				v_seen="${v_key}"
			elif [ "${v_key}" != "${v_seen}" ] && [ $((now - v_mtime)) -ge "${VERDICT_TIMEOUT}" ]; then
				printf 'EVENT verdict-stalled file=%s age=%ds\n' "${v_path}" "$((now - v_mtime))"
				exit 0
			fi
		fi
	fi

	# 6. cf-impl idle/done (agy 하단 실행 중 표시가 있으면 대기)
	if [ "${ist}" = "working" ]; then
		was_impl_busy=1
	elif [ "${ist}" = "idle" ] || [ "${ist}" = "done" ]; then
		if [ "${impl_running}" = "1" ]; then
			was_impl_busy=1
		elif [ "${was_impl_busy}" -eq 1 ] || [ "${ist}" != "${base_ist}" ]; then
			printf 'EVENT impl-%s pane=%s\n' "${ist}" "${ip}"
			exit 0
		fi
	fi

	# 7. 무사건 심장박동(heartbeat)
	now="$(date +%s)"
	if [ "${cst}" = "missing" ] && [ "${critic_grace_start}" -gt 0 ]; then
		IFS=$'\t' read -r cp cs cst <<<"$(snap_agent cf-critic)"
		if [ "${cst}" != "missing" ] && [ "${cp}" = "${base_cp}" ]; then
			base_cs="${cs}"
			critic_grace_start=0
		elif [ $((now - critic_grace_start)) -ge "${CRITIC_GRACE}" ]; then
			printf 'EVENT critic-name-missing pane=%s\n' "${base_cp}"
			exit 0
		fi
	fi
	if [ "${now}" -ge "${deadline}" ]; then
		printf 'EVENT heartbeat impl=%s critic=%s\n' "${ist}" "${cst}"
		exit 0
	fi

	if [ "${INTERVAL}" -gt 0 ]; then
		sleep "${INTERVAL}"
	fi
done

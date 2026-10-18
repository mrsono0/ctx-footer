#!/usr/bin/env bash
# scripts/prompt-read.sh <pane>
# 외부 팀장 전용 agy 명령 확인창 전문 읽기 도우미(zoom 없음).
# 응답 키(1번 등)는 절대 보내지 않으며, 마지막 줄에 상태(OK cursor=1 / UNEXPANDED / UNSUPPORTED <사유>)를 출력한다.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
EXT_LEAD_FILE="${ROOT}/.local/team/external-lead"

unsupported() {
	printf 'UNSUPPORTED %s\n' "$1"
	exit 1
}

unexpanded() {
	printf 'UNEXPANDED\n'
	exit 1
}

if [ "$#" -ne 1 ] || [ -z "${1:-}" ]; then
	unsupported "invalid-args"
fi

TARGET_PANE="$1"
case "${TARGET_PANE}" in
-*) unsupported "invalid-args" ;;
esac

# 화면 구조 판정 공통 Python 보조 함수
FRAME_PY='
import json, os, re, sys

HDR_RE = re.compile(r"^\s*Expanded Tool Permission Editor\b")
FC_RE = re.compile(r"^\s*Full Command:(.*)$")
RP_RE = re.compile(r"^\s*Requested Permission \(Editable\)")
RANGE_RE = re.compile(r"^\s*\((\d+)\s*[\u2013\u2014\-]\s*(\d+)\s+of\s+(\d+)\s+lines\)\s*$")
SEP_RE = re.compile(r"^\s*[\u2500\u2501\u2550]{3,}\s*$")
INPUT_SEP_RE = re.compile(r"^\s*[\u2500\u2501\u2550\-]{3,}\s*$")

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

def has_collapsed_prompt_structure(scr):
    return inspect_collapsed_prompt(scr)[0]

def has_collapsed_prompt(scr):
    is_p, cur1 = inspect_collapsed_prompt(scr)
    return is_p and cur1

def inspect_editor(scr):
    all_lines = scr.splitlines()
    tail = all_lines[-40:]
    all_hdrs = [i for i, l in enumerate(all_lines) if HDR_RE.match(l)]
    tail_hdrs = [i for i, l in enumerate(tail) if HDR_RE.match(l)]
    if len(all_hdrs) != 1 or len(tail_hdrs) != 1:
        return {"frame": False, "readable": False, "ambiguous": False}
    sub = tail[tail_hdrs[0] + 1:]
    fc_idx = next((i for i, l in enumerate(sub) if FC_RE.match(l)), None)
    if fc_idx is None or not all(SEP_RE.match(l) or l.strip() == "" for l in sub[:fc_idx]):
        return {"frame": False, "readable": False, "ambiguous": False}
    rp_cands = [i for i in range(fc_idx + 1, len(sub)) if RP_RE.match(sub[i])]
    if not rp_cands:
        return {"frame": False, "readable": False, "ambiguous": False}
    rp_idx = rp_cands[-1]
    after_rp = sub[rp_idx + 1:]
    if len(after_rp) > 15:
        return {"frame": False, "readable": False, "ambiguous": False}
    for idx_a in range(len(after_rp) - 1):
        if INPUT_SEP_RE.match(after_rp[idx_a]) and re.match(r"^\s*[>❯](\s.*)?$", after_rp[idx_a + 1]):
            return {"frame": False, "readable": False, "ambiguous": False}
    non_empty_after = [l.strip() for l in after_rp if l.strip()]
    if non_empty_after and not (re.match(r"^[>❯]", non_empty_after[0]) or non_empty_after[0] == "Press Esc to close"):
        return {"frame": False, "readable": False, "ambiguous": False}
    if "Press Esc to close" in non_empty_after and non_empty_after[-1] != "Press Esc to close":
        return {"frame": False, "readable": False, "ambiguous": False}
    range_cands = [i for i in range(fc_idx + 1, len(sub)) if RANGE_RE.match(sub[i])]
    if len(rp_cands) > 1 or len(range_cands) > 1:
        return {"frame": True, "readable": False, "ambiguous": True}
    mid = list(sub[fc_idx + 1:rp_idx])
    if mid and SEP_RE.match(mid[0]):
        mid.pop(0)
    if mid and SEP_RE.match(mid[-1]):
        mid.pop()
    while mid and mid[-1].strip() == "":
        mid.pop()
    m_range = RANGE_RE.match(mid[-1]) if mid else None
    if range_cands and not m_range:
        return {"frame": True, "readable": False, "ambiguous": True}
    return {
        "frame": True,
        "readable": bool(m_range),
        "ambiguous": False,
        "fc_line": sub[fc_idx],
        "mid": mid,
        "range": (int(m_range.group(1)), int(m_range.group(2)), int(m_range.group(3))) if m_range else None,
    }
'

check_session_guard() {
	if [ -n "${HERDR_PANE_ID:-}" ]; then
		unsupported "session-guard:herdr-pane"
	fi
	if [ "${CF_EXTERNAL_LEAD:-}" != "1" ]; then
		unsupported "session-guard:not-external-lead"
	fi
	if [ -z "${CLAUDE_CODE_SESSION_ID:-}" ]; then
		unsupported "session-guard:missing-session-id"
	fi
	local pwd_phys="" git_dir="" git_common_dir="" rec_id=""
	pwd_phys="$(pwd -P 2>/dev/null)" || unsupported "session-guard:worktree"
	case "${ROOT}/${pwd_phys}/" in
	*/.claude/worktrees/*) unsupported "session-guard:worktree" ;;
	esac
	git_dir="$(cd "${ROOT}" && d="$(HOME=/dev/null XDG_CONFIG_HOME=/dev/null GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "${ROOT}" rev-parse --git-dir 2>/dev/null)" && [ -n "${d}" ] && cd "${d}" && pwd -P)" || unsupported "session-guard:worktree"
	git_common_dir="$(cd "${ROOT}" && d="$(HOME=/dev/null XDG_CONFIG_HOME=/dev/null GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -C "${ROOT}" rev-parse --git-common-dir 2>/dev/null)" && [ -n "${d}" ] && cd "${d}" && pwd -P)" || unsupported "session-guard:worktree"
	if [ "${git_dir}" != "${git_common_dir}" ]; then
		unsupported "session-guard:worktree"
	fi
	if [ ! -f "${EXT_LEAD_FILE}" ]; then
		unsupported "session-guard:no-record"
	fi
	IFS= read -r rec_id <"${EXT_LEAD_FILE}" || true
	if [ -z "${rec_id}" ] || [ "${rec_id}" != "${CLAUDE_CODE_SESSION_ID}" ]; then
		unsupported "session-guard:record-mismatch"
	fi
}

check_target_guard() {
	local stage="$1"
	local subcmd="${2:-}"
	local ag_json="" check_res="" scr="" scr_res=""
	ag_json="$(herdr agent get cf-impl 2>/dev/null)" || unsupported "target-guard:cf-impl-missing"
	check_res="$(AG_JSON="${ag_json}" TARGET_PANE="${TARGET_PANE}" STAGE="${stage}" python3 -c '
import json, os, sys
try:
    a = json.loads(os.environ["AG_JSON"])["result"]["agent"]
except Exception:
    print("bad-json")
    sys.exit(0)
stage = os.environ["STAGE"]
st = a.get("agent_status")
if a.get("pane_id") != os.environ["TARGET_PANE"]:
    print("pane-mismatch")
elif a.get("agent") != "agy":
    print("not-agy")
elif stage == "initial":
    print("ok" if st == "blocked" else "not-blocked")
elif stage == "expanded":
    print("ok" if st in ("blocked", "done") else "not-blocked")
else:
    print("invalid-stage")
')" || unsupported "target-guard:parse-error"
	if [ "${check_res}" != "ok" ]; then
		unsupported "target-guard:${check_res}"
	fi
	scr="$(herdr pane read "${TARGET_PANE}" --source visible 2>/dev/null)" || unsupported "target-guard:read-failed"
	scr_res="$(SCR="${scr}" STAGE="${stage}" SUBCMD="${subcmd}" python3 -c "${FRAME_PY}"'
scr = os.environ["SCR"]
stage = os.environ["STAGE"]
subcmd = os.environ["SUBCMD"]
if stage == "initial":
    is_p, cur1 = inspect_collapsed_prompt(scr)
    print("ok" if (is_p and cur1) else ("cursor-not-1" if is_p else "not-agy-command-prompt"))
elif stage == "expanded":
    info = inspect_editor(scr)
    if subcmd == "send-keys":
        print("ok" if info["frame"] else "expanded-view-missing")
    else:
        print("ok" if info["readable"] else "expanded-view-missing")
else:
    print("invalid-stage")
')" || unsupported "target-guard:screen-check-error"
	if [ "${scr_res}" != "ok" ]; then
		unsupported "target-guard:${scr_res}"
	fi
}

# 모든 키 전송은 반드시 이 함수만 거친다(세션 가드 + 대상 pane 가드 재확인 후 TARGET_PANE에만 전송).
guarded_send() {
	local stage="$1"
	local subcmd="$2"
	local payload="$3"
	check_session_guard
	check_target_guard "${stage}" "${subcmd}"
	if [ "${subcmd}" = "send-keys" ]; then
		herdr pane send-keys "${TARGET_PANE}" "${payload}" >/dev/null 2>&1 || unsupported "send-keys-failed"
	elif [ "${subcmd}" = "send-text" ]; then
		herdr pane send-text "${TARGET_PANE}" "${payload}" >/dev/null 2>&1 || unsupported "send-text-failed"
	else
		unsupported "invalid-subcmd"
	fi
}

read_screen_poll() {
	local mode="$1"
	local prev_b="${2:-}"
	local attempt=0 scr="" ag_json="" poll_res=""
	while [ "${attempt}" -lt 8 ]; do
		scr="$(herdr pane read "${TARGET_PANE}" --source visible 2>/dev/null)" || scr=""
		ag_json=""
		if [ "${mode}" = "wait_collapsed" ]; then
			ag_json="$(herdr agent get cf-impl 2>/dev/null)" || ag_json=""
		fi
		poll_res="$(SCR="${scr}" AG_JSON="${ag_json}" TARGET_PANE="${TARGET_PANE}" MODE="${mode}" PREV_B="${prev_b}" python3 -c "${FRAME_PY}"'
scr = os.environ["SCR"]
mode = os.environ["MODE"]
prev_b = os.environ["PREV_B"]
info = inspect_editor(scr)
if mode == "wait_expanded":
    if info["frame"]:
        print("ok")
    elif (not has_collapsed_prompt_structure(scr)) or ("Expanded Tool Permission Editor" in scr) or ("Full Command" in scr) or ("Requested Permission" in scr):
        print("abort")
    else:
        print("retry")
elif mode == "wait_page":
    if info.get("ambiguous") or (info["frame"] and not info["readable"]):
        print("ok")
    elif not info["readable"]:
        print("retry")
    else:
        cur_b = info["range"][1]
        prev_b_int = int(prev_b) if prev_b.isdigit() else 0
        print("ok" if (cur_b > prev_b_int) else "retry")
elif mode == "wait_collapsed":
    try:
        a = json.loads(os.environ["AG_JSON"])["result"]["agent"]
        st_ok = (a.get("pane_id") == os.environ["TARGET_PANE"] and a.get("agent") == "agy" and a.get("agent_status") == "blocked")
    except Exception:
        st_ok = False
    no_exp = (not info["frame"]) and ("Expanded Tool Permission Editor" not in scr) and ("Full Command" not in scr)
    print("ok" if (st_ok and no_exp and has_collapsed_prompt(scr)) else "retry")
else:
    print("ok")
')"
		if [ "${poll_res}" = "ok" ]; then
			printf '%s' "${scr}"
			return 0
		elif [ "${poll_res}" = "abort" ]; then
			printf '%s' "${scr}"
			return 1
		fi
		attempt=$((attempt + 1))
		if [ "${attempt}" -lt 8 ]; then
			sleep 0.15
		fi
	done
	printf '%s' "${scr}"
	return 1
}

close_expanded_and_unsupported() {
	local reason="$1"
	local cur_scr="" has_f=""
	cur_scr="$(herdr pane read "${TARGET_PANE}" --source visible 2>/dev/null)" || cur_scr=""
	has_f="$(SCR="${cur_scr}" python3 -c "${FRAME_PY}"'
print("1" if inspect_editor(os.environ["SCR"])["frame"] else "0")
')"
	if [ "${has_f}" = "1" ]; then
		guarded_send "expanded" "send-keys" "esc"
		if ! read_screen_poll "wait_collapsed" "" >/dev/null 2>&1; then
			unsupported "collapse-failed"
		fi
	fi
	unsupported "${reason}"
}

# 1. ctrl+g로 펼치기 (가드 통과 시에만 전송)
guarded_send "initial" "send-keys" "ctrl+g"

scr="$(read_screen_poll "wait_expanded" "")" || true
exp_state="$(SCR="${scr}" python3 -c "${FRAME_PY}"'
scr = os.environ["SCR"]
info = inspect_editor(scr)
if info["frame"]:
    print("frame")
elif has_collapsed_prompt_structure(scr) and ("Expanded Tool Permission Editor" not in scr) and ("Full Command" not in scr) and ("Requested Permission" not in scr):
    print("unexpanded")
else:
    print("malformed")
')"
if [ "${exp_state}" = "unexpanded" ]; then
	unexpanded
elif [ "${exp_state}" != "frame" ]; then
	unsupported "expanded-frame-not-found-after-ctrl-g"
fi

# 2. (a–b of N lines)의 b=N까지 Page Down($'\e[6~') 반복
MAX_PAGES=30
PAGES_JSON="[]"
page_guard=0
completed=0
while true; do
	page_guard=$((page_guard + 1))
	parsed="$(SCR="${scr}" PAGES_JSON="${PAGES_JSON}" python3 -c "${FRAME_PY}"'
def err(r):
    print(json.dumps({"ok": False, "reason": r}))
    sys.exit(0)

scr = os.environ["SCR"]
pages = json.loads(os.environ["PAGES_JSON"])
info = inspect_editor(scr)
if not info["frame"]:
    err("expanded-view-lost")
if info.get("ambiguous"):
    err("ambiguous-editor-boundary")
if not info["readable"]:
    err("missing-line-range")

a_val, b_val, n_val = info["range"]
after_fc = FC_RE.match(info["fc_line"]).group(1)
first_line_extra = (after_fc[1:] if after_fc.startswith(" ") else after_fc) if after_fc.strip() else None

body = ([first_line_extra] if first_line_extra is not None else []) + info["mid"][:-1]
while body and SEP_RE.match(body[-1]):
    body.pop()

box_re = re.compile(r"^\s*([\u2502\u2503])(?: (.*?) |(.*?))\1\s*$")
if body and all(box_re.match(line) for line in body):
    cmd_lines = [(box_re.match(l).group(2) if box_re.match(l).group(2) is not None else box_re.match(l).group(3)) for l in body]
else:
    cmd_lines = body

if not (1 <= a_val <= b_val <= n_val):
    err("invalid-line-range")
if len(cmd_lines) != (b_val - a_val + 1):
    err("line-count-mismatch")
if not pages:
    if a_val != 1:
        err("first-page-not-1")
else:
    prev = pages[-1]
    if prev.get("n") != n_val:
        err("inconsistent-line-range")
    if b_val <= prev.get("b", 0):
        err("page-stall")
    if a_val > prev.get("b", 0) + 1:
        err("incomplete-lines")

pages.append({"a": a_val, "b": b_val, "n": n_val, "lines": cmd_lines})
print(json.dumps({"ok": True, "a": a_val, "b": b_val, "n": n_val, "done": (b_val == n_val), "pages": pages}, ensure_ascii=False))
')" || close_expanded_and_unsupported "parse-page-failed"

	page_ok="$(PARSED="${parsed}" python3 -c 'import json,os; print("1" if json.loads(os.environ["PARSED"]).get("ok") else "0")')"
	if [ "${page_ok}" != "1" ]; then
		fail_reason="$(PARSED="${parsed}" python3 -c 'import json,os; print(json.loads(os.environ["PARSED"]).get("reason","parse-page-failed"))')"
		if [ "${fail_reason}" = "expanded-view-lost" ]; then
			unsupported "${fail_reason}"
		fi
		close_expanded_and_unsupported "${fail_reason}"
	fi
	PAGES_JSON="$(PARSED="${parsed}" python3 -c 'import json,os; print(json.dumps(json.loads(os.environ["PARSED"])["pages"], ensure_ascii=False))')"
	b_val="$(PARSED="${parsed}" python3 -c 'import json,os; print(json.loads(os.environ["PARSED"])["b"])')"
	done_flag="$(PARSED="${parsed}" python3 -c 'import json,os; print("1" if json.loads(os.environ["PARSED"]).get("done") else "0")')"

	if [ "${done_flag}" = "1" ]; then
		completed=1
		break
	fi

	if [ "${page_guard}" -ge "${MAX_PAGES}" ]; then
		close_expanded_and_unsupported "page-limit-exceeded"
	fi

	guarded_send "expanded" "send-text" $'\e[6~'
	if ! scr="$(read_screen_poll "wait_page" "${b_val}")"; then
		close_expanded_and_unsupported "page-stall"
	fi
done

if [ "${completed}" != "1" ]; then
	close_expanded_and_unsupported "page-limit-exceeded"
fi

# 3. esc로 닫기 (펼친 화면 틀이 보일 때만 전송)
guarded_send "expanded" "send-keys" "esc"

scr_after="$(read_screen_poll "wait_collapsed" "")" || true
ag_after="$(herdr agent get cf-impl 2>/dev/null)" || ag_after=""

# 4. 완독·줄 범위·원래 확인창 복귀(blocked + 1번 커서) 모두 검증 후 명령 전문과 상태 줄 출력
PAGES_JSON="${PAGES_JSON}" SCR_AFTER="${scr_after}" AG_AFTER="${ag_after}" TARGET_PANE="${TARGET_PANE}" python3 -c "${FRAME_PY}"'
pages = json.loads(os.environ["PAGES_JSON"])
scr_after = os.environ["SCR_AFTER"]
if not pages:
    print("UNSUPPORTED empty-command")
    sys.exit(1)
expected_n = pages[0].get("n", 0)
if expected_n <= 0 or pages[-1].get("b", 0) != expected_n:
    print("UNSUPPORTED incomplete-lines")
    sys.exit(1)
numbered = {}
for p in pages:
    a, b, lines = p.get("a", 0), p.get("b", 0), p.get("lines", [])
    if p.get("n") != expected_n or len(lines) != (b - a + 1):
        print("UNSUPPORTED line-count-mismatch")
        sys.exit(1)
    for idx, line in enumerate(lines, start=a):
        if idx in numbered and numbered[idx] != line:
            print("UNSUPPORTED overlapping-line-mismatch")
            sys.exit(1)
        numbered[idx] = line
if sorted(numbered.keys()) != list(range(1, expected_n + 1)):
    print("UNSUPPORTED incomplete-lines")
    sys.exit(1)
out_lines = [numbered[k] for k in range(1, expected_n + 1)]
try:
    ag = json.loads(os.environ["AG_AFTER"])["result"]["agent"]
    ag_ok = (ag.get("pane_id") == os.environ["TARGET_PANE"] and ag.get("agent") == "agy" and ag.get("agent_status") == "blocked")
except Exception:
    ag_ok = False
info_after = inspect_editor(scr_after)
no_exp = (not info_after["frame"]) and ("Expanded Tool Permission Editor" not in scr_after) and ("Full Command" not in scr_after)
if not (ag_ok and no_exp and has_collapsed_prompt(scr_after)):
    print("UNSUPPORTED cursor-not-1")
    sys.exit(1)
for line in out_lines:
    print(line)
print("OK cursor=1")
sys.exit(0)
'

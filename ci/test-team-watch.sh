#!/usr/bin/env bash
# scripts/team-watch.sh · scripts/prompt-read.sh 단위 테스트.
# ci/mock/herdr(모의)와 가짜 pane ID(wT:*), 임시 메인 git 저장소만 쓰며 실제 팀에 닿지 않는다.
set -u

unset CF_EXTERNAL_LEAD CF_WORK_ROOT CLAUDE_CODE_SESSION_ID HERDR_ENV HERDR_PANE_ID HERDR_WORKSPACE_ID HERDR_TAB_ID

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ORIG_WATCH="${ROOT}/scripts/team-watch.sh"
ORIG_PROMPT_READ="${ROOT}/scripts/prompt-read.sh"
MOCK_DIR="${ROOT}/ci/mock"
TEST_BASH="${TEAM_WATCH_BASH:-${TEAM_UP_BASH:-bash}}"

REAL_LOCK="${ROOT}/.local/team/external-lead"
REAL_LOCK_BEFORE="none"
if [ -f "${REAL_LOCK}" ]; then
	REAL_LOCK_BEFORE="$(shasum -a 256 "${REAL_LOCK}" | cut -d' ' -f1)"
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cf-team-watch-test.XXXXXX")" || exit 1
TEST_ISSUE_NUM="999999"
TEST_ROUND_SUB="r$$"
TEST_ROUND_ID="i${TEST_ISSUE_NUM}-${TEST_ROUND_SUB}"

cleanup() {
	TMP_TARGET="${TMP}" ROUND_PREFIX="/tmp/cf-${TEST_ROUND_ID}" python3 -c '
import glob, os, shutil
t = os.environ.get("TMP_TARGET", "")
if t and os.path.isdir(t) and ("cf-team-watch-test." in t):
    shutil.rmtree(t, ignore_errors=True)
rp = os.environ.get("ROUND_PREFIX", "")
if rp and rp.startswith("/tmp/cf-i999999-r"):
    for p in glob.glob(rp + "*"):
        if os.path.isdir(p):
            shutil.rmtree(p, ignore_errors=True)
        elif os.path.exists(p):
            os.remove(p)
' 2>/dev/null || true
}
trap cleanup EXIT

export PATH="${MOCK_DIR}:${PATH}"
if [ "$(command -v herdr)" != "${MOCK_DIR}/herdr" ]; then
	echo "FATAL: herdr가 모의(${MOCK_DIR}/herdr)가 아니다: $(command -v herdr)" >&2
	exit 1
fi

STATE="${TMP}/state.json"
LOG="${TMP}/calls.log"
T=$'\t'
PASS=0
FAIL=0
CASE=""
OUT=""
RC=0

EXT_SID="a1b2c3d4-0000-4000-8000-000000000001"
OTHER_SID="deadbeef-9999-4000-8000-000000000002"
IMPL_SID="01a126cd-0000-4000-8000-000000000001"
CRITIC_SID="c0d3c0d3-0000-4000-8000-000000000001"

# 임시 메인 git 저장소 및 연결 worktree 구성 (실제 저장소 .local/team/external-lead 보호)
TEST_REPO_RAW="${TMP}/repo"
WT_LINKED="${TMP}/wt-linked"
mkdir -p "${TEST_REPO_RAW}/scripts" "${TEST_REPO_RAW}/.claude/worktrees/w1" "${TEST_REPO_RAW}/.local/team"
cp "${ORIG_WATCH}" "${TEST_REPO_RAW}/scripts/team-watch.sh"
cp "${ORIG_PROMPT_READ}" "${TEST_REPO_RAW}/scripts/prompt-read.sh"
chmod +x "${TEST_REPO_RAW}/scripts/team-watch.sh" "${TEST_REPO_RAW}/scripts/prompt-read.sh"

(
	cd "${TEST_REPO_RAW}" &&
		HOME="${TMP}" XDG_CONFIG_HOME="${TMP}" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git init -q -b main &&
		printf '.local/\n.claude/\n' >.gitignore &&
		printf 'allowed\n' >allowed.txt &&
		HOME="${TMP}" XDG_CONFIG_HOME="${TMP}" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git add .gitignore allowed.txt scripts/team-watch.sh scripts/prompt-read.sh &&
		HOME="${TMP}" XDG_CONFIG_HOME="${TMP}" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -c user.name=t -c user.email=t@t commit -q -m init &&
		HOME="${TMP}" XDG_CONFIG_HOME="${TMP}" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git update-ref refs/remotes/origin/main HEAD &&
		HOME="${TMP}" XDG_CONFIG_HOME="${TMP}" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git worktree add -q "${WT_LINKED}" -b linked
) || exit 1

TEST_REPO="$(cd "${TEST_REPO_RAW}" && pwd -P)"
WATCH_SCRIPT="${TEST_REPO}/scripts/team-watch.sh"
PROMPT_SCRIPT="${TEST_REPO}/scripts/prompt-read.sh"
EXT_LOCK="${TEST_REPO}/.local/team/external-lead"
printf '%s\n' "${EXT_SID}" >"${EXT_LOCK}"

git_test() {
	HOME="${TMP}" XDG_CONFIG_HOME="${TMP}" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
		git -C "${TEST_REPO}" "$@"
}

wait_watch_ready() {
	local out_file="$1"
	local tries=0
	while [ ! -s "${out_file}" ] && [ "${tries}" -lt 80 ]; do
		sleep 0.05
		tries=$((tries + 1))
	done
}

# 가짜 작업공간/pane ID (wT:p1, wT:p2, wT:p3 — 실제 wN:* 사용 금지)
VICE_SPEC="wT:p1|wT|CF 부팀장 · Claude|claude|cf-vice|${TEST_REPO}|vice-sid-1"
IMPL_SPEC="wT:p2|wT|CF 구현 · agy|agy|cf-impl|${TEST_REPO}|${IMPL_SID}"
CRITIC_SPEC="wT:p3|wT|CF 검토 · Codex|codex|cf-critic|${TEST_REPO}|${CRITIC_SID}"

mkstate() {
	python3 - "$@" >"${STATE}" <<'PY'
import json, sys
panes = []
for s in sys.argv[1:]:
    pid, ws, label, agent, name, cwd, sid, status = (s.split("|") + [""] * 8)[:8]
    p = {
        "pane_id": pid,
        "workspace_id": ws,
        "tab_id": ws + ":t1",
        "cwd": cwd,
        "foreground_cwd": cwd,
        "screen": "",
    }
    if label:
        p["label"] = label
    if agent:
        p["agent"] = agent
        p["agent_status"] = status or "idle"
    if name:
        p["name"] = name
    if sid:
        p["agent_session"] = {"value": sid}
    panes.append(p)
json.dump({"panes": panes, "next": 1}, sys.stdout, ensure_ascii=False, indent=1)
PY
}

patch_pane() {
	local pid="$1"
	local py_patch="$2"
	STATE_FILE="${STATE}" TARGET_PID="${pid}" PY_PATCH="${py_patch}" python3 -c '
import json, os
path = os.environ["STATE_FILE"]
pid = os.environ["TARGET_PID"]
patch = json.loads(os.environ["PY_PATCH"])
with open(path, "r", encoding="utf-8") as f:
    st = json.load(f)
for p in st.get("panes", []):
    if p.get("pane_id") == pid:
        for k, v in patch.items():
            if v is None:
                p.pop(k, None)
            else:
                p[k] = v
tmp_path = f"{path}.tmp.{os.getpid()}"
with open(tmp_path, "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
os.replace(tmp_path, path)
'
}

pass() { PASS=$((PASS + 1)); }
fail() {
	FAIL=$((FAIL + 1))
	printf 'FAIL [%s] %s\n  OUT: %s\n' "${CASE}" "$1" "${OUT}" >&2
}

check() {
	local label="$1" op="$2"
	shift 2
	case "${op}" in
	eq) [ "$1" = "$2" ] && pass || fail "${label}: '$1' != '$2'" ;;
	has) printf '%s\n' "${OUT}" | grep -qF -- "$1" && pass || fail "${label}: '${1}' 없음" ;;
	not_has) ! printf '%s\n' "${OUT}" | grep -qF -- "$1" && pass || fail "${label}: '${1}' 있으면 안 됨" ;;
	last_line)
		local last=""
		last="$(printf '%s\n' "${OUT}" | tail -n 1)"
		[ "${last}" = "$1" ] && pass || fail "${label}: 마지막 줄 '${last}' != '$1'"
		;;
	first_line_prefix)
		local first=""
		first="$(printf '%s\n' "${OUT}" | head -n 1)"
		case "${first}" in
		"$1"*) pass ;;
		*) fail "${label}: 첫 줄 '${first}'이 '$1'로 시작하지 않음" ;;
		esac
		;;
	test) test "$@" && pass || fail "${label}: test $*" ;;
	esac
}

run_prompt_ext() {
	: >"${LOG}"
	OUT="$(cd "${TEST_REPO}" && env -u HERDR_ENV -u HERDR_PANE_ID -u HERDR_WORKSPACE_ID -u HERDR_TAB_ID \
		CF_EXTERNAL_LEAD=1 CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
		MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
		"${TEST_BASH}" "${PROMPT_SCRIPT}" "$@" 2>&1)"
	RC=$?
}

# ===========================================================================
# 1. prompt-read.sh 단위 시험
# ===========================================================================

CASE="prompt-read: 부팀장 형태(HERDR_PANE_ID 있음) 거부 · herdr 호출 0"
mkstate "${VICE_SPEC}" "${IMPL_SPEC}|blocked" "${CRITIC_SPEC}"
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && env HERDR_ENV=1 HERDR_PANE_ID=wT:p1 \
	MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
	"${TEST_BASH}" "${PROMPT_SCRIPT}" wT:p2 2>&1)"
RC=$?
check "부팀장(CF_EXTERNAL_LEAD 없음) rc 1" eq "${RC}" 1
check "부팀장 상태 줄" last_line "UNSUPPORTED session-guard:herdr-pane"
check "부팀장 herdr 호출 0" eq "$(wc -l <"${LOG}" | tr -d ' ')" 0

: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && env HERDR_ENV=1 HERDR_PANE_ID=wT:p1 CF_EXTERNAL_LEAD=1 CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
	"${TEST_BASH}" "${PROMPT_SCRIPT}" wT:p2 2>&1)"
RC=$?
check "HERDR_PANE_ID + CF_EXTERNAL_LEAD=1 rc 1" eq "${RC}" 1
check "HERDR_PANE_ID 거부 상태 줄" last_line "UNSUPPORTED session-guard:herdr-pane"
check "HERDR_PANE_ID herdr 호출 0" eq "$(wc -l <"${LOG}" | tr -d ' ')" 0

CASE="prompt-read: 세션 가드(CF_EXTERNAL_LEAD 없음 / 세션 ID 없음 / 기록 없음 / 기록 불일치 / worktree) 거부"
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && env -u HERDR_PANE_ID -u CF_EXTERNAL_LEAD CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
	"${TEST_BASH}" "${PROMPT_SCRIPT}" wT:p2 2>&1)"
RC=$?
check "CF_EXTERNAL_LEAD 없음 rc 1" eq "${RC}" 1
check "CF_EXTERNAL_LEAD 없음 상태 줄" last_line "UNSUPPORTED session-guard:not-external-lead"
check "CF_EXTERNAL_LEAD 없음 herdr 호출 0" eq "$(wc -l <"${LOG}" | tr -d ' ')" 0

: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && env -u HERDR_PANE_ID -u CLAUDE_CODE_SESSION_ID CF_EXTERNAL_LEAD=1 \
	MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
	"${TEST_BASH}" "${PROMPT_SCRIPT}" wT:p2 2>&1)"
RC=$?
check "CLAUDE_CODE_SESSION_ID 없음 rc 1" eq "${RC}" 1
check "CLAUDE_CODE_SESSION_ID 없음 상태 줄" last_line "UNSUPPORTED session-guard:missing-session-id"
check "CLAUDE_CODE_SESSION_ID 없음 herdr 호출 0" eq "$(wc -l <"${LOG}" | tr -d ' ')" 0

rm -f "${EXT_LOCK}"
run_prompt_ext wT:p2
check "기록 없음 rc 1" eq "${RC}" 1
check "기록 없음 상태 줄" last_line "UNSUPPORTED session-guard:no-record"
check "기록 없음 herdr 호출 0" eq "$(wc -l <"${LOG}" | tr -d ' ')" 0

printf '%s\n' "${OTHER_SID}" >"${EXT_LOCK}"
run_prompt_ext wT:p2
check "기록 불일치 rc 1" eq "${RC}" 1
check "기록 불일치 상태 줄" last_line "UNSUPPORTED session-guard:record-mismatch"
check "기록 불일치 herdr 호출 0" eq "$(wc -l <"${LOG}" | tr -d ' ')" 0
printf '%s\n' "${EXT_SID}" >"${EXT_LOCK}"

: >"${LOG}"
OUT="$(cd "${WT_LINKED}" && env -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
	"${TEST_BASH}" "${WT_LINKED}/scripts/prompt-read.sh" wT:p2 2>&1)"
RC=$?
check "연결 worktree rc 1" eq "${RC}" 1
check "연결 worktree 상태 줄" last_line "UNSUPPORTED session-guard:worktree"
check "연결 worktree herdr 호출 0" eq "$(wc -l <"${LOG}" | tr -d ' ')" 0

: >"${LOG}"
OUT="$(cd "${TEST_REPO}/.claude/worktrees/w1" && env -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
	"${TEST_BASH}" "${PROMPT_SCRIPT}" wT:p2 2>&1)"
RC=$?
check ".claude/worktrees rc 1" eq "${RC}" 1
check ".claude/worktrees 상태 줄" last_line "UNSUPPORTED session-guard:worktree"
check ".claude/worktrees herdr 호출 0" eq "$(wc -l <"${LOG}" | tr -d ' ')" 0

CASE="prompt-read: 대상 pane 가드 거부(다른 pane / 본문에만 문구 있고 blocked 아님 / 끝 15줄 밖·메뉴 줄 없음 / Codex 창 / MCP 확인창)"
mkstate "${VICE_SPEC}" "${IMPL_SPEC}|blocked" "${CRITIC_SPEC}|blocked"
patch_pane "wT:p2" '{"screen": "Run this command?\n> 1. Yes, run command\n  2. Always allow\n  3. No"}'
patch_pane "wT:p3" '{"screen": "Allow command?\n> Yes\n  No (Esc)"}'

run_prompt_ext wT:p3
check "Codex pane(wT:p3) 거부 rc 1" eq "${RC}" 1
check "Codex pane 상태 줄" last_line "UNSUPPORTED target-guard:pane-mismatch"
check "Codex pane 키 전송 0" eq "$(grep -cE "^pane${T}send-(keys|text)${T}" "${LOG}")" 0

run_prompt_ext wT:p9
check "없는 pane(wT:p9) 거부 rc 1" eq "${RC}" 1
check "없는 pane 상태 줄" last_line "UNSUPPORTED target-guard:pane-mismatch"
check "없는 pane 키 전송 0" eq "$(grep -cE "^pane${T}send-(keys|text)${T}" "${LOG}")" 0

# 본문에 Run this command? 문구가 있고 blocked 아님(idle / working) → UNSUPPORTED
patch_pane "wT:p2" '{"agent_status": "idle", "screen": "문서 본문: Run this command? 문구 예시\n> 1. Yes, run command"}'
run_prompt_ext wT:p2
check "본문에 문구만 있고 blocked 아님(idle) rc 1" eq "${RC}" 1
check "본문에 문구만 있고 blocked 아님 상태 줄" last_line "UNSUPPORTED target-guard:not-blocked"
check "본문에 문구만 있고 blocked 아님 키 전송 0" eq "$(grep -cE "^pane${T}send-(keys|text)${T}" "${LOG}")" 0

# 상태는 blocked이나 본문 위쪽(끝 15줄 밖)에만 문구가 있거나 > 1. Yes 메뉴 줄이 없는 경우 → UNSUPPORTED
patch_pane "wT:p2" '{"agent_status": "blocked", "screen": "문서 본문: Run this command? 예시만 있고 메뉴 줄 없음\n진행 중..."}'
run_prompt_ext wT:p2
check "blocked이나 메뉴 줄(> 1. Yes) 없음 rc 1" eq "${RC}" 1
check "blocked이나 메뉴 줄 없음 상태 줄" last_line "UNSUPPORTED target-guard:not-agy-command-prompt"
check "blocked이나 메뉴 줄 없음 키 전송 0" eq "$(grep -cE "^pane${T}send-(keys|text)${T}" "${LOG}")" 0

patch_pane "wT:p2" '{"agent_status": "blocked", "screen": "Allow MCP tool context7/query-docs?\n> 1. Yes\n  2. No"}'
run_prompt_ext wT:p2
check "MCP 확인창(Run this command? 없음) 거부 rc 1" eq "${RC}" 1
check "MCP 확인창 상태 줄" last_line "UNSUPPORTED target-guard:not-agy-command-prompt"
check "MCP 확인창 키 전송 0" eq "$(grep -cE "^pane${T}send-(keys|text)${T}" "${LOG}")" 0

CASE="prompt-read: ctrl+g 후 Full Command 미표시 → UNEXPANDED (Page Down·esc 미전송)"
patch_pane "wT:p2" '{"agent_status": "blocked", "screen": "Run this command?\n> 1. Yes, run command\n  2. Yes, and always allow in this conversation\n  3. Yes, and always allow (Persist to settings.json)\n  4. No, cancel\n\n  \u2191/\u2193 Navigate \u00b7 tab Amend \u00b7 ctrl+g edit/expand command", "expanded_pages": []}'
run_prompt_ext wT:p2
check "UNEXPANDED rc 1" eq "${RC}" 1
check "UNEXPANDED 상태 줄" eq "${OUT}" "UNEXPANDED"
check "ctrl+g 1회만 전송" eq "$(grep -cE "^pane${T}send-keys${T}wT:p2${T}ctrl\+g$" "${LOG}")" 1
check "Page Down·esc 미전송" eq "$(grep -cE "^pane${T}(send-text|send-keys${T}wT:p2${T}esc)" "${LOG}")" 0

CASE="prompt-read: 잘린 7줄 명령(en dash 1–5 of 7 → 3–7 of 7) blocked→done→blocked 전환 및 완독 후 esc·OK cursor=1"
PAGE1="$(printf 'Expanded Tool Permission Editor\n────────────────────\n  Full Command:\n│ cmd_line_1 --alpha │\n│ cmd_line_2 --beta │\n│ cmd_line_3 --gamma │\n│ cmd_line_4 --delta │\n│ cmd_line_5 --eps │\n  (1\xe2\x80\x935 of 7 lines)\n────────────────────\n  Requested Permission (Editable): [\xe2\x86\x93 7]\n> cmd_line_1 --alpha\n  cmd_line_2 --beta\nPress Esc to close')"
PAGE2="$(printf 'Expanded Tool Permission Editor\n────────────────────\n  Full Command:\n│ cmd_line_3 --gamma │\n│ cmd_line_4 --delta │\n│ cmd_line_5 --eps │\n│ cmd_line_6 --zeta │\n│ cmd_line_7 --eta │\n  (3\xe2\x80\x937 of 7 lines)\n────────────────────\n  Requested Permission (Editable): [\xe2\x86\x93 7]\n> cmd_line_1 --alpha\n  cmd_line_2 --beta\nPress Esc to close')"
COLLAPSED="$(printf 'Run this command?\n> 1. Yes, run command\n  2. Yes, and always allow in this conversation for commands that start with '\''cmd_line_1 ...'\''\n  3. Yes, and always allow for commands that start with '\''cmd_line_1 ...'\'' (Persist to settings.json)\n  4. No, cancel\n\n  \xe2\x86\x91/\xe2\x86\x93 Navigate \xc2\xb7 tab Amend \xc2\xb7 ctrl+g edit/expand command')"

pane_status() {
	STATE_FILE="${STATE}" PANE_ID="$1" python3 -c '
import json, os
st = json.load(open(os.environ["STATE_FILE"], encoding="utf-8"))
for p in st["panes"]:
    if p["pane_id"] == os.environ["PANE_ID"]:
        print("%s:%s" % (p.get("agent_status"), p.get("expanded", False)))
'
}

count_pgdn() {
	python3 -c '
import sys
log = open(sys.argv[1], encoding="utf-8").read().splitlines()
print(sum(1 for l in log if l == "pane\tsend-text\twT:p2\t\x1b[6~"))
' "${LOG}"
}

STATE_FILE="${STATE}" P1="${PAGE1}" P2="${PAGE2}" COL="${COLLAPSED}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = os.environ["COL"]
        p["expanded"] = False
        p["expanded_pages"] = [os.environ["P1"], os.environ["P2"]]
        p["screen_after_esc"] = os.environ["COL"]
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
run_prompt_ext wT:p2
EXPECTED_7="$(printf 'cmd_line_1 --alpha\ncmd_line_2 --beta\ncmd_line_3 --gamma\ncmd_line_4 --delta\ncmd_line_5 --eps\ncmd_line_6 --zeta\ncmd_line_7 --eta\nOK cursor=1')"
check "7줄 완독 rc 0" eq "${RC}" 0
check "7줄 전문 + OK cursor=1 정확 일치(구분선 제외)" eq "${OUT}" "${EXPECTED_7}"
check "ctrl+g 1회 전송됨" eq "$(grep -cE "^pane${T}send-keys${T}wT:p2${T}ctrl\+g$" "${LOG}")" 1
check "원시 Page Down(\\x1b[6~) 1회 전송됨" eq "$(count_pgdn)" 1
check "esc 1회 전송됨" eq "$(grep -cE "^pane${T}send-keys${T}wT:p2${T}esc$" "${LOG}")" 1
check "esc 후 상태 blocked·expanded=False 복귀" eq "$(pane_status wT:p2)" "blocked:False"
check "대상 pane(wT:p2) 밖으로 간 키 0" eq "$(grep -E "^pane${T}send-(keys|text)${T}" "${LOG}" | grep -vcE "^pane${T}send-(keys|text)${T}wT:p2${T}")" 0
check "응답 키(1/enter) 전송 0" eq "$(grep -cE "^pane${T}send-(keys|text)${T}wT:p2${T}(1|enter)" "${LOG}")" 0

CASE="prompt-read: 키마다 대상 가드 재확인(ctrl+g 직후 상태가 working으로 바뀌면 Page Down·esc 차단)"
STATE_FILE="${STATE}" P1="${PAGE1}" P2="${PAGE2}" COL="${COLLAPSED}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = os.environ["COL"]
        p["expanded"] = False
        p["expanded_pages"] = [os.environ["P1"], os.environ["P2"]]
        p["on_key"] = [{"agent_status": "working"}]
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
run_prompt_ext wT:p2
check "경합 시 rc 1" eq "${RC}" 1
check "경합 시 상태 줄 not-blocked" last_line "UNSUPPORTED target-guard:not-blocked"
check "경합 시 ctrl+g 1회만 전송" eq "$(grep -cE "^pane${T}send-keys${T}wT:p2${T}ctrl\+g$" "${LOG}")" 1
check "ctrl+g 뒤 Page Down·esc 전송 0" eq "$(grep -cE "^pane${T}(send-text|send-keys${T}wT:p2${T}esc)" "${LOG}")" 0

CASE="prompt-read: F1 단일 페이지 heredoc(앞뒤 공백·리터럴 파이프·연속 중복 줄·빈 줄) 원문 보존"
STATE_FILE="${STATE}" COL="${COLLAPSED}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
page = (
    "Expanded Tool Permission Editor\n"
    "\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n"
    "  Full Command:\n"
    "cat <<'\''EOF'\''\n  keep spaces  \n|literal pipes|\nsame\nsame\n\nEOF\n"
    "  (1\u20137 of 7 lines)\n"
    "\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n"
    "  Requested Permission (Editable): [\u2193 7]\n"
    "> cat <<'\''EOF'\''\n"
    "Press Esc to close"
)
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = os.environ["COL"]
        p["expanded"] = False
        p["expanded_pages"] = [page]
        p["screen_after_esc"] = os.environ["COL"]
        p.pop("on_key", None)
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
run_prompt_ext wT:p2
EXPECTED_HEREDOC="$(printf "cat <<'EOF'\n  keep spaces  \n|literal pipes|\nsame\nsame\n\nEOF\nOK cursor=1")"
check "heredoc 원문 보존 rc 0" eq "${RC}" 0
check "heredoc 원문(공백·파이프·중복 줄·빈 줄) 정확 일치" eq "${OUT}" "${EXPECTED_HEREDOC}"
check "단일 페이지 ctrl+g 1회·PgDn 0회·esc 1회" eq "$(grep -cE "^pane${T}send-keys${T}wT:p2${T}ctrl\+g$" "${LOG}"):$(count_pgdn):$(grep -cE "^pane${T}send-keys${T}wT:p2${T}esc$" "${LOG}")" "1:0:1"
check "단일 페이지 완료 후 blocked 복귀" eq "$(pane_status wT:p2)" "blocked:False"

CASE="prompt-read: F1 다중 페이지(빈 줄·동일 줄·앞뒤 공백·파이프) 줄 범위 병합 보존"
STATE_FILE="${STATE}" COL="${COLLAPSED}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
p1 = (
    "Expanded Tool Permission Editor\n\u2500\u2500\u2500\u2500\n  Full Command:\n"
    "cat <<'\''EOF'\''\n  indent_line  \nrepeat_line\n\n"
    "  (1\u20134 of 6 lines)\n\u2500\u2500\u2500\u2500\n"
    "  Requested Permission (Editable): [\u2193 6]\n> cat <<'\''EOF'\''\nPress Esc to close"
)
p2 = (
    "Expanded Tool Permission Editor\n\u2500\u2500\u2500\u2500\n  Full Command:\n"
    "repeat_line\n\nrepeat_line\nEOF | tee out\n"
    "  (3\u20136 of 6 lines)\n\u2500\u2500\u2500\u2500\n"
    "  Requested Permission (Editable): [\u2193 6]\n> cat <<'\''EOF'\''\nPress Esc to close"
)
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = os.environ["COL"]
        p["expanded"] = False
        p["expanded_pages"] = [p1, p2]
        p["screen_after_esc"] = os.environ["COL"]
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
run_prompt_ext wT:p2
EXPECTED_MP="$(printf "cat <<'EOF'\n  indent_line  \nrepeat_line\n\nrepeat_line\nEOF | tee out\nOK cursor=1")"
check "다중 페이지 빈 줄·중복 줄 병합 rc 0" eq "${RC}" 0
check "다중 페이지 빈 줄·중복 줄 전문 정확 일치" eq "${OUT}" "${EXPECTED_MP}"
check "다중 페이지 ctrl+g 1회·PgDn 1회·esc 1회" eq "$(grep -cE "^pane${T}send-keys${T}wT:p2${T}ctrl\+g$" "${LOG}"):$(count_pgdn):$(grep -cE "^pane${T}send-keys${T}wT:p2${T}esc$" "${LOG}")" "1:1:1"
check "다중 페이지 완료 후 blocked 복귀" eq "$(pane_status wT:p2)" "blocked:False"

CASE="prompt-read: F1 줄 복원 불확실(표시 줄 수 != b-a+1) 시 성공 전문 미출력·esc 닫기·UNSUPPORTED 반환"
STATE_FILE="${STATE}" COL="${COLLAPSED}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
bad_page = (
    "Expanded Tool Permission Editor\n\u2500\u2500\u2500\u2500\n  Full Command:\n"
    "only_line_1\nonly_line_2\n"
    "  (1\u20135 of 5 lines)\n\u2500\u2500\u2500\u2500\n"
    "  Requested Permission (Editable): [\u2193 5]\n> only_line_1\nPress Esc to close"
)
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = os.environ["COL"]
        p["expanded"] = False
        p["expanded_pages"] = [bad_page]
        p["screen_after_esc"] = os.environ["COL"]
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
run_prompt_ext wT:p2
check "줄 수 불일치 rc 1" eq "${RC}" 1
check "줄 수 불일치 UNSUPPORTED line-count-mismatch 단독 출력" eq "${OUT}" "UNSUPPORTED line-count-mismatch"
check "줄 수 불일치 시 ctrl+g 1회·PgDn 0회·esc 1회" eq "$(grep -cE "^pane${T}send-keys${T}wT:p2${T}ctrl\+g$" "${LOG}"):$(count_pgdn):$(grep -cE "^pane${T}send-keys${T}wT:p2${T}esc$" "${LOG}")" "1:0:1"
check "줄 수 불일치 시 esc 후 blocked 복귀" eq "$(pane_status wT:p2)" "blocked:False"

CASE="prompt-read: F2 31페이지(상한 30 초과 미완독) 시 done 상태에서 esc로 닫고 blocked 복귀·UNSUPPORTED page-limit-exceeded 반환"
STATE_FILE="${STATE}" COL="${COLLAPSED}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
pages_31 = [
    f"Expanded Tool Permission Editor\n\u2500\u2500\u2500\u2500\n  Full Command:\ncommand_line_{i}\n  ({i}\u2013{i} of 31 lines)\n\u2500\u2500\u2500\u2500\n  Requested Permission (Editable): [\u2193 31]\n> command_line_1\nPress Esc to close"
    for i in range(1, 32)
]
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = os.environ["COL"]
        p["expanded"] = False
        p["expanded_pages"] = pages_31
        p["screen_after_esc"] = os.environ["COL"]
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
run_prompt_ext wT:p2
check "31페이지 미완독 rc 1" eq "${RC}" 1
check "31페이지 미완독 UNSUPPORTED page-limit-exceeded 단독 출력(부분 전문 미출력)" eq "${OUT}" "UNSUPPORTED page-limit-exceeded"
check "31페이지 실패 시 ctrl+g 1회·PgDn 29회·esc 1회" eq "$(grep -cE "^pane${T}send-keys${T}wT:p2${T}ctrl\+g$" "${LOG}"):$(count_pgdn):$(grep -cE "^pane${T}send-keys${T}wT:p2${T}esc$" "${LOG}")" "1:29:1"
check "31페이지 실패 시 esc 후 blocked 복귀" eq "$(pane_status wT:p2)" "blocked:False"
check "31페이지 실패 시 대상 pane 밖 키 전송 0" eq "$(grep -E "^pane${T}send-(keys|text)${T}" "${LOG}" | grep -vcE "^pane${T}send-(keys|text)${T}wT:p2${T}")" 0

CASE="prompt-read: F2 Page Down 후 페이지 이동 정체(b 미증가) 시 esc 닫기·UNSUPPORTED page-stall 반환"
STATE_FILE="${STATE}" COL="${COLLAPSED}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
stall_page = (
    "Expanded Tool Permission Editor\n\u2500\u2500\u2500\u2500\n  Full Command:\n"
    "cmd_1\ncmd_2\ncmd_3\n  (1\u20133 of 6 lines)\n\u2500\u2500\u2500\u2500\n"
    "  Requested Permission (Editable): [\u2193 6]\n> cmd_1\nPress Esc to close"
)
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = os.environ["COL"]
        p["expanded"] = False
        p["expanded_pages"] = [stall_page, stall_page]
        p["screen_after_esc"] = os.environ["COL"]
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
run_prompt_ext wT:p2
check "페이지 정체 rc 1" eq "${RC}" 1
check "페이지 정체 UNSUPPORTED page-stall 단독 출력" eq "${OUT}" "UNSUPPORTED page-stall"
check "페이지 정체 시 ctrl+g 1회·PgDn 1회·esc 1회" eq "$(grep -cE "^pane${T}send-keys${T}wT:p2${T}ctrl\+g$" "${LOG}"):$(count_pgdn):$(grep -cE "^pane${T}send-keys${T}wT:p2${T}esc$" "${LOG}")" "1:1:1"
check "페이지 정체 시 esc 후 blocked 복귀" eq "$(pane_status wT:p2)" "blocked:False"

CASE="prompt-read: ③ 무범위 화면 회귀 3건 — (1) 실화면 틀(①+②+본문+④+편집칸+footer, ③ 제외) → esc 닫고 blocked 복귀·UNSUPPORTED"
for subcase in esc_heredoc rule_heredoc rp_heredoc; do
	STATE_FILE="${STATE}" COL="${COLLAPSED}" SUB="${subcase}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
sub = os.environ["SUB"]
if sub == "esc_heredoc":
    cmd = "cat <<'\''EOF'\''\nPress Esc to close\nEOF\nprintf '\''after heredoc\\n'\''"
elif sub == "rule_heredoc":
    cmd = "cat <<'\''EOF'\''\nbefore\n\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\nafter\nEOF"
else:
    cmd = "cat <<'\''Requested Permission'\''\nhello\nRequested Permission"
page = (
    "Expanded Tool Permission Editor\n\u2500\u2500\u2500\u2500\n  Full Command:\n"
    + cmd + "\n\u2500\u2500\u2500\u2500\n"
    "  Requested Permission (Editable): [\u2193 4]\n> " + cmd.splitlines()[0] + "\nPress Esc to close"
)
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = os.environ["COL"]
        p["expanded"] = False
        p["expanded_pages"] = [page]
        p["screen_after_esc"] = os.environ["COL"]
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
	run_prompt_ext wT:p2
	check "실화면 틀 무범위(${subcase}) rc 1" eq "${RC}" 1
	check "실화면 틀 무범위(${subcase}) 부분 전문 미출력·UNSUPPORTED missing-line-range 단독 출력" eq "${OUT}" "UNSUPPORTED missing-line-range"
	check "실화면 틀 무범위(${subcase}) ctrl+g 1회·PgDn 0회·esc 1회" eq "$(grep -cE "^pane${T}send-keys${T}wT:p2${T}ctrl\+g$" "${LOG}"):$(count_pgdn):$(grep -cE "^pane${T}send-keys${T}wT:p2${T}esc$" "${LOG}")" "1:0:1"
	check "실화면 틀 무범위(${subcase}) esc 후 blocked 복귀" eq "$(pane_status wT:p2)" "blocked:False"
done

CASE="prompt-read: ③ 무범위 화면 회귀 3건 — (2) 옛 REPRO 원문 모양(Full Command:..Press Esc to close, 머리줄 없음) → ctrl+g 1회·esc 0회·UNSUPPORTED"
for subcase in esc_heredoc rule_heredoc rp_heredoc; do
	STATE_FILE="${STATE}" COL="${COLLAPSED}" SUB="${subcase}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
sub = os.environ["SUB"]
if sub == "esc_heredoc":
    cmd = "cat <<'\''EOF'\''\nPress Esc to close\nEOF\nprintf '\''after heredoc\\n'\''"
elif sub == "rule_heredoc":
    cmd = "cat <<'\''EOF'\''\nbefore\n\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\nafter\nEOF"
else:
    cmd = "cat <<'\''Requested Permission'\''\nhello\nRequested Permission"
page = "Full Command:\n" + cmd + "\nPress Esc to close"
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = os.environ["COL"]
        p["expanded"] = False
        p["expanded_pages"] = [page]
        p["screen_after_esc"] = os.environ["COL"]
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
	run_prompt_ext wT:p2
	check "옛 REPRO 무틀(${subcase}) rc 1" eq "${RC}" 1
	check "옛 REPRO 무틀(${subcase}) 부분 전문 미출력·UNSUPPORTED 단독 출력" eq "${OUT}" "UNSUPPORTED expanded-frame-not-found-after-ctrl-g"
	check "옛 REPRO 무틀(${subcase}) ctrl+g 1회·PgDn 0회·esc 0회" eq "$(grep -cE "^pane${T}send-keys${T}wT:p2${T}ctrl\+g$" "${LOG}"):$(count_pgdn):$(grep -cE "^pane${T}send-keys${T}wT:p2${T}esc$" "${LOG}")" "1:0:0"
done

CASE="prompt-read: 교정 1·1b·보충 — 본문 문구 오인 차단(done 본문 문구 키 0 / 중복 머리줄·역순 차단 / 본문 4줄+아래 일반출력·입력란 차단)"
# (a) 상태 done이고 본문에 Full Command 및 구조 문구 일부가 있는 화면 → 키 0, UNSUPPORTED
STATE_FILE="${STATE}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "done"
        p["screen"] = "DIRECTIVE 본문:\nFull Command:\n(1\u20135 of 74 lines)\nRequested Permission (Editable)"
        p["expanded"] = False
        p["expanded_pages"] = []
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
run_prompt_ext wT:p2
check "done + 본문 Full Command 문구 rc 1" eq "${RC}" 1
check "done + 본문 Full Command 문구 UNSUPPORTED" eq "${OUT}" "UNSUPPORTED target-guard:not-blocked"
check "done + 본문 Full Command 문구 키 전송 0" eq "$(grep -cE "^pane${T}send-(keys|text)${T}" "${LOG}")" 0

# (b) ctrl+g 뒤 머리줄이 둘 이상이거나 순서가 어긋난 화면 → ctrl+g 1회, PgDn·esc 0회, UNSUPPORTED
for bad_kind in dup_hdr wrong_order; do
	STATE_FILE="${STATE}" COL="${COLLAPSED}" KIND="${bad_kind}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
if os.environ["KIND"] == "dup_hdr":
    bad_scr = (
        "Expanded Tool Permission Editor\n"
        "Expanded Tool Permission Editor\n\u2500\u2500\u2500\u2500\n  Full Command:\n"
        "echo hi\n  (1\u20131 of 1 lines)\n\u2500\u2500\u2500\u2500\n"
        "  Requested Permission (Editable): [\u2193 1]\n> echo hi\nPress Esc to close"
    )
else:
    bad_scr = (
        "Expanded Tool Permission Editor\n\u2500\u2500\u2500\u2500\n"
        "  Requested Permission (Editable): [\u2193 1]\n"
        "  Full Command:\necho hi\n  (1\u20131 of 1 lines)\n> echo hi\nPress Esc to close"
    )
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = os.environ["COL"]
        p["expanded"] = False
        p["expanded_pages"] = [bad_scr]
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
	run_prompt_ext wT:p2
	check "구조 불일치(${bad_kind}) rc 1" eq "${RC}" 1
	check "구조 불일치(${bad_kind}) UNSUPPORTED 단독 출력" eq "${OUT}" "UNSUPPORTED expanded-frame-not-found-after-ctrl-g"
	check "구조 불일치(${bad_kind}) ctrl+g 1회·PgDn 0회·esc 0회" eq "$(grep -cE "^pane${T}send-keys${T}wT:p2${T}ctrl\+g$" "${LOG}"):$(count_pgdn):$(grep -cE "^pane${T}send-keys${T}wT:p2${T}esc$" "${LOG}")" "1:0:0"
done

# (c) ANSWER §3·§4: 시작은 정상 확인창(blocked) → ctrl+g 뒤 「본문에 네 줄이 순서대로 다 있지만 아래로 일반 출력과 agy 입력란(구분선 사이 >)」(done)으로 바뀜
STATE_FILE="${STATE}" COL="${COLLAPSED}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
body_with_input_box = (
    "Expanded Tool Permission Editor\n"
    "\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n"
    "  Full Command:\n"
    "  python3 -c '\''print(1)'\''\n"
    "  (1\u20131 of 1 lines)\n"
    "\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n"
    "  Requested Permission (Editable): [\u2193 1]\n"
    "> python3 -c '\''print(1)'\''\n"
    "Press Esc to close\n"
    "\u25cf Reading CORRECTION-r4-1.md completed.\n"
    "\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n"
    "> \n"
    "\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500"
)
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = os.environ["COL"]
        p["expanded"] = False
        p["expanded_pages"] = [body_with_input_box]
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
run_prompt_ext wT:p2
check "본문 4줄+아래 일반출력·입력란(ctrl+g 후 done) rc 1" eq "${RC}" 1
check "본문 4줄+아래 일반출력·입력란 부분 전문 미출력·UNSUPPORTED 단독 출력" eq "${OUT}" "UNSUPPORTED expanded-frame-not-found-after-ctrl-g"
check "본문 4줄+아래 일반출력·입력란 ctrl+g 1회·PgDn 0회·esc 0회" eq "$(grep -cE "^pane${T}send-keys${T}wT:p2${T}ctrl\+g$" "${LOG}"):$(count_pgdn):$(grep -cE "^pane${T}send-keys${T}wT:p2${T}esc$" "${LOG}")" "1:0:0"

CASE="prompt-read: i3-r5 편집기 경계 모호성 거부 (a: STATIC-F1 가짜 범위+RP / b: 가짜 범위만 2개 / c: 1쪽 정상·2쪽 가짜 범위)"
# (a) STATIC-F1.md 반례: 본문에 가짜 (1–1 of 1 lines) + 가짜 Requested Permission (Editable):, 실제 UI 범위 (1–6 of 6 lines)
STATE_FILE="${STATE}" COL="${COLLAPSED}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
static_f1_page = (
    "Expanded Tool Permission Editor\n\u2500\u2500\u2500\u2500\n  Full Command:\n"
    "cat <<'\''EOF'\''\n(1\u20131 of 1 lines)\nRequested Permission (Editable):\n> heredoc text\nEOF\nprintf '\''after\\n'\''\n"
    "  (1\u20136 of 6 lines)\n\u2500\u2500\u2500\u2500\n"
    "  Requested Permission (Editable): [\u2193 6]\n> cat <<'\''EOF'\''\nPress Esc to close"
)
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = os.environ["COL"]
        p["expanded"] = False
        p["expanded_pages"] = [static_f1_page]
        p["screen_after_esc"] = os.environ["COL"]
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
run_prompt_ext wT:p2
check "r5(a) STATIC-F1 가짜 범위+RP rc 1" eq "${RC}" 1
check "r5(a) STATIC-F1 부분 전문 미출력·UNSUPPORTED ambiguous-editor-boundary 단독 출력" eq "${OUT}" "UNSUPPORTED ambiguous-editor-boundary"
check "r5(a) STATIC-F1 기대 키 수 ctrl+g 1회·PgDn 0회·esc 1회" eq "$(grep -cE "^pane${T}send-keys${T}wT:p2${T}ctrl\+g$" "${LOG}"):$(count_pgdn):$(grep -cE "^pane${T}send-keys${T}wT:p2${T}esc$" "${LOG}")" "1:0:1"
check "r5(a) STATIC-F1 esc 후 blocked 복귀" eq "$(pane_status wT:p2)" "blocked:False"

# (b) 본문에 가짜 범위 줄만 있고 RP 줄은 하나인 화면
STATE_FILE="${STATE}" COL="${COLLAPSED}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
dup_range_page = (
    "Expanded Tool Permission Editor\n\u2500\u2500\u2500\u2500\n  Full Command:\n"
    "cat <<'\''EOF'\''\n(1\u20131 of 1 lines)\nEOF\nprintf '\''after\\n'\''\n"
    "  (1\u20134 of 4 lines)\n\u2500\u2500\u2500\u2500\n"
    "  Requested Permission (Editable): [\u2193 4]\n> cat <<'\''EOF'\''\nPress Esc to close"
)
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = os.environ["COL"]
        p["expanded"] = False
        p["expanded_pages"] = [dup_range_page]
        p["screen_after_esc"] = os.environ["COL"]
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
run_prompt_ext wT:p2
check "r5(b) 가짜 범위 줄만 2개 rc 1" eq "${RC}" 1
check "r5(b) 가짜 범위 줄만 2개 부분 전문 미출력·UNSUPPORTED ambiguous-editor-boundary 단독 출력" eq "${OUT}" "UNSUPPORTED ambiguous-editor-boundary"
check "r5(b) 가짜 범위 줄만 2개 기대 키 수 ctrl+g 1회·PgDn 0회·esc 1회" eq "$(grep -cE "^pane${T}send-keys${T}wT:p2${T}ctrl\+g$" "${LOG}"):$(count_pgdn):$(grep -cE "^pane${T}send-keys${T}wT:p2${T}esc$" "${LOG}")" "1:0:1"
check "r5(b) 가짜 범위 줄만 2개 esc 후 blocked 복귀" eq "$(pane_status wT:p2)" "blocked:False"

# (c) 교정 i3-r5 (1): 1쪽은 정상(1–4 of 6)이고, PgDn 뒤 2쪽(3–6 of 6) 본문에 가짜 범위 줄이 나오는 화면
STATE_FILE="${STATE}" COL="${COLLAPSED}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
p1_ok = (
    "Expanded Tool Permission Editor\n\u2500\u2500\u2500\u2500\n  Full Command:\n"
    "cat <<'\''EOF'\''\nline_2\nline_3\nline_4\n"
    "  (1\u20134 of 6 lines)\n\u2500\u2500\u2500\u2500\n"
    "  Requested Permission (Editable): [\u2193 6]\n> cat <<'\''EOF'\''\nPress Esc to close"
)
p2_ambig = (
    "Expanded Tool Permission Editor\n\u2500\u2500\u2500\u2500\n  Full Command:\n"
    "line_3\nline_4\n(1\u20131 of 1 lines)\nEOF\n"
    "  (3\u20136 of 6 lines)\n\u2500\u2500\u2500\u2500\n"
    "  Requested Permission (Editable): [\u2193 6]\n> cat <<'\''EOF'\''\nPress Esc to close"
)
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = os.environ["COL"]
        p["expanded"] = False
        p["expanded_pages"] = [p1_ok, p2_ambig]
        p["screen_after_esc"] = os.environ["COL"]
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
run_prompt_ext wT:p2
check "r5(c) 1쪽 정상·2쪽 가짜 범위 줄 rc 1" eq "${RC}" 1
check "r5(c) 1쪽 정상·2쪽 가짜 범위 줄 부분 전문 미출력·UNSUPPORTED ambiguous-editor-boundary 단독 출력" eq "${OUT}" "UNSUPPORTED ambiguous-editor-boundary"
check "r5(c) 1쪽 정상·2쪽 가짜 범위 줄 기대 키 수 ctrl+g 1회·PgDn 1회·esc 1회" eq "$(grep -cE "^pane${T}send-keys${T}wT:p2${T}ctrl\+g$" "${LOG}"):$(count_pgdn):$(grep -cE "^pane${T}send-keys${T}wT:p2${T}esc$" "${LOG}")" "1:1:1"
check "r5(c) 1쪽 정상·2쪽 가짜 범위 줄 esc 후 blocked 복귀" eq "$(pane_status wT:p2)" "blocked:False"


# ===========================================================================
# 2. team-watch.sh 단위 시험
# ===========================================================================

CASE="team-watch: 시작 시 자기 mktemp 사본 exec · 첫 줄 판 출력 · 원본 변경 내성 · trap 정리 · 심장박동"
mkstate "${VICE_SPEC}" "${IMPL_SPEC}|idle" "${CRITIC_SPEC}|idle"
SELF_TMP="${TMP}/self-tmp"
mkdir -p "${SELF_TMP}"
EXPECTED_HASH="$(git_test hash-object "${WATCH_SCRIPT}")"
: >"${LOG}"
WATCH_OUT="${TMP}/watch-self.out"
: >"${WATCH_OUT}"
(
	cd "${TEST_REPO}" &&
		TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
			"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 2 --interval 1 >"${WATCH_OUT}" 2>&1
) &
BG_PID=$!
wait_watch_ready "${WATCH_OUT}"
SELF_COPIES="$(find "${SELF_TMP}" -name 'cf-team-watch-self.*' | wc -l | tr -d ' ')"
check "실행 중 mktemp 자기 사본 존재" eq "${SELF_COPIES}" 1
# 감시 도중 저장소 원본 스크립트를 망가뜨려도 이미 exec된 사본은 정상 종료해야 함
printf '#!/usr/bin/env bash\nexit 99\n' >"${WATCH_SCRIPT}"
wait "${BG_PID}"
RC=$?
OUT="$(cat "${WATCH_OUT}")"
cp "${ORIG_WATCH}" "${WATCH_SCRIPT}"
chmod +x "${WATCH_SCRIPT}"
git_test checkout -- scripts/team-watch.sh
check "원본 변경에도 종료 코드 0" eq "${RC}" 0
check "첫 줄 git hash-object 판 출력" first_line_prefix "team-watch version=${EXPECTED_HASH} mode=general"
check "무사건 heartbeat 출력" last_line "EVENT heartbeat impl=idle critic=idle"
SELF_AFTER="$(find "${SELF_TMP}" -name 'cf-team-watch-self.*' | wc -l | tr -d ' ')"
check "종료 후 trap으로 mktemp 사본 삭제됨" eq "${SELF_AFTER}" 0
check "읽기 전용(키·rename·process-info 호출 0)" eq "$(grep -cE "^(pane${T}(send-keys|send-text|rename|move|split|run|process-info)|agent${T}rename|tab${T}close)" "${LOG}")" 0

CASE="team-watch: 확인창 감지(impl-blocked / critic-blocked) + 본문에만 문구 있고 blocked 아니면 미감지"
# 1) 본문에 Run this command? + > 1. Yes가 있어도 blocked가 아니면(idle) 확인창 사건이 아님 → heartbeat
mkstate "${VICE_SPEC}" "${IMPL_SPEC}|idle" "${CRITIC_SPEC}|idle"
patch_pane "wT:p2" '{"screen": "본문에 Run this command? 문구가 섞임\n> 1. Yes, run command"}'
OUT="$(cd "${TEST_REPO}" && TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
	"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 1 --interval 1 2>&1)"
RC=$?
check "본문에만 문구 있고 blocked 아님 rc 0" eq "${RC}" 0
check "본문에만 문구 있고 blocked 아님 → heartbeat(확인창 사건 아님)" last_line "EVENT heartbeat impl=idle critic=idle"

# 2) cf-impl이 blocked이고 확인창 구조(상태줄 → ctrl+g 안내 줄 → 4. No, cancel → > 1. Yes → Run this command?)가 맞을 때 impl-blocked
mkstate "${VICE_SPEC}" "${IMPL_SPEC}|blocked" "${CRITIC_SPEC}|idle"
patch_pane "wT:p2" '{"screen": "Run this command?\n> 1. Yes, run command\n  2. Yes, and always allow in this conversation for commands that start with '\''secret_cmd_do_not_read'\''\n  3. Yes, and always allow for commands that start with '\''secret_cmd_do_not_read'\'' (Persist to settings.json)\n  4. No, cancel\n\n  \u2191/\u2193 Navigate \u00b7 tab Amend \u00b7 ctrl+g edit/expand command"}'
OUT="$(cd "${TEST_REPO}" && TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
	"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 3 --interval 1 2>&1)"
RC=$?
check "impl-blocked rc 0" eq "${RC}" 0
check "impl-blocked EVENT + 포커스 기록" last_line "EVENT impl-blocked pane=wT:p2 status=blocked focused_pane_id=- zoomed=false active_workspace=wT"
check "확인창 내용 미출력" not_has "secret_cmd_do_not_read"
check "키 전송 0" eq "$(grep -cE "^pane${T}send-" "${LOG}")" 0

# 3) cf-critic은 blocked만으로 critic-blocked
mkstate "${VICE_SPEC}" "${IMPL_SPEC}|idle" "${CRITIC_SPEC}|blocked"
OUT="$(cd "${TEST_REPO}" && TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
	"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 3 --interval 1 2>&1)"
RC=$?
check "critic-blocked rc 0" eq "${RC}" 0
check "critic-blocked EVENT" last_line "EVENT critic-blocked pane=wT:p3 status=blocked focused_pane_id=- zoomed=false active_workspace=wT"

CASE="i3-r6 회귀 시험 (r1~r5): 17줄 긴 메뉴 실화면 원문(68b27838c7b19249) 구조 판정 · 본문 오인 방지 · 안내 줄 누락 · 커서 2번 이동"
REAL_PROMPT_FILE="${TMP}/real-prompt-long-menu.txt"
cat <<'EOF' >"${REAL_PROMPT_FILE}"

Run this command?
> 1. Yes, run command
  2. Yes, and always allow in this conversation for commands that start with
'/opt/local/bin/bash -c 'echo realtest-01
echo realtest-02
echo realtest-03
echo ...'
  3. Yes, and always allow for commands that start with '/opt/local/bin/bash -c 'echo
realtest-01
echo realtest-02
echo realtest-03
echo ...' (Persist to settings.json)
  4. No, cancel

  ↑/↓ Navigate · tab Amend · ctrl+g edit/expand command
esc to cancel        accept-edits · Gemini 4 Argon · high · AI: 939 (/credits to add mo
EOF
check "r6 실화면 원문 sha256(68b27838c7b19249) 일치" eq "$(shasum -a 256 "${REAL_PROMPT_FILE}" | cut -c1-16)" "68b27838c7b19249"

# (r1) 실화면 원문 그대로(17줄) + 상태 blocked → team-watch: EVENT impl-blocked, 키 전송 0
mkstate "${VICE_SPEC}" "${IMPL_SPEC}|blocked" "${CRITIC_SPEC}|idle"
STATE_FILE="${STATE}" RP_FILE="${REAL_PROMPT_FILE}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
raw = open(os.environ["RP_FILE"], "r", encoding="utf-8").read()
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = raw
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
	"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 3 --interval 1 2>&1)"
RC=$?
check "r6(r1) 17줄 실화면 원문 team-watch rc 0" eq "${RC}" 0
check "r6(r1) 17줄 실화면 원문 team-watch EVENT impl-blocked" last_line "EVENT impl-blocked pane=wT:p2 status=blocked focused_pane_id=- zoomed=false active_workspace=wT"
check "r6(r1) 17줄 실화면 원문 team-watch 기대 키 수 0" eq "$(grep -cE "^pane${T}send-(keys|text)${T}" "${LOG}")" 0

# (r2) 같은 17줄 실화면 원문으로 prompt-read 전체 흐름(복귀 화면도 이 원문) → ctrl+g 1회·PgDn 1회·esc 1회, OK cursor=1
STATE_FILE="${STATE}" RP_FILE="${REAL_PROMPT_FILE}" P1="${PAGE1}" P2="${PAGE2}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
raw = open(os.environ["RP_FILE"], "r", encoding="utf-8").read()
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = raw
        p["expanded"] = False
        p["expanded_pages"] = [os.environ["P1"], os.environ["P2"]]
        p["screen_after_esc"] = raw
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
run_prompt_ext wT:p2
check "r6(r2) 17줄 실화면 원문 prompt-read 완독 rc 0" eq "${RC}" 0
check "r6(r2) 17줄 실화면 원문 prompt-read 전문 + OK cursor=1" eq "${OUT}" "${EXPECTED_7}"
check "r6(r2) 17줄 실화면 원문 prompt-read 기대 키 수 ctrl+g 1회·PgDn 1회·esc 1회" eq "$(grep -cE "^pane${T}send-keys${T}wT:p2${T}ctrl\+g$" "${LOG}"):$(count_pgdn):$(grep -cE "^pane${T}send-keys${T}wT:p2${T}esc$" "${LOG}")" "1:1:1"
check "r6(r2) 17줄 실화면 원문 esc 후 blocked 복귀" eq "$(pane_status wT:p2)" "blocked:False"

# (r3) 본문 오인 방지: 같은 메뉴 글자들이 화면 위쪽 본문에 있고 그 아래에 agy 일반 입력란과 상태줄이 오는 화면(상태 blocked)
mkstate "${VICE_SPEC}" "${IMPL_SPEC}|blocked" "${CRITIC_SPEC}|idle"
STATE_FILE="${STATE}" RP_FILE="${REAL_PROMPT_FILE}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
raw_lines = open(os.environ["RP_FILE"], "r", encoding="utf-8").read().splitlines()
status_line = raw_lines[-1]
body_menu = "\n".join(raw_lines[:-1])
fake_body_scr = (
    body_menu + "\n"
    "\u25cf Done printing example menu.\n"
    "\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n"
    "> \n"
    "\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n"
    + status_line
)
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = fake_body_scr
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
	"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 1 --interval 1 2>&1)"
RC=$?
check "r6(r3) 본문 메뉴+아래 입력란 team-watch rc 0" eq "${RC}" 0
check "r6(r3) 본문 메뉴+아래 입력란 team-watch impl-blocked 미발생(heartbeat)" last_line "EVENT heartbeat impl=blocked critic=idle"
check "r6(r3) 본문 메뉴+아래 입력란 team-watch 기대 키 수 0" eq "$(grep -cE "^pane${T}send-(keys|text)${T}" "${LOG}")" 0

run_prompt_ext wT:p2
check "r6(r3) 본문 메뉴+아래 입력란 prompt-read rc 1" eq "${RC}" 1
check "r6(r3) 본문 메뉴+아래 입력란 prompt-read UNSUPPORTED target-guard:not-agy-command-prompt" eq "${OUT}" "UNSUPPORTED target-guard:not-agy-command-prompt"
check "r6(r3) 본문 메뉴+아래 입력란 prompt-read 기대 키 수 ctrl+g 0·PgDn 0·esc 0" eq "$(grep -cE "^pane${T}send-(keys|text)${T}" "${LOG}")" 0

# (r4) 안내 줄(ctrl+g)이 빠진 메뉴(상태 blocked) → 두 도구 모두 확인창이 아님
mkstate "${VICE_SPEC}" "${IMPL_SPEC}|blocked" "${CRITIC_SPEC}|idle"
STATE_FILE="${STATE}" RP_FILE="${REAL_PROMPT_FILE}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
no_hint = "\n".join(
    l for l in open(os.environ["RP_FILE"], "r", encoding="utf-8").read().splitlines()
    if "ctrl+g edit/expand command" not in l
)
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = no_hint
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
	"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 1 --interval 1 2>&1)"
RC=$?
check "r6(r4) 안내 줄 누락 메뉴 team-watch rc 0" eq "${RC}" 0
check "r6(r4) 안내 줄 누락 메뉴 team-watch impl-blocked 미발생(heartbeat)" last_line "EVENT heartbeat impl=blocked critic=idle"
check "r6(r4) 안내 줄 누락 메뉴 team-watch 기대 키 수 0" eq "$(grep -cE "^pane${T}send-(keys|text)${T}" "${LOG}")" 0

run_prompt_ext wT:p2
check "r6(r4) 안내 줄 누락 메뉴 prompt-read rc 1" eq "${RC}" 1
check "r6(r4) 안내 줄 누락 메뉴 prompt-read UNSUPPORTED target-guard:not-agy-command-prompt" eq "${OUT}" "UNSUPPORTED target-guard:not-agy-command-prompt"
check "r6(r4) 안내 줄 누락 메뉴 prompt-read 기대 키 수 ctrl+g 0·PgDn 0·esc 0" eq "$(grep -cE "^pane${T}send-(keys|text)${T}" "${LOG}")" 0

# (r5) 교정 i3-r6 (1): 실화면 원문에서 표지(>)만 2번 줄로 옮긴 화면(상태 blocked)
# → team-watch: EVENT impl-blocked / prompt-read: 키 0, UNSUPPORTED target-guard:cursor-not-1
mkstate "${VICE_SPEC}" "${IMPL_SPEC}|blocked" "${CRITIC_SPEC}|idle"
STATE_FILE="${STATE}" RP_FILE="${REAL_PROMPT_FILE}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
raw = open(os.environ["RP_FILE"], "r", encoding="utf-8").read()
cur2 = raw.replace("> 1. Yes, run command\n  2. Yes,", "  1. Yes, run command\n> 2. Yes,", 1)
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = cur2
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
	"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 3 --interval 1 2>&1)"
RC=$?
check "r6(r5) 표지 2번 이동 확인창 team-watch rc 0" eq "${RC}" 0
check "r6(r5) 표지 2번 이동 확인창 team-watch EVENT impl-blocked" last_line "EVENT impl-blocked pane=wT:p2 status=blocked focused_pane_id=- zoomed=false active_workspace=wT"
check "r6(r5) 표지 2번 이동 확인창 team-watch 기대 키 수 0" eq "$(grep -cE "^pane${T}send-(keys|text)${T}" "${LOG}")" 0

run_prompt_ext wT:p2
check "r6(r5) 표지 2번 이동 확인창 prompt-read rc 1" eq "${RC}" 1
check "r6(r5) 표지 2번 이동 확인창 prompt-read UNSUPPORTED target-guard:cursor-not-1" eq "${OUT}" "UNSUPPORTED target-guard:cursor-not-1"
check "r6(r5) 표지 2번 이동 확인창 prompt-read 기대 키 수 ctrl+g 0·PgDn 0·esc 0" eq "$(grep -cE "^pane${T}send-(keys|text)${T}" "${LOG}")" 0

CASE="i3-r7 회귀 시험 (x1·x2): 실화면 펼침 원문 4쪽(p1~p4, 범위 줄 아래 빈 줄·footer 없음) 12줄 완독 및 p2 범위 줄 누락 거부"
REAL_EXP_P1="${TMP}/real-expanded-p1.txt"
REAL_EXP_P2="${TMP}/real-expanded-p2.txt"
REAL_EXP_P3="${TMP}/real-expanded-p3.txt"
REAL_EXP_P4="${TMP}/real-expanded-p4.txt"
cat <<'EOF' >"${REAL_EXP_P1}"
Expanded Tool Permission Editor
───────────────────────────────────────────────────────────────────────────────────────────

  Full Command:
    /opt/local/bin/bash -c 'echo realtest-01
    echo realtest-02
    echo realtest-03
    echo realtest-04
    echo realtest-05
  (1–5 of 12 lines)

───────────────────────────────────────────────────────────────────────────────────────────
  Requested Permission (Editable): [↓ 9]
  > /opt/local/bin/bash -c 'echo realtest-01
    echo realtest-02
    echo realtest-03
EOF
cat <<'EOF' >"${REAL_EXP_P2}"
Expanded Tool Permission Editor
───────────────────────────────────────────────────────────────────────────────────────────

  Full Command:
    echo realtest-04
    echo realtest-05
    echo realtest-06
    echo realtest-07
    echo realtest-08
  (4–8 of 12 lines)

───────────────────────────────────────────────────────────────────────────────────────────
  Requested Permission (Editable): [↓ 9]
  > /opt/local/bin/bash -c 'echo realtest-01
    echo realtest-02
    echo realtest-03
EOF
cat <<'EOF' >"${REAL_EXP_P3}"
Expanded Tool Permission Editor
───────────────────────────────────────────────────────────────────────────────────────────

  Full Command:
    echo realtest-07
    echo realtest-08
    echo realtest-09
    echo realtest-10
    echo realtest-11
  (7–11 of 12 lines)

───────────────────────────────────────────────────────────────────────────────────────────
  Requested Permission (Editable): [↓ 9]
  > /opt/local/bin/bash -c 'echo realtest-01
    echo realtest-02
    echo realtest-03
EOF
cat <<'EOF' >"${REAL_EXP_P4}"
Expanded Tool Permission Editor
───────────────────────────────────────────────────────────────────────────────────────────

  Full Command:
    echo realtest-08
    echo realtest-09
    echo realtest-10
    echo realtest-11
    echo realtest-12'
  (8–12 of 12 lines)

───────────────────────────────────────────────────────────────────────────────────────────
  Requested Permission (Editable): [↓ 9]
  > /opt/local/bin/bash -c 'echo realtest-01
    echo realtest-02
    echo realtest-03
EOF
check "r7 REAL-EXPANDED-p1.txt sha256 일치" eq "$(shasum -a 256 "${REAL_EXP_P1}" | cut -d' ' -f1)" "f382dcbadc76ff8213c129b30e685de3ad2e4db7f893a32d35bc8312e0963014"
check "r7 REAL-EXPANDED-p2.txt sha256 일치" eq "$(shasum -a 256 "${REAL_EXP_P2}" | cut -d' ' -f1)" "9b177775f0d9e4402fbd9bba434f2c53db320cfbb43157decb0652da8e36ae40"
check "r7 REAL-EXPANDED-p3.txt sha256 일치" eq "$(shasum -a 256 "${REAL_EXP_P3}" | cut -d' ' -f1)" "69957df6b72bf30222f04630c944bbcfa682b06cb1dda6d308a0d47936653563"
check "r7 REAL-EXPANDED-p4.txt sha256 일치" eq "$(shasum -a 256 "${REAL_EXP_P4}" | cut -d' ' -f1)" "5f844212f392d3c34b01d823959f6672ab596f6c818ea66bc4e7cc9eb87da764"

# (x1) REAL-COLLAPSED-19row.txt(blocked) → ctrl+g → p1~p4(done) → esc → REAL-COLLAPSED-19row.txt(blocked)
STATE_FILE="${STATE}" RP_COL="${REAL_PROMPT_FILE}" EP1="${REAL_EXP_P1}" EP2="${REAL_EXP_P2}" EP3="${REAL_EXP_P3}" EP4="${REAL_EXP_P4}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
col = open(os.environ["RP_COL"], "r", encoding="utf-8").read()
pages = [open(os.environ[k], "r", encoding="utf-8").read() for k in ("EP1", "EP2", "EP3", "EP4")]
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = col
        p["expanded"] = False
        p["expanded_pages"] = pages
        p["screen_after_esc"] = col
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
run_prompt_ext wT:p2
EXPECTED_REAL_12="$(printf "    /opt/local/bin/bash -c 'echo realtest-01\n    echo realtest-02\n    echo realtest-03\n    echo realtest-04\n    echo realtest-05\n    echo realtest-06\n    echo realtest-07\n    echo realtest-08\n    echo realtest-09\n    echo realtest-10\n    echo realtest-11\n    echo realtest-12'\nOK cursor=1")"
check "r7(x1) 실화면 4쪽 12줄 완독 rc 0" eq "${RC}" 0
check "r7(x1) 실화면 12줄 전문(순서·겹침 제거·원문 보존) + OK cursor=1" eq "${OUT}" "${EXPECTED_REAL_12}"
check "r7(x1) 기대 키 수 ctrl+g 1회·PgDn 3회·esc 1회" eq "$(grep -cE "^pane${T}send-keys${T}wT:p2${T}ctrl\+g$" "${LOG}"):$(count_pgdn):$(grep -cE "^pane${T}send-keys${T}wT:p2${T}esc$" "${LOG}")" "1:3:1"
check "r7(x1) esc 후 blocked 복귀" eq "$(pane_status wT:p2)" "blocked:False"

# (x2) 같은 흐름에서 p2의 범위 줄 (4–8 of 12 lines)을 지운 화면 → 부분 전문 미출력·esc 닫기·UNSUPPORTED missing-line-range·rc 1
STATE_FILE="${STATE}" RP_COL="${REAL_PROMPT_FILE}" EP1="${REAL_EXP_P1}" EP2="${REAL_EXP_P2}" EP3="${REAL_EXP_P3}" EP4="${REAL_EXP_P4}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
col = open(os.environ["RP_COL"], "r", encoding="utf-8").read()
p1 = open(os.environ["EP1"], "r", encoding="utf-8").read()
p2_no_range = "\n".join(
    l for l in open(os.environ["EP2"], "r", encoding="utf-8").read().splitlines()
    if "(4\u20138 of 12 lines)" not in l
)
p3 = open(os.environ["EP3"], "r", encoding="utf-8").read()
p4 = open(os.environ["EP4"], "r", encoding="utf-8").read()
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = col
        p["expanded"] = False
        p["expanded_pages"] = [p1, p2_no_range, p3, p4]
        p["screen_after_esc"] = col
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
run_prompt_ext wT:p2
check "r7(x2) p2 범위 줄 누락 rc 1" eq "${RC}" 1
check "r7(x2) p2 범위 줄 누락 부분 전문 미출력·UNSUPPORTED missing-line-range 단독 출력" eq "${OUT}" "UNSUPPORTED missing-line-range"
check "r7(x2) p2 범위 줄 누락 기대 키 수 ctrl+g 1회·PgDn 1회·esc 1회" eq "$(grep -cE "^pane${T}send-keys${T}wT:p2${T}ctrl\+g$" "${LOG}"):$(count_pgdn):$(grep -cE "^pane${T}send-keys${T}wT:p2${T}esc$" "${LOG}")" "1:1:1"
check "r7(x2) p2 범위 줄 누락 esc 후 blocked 복귀" eq "$(pane_status wT:p2)" "blocked:False"
: >"${LOG}"

CASE="i8 회귀 시험 (mcp): MCP 확인창 실화면 원문(d24d7cfca3fc2ab7) 구조 판정 · 질문 문구 단독/본문 오인/안내 줄 누락 미감지 · 커서 이동"
REAL_MCP_PROMPT_FILE="${TMP}/mcp-prompt-screen.ansi"
MCP_B64="DQobWzBtG1szODsyOzE0NzsxNjE7MTYxbXdmMy1jb2RlLXJlc2VhcmNoX2NvbnRleHQ3L3Jlc29sdmUtbGlicmFyeS1pZBtbMG0NCg0KG1swbRtbMW1BbGxvdyBjYWxsaW5nIHRoaXMgdG9vbD8bWzBtDQobWzBtG1szODsyOzM4OzEzOTsyMTBtPiAxLiBZZXMsIGFsbG93IHRvb2wgY2FsbBtbMG0NCiAgMi4gWWVzLCBhbmQgYWx3YXlzIGFsbG93IHRvb2wgJ3dmMy1jb2RlLXJlc2VhcmNoX2NvbnRleHQ3L3Jlc29sdmUtbGlicmFyeS1pZCcgaW4gdGhpcw0KY29udmVyc2F0aW9uDQogIDMuIFllcywgYW5kIGFsd2F5cyBhbGxvdyB0b29sICd3ZjMtY29kZS1yZXNlYXJjaF9jb250ZXh0Ny9yZXNvbHZlLWxpYnJhcnktaWQnIChQZXJzaXN0DQp0byBzZXR0aW5ncy5qc29uKQ0KICA0LiBObywgZGVueSB0b29sIGNhbGwNCiAgNS4gTm8sIGFuZCBhbHdheXMgZGVueSB0b29sICd3ZjMtY29kZS1yZXNlYXJjaF9jb250ZXh0Ny9yZXNvbHZlLWxpYnJhcnktaWQnIGluIHRoaXMNCmNvbnZlcnNhdGlvbg0KICA2LiBObywgYW5kIGFsd2F5cyBkZW55IHRvb2wgJ3dmMy1jb2RlLXJlc2VhcmNoX2NvbnRleHQ3L3Jlc29sdmUtbGlicmFyeS1pZCcgKFBlcnNpc3QgdG8NCnNldHRpbmdzLmpzb24pDQoNCiAgG1swbRtbMW0bWzM4OzI7Mzg7MTM5OzIxMG3ihpEv4oaTG1swbRtbMzg7MjsxMzE7MTQ4OzE1MG0gTmF2aWdhdGUgwrcgG1swbRtbMW0bWzM4OzI7Mzg7MTM5OzIxMG10YWIbWzBtG1szODsyOzEzMTsxNDg7MTUwbSBBbWVuZBtbMG0NChtbMG0bWzM4OzI7MTMxOzE0ODsxNTBtZXNjIHRvIGNhbmNlbBtbMG0gICAgICAgIBtbMG0bWzM4OzI7MTMzOzE1MzswbWFjY2VwdC1lZGl0cxtbMG0bWzM4OzI7MTMxOzE0ODsxNTBtIMK3IEdlbWluaSA0IEFyZ29uIMK3IGhpZ2ggwrcgG1swbRtbMW0bWzM4OzI7MjAzOzc1OzIybUFJOiA5MzkgKC9jcmVkaXRzIHRvIGFkZCBtbxtbMG0="
MCP_B64="${MCP_B64}" OUT_FILE="${REAL_MCP_PROMPT_FILE}" python3 -c '
import base64, os
with open(os.environ["OUT_FILE"], "wb") as f:
    f.write(base64.b64decode(os.environ["MCP_B64"]))
'
check "i8 MCP 실화면 원문 sha256(d24d7cfca3fc2ab7) 일치" eq "$(shasum -a 256 "${REAL_MCP_PROMPT_FILE}" | cut -c1-16)" "d24d7cfca3fc2ab7"

# (m1) 실화면 원문(ANSI 포함) + 상태 blocked → EVENT impl-blocked kind=mcp
mkstate "${VICE_SPEC}" "${IMPL_SPEC}|blocked" "${CRITIC_SPEC}|idle"
STATE_FILE="${STATE}" MCP_FILE="${REAL_MCP_PROMPT_FILE}" python3 -c '
import json, os
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
raw = open(os.environ["MCP_FILE"], "rb").read().decode("utf-8")
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = raw
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
	"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 3 --interval 1 2>&1)"
RC=$?
check "i8(m1) MCP 실화면 원문 team-watch rc 0" eq "${RC}" 0
check "i8(m1) MCP 실화면 원문 EVENT impl-blocked kind=mcp" last_line "EVENT impl-blocked kind=mcp pane=wT:p2 status=blocked focused_pane_id=- zoomed=false active_workspace=wT"
check "i8(m1) MCP 확인창 도구 이름 미출력" not_has "wf3-code-research_context7"
check "i8(m1) MCP 실화면 원문 키 전송 0" eq "$(grep -cE "^pane${T}send-(keys|text)${T}" "${LOG}")" 0

# (m2) ANSI 제거 평문(visible) + 커서 2번 이동 + 상태 blocked → EVENT impl-blocked kind=mcp
STATE_FILE="${STATE}" MCP_FILE="${REAL_MCP_PROMPT_FILE}" python3 -c '
import json, os, re
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
raw = open(os.environ["MCP_FILE"], "rb").read().decode("utf-8")
plain = re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", raw).replace("\r\n", "\n")
cur2 = plain.replace("> 1. Yes, allow tool call\n  2. Yes,", "  1. Yes, allow tool call\n> 2. Yes,", 1)
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = cur2
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
	"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 3 --interval 1 2>&1)"
RC=$?
check "i8(m2) MCP 평문·커서 2번 이동 rc 0" eq "${RC}" 0
check "i8(m2) MCP 평문·커서 2번 이동 EVENT impl-blocked kind=mcp" last_line "EVENT impl-blocked kind=mcp pane=wT:p2 status=blocked focused_pane_id=- zoomed=false active_workspace=wT"

# (m3) MCP 화면이나 상태가 blocked가 아님(idle) → heartbeat
patch_pane "wT:p2" '{"agent_status": "idle"}'
OUT="$(cd "${TEST_REPO}" && TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
	"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 1 --interval 1 2>&1)"
RC=$?
check "i8(m3) MCP 화면이나 idle이면 미감지(heartbeat)" last_line "EVENT heartbeat impl=idle critic=idle"

# (m4) 질문 문구 단독 / 본문 메뉴+아래 입력란 / 안내 줄 누락(상태 blocked, 짧은 시간) → kind=mcp 미발생(heartbeat)
for neg_kind in question_only body_with_input no_hint; do
	STATE_FILE="${STATE}" MCP_FILE="${REAL_MCP_PROMPT_FILE}" NEG="${neg_kind}" python3 -c '
import json, os, re
with open(os.environ["STATE_FILE"], "r", encoding="utf-8") as f:
    st = json.load(f)
raw = open(os.environ["MCP_FILE"], "rb").read().decode("utf-8")
plain = re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", raw).replace("\r\n", "\n")
neg = os.environ["NEG"]
if neg == "question_only":
    scr = "Allow calling this tool?\n> 1. Yes, allow tool call"
elif neg == "body_with_input":
    lines = plain.splitlines()
    scr = "\n".join(lines[:-1]) + "\n\u25cf Done.\n\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n> \n\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\n" + lines[-1]
else:
    scr = "\n".join(l for l in plain.splitlines() if "Navigate" not in l)
for p in st["panes"]:
    if p["pane_id"] == "wT:p2":
        p["agent_status"] = "blocked"
        p["screen"] = scr
with open(os.environ["STATE_FILE"], "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
	OUT="$(cd "${TEST_REPO}" && TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
		"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 1 --interval 1 2>&1)"
	RC=$?
	check "i8(m4:${neg_kind}) 구조 불일치 시 kind=mcp 미발생(heartbeat)" last_line "EVENT heartbeat impl=blocked critic=idle"
done

CASE="i8 회귀 시험 (unknown blocked): 미인식 blocked가 기준 시간을 넘지 않을 때 미발생 · 넘을 때 kind=unknown 알림"
# (u1) 미인식 blocked가 기준(2초) 이하(약 0.5초 후 done 전환 — 펼친 확인창 닫기 뒤 지연 모사) → kind=unknown 미발생, impl-done
mkstate "${VICE_SPEC}" "${IMPL_SPEC}|blocked" "${CRITIC_SPEC}|idle"
patch_pane "wT:p2" '{"screen": "Expanded Tool Permission Editor\nClosing..."}'
WATCH_OUT="${TMP}/watch-unk-short.out"
: >"${WATCH_OUT}"
(
	cd "${TEST_REPO}" &&
		TMPDIR="${SELF_TMP}" UNKNOWN_BLOCKED_SEC=2 MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
			"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 5 --interval 1 >"${WATCH_OUT}" 2>&1
) &
BG_PID=$!
wait_watch_ready "${WATCH_OUT}"
sleep 0.5
check "i8(u1) 짧은 미인식 blocked 중 EVENT 미발생" eq "$(grep -c '^EVENT ' "${WATCH_OUT}")" 0
patch_pane "wT:p2" '{"agent_status": "done", "screen": "작업 완료"}'
wait "${BG_PID}"
RC=$?
OUT="$(cat "${WATCH_OUT}")"
check "i8(u1) 짧은 미인식 blocked 해소 후 rc 0" eq "${RC}" 0
check "i8(u1) 짧은 미인식 blocked 해소 시 kind=unknown 없이 impl-done" last_line "EVENT impl-done pane=wT:p2"

# (u2) 미인식 blocked가 기준(2초)을 넘지 않은 채 감시 종료(--duration 2 --interval 1) → kind=unknown 미발생(heartbeat)
mkstate "${VICE_SPEC}" "${IMPL_SPEC}|blocked" "${CRITIC_SPEC}|idle"
patch_pane "wT:p2" '{"screen": "Unrecognized blocked screen"}'
OUT="$(cd "${TEST_REPO}" && TMPDIR="${SELF_TMP}" UNKNOWN_BLOCKED_SEC=2 MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
	"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 2 --interval 1 2>&1)"
RC=$?
check "i8(u2) 기준(2초) 이하 감시 종료 rc 0" eq "${RC}" 0
check "i8(u2) 기준(2초) 이하 감시 종료 시 heartbeat(kind=unknown 미발생)" last_line "EVENT heartbeat impl=blocked critic=idle"

# (u3) 미인식 blocked가 기준(1초)을 넘어 지속(--duration 6 --interval 1) → EVENT impl-blocked kind=unknown
mkstate "${VICE_SPEC}" "${IMPL_SPEC}|blocked" "${CRITIC_SPEC}|idle"
patch_pane "wT:p2" '{"screen": "Unrecognized blocked screen"}'
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && TMPDIR="${SELF_TMP}" UNKNOWN_BLOCKED_SEC=1 MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
	"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 6 --interval 1 2>&1)"
RC=$?
check "i8(u3) 기준 초과 미인식 blocked rc 0" eq "${RC}" 0
check "i8(u3) 기준 초과 미인식 blocked EVENT impl-blocked kind=unknown" last_line "EVENT impl-blocked kind=unknown pane=wT:p2 status=blocked focused_pane_id=- zoomed=false active_workspace=wT"
check "i8(u3) 기준 초과 미인식 blocked 키 전송 0" eq "$(grep -cE "^pane${T}send-(keys|text)${T}" "${LOG}")" 0

CASE="team-watch: cf-impl idle/done (하단 ● [시각] ... running 표시 동안 대기 후 해제 시 EVENT)"
mkstate "${VICE_SPEC}" "${IMPL_SPEC}|idle" "${CRITIC_SPEC}|idle"
patch_pane "wT:p2" '{"screen": "작업 출력\n● [19:00:01] bash test ... running"}'
WATCH_OUT="${TMP}/watch-idle.out"
: >"${WATCH_OUT}"
(
	cd "${TEST_REPO}" &&
		TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
			"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 5 --interval 1 >"${WATCH_OUT}" 2>&1
) &
BG_PID=$!
wait_watch_ready "${WATCH_OUT}"
sleep 0.5
check "하단 running 표시 중에는 EVENT 미발생(대기 유지)" eq "$(grep -c '^EVENT ' "${WATCH_OUT}")" 0
patch_pane "wT:p2" '{"screen": "작업 출력\n완료됨"}'
wait "${BG_PID}"
RC=$?
OUT="$(cat "${WATCH_OUT}")"
check "running 해제 후 rc 0" eq "${RC}" 0
check "EVENT impl-idle 출력" last_line "EVENT impl-idle pane=wT:p2"

mkstate "${VICE_SPEC}" "${IMPL_SPEC}|working" "${CRITIC_SPEC}|idle"
WATCH_OUT="${TMP}/watch-done.out"
: >"${WATCH_OUT}"
(
	cd "${TEST_REPO}" &&
		TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
			"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 5 --interval 1 >"${WATCH_OUT}" 2>&1
) &
BG_PID=$!
wait_watch_ready "${WATCH_OUT}"
patch_pane "wT:p2" '{"agent_status": "done"}'
wait "${BG_PID}"
RC=$?
OUT="$(cat "${WATCH_OUT}")"
check "working→done rc 0" eq "${RC}" 0
check "EVENT impl-done 출력" last_line "EVENT impl-done pane=wT:p2"

CASE="team-watch: 이름 풀림(impl 즉시, critic /new 유예 시간 안 재등록은 무시·유예 초과 시 EVENT)"
mkstate "${VICE_SPEC}" "wT:p2|wT|CF 구현 · agy|agy||${TEST_REPO}|${IMPL_SID}|idle" "${CRITIC_SPEC}|idle"
OUT="$(cd "${TEST_REPO}" && TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
	"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 3 --interval 1 2>&1)"
RC=$?
check "impl-name-missing rc 0" eq "${RC}" 0
check "EVENT impl-name-missing" last_line "EVENT impl-name-missing"

# critic /new 직후 이름 풀림 + 새 세션 → 유예(6초) 안에 재등록 시 사건 없이 heartbeat
mkstate "${VICE_SPEC}" "${IMPL_SPEC}|idle" "${CRITIC_SPEC}|idle"
WATCH_OUT="${TMP}/watch-critic-grace.out"
: >"${WATCH_OUT}"
prev_pane_lists="$(grep -F "pane${T}list" "${LOG}" | wc -l | tr -d ' ')"
(
	cd "${TEST_REPO}" &&
		TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
			"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 4 --interval 1 --critic-grace 12 >"${WATCH_OUT}" 2>&1
) &
BG_PID=$!
wait_watch_ready "${WATCH_OUT}"
patch_pane "wT:p3" '{"name": null, "agent_session": {"value": "c0d3-new-session"}, "screen": "100% context left\n› "}'
grace_tries=0
while [ "$(grep -F "pane${T}list" "${LOG}" | wc -l | tr -d ' ')" -le "${prev_pane_lists}" ] && [ "${grace_tries}" -lt 120 ]; do
	sleep 0.05
	grace_tries=$((grace_tries + 1))
done
patch_pane "wT:p3" '{"name": "cf-critic"}'
wait "${BG_PID}"
RC=$?
OUT="$(cat "${WATCH_OUT}")"
check "critic /new 유예 진입(pane list 호출) 확인" test "$(grep -F "pane${T}list" "${LOG}" | wc -l | tr -d ' ')" -gt "${prev_pane_lists}"
check "critic /new 유예 내 재등록 rc 0" eq "${RC}" 0
check "critic /new 유예 내 재등록 시 heartbeat" last_line "EVENT heartbeat impl=idle critic=idle"

# critic 이름 풀림이 유예(1초)를 넘기면 EVENT critic-name-missing
mkstate "${VICE_SPEC}" "${IMPL_SPEC}|idle" "${CRITIC_SPEC}|idle"
WATCH_OUT="${TMP}/watch-critic-missing.out"
: >"${WATCH_OUT}"
(
	cd "${TEST_REPO}" &&
		TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
			"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 10 --interval 1 --critic-grace 1 >"${WATCH_OUT}" 2>&1
) &
BG_PID=$!
wait_watch_ready "${WATCH_OUT}"
patch_pane "wT:p3" '{"name": null}'
wait "${BG_PID}"
RC=$?
OUT="$(cat "${WATCH_OUT}")"
check "critic 유예 초과 rc 0" eq "${RC}" 0
check "EVENT critic-name-missing" last_line "EVENT critic-name-missing pane=wT:p3"

CASE="team-watch: 팀원 pane·세션 바뀜(impl-changed / critic-changed)"
mkstate "${VICE_SPEC}" "${IMPL_SPEC}|idle" "${CRITIC_SPEC}|idle"
WATCH_OUT="${TMP}/watch-impl-chg.out"
: >"${WATCH_OUT}"
(
	cd "${TEST_REPO}" &&
		TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
			"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 5 --interval 1 >"${WATCH_OUT}" 2>&1
) &
BG_PID=$!
wait_watch_ready "${WATCH_OUT}"
patch_pane "wT:p2" '{"agent_session": {"value": "new-impl-sid"}}'
wait "${BG_PID}"
RC=$?
OUT="$(cat "${WATCH_OUT}")"
check "impl-changed rc 0" eq "${RC}" 0
check "EVENT impl-changed" last_line "EVENT impl-changed was=wT:p2/${IMPL_SID} now=wT:p2/new-impl-sid"

mkstate "${VICE_SPEC}" "${IMPL_SPEC}|idle" "${CRITIC_SPEC}|idle"
WATCH_OUT="${TMP}/watch-critic-chg.out"
: >"${WATCH_OUT}"
(
	cd "${TEST_REPO}" &&
		TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
			"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 5 --interval 1 >"${WATCH_OUT}" 2>&1
) &
BG_PID=$!
wait_watch_ready "${WATCH_OUT}"
patch_pane "wT:p3" '{"agent_session": {"value": "unexpected-critic-sid"}, "screen": "working on review"}'
wait "${BG_PID}"
RC=$?
OUT="$(cat "${WATCH_OUT}")"
check "critic-changed rc 0" eq "${RC}" 0
check "EVENT critic-changed" last_line "EVENT critic-changed was=wT:p3/${CRITIC_SID} now=wT:p3/unexpected-critic-sid"

CASE="team-watch: HEAD · refs/heads · origin/main · external-lead 변화 감지"
mkstate "${VICE_SPEC}" "${IMPL_SPEC}|idle" "${CRITIC_SPEC}|idle"

# 1) refs/heads 변화(같은 커밋에서 새 브랜치 생성)
WATCH_OUT="${TMP}/watch-refs.out"
: >"${WATCH_OUT}"
(
	cd "${TEST_REPO}" &&
		TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
			"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 5 --interval 1 >"${WATCH_OUT}" 2>&1
) &
BG_PID=$!
wait_watch_ready "${WATCH_OUT}"
git_test branch temp-branch
wait "${BG_PID}"
RC=$?
OUT="$(cat "${WATCH_OUT}")"
git_test branch -D temp-branch >/dev/null 2>&1
check "refs-heads-changed rc 0" eq "${RC}" 0
check "EVENT refs-heads-changed" has "EVENT refs-heads-changed "

# 2) HEAD 변화(새 커밋)
WATCH_OUT="${TMP}/watch-head.out"
: >"${WATCH_OUT}"
(
	cd "${TEST_REPO}" &&
		TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
			"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 5 --interval 1 >"${WATCH_OUT}" 2>&1
) &
BG_PID=$!
wait_watch_ready "${WATCH_OUT}"
git_test -c user.name=t -c user.email=t@t commit -q --allow-empty -m second
wait "${BG_PID}"
RC=$?
OUT="$(cat "${WATCH_OUT}")"
check "head-changed rc 0" eq "${RC}" 0
check "EVENT head-changed" has "EVENT head-changed "

# 3) origin/main 변화(fetch 없이 로컬 추적 ref 갱신 감지)
WATCH_OUT="${TMP}/watch-origin.out"
: >"${WATCH_OUT}"
(
	cd "${TEST_REPO}" &&
		TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
			"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 5 --interval 1 >"${WATCH_OUT}" 2>&1
) &
BG_PID=$!
wait_watch_ready "${WATCH_OUT}"
git_test update-ref refs/remotes/origin/main HEAD
wait "${BG_PID}"
RC=$?
OUT="$(cat "${WATCH_OUT}")"
check "origin-main-changed rc 0" eq "${RC}" 0
check "EVENT origin-main-changed" has "EVENT origin-main-changed "

# 4) external-lead 기록 해시 변화
WATCH_OUT="${TMP}/watch-rec.out"
: >"${WATCH_OUT}"
(
	cd "${TEST_REPO}" &&
		TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
			"${TEST_BASH}" "${WATCH_SCRIPT}" general --duration 5 --interval 1 >"${WATCH_OUT}" 2>&1
) &
BG_PID=$!
wait_watch_ready "${WATCH_OUT}"
printf '%s\n' "${OTHER_SID}" >"${EXT_LOCK}"
wait "${BG_PID}"
RC=$?
OUT="$(cat "${WATCH_OUT}")"
printf '%s\n' "${EXT_SID}" >"${EXT_LOCK}"
check "external-lead-changed rc 0" eq "${RC}" 0
check "EVENT external-lead-changed" has "EVENT external-lead-changed "

CASE="team-watch: round 모드(허용 파일 밖 변경 · to-lead 새 파일 · CF_WORK_ROOT · VERDICT 후 정체)"
ROUND_TO_LEAD="${TMP}/cf-work/issues/${TEST_ISSUE_NUM}/${TEST_ROUND_SUB}/to-lead"
mkdir -p "${ROUND_TO_LEAD}"
printf 'ack\n' >"${ROUND_TO_LEAD}/01-ACK.md"

# 0) 잘못된 회차ID(i<번호>-<회차> 형식이 아님)는 종료 2로 거부
OUT="$(cd "${TEST_REPO}" && TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" "${TEST_BASH}" "${WATCH_SCRIPT}" round "badround-1" '^allowed\.txt$' --duration 1 --interval 1 2>&1)"
RC=$?
check "잘못된 회차ID 거부 rc 2" eq "${RC}" 2
check "잘못된 회차ID 안내" has "사용법: scripts/team-watch.sh"

# 1) 허용된 파일 변경은 통과하고, 허용 밖 미추적 파일 생성 시 EVENT out-of-scope
printf 'allowed-change\n' >"${TEST_REPO}/allowed.txt"
WATCH_OUT="${TMP}/watch-scope.out"
: >"${WATCH_OUT}"
(
	cd "${TEST_REPO}" &&
		TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
			"${TEST_BASH}" "${WATCH_SCRIPT}" round "${TEST_ROUND_ID}" '^(allowed\.txt|scripts/.*\.sh)$' --duration 5 --interval 1 >"${WATCH_OUT}" 2>&1
) &
BG_PID=$!
wait_watch_ready "${WATCH_OUT}"
printf 'oops\n' >"${TEST_REPO}/unallowed.txt"
wait "${BG_PID}"
RC=$?
OUT="$(cat "${WATCH_OUT}")"
rm -f "${TEST_REPO}/unallowed.txt"
git_test checkout -- allowed.txt
check "out-of-scope rc 0" eq "${RC}" 0
check "EVENT out-of-scope" last_line "EVENT out-of-scope file=unallowed.txt"

# 2) 기본 작업 뿌리(<저장소 상위 폴더>/cf-work/issues/<번호>/<회차>/to-lead)에 감시 시작 때 없던 새 파일 등장 시 EVENT to-lead
WATCH_OUT="${TMP}/watch-tolead.out"
: >"${WATCH_OUT}"
(
	cd "${TEST_REPO}" &&
		TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
			"${TEST_BASH}" "${WATCH_SCRIPT}" round "${TEST_ROUND_ID}" '^allowed\.txt$' --duration 5 --interval 1 >"${WATCH_OUT}" 2>&1
) &
BG_PID=$!
wait_watch_ready "${WATCH_OUT}"
printf 'report\n' >"${ROUND_TO_LEAD}/02-REPORT.md"
wait "${BG_PID}"
RC=$?
OUT="$(cat "${WATCH_OUT}")"
check "to-lead 새 파일 rc 0" eq "${RC}" 0
check "EVENT to-lead" last_line "EVENT to-lead file=02-REPORT.md"

# 2b) CF_WORK_ROOT로 지정한 작업 뿌리(<CF_WORK_ROOT>/issues/<번호>/<회차>/to-lead)에서도 새 파일 감지
CUSTOM_WORK_ROOT="${TMP}/custom-work"
CUSTOM_TO_LEAD="${CUSTOM_WORK_ROOT}/issues/17/d2-sub/to-lead"
mkdir -p "${CUSTOM_TO_LEAD}"
WATCH_OUT="${TMP}/watch-tolead-custom.out"
: >"${WATCH_OUT}"
(
	cd "${TEST_REPO}" &&
		CF_WORK_ROOT="${CUSTOM_WORK_ROOT}" TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
			"${TEST_BASH}" "${WATCH_SCRIPT}" round "i17-d2-sub" '^allowed\.txt$' --duration 5 --interval 1 >"${WATCH_OUT}" 2>&1
) &
BG_PID=$!
wait_watch_ready "${WATCH_OUT}"
printf 'report\n' >"${CUSTOM_TO_LEAD}/01-REPORT.md"
wait "${BG_PID}"
RC=$?
OUT="$(cat "${WATCH_OUT}")"
check "CF_WORK_ROOT to-lead 새 파일 rc 0" eq "${RC}" 0
check "CF_WORK_ROOT EVENT to-lead" last_line "EVENT to-lead file=01-REPORT.md"

# 3) 동결 사본 VERDICT.md 생성 후 cf-impl이 정체되면 EVENT verdict-stalled
REVIEW_DIR="/tmp/cf-${TEST_ROUND_ID}-review.1"
mkdir -p "${REVIEW_DIR}"
WATCH_OUT="${TMP}/watch-verdict.out"
: >"${WATCH_OUT}"
(
	cd "${TEST_REPO}" &&
		TMPDIR="${SELF_TMP}" MOCK_HERDR_STATE="${STATE}" MOCK_HERDR_LOG="${LOG}" \
			"${TEST_BASH}" "${WATCH_SCRIPT}" round "${TEST_ROUND_ID}" '^allowed\.txt$' --duration 5 --interval 1 --verdict-timeout 1 >"${WATCH_OUT}" 2>&1
) &
BG_PID=$!
wait_watch_ready "${WATCH_OUT}"
printf 'VERDICT: APPROVE\n' >"${REVIEW_DIR}/VERDICT.md"
wait "${BG_PID}"
RC=$?
OUT="$(cat "${WATCH_OUT}")"
check "verdict-stalled rc 0" eq "${RC}" 0
check "EVENT verdict-stalled" has "EVENT verdict-stalled file=${REVIEW_DIR}/VERDICT.md age="

CASE="실제 저장소 .local/team/external-lead 무변경 및 team-watch 전체 읽기 전용 확인"
REAL_LOCK_AFTER="none"
if [ -f "${REAL_LOCK}" ]; then
	REAL_LOCK_AFTER="$(shasum -a 256 "${REAL_LOCK}" | cut -d' ' -f1)"
fi
check "실제 저장소 external-lead 불변" eq "${REAL_LOCK_AFTER}" "${REAL_LOCK_BEFORE}"
check "team-watch 전체 구간 변이·process-info 호출 0" eq "$(grep -cE "^(pane${T}(send-keys|send-text|rename|move|split|run|process-info)|agent${T}(rename|prompt)|tab${T}close)" "${LOG}")" 0

# shellcheck disable=SC2016
echo "team-watch 테스트: 통과 ${PASS} / 전체 $((PASS + FAIL)) (bash: $("${TEST_BASH}" -c 'echo $BASH_VERSION'))"
[ "${FAIL}" -eq 0 ]

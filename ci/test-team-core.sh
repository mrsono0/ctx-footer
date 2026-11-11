#!/usr/bin/env bash
# scripts/team-core.sh · scripts/core-watch.sh 모의 단위 테스트.
# ci/mock/hc(모의)와 임시 git 저장소만 쓰며 실제 Herdr/Core에 닿지 않는다.
set -u

unset CF_EXTERNAL_LEAD CF_HERDR_SPACE CF_WORK_ROOT CLAUDE_CODE_SESSION_ID HERDR_ENV HERDR_PANE_ID HERDR_WORKSPACE_ID HERDR_TAB_ID HC_BIN HERDR_APP_BIN CF_APP_RETRIES CF_APP_RETRY_SLEEP

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ORIG_CORE="${ROOT}/scripts/team-core.sh"
ORIG_WATCH="${ROOT}/scripts/core-watch.sh"
MOCK_HC="${ROOT}/ci/mock/hc"
MOCK_APP="${ROOT}/ci/mock/herdr-app"
TEST_BASH="${TEAM_CORE_BASH:-${TEAM_UP_BASH:-bash}}"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cf-team-core-test.XXXXXX")" || exit 1
cleanup() { [ -n "$TMP" ] && [ -d "$TMP" ] && rm -rf -- "$TMP"; }
trap cleanup EXIT

mkdir -p "${TMP}/bin"
cp "${ROOT}/ci/mock/hc" "${TMP}/bin/hc"
cp "${ROOT}/ci/mock/herdr-app" "${TMP}/bin/herdr-app"
chmod +x "${TMP}/bin/hc" "${TMP}/bin/herdr-app"
MOCK_HC="${TMP}/bin/hc"
MOCK_APP="${TMP}/bin/herdr-app"

STATE="${TMP}/hc-state.json"
LOG="${TMP}/hc-calls.log"
APP_STATE="${TMP}/app-state.json"
APP_LOG="${TMP}/app-calls.log"
printf '{"spaces": []}\n' >"${APP_STATE}"
: >"${APP_LOG}"
export HERDR_APP_BIN="${MOCK_APP}" MOCK_APP_STATE="${APP_STATE}" MOCK_APP_LOG="${APP_LOG}" CF_APP_RETRIES=3 CF_APP_RETRY_SLEEP=0.02
T=$'\t'
PASS=0
FAIL=0
CASE=""
OUT=""
RC=0

EXT_SID="a1b2c3d4-0000-4000-8000-000000000001"
OTHER_SID="deadbeef-9999-4000-8000-000000000002"
IMPL_CONV="01a126cd-0000-4000-8000-000000000001"

# 임시 메인 git 저장소 및 연결 worktree 구성
TEST_REPO_RAW="${TMP}/repo"
WT_LINKED="${TMP}/wt-linked"
mkdir -p "${TEST_REPO_RAW}/scripts" "${TEST_REPO_RAW}/.claude/worktrees/w1" "${TEST_REPO_RAW}/.local/team"
cp "${ORIG_CORE}" "${TEST_REPO_RAW}/scripts/team-core.sh"
cp "${ORIG_WATCH}" "${TEST_REPO_RAW}/scripts/core-watch.sh"
chmod +x "${TEST_REPO_RAW}/scripts/team-core.sh" "${TEST_REPO_RAW}/scripts/core-watch.sh"

(
	cd "${TEST_REPO_RAW}" &&
		HOME="${TMP}" XDG_CONFIG_HOME="${TMP}" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git init -q -b main &&
		printf '.local/\n.claude/\n' >.gitignore &&
		HOME="${TMP}" XDG_CONFIG_HOME="${TMP}" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git add .gitignore scripts/team-core.sh scripts/core-watch.sh &&
		HOME="${TMP}" XDG_CONFIG_HOME="${TMP}" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -c user.name=t -c user.email=t@t commit -q -m init &&
		HOME="${TMP}" XDG_CONFIG_HOME="${TMP}" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git worktree add -q "${WT_LINKED}" -b linked
) || exit 1

TEST_REPO="$(cd "${TEST_REPO_RAW}" && pwd -P)"
CORE_SCRIPT="${TEST_REPO}/scripts/team-core.sh"
WATCH_SCRIPT="${TEST_REPO}/scripts/core-watch.sh"
EXT_LOCK="${TEST_REPO}/.local/team/external-lead"
printf '%s\n' "${EXT_SID}" >"${EXT_LOCK}"

# 기본 정상 상태 생성 도우미:
# 인자: "impl[:s_state[:conv_id[:t_state]]]" "critic[:s_state[:t_state]]"
mkstate() {
	TEST_REPO_ENV="${TEST_REPO}" python3 - "$@" >"${STATE}" <<'PY'
import json, os, sys

cwd = os.environ["TEST_REPO_ENV"]
terms = []
for arg in sys.argv[1:]:
    parts = (arg.split(":") + ["", "", "", ""])[:4]
    role = parts[0]
    if role == "impl":
        s_state = parts[1] or "idle"
        conv = parts[2]
        t_state = parts[3] or "live"
        argv = ["agy"]
        if conv:
            argv += ["--conversation", conv]
        argv += ["--model", "gemini-4-argon-high", "--mode", "accept-edits", "--sandbox"]
        terms.append({
            "address": "t26",
            "argv": argv,
            "created_at": 1776478400338,
            "cwd": cwd,
            "exit_code": None if t_state == "live" else 0,
            "id": "019da031-76c2-74a1-a6e1-19fd6b73ccad",
            "labels": {"role": "impl", "team": "cf"},
            "name": "cf-impl",
            "parent": None,
            "pid": 14635 if t_state == "live" else None,
            "pty": {"cols": 80, "rows": 24},
            "state": t_state,
            "status": {"app": "agy", "msg": "", "state": s_state},
            "title": "agy",
            "turn": 1,
        })
    elif role == "critic":
        s_state = parts[1] or "idle"
        t_state = parts[2] or "live"
        argv = [
            "codex", "--search", "--yolo", "--disable", "worktrees",
            "--disable", "memories", "-m", "gpt-6.1-sol", "-c", "model_reasoning_effort=high",
        ]
        terms.append({
            "address": "t27",
            "argv": argv,
            "created_at": 1776478403109,
            "cwd": cwd,
            "exit_code": None if t_state == "live" else 0,
            "id": "019da031-8195-7552-ac25-df10c19d7fb5",
            "labels": {"role": "critic", "team": "cf"},
            "name": "cf-critic",
            "parent": None,
            "pid": 14957 if t_state == "live" else None,
            "pty": {"cols": 80, "rows": 24},
            "state": t_state,
            "status": {"app": "codex", "msg": "", "state": s_state},
            "title": "codex",
            "turn": 1,
        })
json.dump({"terminals": terms, "next": 28}, sys.stdout, ensure_ascii=False, indent=1)
PY
}

patch_term() {
	local target="$1" py_patch="$2"
	STATE_FILE="${STATE}" TARGET_NAME="${target}" PY_PATCH="${py_patch}" python3 -c '
import json, os
path = os.environ["STATE_FILE"]
target = os.environ["TARGET_NAME"]
patch = json.loads(os.environ["PY_PATCH"])
with open(path, "r", encoding="utf-8") as f:
    st = json.load(f)
for t in st.get("terminals", []):
    if t.get("name") == target or t.get("address") == target:
        for k, v in patch.items():
            if k == "status" and isinstance(v, dict):
                t.setdefault("status", {}).update(v)
            else:
                t[k] = v
with open(path, "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
}

mkappstate() {
	if [ "$#" -ge 1 ]; then
		printf '%s\n' "$1" >"${APP_STATE}"
	else
		printf '{"spaces": []}\n' >"${APP_STATE}"
	fi
	: >"${APP_LOG}"
}

run_core() {
	: >"${LOG}"
	: >"${APP_LOG}"
	OUT="$(cd "${TEST_REPO}" && env -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
		HC_BIN="${MOCK_HC}" MOCK_HC_STATE="${STATE}" MOCK_HC_LOG="${LOG}" \
		HERDR_APP_BIN="${MOCK_APP}" MOCK_APP_STATE="${APP_STATE}" MOCK_APP_LOG="${APP_LOG}" \
		CF_APP_RETRIES=3 CF_APP_RETRY_SLEEP=0.02 \
		"${TEST_BASH}" "${CORE_SCRIPT}" "$@" 2>&1)"
	RC=$?
}

run_watch_cmd() {
	: >"${LOG}"
	OUT="$(cd "${TEST_REPO}" && env -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
		HC_BIN="${MOCK_HC}" MOCK_HC_STATE="${STATE}" MOCK_HC_LOG="${LOG}" \
		CF_RETRIES=5 CF_RETRY_SLEEP=0.05 \
		"${TEST_BASH}" "${WATCH_SCRIPT}" "$@" 2>&1)"
	RC=$?
}

check() {
	local desc="$1"
	shift
	if "$@"; then
		PASS=$((PASS + 1))
	else
		FAIL=$((FAIL + 1))
		echo "FAIL [$CASE] $desc" >&2
		echo "  --- 출력 (rc=$RC)" >&2
		printf '%s\n' "$OUT" | sed 's/^/  | /' >&2
		echo "  --- hc 호출" >&2
		sed 's/^/  > /' "$LOG" >&2
	fi
}

eq() { [ "$1" = "$2" ] || { echo "  기대 '$2' / 실제 '$1'" >&2; return 1; }; }
has() { local s; for s in "$@"; do case "$OUT" in *"$s"*) ;; *) return 1 ;; esac; done; }
not_has() { local s; for s in "$@"; do case "$OUT" in *"$s"*) echo "  출력에 없어야 할 '$s' 포함" >&2; return 1 ;; esac; done; }
line_matches() { printf '%s\n' "$OUT" | grep -E "$1" >/dev/null; }
no_hc_mutations() { [ "$(grep -vcE "^(get|ls|list)(${T}|\$)" "$LOG")" = 0 ]; }

# ===========================================================================
# 1. team-core.sh 전제 가드
# ===========================================================================
CASE="team-core: 전제 가드(CF_EXTERNAL_LEAD 누락 · HERDR_PANE_ID 존재 · CLAUDE_CODE_SESSION_ID 누락 · worktree 차단)"
mkstate "impl:idle" "critic:idle"

: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && env -u CF_EXTERNAL_LEAD -u HERDR_PANE_ID CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	HC_BIN="${MOCK_HC}" MOCK_HC_STATE="${STATE}" MOCK_HC_LOG="${LOG}" \
	"${TEST_BASH}" "${CORE_SCRIPT}" --check 2>&1)"
RC=$?
check "CF_EXTERNAL_LEAD 누락 시 rc 2" eq "$RC" 2
check "CF_EXTERNAL_LEAD 누락 시 hc 호출 0" eq "$(wc -l <"${LOG}" | tr -d ' ')" 0

: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && CF_EXTERNAL_LEAD=1 HERDR_PANE_ID="wN:p1" CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	HC_BIN="${MOCK_HC}" MOCK_HC_STATE="${STATE}" MOCK_HC_LOG="${LOG}" \
	"${TEST_BASH}" "${CORE_SCRIPT}" --check 2>&1)"
RC=$?
check "HERDR_PANE_ID 존재 시 rc 1" eq "$RC" 1
check "HERDR_PANE_ID 존재 시 hc 호출 0" eq "$(wc -l <"${LOG}" | tr -d ' ')" 0

: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && env -u CLAUDE_CODE_SESSION_ID -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 \
	HC_BIN="${MOCK_HC}" MOCK_HC_STATE="${STATE}" MOCK_HC_LOG="${LOG}" \
	"${TEST_BASH}" "${CORE_SCRIPT}" --check 2>&1)"
RC=$?
check "CLAUDE_CODE_SESSION_ID 누락 시 rc 1" eq "$RC" 1

: >"${LOG}"
OUT="$(cd "${WT_LINKED}" && env -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	HC_BIN="${MOCK_HC}" MOCK_HC_STATE="${STATE}" MOCK_HC_LOG="${LOG}" \
	"${TEST_BASH}" "${WT_LINKED}/scripts/team-core.sh" --check 2>&1)"
RC=$?
check "연결 worktree 차단 rc 1" eq "$RC" 1

printf '%s\n' "${OTHER_SID}" >"${EXT_LOCK}"
run_core --up
check "다른 외부 팀장 세션 잠금 시 --up 거부 rc 1" eq "$RC" 1
printf '%s\n' "${EXT_SID}" >"${EXT_LOCK}"

# ===========================================================================
# 2. team-core.sh --check
# ===========================================================================
CASE="team-core --check: 두 팀원 live·옵션 일치 · 대화 id 추출 · herdr.space 표 칸 · 불일치 · 없음"
mkstate "impl:idle:${IMPL_CONV}" "critic:idle"
run_core --check
check "모두 정상 rc 0" eq "$RC" 0
check "읽기 전용(변경 호출 없음)" no_hc_mutations
check "--check 표 머리말에 herdr.space 칸 포함" line_matches "^석[[:space:]]+이름[[:space:]]+address[[:space:]]+agent[[:space:]]+상태[[:space:]]+turn[[:space:]]+herdr\\.space[[:space:]]+--up 조치\$"
check "--check 표 기본 herdr.space 없음(cf-impl)" line_matches "^impl[[:space:]]+cf-impl[[:space:]]+t26[[:space:]]+agy[[:space:]]+live\\(idle\\)[[:space:]]+1[[:space:]]+없음[[:space:]]+유지\$"
check "--check 표 기본 herdr.space 없음(cf-critic)" line_matches "^critic[[:space:]]+cf-critic[[:space:]]+t27[[:space:]]+codex[[:space:]]+live\\(idle\\)[[:space:]]+1[[:space:]]+없음[[:space:]]+유지\$"
check "cf-impl 요약 줄 + 대화 id 추출" line_matches "^cf-impl t26 ok 대화=${IMPL_CONV}\$"
check "cf-critic 요약 줄" line_matches "^cf-critic t27 ok\$"

# herdr.space 라벨이 있을 때 --check 표에 값 표시 및 옵션 불일치 판정에 넣지 않음
patch_term "cf-impl" '{"labels": {"role": "impl", "team": "cf", "herdr.space": "dummy-space-01"}}'
run_core --check
check "herdr.space 라벨 있어도 옵션 일치 rc 0" eq "$RC" 0
check "--check 표 cf-impl 행에 herdr.space 값 표시" line_matches "^impl[[:space:]]+cf-impl[[:space:]]+t26[[:space:]]+agy[[:space:]]+live\\(idle\\)[[:space:]]+1[[:space:]]+dummy-space-01[[:space:]]+유지\$"
check "--check 표 cf-critic 행에 herdr.space 없음 유지" line_matches "^critic[[:space:]]+cf-critic[[:space:]]+t27[[:space:]]+codex[[:space:]]+live\\(idle\\)[[:space:]]+1[[:space:]]+없음[[:space:]]+유지\$"

# 옵션 불일치(cf-impl --model 값 다름, cf-critic --sandbox 등 누락)
patch_term "cf-impl" '{"argv": ["agy", "--model", "wrong-model", "--mode", "accept-edits"]}'
run_core --check
check "옵션 불일치 시 rc 1" eq "$RC" 1
check "옵션 불일치 안내 줄" has "옵션 불일치:"
check "cf-impl mismatch 요약 줄" line_matches "^cf-impl t26 mismatch 실제=.* 기대=.*"

# critic 없음
mkstate "impl:idle"
run_core --check
check "critic 없음 시 rc 1" eq "$RC" 1
check "critic unknown 없음 요약 줄" line_matches "^cf-critic - unknown 없음\$"

# ===========================================================================
# 3. team-core.sh --up
# ===========================================================================
CASE="team-core --up: 없는 석만 기동 · 대화 id 없을 때 경고 · 대화 id 있을 때 전달 · CF_HERDR_SPACE 유무 두 갈래 · 살아 있는 같은 이름 hc run 거부"
# (1) cf-impl은 살아 있고 cf-critic만 없을 때 → cf-critic만 기동
mkstate "impl:idle:${IMPL_CONV}"
run_core --up
check "빠진 critic만 기동 rc 0" eq "$RC" 0
check "살아 있는 cf-impl 그대로 둠" has "cf-impl: 살아 있음(t26); 그대로 둠"
check "cf-critic 기동 완료(t28)" has "cf-critic: 기동 완료(t28)"
check "hc run 1회만 호출됨" eq "$(grep -c '^run	' "${LOG}")" 1
check "hc run이 cf-critic에만 호출됨" eq "$(grep -c '^run	.*--name	cf-critic	' "${LOG}")" 1

# (2) 둘 다 없을 때 대화 id 없이 기동(CF_HERDR_SPACE 미설정) → 경고 출력 후 기존 라벨 인자로만 기동
mkstate
run_core --up
check "둘 다 기동 rc 0" eq "$RC" 0
check "대화 id 없음 경고 출력" has "대화 id 없음 — 새 대화로 띄움"
check "hc run 2회 호출됨" eq "$(grep -c '^run	' "${LOG}")" 2
check "CF_HERDR_SPACE 미설정 시 herdr.space 라벨 미전달" eq "$(grep -c 'herdr\.space' "${LOG}")" 0
check "CF_HERDR_SPACE 미설정 시 cf-impl 기본 라벨 순서(--label team=cf --label role=impl --)" eq "$(grep -c "^run${T}--bg${T}--json${T}--no-parent${T}--outlive-parent${T}--name${T}cf-impl${T}--cwd${T}${TEST_REPO}${T}--label${T}team=cf${T}--label${T}role=impl${T}--${T}agy${T}" "${LOG}")" 1
check "CF_HERDR_SPACE 미설정 시 cf-critic 기본 라벨 순서(--label team=cf --label role=critic --)" eq "$(grep -c "^run${T}--bg${T}--json${T}--no-parent${T}--outlive-parent${T}--name${T}cf-critic${T}--cwd${T}${TEST_REPO}${T}--label${T}team=cf${T}--label${T}role=critic${T}--${T}codex${T}" "${LOG}")" 1
run_core --check
check "기동 후 재점검 rc 0" eq "$RC" 0

# (3) CF_HERDR_SPACE가 빈 문자열일 때도 기존과 동일(herdr.space 미전달)
mkstate "critic:idle"
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && env -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 CF_HERDR_SPACE="" CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	HC_BIN="${MOCK_HC}" MOCK_HC_STATE="${STATE}" MOCK_HC_LOG="${LOG}" \
	"${TEST_BASH}" "${CORE_SCRIPT}" --up "${IMPL_CONV}" 2>&1)"
RC=$?
check "대화 id 지정 기동(빈 CF_HERDR_SPACE) rc 0" eq "$RC" 0
check "대화 id 없음 경고 미출력" not_has "대화 id 없음 — 새 대화로 띄움"
check "--conversation 인자 전달됨" eq "$(grep -c "^run	.*--conversation	${IMPL_CONV}	" "${LOG}")" 1
check "빈 CF_HERDR_SPACE 시 herdr.space 라벨 미전달" eq "$(grep -c 'herdr\.space' "${LOG}")" 0

# (4) CF_HERDR_SPACE 설정 시 --label herdr.space=<값> 전달(기존 라벨 뒤, -- 앞, herdr.tab 없음) 및 --check 표 반영
mkstate
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && env -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 CF_HERDR_SPACE="dummy-space-01" CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	HC_BIN="${MOCK_HC}" MOCK_HC_STATE="${STATE}" MOCK_HC_LOG="${LOG}" \
	"${TEST_BASH}" "${CORE_SCRIPT}" --up "${IMPL_CONV}" 2>&1)"
RC=$?
check "CF_HERDR_SPACE 설정 기동 rc 0" eq "$RC" 0
check "CF_HERDR_SPACE 설정 시 cf-impl에 --label herdr.space=dummy-space-01 전달(기존 라벨 뒤)" eq "$(grep -c "^run${T}--bg${T}--json${T}--no-parent${T}--outlive-parent${T}--name${T}cf-impl${T}--cwd${T}${TEST_REPO}${T}--label${T}team=cf${T}--label${T}role=impl${T}--label${T}herdr.space=dummy-space-01${T}--${T}agy${T}" "${LOG}")" 1
check "CF_HERDR_SPACE 설정 시 cf-critic에 --label herdr.space=dummy-space-01 전달(기존 라벨 뒤)" eq "$(grep -c "^run${T}--bg${T}--json${T}--no-parent${T}--outlive-parent${T}--name${T}cf-critic${T}--cwd${T}${TEST_REPO}${T}--label${T}team=cf${T}--label${T}role=critic${T}--label${T}herdr.space=dummy-space-01${T}--${T}codex${T}" "${LOG}")" 1
check "herdr.tab 라벨은 붙이지 않음" eq "$(grep -c 'herdr\.tab' "${LOG}")" 0
run_core --check
check "CF_HERDR_SPACE 기동 후 --check rc 0" eq "$RC" 0
check "CF_HERDR_SPACE 기동 후 --check 표 cf-impl herdr.space 표시" line_matches "^impl[[:space:]]+cf-impl[[:space:]]+t28[[:space:]]+agy[[:space:]]+live\\(idle\\)[[:space:]]+1[[:space:]]+dummy-space-01[[:space:]]+유지\$"
check "CF_HERDR_SPACE 기동 후 --check 표 cf-critic herdr.space 표시" line_matches "^critic[[:space:]]+cf-critic[[:space:]]+t29[[:space:]]+codex[[:space:]]+live\\(idle\\)[[:space:]]+1[[:space:]]+dummy-space-01[[:space:]]+유지\$"

# (5) CF_HERDR_SPACE에 공백이 포함된 값도 가공·단어 분리 없이 그대로 전달
mkstate "critic:idle"
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && env -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 CF_HERDR_SPACE="dummy space 02" CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	HC_BIN="${MOCK_HC}" MOCK_HC_STATE="${STATE}" MOCK_HC_LOG="${LOG}" \
	"${TEST_BASH}" "${CORE_SCRIPT}" --up "${IMPL_CONV}" 2>&1)"
RC=$?
check "공백 포함 CF_HERDR_SPACE 기동 rc 0" eq "$RC" 0
check "공백 포함 CF_HERDR_SPACE 인용 보존 전달" eq "$(grep -c "^run${T}--bg${T}--json${T}--no-parent${T}--outlive-parent${T}--name${T}cf-impl${T}--cwd${T}${TEST_REPO}${T}--label${T}team=cf${T}--label${T}role=impl${T}--label${T}herdr.space=dummy space 02${T}--${T}agy${T}" "${LOG}")" 1

# (6) 살아 있는 같은 이름에 hc run 거부 경로(점검 직후 경합으로 이미 살아 있는 이름에 hc run 호출 시 거부)
mkstate "impl:idle" "critic:idle"
STATE_FILE="${STATE}" python3 -c '
import json, os
p = os.environ["STATE_FILE"]
st = json.load(open(p, encoding="utf-8"))
st["skip_get_once"] = ["cf-impl"]
json.dump(st, open(p, "w", encoding="utf-8"), indent=1)
'
run_core --up "${IMPL_CONV}"
check "살아 있는 같은 이름 hc run 거부 시 rc 1" eq "$RC" 1
check "hc 거부 원문 보고" has 'error: terminal "cf-impl" is already live'

# ===========================================================================
# 3b. team-core.sh --up App 탭 이름 부착 (⑴~⑻)
# ===========================================================================
CASE="team-core --up App 탭 이름 부착: ⑴ App 있음 · ⑵ 2번째 확인에 탭 나타남 · ⑶ 탭 끝내 없음 · ⑷ App 실행 파일 없음 · ⑸ 같은 탭 다른 터미널 · ⑹ CF_HERDR_SPACE 비어 있음/없음 · ⑺ rename 실패 응답 · ⑻ 살아 있는 석"

# ⑴ App 있음: rename 1회, --id·--name 인자 검사
mkstate "critic:idle"
mkappstate '{
 "spaces": [
  {
   "id": "cf",
   "name": "cf",
   "tabs": [
    {"id": "tb-dummy-lead", "name": "1", "terminals": [{"terminal": "t25", "name": "cf-lead"}]},
    {"id": "tb-dummy-impl", "name": "2", "terminals": [{"terminal": "t28", "name": "cf-impl"}]},
    {"id": "tb-dummy-critic", "name": "cf-critic", "terminals": [{"terminal": "t27", "name": "cf-critic"}]}
   ]
  }
 ]
}'
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && env -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 CF_HERDR_SPACE="cf" CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	HC_BIN="${MOCK_HC}" MOCK_HC_STATE="${STATE}" MOCK_HC_LOG="${LOG}" \
	HERDR_APP_BIN="${MOCK_APP}" MOCK_APP_STATE="${APP_STATE}" MOCK_APP_LOG="${APP_LOG}" \
	CF_APP_RETRIES=3 CF_APP_RETRY_SLEEP=0.02 \
	"${TEST_BASH}" "${CORE_SCRIPT}" --up "${IMPL_CONV}" 2>&1)"
RC=$?
check "⑴ App 있음: 기동 rc 0" eq "$RC" 0
check "⑴ App 있음: 기동 완료 출력" has "cf-impl: 기동 완료(t28)"
check "⑴ App 있음: 경고 미출력" not_has "탭 이름을" "이름 변경 실패"
check "⑴ App 있음: herdr-app ls 1회 호출" eq "$(grep -c '^ls$' "${APP_LOG}")" 1
check "⑴ App 있음: herdr-app do tab.rename 1회 호출" eq "$(grep -c '^do	tab\.rename	' "${APP_LOG}")" 1
check "⑴ App 있음: --id·--name 인자 정확 일치" eq "$(grep -c "^do${T}tab\\.rename${T}--id${T}tb-dummy-impl${T}--name${T}cf-impl\$" "${APP_LOG}")" 1
check "⑴ App 있음: App 전체 호출 2회(ls + do tab.rename만)" eq "$(wc -l <"${APP_LOG}" | tr -d ' ')" 2

# ⑵ 탭이 2번째 확인에 나타남: rename 1회
mkstate "critic:idle"
mkappstate '{
 "appear_on_ls": 2,
 "spaces": [
  {
   "id": "cf",
   "name": "cf",
   "tabs": [
    {"id": "tb-delayed-28", "name": "2", "terminals": [{"terminal": "t28", "name": "cf-impl"}]}
   ]
  }
 ]
}'
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && env -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 CF_HERDR_SPACE="cf" CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	HC_BIN="${MOCK_HC}" MOCK_HC_STATE="${STATE}" MOCK_HC_LOG="${LOG}" \
	HERDR_APP_BIN="${MOCK_APP}" MOCK_APP_STATE="${APP_STATE}" MOCK_APP_LOG="${APP_LOG}" \
	CF_APP_RETRIES=3 CF_APP_RETRY_SLEEP=0.02 \
	"${TEST_BASH}" "${CORE_SCRIPT}" --up "${IMPL_CONV}" 2>&1)"
RC=$?
check "⑵ 2번째 확인에 탭 나타남: rc 0" eq "$RC" 0
check "⑵ 2번째 확인에 탭 나타남: 경고 미출력" not_has "탭 이름을" "이름 변경 실패"
check "⑵ 2번째 확인에 탭 나타남: herdr-app ls 2회 호출" eq "$(grep -c '^ls$' "${APP_LOG}")" 2
check "⑵ 2번째 확인에 탭 나타남: herdr-app do tab.rename 1회 호출" eq "$(grep -c '^do	tab\.rename	' "${APP_LOG}")" 1
check "⑵ 2번째 확인에 탭 나타남: --id·--name 인자 정확 일치" eq "$(grep -c "^do${T}tab\\.rename${T}--id${T}tb-delayed-28${T}--name${T}cf-impl\$" "${APP_LOG}")" 1

# ⑶ 탭 끝내 없음: rename 0회·경고·rc 0
mkstate "critic:idle"
mkappstate '{
 "spaces": [
  {
   "id": "cf",
   "name": "cf",
   "tabs": [
    {"id": "tb-other-only", "name": "1", "terminals": [{"terminal": "t25", "name": "cf-lead"}]}
   ]
  }
 ]
}'
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && env -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 CF_HERDR_SPACE="cf" CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	HC_BIN="${MOCK_HC}" MOCK_HC_STATE="${STATE}" MOCK_HC_LOG="${LOG}" \
	HERDR_APP_BIN="${MOCK_APP}" MOCK_APP_STATE="${APP_STATE}" MOCK_APP_LOG="${APP_LOG}" \
	CF_APP_RETRIES=3 CF_APP_RETRY_SLEEP=0.02 \
	"${TEST_BASH}" "${CORE_SCRIPT}" --up "${IMPL_CONV}" 2>&1)"
RC=$?
check "⑶ 탭 끝내 없음: rc 0" eq "$RC" 0
check "⑶ 탭 끝내 없음: 기동 완료 출력" has "cf-impl: 기동 완료(t28)"
check "⑶ 탭 끝내 없음: 경고 출력" has "team-core: cf-impl: 공간 'cf'에서 탭을 찾지 못해 탭 이름을 붙이지 못함(t28)"
check "⑶ 탭 끝내 없음: herdr-app ls 상한(3회)만큼만 호출" eq "$(grep -c '^ls$' "${APP_LOG}")" 3
check "⑶ 탭 끝내 없음: rename 호출 0회" eq "$(grep -c '^do	' "${APP_LOG}")" 0

# ⑷ App 실행 파일 없음: 경고·rc 0
mkstate "critic:idle"
mkappstate
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && env -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 CF_HERDR_SPACE="cf" CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	HC_BIN="${MOCK_HC}" MOCK_HC_STATE="${STATE}" MOCK_HC_LOG="${LOG}" \
	HERDR_APP_BIN="${TMP}/bin/no-such-herdr-app" MOCK_APP_STATE="${APP_STATE}" MOCK_APP_LOG="${APP_LOG}" \
	CF_APP_RETRIES=3 CF_APP_RETRY_SLEEP=0.02 \
	"${TEST_BASH}" "${CORE_SCRIPT}" --up "${IMPL_CONV}" 2>&1)"
RC=$?
check "⑷ App 실행 파일 없음: rc 0" eq "$RC" 0
check "⑷ App 실행 파일 없음: 기동 완료 출력" has "cf-impl: 기동 완료(t28)"
check "⑷ App 실행 파일 없음: 경고 출력" has "이 없어 탭 이름을 붙이지 못함(t28)"
check "⑷ App 실행 파일 없음: App 호출 0회" eq "$(wc -l <"${APP_LOG}" | tr -d ' ')" 0

# ⑸ 같은 탭에 다른 터미널: rename 0회·경고
mkstate "critic:idle"
mkappstate '{
 "spaces": [
  {
   "id": "cf",
   "name": "cf",
   "tabs": [
    {
     "id": "tb-shared-01",
     "name": "1",
     "terminals": [
      {"terminal": "t25", "name": "cf-lead"},
      {"terminal": "t28", "name": "cf-impl"}
     ]
    }
   ]
  }
 ]
}'
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && env -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 CF_HERDR_SPACE="cf" CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	HC_BIN="${MOCK_HC}" MOCK_HC_STATE="${STATE}" MOCK_HC_LOG="${LOG}" \
	HERDR_APP_BIN="${MOCK_APP}" MOCK_APP_STATE="${APP_STATE}" MOCK_APP_LOG="${APP_LOG}" \
	CF_APP_RETRIES=3 CF_APP_RETRY_SLEEP=0.02 \
	"${TEST_BASH}" "${CORE_SCRIPT}" --up "${IMPL_CONV}" 2>&1)"
RC=$?
check "⑸ 같은 탭 다른 터미널: rc 0" eq "$RC" 0
check "⑸ 같은 탭 다른 터미널: 기동 완료 출력" has "cf-impl: 기동 완료(t28)"
check "⑸ 같은 탭 다른 터미널: 경고 출력" has "team-core: cf-impl: 탭(tb-shared-01)에 다른 터미널이 함께 있어 탭 이름을 바꾸지 않음(t28)"
check "⑸ 같은 탭 다른 터미널: herdr-app ls 1회 호출(재시도 없음)" eq "$(grep -c '^ls$' "${APP_LOG}")" 1
check "⑸ 같은 탭 다른 터미널: rename 호출 0회" eq "$(grep -c '^do	' "${APP_LOG}")" 0

# ⑹ CF_HERDR_SPACE 비어 있음/없음: App 호출 0회
mkstate "critic:idle"
mkappstate '{
 "spaces": [
  {
   "id": "cf",
   "name": "cf",
   "tabs": [{"id": "tb-28", "name": "2", "terminals": [{"terminal": "t28"}]}]
  }
 ]
}'
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && env -u HERDR_PANE_ID -u CF_HERDR_SPACE CF_EXTERNAL_LEAD=1 CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	HC_BIN="${MOCK_HC}" MOCK_HC_STATE="${STATE}" MOCK_HC_LOG="${LOG}" \
	HERDR_APP_BIN="${MOCK_APP}" MOCK_APP_STATE="${APP_STATE}" MOCK_APP_LOG="${APP_LOG}" \
	"${TEST_BASH}" "${CORE_SCRIPT}" --up "${IMPL_CONV}" 2>&1)"
RC=$?
check "⑹(없음) CF_HERDR_SPACE 미설정: rc 0" eq "$RC" 0
check "⑹(없음) CF_HERDR_SPACE 미설정: App 호출 0회" eq "$(wc -l <"${APP_LOG}" | tr -d ' ')" 0

mkstate "critic:idle"
: >"${LOG}"
: >"${APP_LOG}"
OUT="$(cd "${TEST_REPO}" && env -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 CF_HERDR_SPACE="" CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	HC_BIN="${MOCK_HC}" MOCK_HC_STATE="${STATE}" MOCK_HC_LOG="${LOG}" \
	HERDR_APP_BIN="${MOCK_APP}" MOCK_APP_STATE="${APP_STATE}" MOCK_APP_LOG="${APP_LOG}" \
	"${TEST_BASH}" "${CORE_SCRIPT}" --up "${IMPL_CONV}" 2>&1)"
RC=$?
check "⑹(비어 있음) 빈 CF_HERDR_SPACE: rc 0" eq "$RC" 0
check "⑹(비어 있음) 빈 CF_HERDR_SPACE: App 호출 0회" eq "$(wc -l <"${APP_LOG}" | tr -d ' ')" 0

# ⑺ rename 실패 응답: 경고·rc 0
mkstate "critic:idle"
mkappstate '{
 "rename_response": {"ok": false, "error": "tab locked"},
 "spaces": [
  {
   "id": "cf",
   "name": "cf",
   "tabs": [{"id": "tb-fail-json", "name": "2", "terminals": [{"terminal": "t28"}]}]
  }
 ]
}'
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && env -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 CF_HERDR_SPACE="cf" CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	HC_BIN="${MOCK_HC}" MOCK_HC_STATE="${STATE}" MOCK_HC_LOG="${LOG}" \
	HERDR_APP_BIN="${MOCK_APP}" MOCK_APP_STATE="${APP_STATE}" MOCK_APP_LOG="${APP_LOG}" \
	"${TEST_BASH}" "${CORE_SCRIPT}" --up "${IMPL_CONV}" 2>&1)"
RC=$?
check "⑺(ok:false) rename 실패 응답: rc 0" eq "$RC" 0
check "⑺(ok:false) rename 실패 응답: 기동 완료 출력" has "cf-impl: 기동 완료(t28)"
check "⑺(ok:false) rename 실패 응답: 경고 출력" has "team-core: cf-impl: 탭(tb-fail-json) 이름 변경 실패(rc=0):"
check "⑺(ok:false) rename 실패 응답: ls 1회·do tab.rename 1회 호출" eq "$(grep -c '^do	tab\.rename	' "${APP_LOG}")" 1

mkstate "critic:idle"
mkappstate '{
 "rename_rc": 1,
 "rename_stderr": "error: tab.rename failed",
 "spaces": [
  {
   "id": "cf",
   "name": "cf",
   "tabs": [{"id": "tb-fail-rc", "name": "2", "terminals": [{"terminal": "t28"}]}]
  }
 ]
}'
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && env -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 CF_HERDR_SPACE="cf" CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	HC_BIN="${MOCK_HC}" MOCK_HC_STATE="${STATE}" MOCK_HC_LOG="${LOG}" \
	HERDR_APP_BIN="${MOCK_APP}" MOCK_APP_STATE="${APP_STATE}" MOCK_APP_LOG="${APP_LOG}" \
	"${TEST_BASH}" "${CORE_SCRIPT}" --up "${IMPL_CONV}" 2>&1)"
RC=$?
check "⑺(비0 종료) rename 실패 응답: rc 0" eq "$RC" 0
check "⑺(비0 종료) rename 실패 응답: 기동 완료 출력" has "cf-impl: 기동 완료(t28)"
check "⑺(비0 종료) rename 실패 응답: 경고 출력" has "team-core: cf-impl: 탭(tb-fail-rc) 이름 변경 실패(rc=1):"
check "⑺(비0 종료) rename 실패 응답: ls 1회·do tab.rename 1회 호출" eq "$(grep -c '^do	tab\.rename	' "${APP_LOG}")" 1

# ⑻ 살아 있는 석(기동 안 함): App 호출 0회
mkstate "impl:idle:${IMPL_CONV}" "critic:idle"
mkappstate '{
 "spaces": [
  {
   "id": "cf",
   "name": "cf",
   "tabs": [
    {"id": "tb-26", "name": "cf-impl", "terminals": [{"terminal": "t26"}]},
    {"id": "tb-27", "name": "cf-critic", "terminals": [{"terminal": "t27"}]}
   ]
  }
 ]
}'
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && env -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 CF_HERDR_SPACE="cf" CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	HC_BIN="${MOCK_HC}" MOCK_HC_STATE="${STATE}" MOCK_HC_LOG="${LOG}" \
	HERDR_APP_BIN="${MOCK_APP}" MOCK_APP_STATE="${APP_STATE}" MOCK_APP_LOG="${APP_LOG}" \
	"${TEST_BASH}" "${CORE_SCRIPT}" --up "${IMPL_CONV}" 2>&1)"
RC=$?
check "⑻ 살아 있는 석: rc 0" eq "$RC" 0
check "⑻ 살아 있는 석: 그대로 둠 출력" has "cf-impl: 살아 있음(t26); 그대로 둠" "cf-critic: 살아 있음(t27); 그대로 둠"
check "⑻ 살아 있는 석: App 호출 0회" eq "$(wc -l <"${APP_LOG}" | tr -d ' ')" 0

# ===========================================================================
# 4. team-core.sh --status
# ===========================================================================
CASE="team-core --status: 마탑 가이드 §3 보고 꼴 출력 및 확인창 상태 표시"
mkstate "impl:blocked:${IMPL_CONV}" "critic:idle"
run_core --status "이주점검"
check "--status rc 0" eq "$RC" 0
check "읽기 전용" no_hc_mutations
check "머리말 출력" has "[CF 팀장→마탑] 답: 팀 점검·구성(이주점검,"
check "팀장 세션·잠금 mine 출력" has "팀장 모드 외부(Core), 잠금 mine"
check "cf-impl 확인창 있음·blocked 표시" has "- 팀원: cf-impl t26 agy 옵션 일치 ○ 세션 id 기록 ○ 확인창 있음 상태 blocked"
check "cf-critic 확인창 없음·idle 표시" has "- 팀원: cf-critic t27 codex 옵션 일치 ○ 세션 id 기록 × 확인창 없음 상태 idle"
check "고정 꼬리말 출력" has "이 메시지는 승인이 아니다."

# ===========================================================================
# 5. team-core.sh --down
# ===========================================================================
CASE="team-core --down: working·blocked 거부 및 idle·done 시 kill→rm"
mkstate "impl:working" "critic:blocked"
run_core --down cf-impl
check "working 상태 --down 거부 rc 1" eq "$RC" 1
check "working 상태 kill·rm 호출 0" eq "$(grep -cE '^(kill|rm)	' "${LOG}")" 0

run_core --down cf-critic
check "blocked 상태 --down 거부 rc 1" eq "$RC" 1
check "blocked 상태 kill·rm 호출 0" eq "$(grep -cE '^(kill|rm)	' "${LOG}")" 0

mkstate "impl:done" "critic:idle"
run_core --down cf-impl
check "done 상태 --down rc 0" eq "$RC" 0
check "kill 후 rm 순서 호출" eq "$(grep -E '^(kill|rm)	' "${LOG}" | tr '\n' ';')" "kill${T}cf-impl${T}--json;rm${T}cf-impl${T}--json;"

run_core --down cf-critic
check "idle 상태 --down rc 0" eq "$RC" 0
check "kill 후 rm 호출" eq "$(grep -E '^(kill|rm)	' "${LOG}" | tr '\n' ';')" "kill${T}cf-critic${T}--json;rm${T}cf-critic${T}--json;"

# ===========================================================================
# 6. core-watch.sh --send
# ===========================================================================
CASE="core-watch --send: idle은 --if idle · done은 --if 없이 · blocked·working은 거부"
mkstate "impl:idle" "critic:done"
run_watch_cmd --send cf-impl "hello-impl"
check "idle 전송 rc 0" eq "$RC" 0
check "idle 전송 시 hc send --if idle 호출" eq "$(grep -c "^send${T}--if${T}idle${T}cf-impl${T}hello-impl\$" "${LOG}")" 1

run_watch_cmd --send cf-critic "hello-critic"
check "done 전송 rc 0(done != idle 처리)" eq "$RC" 0
check "done 전송 시 --if 없이 hc send 호출" eq "$(grep -c "^send${T}cf-critic${T}hello-critic\$" "${LOG}")" 1

mkstate "impl:blocked" "critic:working"
run_watch_cmd --send cf-impl "never-send-1"
check "blocked 전송 거부 rc 1" eq "$RC" 1
check "blocked 거부 이벤트 출력" has "EVENT send-refused cf-impl status=blocked"
check "blocked 시 hc send 호출 0" eq "$(grep -c '^send	' "${LOG}")" 0

run_watch_cmd --send cf-critic "never-send-2"
check "working 전송 거부 rc 1" eq "$RC" 1
check "working 거부 이벤트 출력" has "EVENT send-refused cf-critic status=working"
check "working 시 hc send 호출 0" eq "$(grep -c '^send	' "${LOG}")" 0

# ===========================================================================
# 7. core-watch.sh --approve-once
# ===========================================================================
CASE="core-watch --approve-once: --allow-file 바이트 정확 일치 1건 승인 · 공백/옵션/경로/접두어/결합옵션/여러줄/파일없음/msg누락/비blocked 거부"
mkstate "impl:blocked" "critic:idle"
ALLOW_FILE="${TMP}/allowed-cmds.txt"
EMPTY_ALLOW_FILE="${TMP}/allowed-empty.txt"
printf 'hc get cf-critic --json\n' >"${ALLOW_FILE}"
: >"${EMPTY_ALLOW_FILE}"

# (1) 정확 일치 승인 1건(--allow-file 줄과 status.msg 바이트 그대로 일치)
patch_term "cf-impl" '{"status": {"state": "blocked", "msg": "hc get cf-critic --json"}}'
run_watch_cmd --approve-once cf-impl --allow-file "${ALLOW_FILE}"
check "정확 일치 승인 rc 0" eq "$RC" 0
check "정확 일치 APPROVED 출력" eq "$OUT" "APPROVED cf-impl enter"
check "정확 일치 hc keys cf-impl enter --json 1회 호출" eq "$(grep -c "^keys${T}cf-impl${T}enter${T}--json\$" "${LOG}")" 1

# (2) 허용 파일 없음·미지정·빈 파일 거부 (keys 호출 0회)
patch_term "cf-impl" '{"status": {"state": "blocked", "msg": "hc get cf-critic --json"}}'
run_watch_cmd --approve-once cf-impl
check "--allow-file 미지정 거부 rc 1" eq "$RC" 1
check "--allow-file 미지정 allow-file-missing 출력" eq "$OUT" "EVENT blocked-unhandled cf-impl allow-file-missing"
check "--allow-file 미지정 keys 호출 0" eq "$(grep -c '^keys	' "${LOG}")" 0

run_watch_cmd --approve-once cf-impl --allow-file "${TMP}/no-such-file.txt"
check "존재하지 않는 --allow-file 거부 rc 1" eq "$RC" 1
check "존재하지 않는 --allow-file allow-file-missing 출력" eq "$OUT" "EVENT blocked-unhandled cf-impl allow-file-missing"
check "존재하지 않는 --allow-file keys 호출 0" eq "$(grep -c '^keys	' "${LOG}")" 0

run_watch_cmd --approve-once cf-impl --allow-file "${EMPTY_ALLOW_FILE}"
check "빈 --allow-file 거부 rc 1" eq "$RC" 1
check "빈 --allow-file allow-file-empty 출력" eq "$OUT" "EVENT blocked-unhandled cf-impl allow-file-empty"
check "빈 --allow-file keys 호출 0" eq "$(grep -c '^keys	' "${LOG}")" 0

# (3) 공백·옵션·경로·접두어·결합 옵션·쓰기 변형 거부 (모두 keys 호출 0회)
for bad_cmd in \
	" hc get cf-critic --json" \
	"hc get cf-critic --json " \
	"hc  get cf-critic --json" \
	"hc get cf-critic" \
	"hc get --json cf-critic" \
	"/usr/local/bin/hc get cf-critic --json" \
	"/tmp/unapproved/hc get cf-critic --json" \
	"/tmp/unapproved/git status" \
	"Run this command? hc get cf-critic --json" \
	"env hc get cf-critic --json" \
	"git hash-object -wt blob README.md" \
	"git diff --ext-diff" \
	"git log --ext-diff -p -1" \
	"git add AGENTS.md" \
	"git commit -F /tmp/cf-i30-c1/commit-msg.txt" \
	"herdr pane send-keys other-team-pane down enter" \
	"herdr agent rename wOther:p99 cf-critic" \
	"herdr agent prompt cf-critic /new" \
	"hc get cf-critic --json && rm -rf /tmp/x"; do
	patch_term "cf-impl" "{\"status\": {\"state\": \"blocked\", \"msg\": \"${bad_cmd}\"}}"
	run_watch_cmd --approve-once cf-impl --allow-file "${ALLOW_FILE}"
	check "변형 거부(${bad_cmd}) rc 1" eq "$RC" 1
	check "변형 거부(${bad_cmd}) disallowed-command" eq "$OUT" "EVENT blocked-unhandled cf-impl disallowed-command"
	check "변형 거부(${bad_cmd}) keys 호출 0" eq "$(grep -c '^keys	' "${LOG}")" 0
done

# (4) 여러 줄 변형(첫 줄 일치+둘째 줄 추가 / 머리말 줄바꿈 / 잘림 줄바꿈) 거부 (keys 호출 0회)
patch_term "cf-impl" '{"status": {"state": "blocked", "msg": "hc get cf-critic --json\ngit push --force origin main"}}'
run_watch_cmd --approve-once cf-impl --allow-file "${ALLOW_FILE}"
check "여러 줄 변형(첫 줄 일치+둘째 줄 추가) 거부 rc 1" eq "$RC" 1
check "여러 줄 변형 disallowed-command 출력" eq "$OUT" "EVENT blocked-unhandled cf-impl disallowed-command"
check "여러 줄 변형 keys 호출 0" eq "$(grep -c '^keys	' "${LOG}")" 0

patch_term "cf-impl" '{"status": {"state": "blocked", "msg": "Run this command?\nhc get cf-critic --json"}}'
run_watch_cmd --approve-once cf-impl --allow-file "${ALLOW_FILE}"
check "여러 줄 변형(머리말 줄바꿈) 거부 rc 1" eq "$RC" 1
check "여러 줄 변형(머리말 줄바꿈) keys 호출 0" eq "$(grep -c '^keys	' "${LOG}")" 0

patch_term "cf-impl" '{"status": {"state": "blocked", "msg": "hc get cf-critic --json\n\u2026"}}'
run_watch_cmd --approve-once cf-impl --allow-file "${ALLOW_FILE}"
check "여러 줄 변형(잘림 줄바꿈) 거부 rc 1" eq "$RC" 1
check "여러 줄 변형(잘림 줄바꿈) keys 호출 0" eq "$(grep -c '^keys	' "${LOG}")" 0

# (5) status.msg 비어 있음(누락) → 거부 및 키 미전송
patch_term "cf-impl" '{"status": {"state": "blocked", "msg": ""}}'
run_watch_cmd --approve-once cf-impl --allow-file "${ALLOW_FILE}"
check "status.msg 비어 있을 때 거부 rc 1" eq "$RC" 1
check "blocked-unhandled msg-empty 출력" eq "$OUT" "EVENT blocked-unhandled cf-impl msg-empty"
check "msg 비어 있을 때 hc keys 호출 0" eq "$(grep -c '^keys	' "${LOG}")" 0

# (6) blocked 아님(idle) → 거부 및 키 미전송
patch_term "cf-impl" '{"status": {"state": "idle", "msg": "hc get cf-critic --json"}}'
run_watch_cmd --approve-once cf-impl --allow-file "${ALLOW_FILE}"
check "idle 상태 --approve-once 거부 rc 1" eq "$RC" 1
check "blocked-unhandled not-blocked 출력" has "EVENT blocked-unhandled cf-impl not-blocked"
check "idle 상태 시 hc keys 호출 0" eq "$(grep -c '^keys	' "${LOG}")" 0

# ===========================================================================
# 8. core-watch.sh --critic-new
# ===========================================================================
CASE="core-watch --critic-new: ⒜ 선택창 있음(idle·turn 불변→enter 1회→turn+1) · ⒝ 선택창 없음(turn 즉시 증가→enter 0회) · ⒞ turn 미증가 지속(enter 1회 뒤 실패) · ⒟ 비idle(keys 0회)"
# ⒜ 선택창 있음: /new 뒤 status.state=="idle"·turn 불변 → hc keys cf-critic enter 1회 → turn+1 → 성공
mkstate "impl:idle" "critic:idle"
STATE_FILE="${STATE}" python3 -c '
import json, os
p = os.environ["STATE_FILE"]
st = json.load(open(p, encoding="utf-8"))
st["no_turn_inc_on_new"] = True
json.dump(st, open(p, "w", encoding="utf-8"), indent=1)
'
MOCK_HC_ENTER="${TMP}/bin/hc-critic-enter"
cat >"${MOCK_HC_ENTER}" <<EOF
#!/usr/bin/env bash
"${MOCK_HC}" "\$@"
rc=\$?
if [ "\$rc" -eq 0 ] && [ "\${1:-}" = "keys" ] && [ "\${2:-}" = "cf-critic" ] && [ "\${3:-}" = "enter" ]; then
	python3 -c '
import json, os
p = os.environ["MOCK_HC_STATE"]
with open(p, encoding="utf-8") as f:
    st = json.load(f)
for t in st.get("terminals", []):
    if t.get("name") == "cf-critic":
        t["turn"] = int(t.get("turn") or 1) + 1
with open(p, "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False, indent=1)
'
fi
exit "\$rc"
EOF
chmod +x "${MOCK_HC_ENTER}"
: >"${LOG}"
OUT="$(cd "${TEST_REPO}" && env -u HERDR_PANE_ID CF_EXTERNAL_LEAD=1 CLAUDE_CODE_SESSION_ID="${EXT_SID}" \
	HC_BIN="${MOCK_HC_ENTER}" MOCK_HC_STATE="${STATE}" MOCK_HC_LOG="${LOG}" \
	CF_RETRIES=5 CF_RETRY_SLEEP=0.05 \
	"${TEST_BASH}" "${WATCH_SCRIPT}" --critic-new 2>&1)"
RC=$?
check "⒜ 선택창 있음(idle·turn 불변→enter 1회→turn+1) rc 0" eq "$RC" 0
check "⒜ turn 1→2 및 status=idle 확인 출력" has "cf-critic: /new 완료 (turn 1→2, status=idle)"
check "⒜ idle 시작 시 hc send --if idle cf-critic /new 1회 호출" eq "$(grep -c "^send${T}--if${T}idle${T}cf-critic${T}/new\$" "${LOG}")" 1
check "⒜ 선택창에 hc keys cf-critic enter 정확히 1회 호출" eq "$(grep -c "^keys${T}cf-critic${T}enter\$" "${LOG}")" 1
check "⒜ 전체 keys 호출 횟수 1회" eq "$(grep -c '^keys	' "${LOG}")" 1
check "⒜ rename 호출 없음" eq "$(grep -c 'rename' "${LOG}")" 0
check "⒜ 화면 읽기(hc read) 호출 0" eq "$(grep -c '^read	' "${LOG}")" 0

# ⒝ 선택창 없음(1): done 시작 분기 (/new 뒤 turn 즉시 증가 → enter 0회 → 성공)
mkstate "impl:idle" "critic:done"
run_watch_cmd --critic-new
check "⒝ 선택창 없음(done 시작) rc 0" eq "$RC" 0
check "⒝(done 시작) turn 1→2 및 status=idle 확인 출력" has "cf-critic: /new 완료 (turn 1→2, status=idle)"
check "⒝(done 시작) --if 없이 hc send cf-critic /new 호출됨" eq "$(grep -c "^send${T}cf-critic${T}/new\$" "${LOG}")" 1
check "⒝(done 시작) turn 즉시 증가 시 keys 호출 0회" eq "$(grep -c '^keys	' "${LOG}")" 0
check "⒝(done 시작) rename 호출 없음" eq "$(grep -c 'rename' "${LOG}")" 0

# ⒝ 선택창 없음(2): idle 시작 분기 (/new 뒤 turn 즉시 증가 → enter 0회 → 성공)
mkstate "impl:idle" "critic:idle"
run_watch_cmd --critic-new
check "⒝ 선택창 없음(idle 시작) rc 0" eq "$RC" 0
check "⒝(idle 시작) hc send --if idle cf-critic /new 호출됨" eq "$(grep -c "^send${T}--if${T}idle${T}cf-critic${T}/new\$" "${LOG}")" 1
check "⒝(idle 시작) turn 즉시 증가 시 keys 호출 0회" eq "$(grep -c '^keys	' "${LOG}")" 0

# ⒞ turn 미증가 지속: /new 뒤 idle·turn 불변 → enter 1회 전송 뒤에도 turn 불변 지속 → 실패(rc 1) 및 keys 총 1회만 호출
mkstate "impl:idle" "critic:idle"
STATE_FILE="${STATE}" python3 -c '
import json, os
p = os.environ["STATE_FILE"]
st = json.load(open(p, encoding="utf-8"))
st["no_turn_inc_on_new"] = True
json.dump(st, open(p, "w", encoding="utf-8"), indent=1)
'
run_watch_cmd --critic-new
check "⒞ turn 미증가 지속 시 --critic-new 실패 rc 1" eq "$RC" 1
check "⒞ turn 미증가 지속 시에도 hc keys cf-critic enter는 1회만 호출" eq "$(grep -c "^keys${T}cf-critic${T}enter\$" "${LOG}")" 1
check "⒞ 전체 keys 호출 횟수 1회(반복 전송 없음)" eq "$(grep -c '^keys	' "${LOG}")" 1

# ⒟ 비idle 상태 검증: 시작이 working이거나 /new 뒤 blocked·working이면 keys 호출 0회 및 실패(rc 1)
mkstate "impl:idle" "critic:working"
run_watch_cmd --critic-new
check "⒟ critic working 시작 시 --critic-new 거부 rc 1" eq "$RC" 1
check "⒟ critic working 시작 시 hc send 호출 0" eq "$(grep -c '^send	' "${LOG}")" 0
check "⒟ critic working 시작 시 hc keys 호출 0" eq "$(grep -c '^keys	' "${LOG}")" 0

mkstate "impl:idle" "critic:idle"
STATE_FILE="${STATE}" python3 -c '
import json, os
p = os.environ["STATE_FILE"]
st = json.load(open(p, encoding="utf-8"))
st["no_turn_inc_on_new"] = True
st["status_after_new"] = "blocked"
json.dump(st, open(p, "w", encoding="utf-8"), indent=1)
'
run_watch_cmd --critic-new
check "⒟ /new 뒤 blocked 상태일 때 실패 rc 1" eq "$RC" 1
check "⒟ /new 뒤 blocked 상태일 때 keys 호출 0회" eq "$(grep -c '^keys	' "${LOG}")" 0

mkstate "impl:idle" "critic:idle"
STATE_FILE="${STATE}" python3 -c '
import json, os
p = os.environ["STATE_FILE"]
st = json.load(open(p, encoding="utf-8"))
st["no_turn_inc_on_new"] = True
st["status_after_new"] = "working"
json.dump(st, open(p, "w", encoding="utf-8"), indent=1)
'
run_watch_cmd --critic-new
check "⒟ /new 뒤 working 지속일 때 실패 rc 1" eq "$RC" 1
check "⒟ /new 뒤 working 지속일 때 keys 호출 0회" eq "$(grep -c '^keys	' "${LOG}")" 0

# ===========================================================================
# 9. core-watch.sh --watch
# ===========================================================================
CASE="core-watch --watch: to-lead 새 파일 감지 · blocked 시 여러 줄 status.msg 전체 출력 · error 감지 · --max 타임아웃"
ROUND_DIR="${TMP}/cf-work/issues/30/r1"
mkdir -p "${ROUND_DIR}/to-lead"
printf 'ack\n' >"${ROUND_DIR}/to-lead/01-ACK.md"

# (1) to-lead/ 새 REPORT 파일 감지(01-ACK.md는 무시하고 새로 생긴 02-REPORT.md 감지)
mkstate "impl:working" "critic:idle"
(
	sleep 0.2
	printf 'done\n' >"${ROUND_DIR}/to-lead/02-REPORT.md"
) &
BG_WRITER=$!
run_watch_cmd --watch "${ROUND_DIR}" --max 5 --interval 1
wait "${BG_WRITER}"
check "to-lead 새 파일 감지 rc 0" eq "$RC" 0
check "EVENT to-lead 경로 출력" eq "$OUT" "EVENT to-lead ${ROUND_DIR}/to-lead/02-REPORT.md"

# (2) blocked 감지 시 여러 줄 status.msg 원문 전체를 잘리지 않고 출력
mkstate "impl:blocked" "critic:idle"
patch_term "cf-impl" '{"status": {"state": "blocked", "msg": "Run this command?\ngit commit -F /tmp/cf-i30-c1/commit-msg.txt"}}'
run_watch_cmd --watch "${ROUND_DIR}" --max 5 --interval 1
check "blocked 감지 rc 0" eq "$RC" 0
check "EVENT blocked 및 여러 줄 status.msg 전체 출력" eq "$OUT" "$(printf 'EVENT blocked cf-impl\nRun this command?\ngit commit -F /tmp/cf-i30-c1/commit-msg.txt')"

# (3) error 감지(status.state == error 또는 state != live)
mkstate "impl:error" "critic:idle"
run_watch_cmd --watch "${ROUND_DIR}" --max 5 --interval 1
check "error 상태 감지 rc 0" eq "$RC" 0
check "EVENT error 출력" eq "$OUT" "EVENT error cf-impl state=live status=error"

mkstate "impl:idle" "critic:idle:exited"
run_watch_cmd --watch "${ROUND_DIR}" --max 5 --interval 1
check "exited 상태 감지 rc 0" eq "$RC" 0
check "EVENT error state=exited 출력" eq "$OUT" "EVENT error cf-critic state=exited status=idle"

# (4) --max 타임아웃
mkstate "impl:working" "critic:idle"
run_watch_cmd --watch "${ROUND_DIR}" --max 1 --interval 1
check "--max 타임아웃 rc 0" eq "$RC" 0
check "EVENT timeout 출력" eq "$OUT" "EVENT timeout"
check "화면 읽기(hc read) 호출 0" eq "$(grep -c '^read	' "${LOG}")" 0

# shellcheck disable=SC2016
echo "team-core 테스트: 통과 ${PASS} / 전체 $((PASS + FAIL)) (bash: $("${TEST_BASH}" -c 'echo $BASH_VERSION'))"
[ "${FAIL}" -eq 0 ]

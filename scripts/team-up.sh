#!/usr/bin/env bash
# ctx-footer 팀(팀장 1 + 팀원 2) 기동·복구. Herdr pane 안(또는 CF_EXTERNAL_LEAD=1 외부 팀장), 이 저장소 안에서만 동작한다.
#   scripts/team-up.sh [--check]              점검만: 세 석의 pane·agent·상태 표 + 팀원마다 공통 한 줄 출력(변경 없음)
#                                             종료 코드 0 = 세 석 모두 살아 있고 팀원 옵션 일치, 1 = 아니거나 오류
#   scripts/team-up.sh --up [<agy 대화 id>]   이 pane을 cf-lead로 확보하고(외부 팀장은 생략) 없는 팀원을 띄운 뒤 배치를 맞춘다
#   scripts/team-up.sh --status [<계기>]      마탑 가이드 §3 보고 꼴 출력(변경 없음)
#   scripts/team-up.sh --lock status          외부 팀장 전용(CF_EXTERNAL_LEAD=1): 잠금 판정 한 줄(none|mine|other live|stale|unknown)
#   scripts/team-up.sh --lock claim [--force] 외부 팀장 전용(CF_EXTERNAL_LEAD=1): 외부 팀장 기록을 이 세션으로 잡는다
#   scripts/team-up.sh --lock release         외부 팀장 전용(CF_EXTERNAL_LEAD=1): 기록이 mine일 때만 지운다
#   scripts/team-up.sh --hook [--hook-clear]  SessionStart(clear) 훅 전용: 팀장 pane에 cf-lead 이름을 다시 붙인다
# 다른 pane이 쓰는 이름은 건드리지 않는다. 살아 있는 팀원은 재생성하지 않는다.
# 남은 빈 셸 pane(같은 작업공간·label 일치·agent 없음·저장소 cwd)은 새로 만들지 않고 재사용한다.
set -u

# --- 팀 정의: AGENTS.md 「팀」 표와 일치시킨다 (인덱스 0 = 팀장, 1..2 = 아래 줄 왼쪽부터) ---
# 상주 scout가 필요해지면 4석째 cf-scout(GJC kimi3)를 이 표에 추가한다(docs/04 §1 — 지금은 자리만 비워 둠).
IMPL_MODEL="gemini-4-argon-high"
SEAT_ROLE=(lead impl critic)
SEAT_NAME=(cf-lead cf-impl cf-critic)
SEAT_KIND=(claude agy codex) # Herdr가 감지하는 agent 종류
SEAT_LABEL=("CF 팀장 · Claude" "CF 구현 · agy" "CF 검토 · Codex")
SEAT_CMD=(
	"" # 팀장은 사람이 이 pane에서 띄운다. 스크립트는 팀장을 실행하지 않는다.
	"agy --model $IMPL_MODEL --mode accept-edits --sandbox"
	'codex --search --yolo --disable worktrees -m gpt-6.1-sol -c model_reasoning_effort="high"'
)
LEAD_RATIO=0.6                       # 배치 기준: 팀장(위) pane이 차지하는 세로 비율
ROW_RATIO=0.5                        # 배치 기준: 아래 줄 impl(왼쪽) 몫. 비율 허용 오차는 ±0.01
TEMP_TAB_WAIT=2.5                    # 임시 탭 pane 목록 안정 대기 상한(초)
RETRIES="${CF_RETRIES:-30}"         # 감지·보고 지연 대기 횟수
RETRY_SLEEP="${CF_RETRY_SLEEP:-2}"  # 대기 간격(초) → 기본 최대 약 60초

usage() {
	sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}
warn() { echo "team-up: $*" >&2; }
die() { warn "$*"; exit 1; }

mode=check
resume_id=""
hook_sid=""
status_trigger="계기 미기재"
lock_op=""
lock_force=0
case "${1:-}" in
"" | --check)
	mode=check
	;;
--up)
	mode=up
	if [ "$#" -ge 2 ]; then
		resume_id="${2:-}"
		[ -n "$resume_id" ] || usage
		shift
	fi
	;;
--status)
	mode=status
	if [ "$#" -ge 2 ]; then
		status_trigger="${2:-}"
		[ -n "$status_trigger" ] || usage
		case "$status_trigger" in -*) usage ;; esac
		shift
	fi
	;;
--lock)
	mode=lock
	lock_op="${2:-}"
	case "$lock_op" in
	status | release)
		[ "$#" -eq 2 ] || usage
		shift
		;;
	claim)
		if [ "$#" -eq 3 ]; then
			[ "${3:-}" = "--force" ] || usage
			lock_force=1
			shift 2
		elif [ "$#" -eq 2 ]; then
			shift
		else
			usage
		fi
		;;
	*) usage ;;
	esac
	;;
--hook | --hook-clear)
	mode=hook
	if [ "$#" -ge 2 ]; then
		hook_sid="${2:-}" # 비었으면 훅 진입점(stdin), 있으면 백그라운드 작업
		[ -n "$hook_sid" ] || usage
		shift
	fi
	;;
--resume-impl)
	warn "--resume-impl은 없앴다; 새 이름: scripts/team-up.sh --up <agy 대화 id>"
	usage
	;;
--layout)
	warn "--layout은 없앴다; 새 이름: scripts/team-up.sh --up"
	usage
	;;
--claim-external)
	warn "--claim-external은 없앴다; 새 이름: CF_EXTERNAL_LEAD=1 scripts/team-up.sh --lock claim [--force]"
	usage
	;;
*) usage ;;
esac
[ "$#" -le 1 ] || usage

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
EXT_LEAD=0
EXT_LEAD_FILE="$ROOT/.local/team/external-lead"

# 외부 모드에서는 --hook/--hook-clear가 아무것도 하지 않고 바로 0으로 끝난다.
if [ "$mode" = hook ] && [ "${CF_EXTERNAL_LEAD:-}" = 1 ] && [ -z "${HERDR_PANE_ID:-}" ]; then
	exit 0
fi

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

# --- 가드: Herdr pane 안(또는 CF_EXTERNAL_LEAD=1 외부 팀장), 이 저장소 안에서만 ---
if [ "$mode" = lock ] && [ "${CF_EXTERNAL_LEAD:-}" != 1 ]; then
	warn "--lock은 외부 팀장 모드(CF_EXTERNAL_LEAD=1) 전용이다; 아무것도 하지 않음"
	exit 2
fi
if [ "${CF_EXTERNAL_LEAD:-}" = 1 ]; then
	[ -z "${HERDR_PANE_ID:-}" ] || die "Herdr pane 안 세션에서는 CF_EXTERNAL_LEAD를 쓰지 않는다; 아무것도 하지 않음"
	EXT_LEAD=1
else
	[ "${HERDR_ENV:-}" = 1 ] && [ -n "${HERDR_PANE_ID:-}" ] || die "Herdr pane 안이 아니다; 아무것도 하지 않음"
fi
under_root() { case "${1%/}/" in "$ROOT"/*) return 0 ;; esac; return 1; }
under_root "$(pwd -P)" || die "현재 디렉터리가 $ROOT 밖이다; 아무것도 하지 않음"
command -v herdr >/dev/null || die "herdr 명령이 없다"
command -v python3 >/dev/null || die "python3 명령이 없다"

TAB=$'\t'
EXT_LEAD_LOCK_DIR="$ROOT/.local/team/external-lead.lock"
EXT_LEAD_LOCK_HELD=0

acquire_ext_lead_lock() {
	local tries=0
	mkdir -p "$ROOT/.local/team" || die ".local/team 디렉터리를 만들지 못했다"
	while ! mkdir "$EXT_LEAD_LOCK_DIR" 2>/dev/null; do
		tries=$((tries + 1))
		[ "$tries" -lt 100 ] || die "외부 팀장 기록 잠금($EXT_LEAD_LOCK_DIR) 대기 시간 초과"
		sleep 0.05
	done
	EXT_LEAD_LOCK_HELD=1
	trap 'release_ext_lead_lock' EXIT
	trap 'release_ext_lead_lock; exit 129' HUP
	trap 'release_ext_lead_lock; exit 130' INT
	trap 'release_ext_lead_lock; exit 143' TERM
}

release_ext_lead_lock() {
	if [ "${EXT_LEAD_LOCK_HELD:-0}" = 1 ]; then
		rm -f "$EXT_LEAD_FILE.tmp.$$" 2>/dev/null || true
		rmdir "$EXT_LEAD_LOCK_DIR" 2>/dev/null || true
		EXT_LEAD_LOCK_HELD=0
		trap - EXIT HUP INT TERM
	fi
}

trim_ws() {
	local s="$1"
	s="${s#"${s%%[![:space:]]*}"}"
	s="${s%"${s##*[![:space:]]}"}"
	printf '%s' "$s"
}

valid_lstart() {
	local dow mon dom hms yr extra hh mm ss max_d
	case "$1" in '' | *[!A-Za-z0-9:\ ]*) return 1 ;; esac
	IFS=' ' read -r dow mon dom hms yr extra <<<"$1" || return 1
	[ -z "$extra" ] || return 1
	case "$dow" in Sun | Mon | Tue | Wed | Thu | Fri | Sat) ;; *) return 1 ;; esac
	case "$yr" in [1-9][0-9][0-9][0-9]) ;; *) return 1 ;; esac
	case "$mon" in
	Jan | Mar | May | Jul | Aug | Oct | Dec) max_d=31 ;;
	Apr | Jun | Sep | Nov) max_d=30 ;;
	Feb)
		if [ $((yr % 4)) = 0 ] && { [ $((yr % 100)) != 0 ] || [ $((yr % 400)) = 0 ]; }; then
			max_d=29
		else
			max_d=28
		fi
		;;
	*) return 1 ;;
	esac
	case "$dom" in
	[1-9])
		[ "$1" = "$dow $mon $dom $hms $yr" ] || [ "$1" = "$dow $mon  $dom $hms $yr" ] || return 1
		;;
	[12][0-9] | 3[01])
		[ "$1" = "$dow $mon $dom $hms $yr" ] || return 1
		;;
	*) return 1 ;;
	esac
	[ "$((10#$dom))" -ge 1 ] && [ "$((10#$dom))" -le "$max_d" ] || return 1
	case "$hms" in [0-9][0-9]:[0-9][0-9]:[0-9][0-9]) ;; *) return 1 ;; esac
	IFS=':' read -r hh mm ss <<<"$hms"
	[ "$((10#$hh))" -le 23 ] && [ "$((10#$mm))" -le 59 ] && [ "$((10#$ss))" -le 59 ] || return 1
	return 0
}

ext_lead_self_info() {
	local pid="$$" hops=0 line ppid comm base lstart
	while [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null && [ "$hops" -lt 32 ]; do
		hops=$((hops + 1))
		line="$(LC_ALL=C ps -o ppid=,comm= -p "$pid" 2>/dev/null)" || return 1
		case "$line" in *$'\n'*) return 1 ;; esac
		line="$(trim_ws "$line")"
		[ -n "$line" ] || return 1
		ppid="${line%%[[:space:]]*}"
		case "$ppid" in '' | *[!0-9]*) return 1 ;; esac
		comm="$(trim_ws "${line#"$ppid"}")"
		[ -n "$comm" ] || return 1
		base="${comm##*/}"
		if [ "$base" = "claude" ]; then
			lstart="$(LC_ALL=C ps -o lstart= -p "$pid" 2>/dev/null)" || return 1
			case "$lstart" in *$'\n'* | *"$TAB"*) return 1 ;; esac
			lstart="$(trim_ws "$lstart")"
			valid_lstart "$lstart" || return 1
			printf '%s\t%s' "$pid" "$lstart"
			return 0
		fi
		[ "$ppid" != "$pid" ] || return 1
		pid="$ppid"
	done
	return 1
}

read_ext_lead_id() {
	local id=""
	[ -f "$EXT_LEAD_FILE" ] && IFS= read -r id <"$EXT_LEAD_FILE" || true
	printf '%s' "$id"
}

read_ext_lead_line2() {
	local id="" line2="" extra="" pid lstart
	[ -f "$EXT_LEAD_FILE" ] || return 1
	{
		IFS= read -r id || [ -n "$id" ] || return 1
		IFS= read -r line2 || [ -n "$line2" ] || return 1
		if IFS= read -r extra || [ -n "$extra" ]; then
			return 1
		fi
	} <"$EXT_LEAD_FILE"
	case "$line2" in
	*"$TAB"*) ;;
	*) return 1 ;;
	esac
	pid="${line2%%"$TAB"*}"
	lstart="${line2#*"$TAB"}"
	case "$pid" in '' | 0* | *[!0-9]*) return 1 ;; esac
	case "$lstart" in *"$TAB"*) return 1 ;; esac
	lstart="$(trim_ws "$lstart")"
	valid_lstart "$lstart" || return 1
	printf '%s\t%s' "$pid" "$lstart"
}

classify_ext_lead_owner() {
	local line2 rec_pid rec_lstart out rc cur_lstart
	ext_lead_self_info >/dev/null || { printf 'unverifiable'; return 0; }
	line2="$(read_ext_lead_line2)" || { printf 'unverifiable'; return 0; }
	rec_pid="${line2%%"$TAB"*}"
	rec_lstart="${line2#*"$TAB"}"
	out="$(LC_ALL=C ps -o lstart= -p "$rec_pid" 2>&1)"
	rc=$?
	if [ "$rc" = 0 ]; then
		case "$out" in *$'\n'*) printf 'unverifiable'; return 0 ;; esac
		cur_lstart="$(trim_ws "$out")"
		if ! valid_lstart "$cur_lstart"; then
			printf 'unverifiable'
		elif [ "$cur_lstart" = "$rec_lstart" ]; then
			printf 'alive'
		else
			printf 'gone'
		fi
		return 0
	fi
	if [ "$rc" = 1 ] && [ -z "$out" ]; then
		printf 'gone'
		return 0
	fi
	printf 'unverifiable'
}

die_ext_lead_mismatch() { # recorded_id
	release_ext_lead_lock
	die "다른 세션(${1:0:8}…)이 외부 팀장으로 기록돼 있다; 사용자 승인 뒤 이 세션에서 CF_EXTERNAL_LEAD=1 scripts/team-up.sh --lock claim --force (같은 외부 팀장이 /clear·새 대화 뒤라 세션 id가 바뀐 경우도 사용자 확인 후 --lock claim --force)"
}

write_ext_lead_record() { # self_info
	printf '%s\n%s\n' "$CLAUDE_CODE_SESSION_ID" "$1" >|"$EXT_LEAD_FILE.tmp.$$" &&
		mv -f "$EXT_LEAD_FILE.tmp.$$" "$EXT_LEAD_FILE" || {
		rm -f "$EXT_LEAD_FILE.tmp.$$" 2>/dev/null || true
		release_ext_lead_lock
		die "외부 팀장 기록($EXT_LEAD_FILE)을 쓰지 못했다"
	}
}

# 외부 팀장 기록 상태 판정(잠금 없이 읽기만 할 때도 호출 가능):
# 출력: none | mine | other live | stale | unknown
ext_lock_state() {
	local rec_id
	[ -e "$EXT_LEAD_FILE" ] || { printf 'none'; return 0; }
	rec_id="$(read_ext_lead_id)"
	[ -n "$rec_id" ] || { printf 'unknown'; return 0; }
	if [ -n "${CLAUDE_CODE_SESSION_ID:-}" ] && [ "$rec_id" = "$CLAUDE_CODE_SESSION_ID" ]; then
		printf 'mine'
		return 0
	fi
	case "$(classify_ext_lead_owner)" in
	alive) printf 'other live' ;;
	gone) printf 'stale' ;;
	*) printf 'unknown' ;;
	esac
}

run_lock_cmd() {
	local st self_info rec_id
	case "$lock_op" in
	status)
		printf '%s\n' "$(ext_lock_state)"
		exit 0
		;;
	claim)
		acquire_ext_lead_lock
		st="$(ext_lock_state)"
		rec_id="$(read_ext_lead_id)"
		case "$st" in
		mine)
			release_ext_lead_lock
			exit 0
			;;
		none | stale)
			self_info="$(ext_lead_self_info)" || {
				release_ext_lead_lock
				die "외부 팀장 claude 프로세스(pid·시작 시각)를 확인할 수 없다; 사용자 승인 뒤 이 세션에서 CF_EXTERNAL_LEAD=1 scripts/team-up.sh --lock claim --force"
			}
			write_ext_lead_record "$self_info"
			release_ext_lead_lock
			if [ "$st" = stale ]; then
				warn "외부 팀장 기록 자동 회수: 옛 세션(${rec_id:0:8}…) 종료 확인"
			else
				echo "외부 팀장 기록 갱신: ${CLAUDE_CODE_SESSION_ID:0:8}…"
			fi
			exit 0
			;;
		other\ live | unknown)
			if [ "$lock_force" = 1 ]; then
				self_info="$(ext_lead_self_info)" || {
					release_ext_lead_lock
					die "외부 팀장 claude 프로세스(pid·시작 시각)를 확인할 수 없다"
				}
				write_ext_lead_record "$self_info"
				release_ext_lead_lock
				echo "외부 팀장 기록 갱신: ${CLAUDE_CODE_SESSION_ID:0:8}…"
				exit 0
			fi
			release_ext_lead_lock
			warn "외부 팀장 기록이 '$st' 상태다(${rec_id:0:8}…); 덮어쓰려면 사용자 승인 뒤 CF_EXTERNAL_LEAD=1 scripts/team-up.sh --lock claim --force"
			exit 3
			;;
		esac
		;;
	release)
		if [ ! -e "$EXT_LEAD_FILE" ] && [ ! -d "$ROOT/.local/team" ]; then
			exit 0
		fi
		acquire_ext_lead_lock
		st="$(ext_lock_state)"
		case "$st" in
		none)
			release_ext_lead_lock
			exit 0
			;;
		mine)
			rm -f "$EXT_LEAD_FILE" || {
				release_ext_lead_lock
				die "외부 팀장 기록($EXT_LEAD_FILE)을 지우지 못했다"
			}
			release_ext_lead_lock
			echo "외부 팀장 기록 해제: ${CLAUDE_CODE_SESSION_ID:0:8}…"
			exit 0
			;;
		*)
			release_ext_lead_lock
			warn "외부 팀장 기록이 이 세션(mine)이 아니다($st); 지우지 않음"
			exit 3
			;;
		esac
		;;
	esac
}

ensure_external_lead_lock() {
	local rec_id self_info
	[ "$EXT_LEAD" = 1 ] || return 0
	acquire_ext_lead_lock
	if [ ! -e "$EXT_LEAD_FILE" ]; then
		self_info="$(ext_lead_self_info)" || {
			release_ext_lead_lock
			die "외부 팀장 claude 프로세스(pid·시작 시각)를 확인할 수 없다; 사용자 승인 뒤 이 세션에서 CF_EXTERNAL_LEAD=1 scripts/team-up.sh --lock claim --force"
		}
		# 기록이 이미 있으면 쓰기를 시도하지 않는다(실패 오류 문구를 만들다 MacPorts bash 5.2가 LANG 없는 환경에서 죽는다 — extlead-r4)
		(set -o noclobber; printf '%s\n%s\n' "$CLAUDE_CODE_SESSION_ID" "$self_info" >"$EXT_LEAD_FILE") 2>/dev/null || true
	fi
	rec_id="$(read_ext_lead_id)"
	if [ -n "$rec_id" ] && [ "$rec_id" = "$CLAUDE_CODE_SESSION_ID" ]; then
		release_ext_lead_lock
		return 0
	fi
	if [ -n "$rec_id" ] && [ "$(classify_ext_lead_owner)" = gone ]; then
		self_info="$(ext_lead_self_info)" || die_ext_lead_mismatch "$rec_id"
		write_ext_lead_record "$self_info"
		release_ext_lead_lock
		warn "외부 팀장 기록 자동 회수: 옛 세션(${rec_id:0:8}…) 종료 확인"
		return 0
	fi
	die_ext_lead_mismatch "$rec_id"
}

if [ "$EXT_LEAD" = 1 ]; then
	WT_ERR="데스크톱 세션의 worktree 옵션을 끄고 저장소 폴더에서 새 세션을 연다"
	case "$ROOT/$(pwd -P)/" in */.claude/worktrees/*) die "$WT_ERR" ;; esac
	git_dir="$(cd "$ROOT" && d="$(HOME=/dev/null XDG_CONFIG_HOME=/dev/null GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_OPTIONAL_LOCKS=0 git --no-optional-locks -C "$ROOT" rev-parse --git-dir 2>/dev/null)" && [ -n "$d" ] && cd "$d" && pwd -P)" || die "$WT_ERR"
	git_common_dir="$(cd "$ROOT" && d="$(HOME=/dev/null XDG_CONFIG_HOME=/dev/null GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_OPTIONAL_LOCKS=0 git --no-optional-locks -C "$ROOT" rev-parse --git-common-dir 2>/dev/null)" && [ -n "$d" ] && cd "$d" && pwd -P)" || die "$WT_ERR"
	[ "$git_dir" = "$git_common_dir" ] || die "$WT_ERR"
	[ -n "${CLAUDE_CODE_SESSION_ID:-}" ] || die "CLAUDE_CODE_SESSION_ID가 없다; 외부 팀장 세션을 확인할 수 없음"
	if [ "$mode" = lock ]; then
		run_lock_cmd
	fi
	if [ "$mode" = up ]; then
		rec_id="$(read_ext_lead_id)"
		if [ -n "$rec_id" ] && [ "$rec_id" != "$CLAUDE_CODE_SESSION_ID" ]; then
			[ "$(classify_ext_lead_owner)" = gone ] || die_ext_lead_mismatch "$rec_id"
		fi
	fi
fi

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

# 외부 모드: herdr pane list와 팀원(cf-impl·cf-critic) 소유 pane에서 작업공간을 찾는다.
# shellcheck disable=SC2016
PY_FIND_WS='import sys,os,json
root=sys.argv[1]
labels=set(sys.argv[2:4])
def load(s,*path):
    try: d=json.loads(s)
    except Exception: return None
    for k in path: d=d.get(k) if isinstance(d,dict) else None
    return d
panes=load(os.environ.get("PANES_JSON",""),"result","panes") or []
by_id={p.get("pane_id"):p for p in panes if isinstance(p,dict) and p.get("pane_id")}
def inroot(p): return ((p.get("foreground_cwd") or p.get("cwd") or "").rstrip("/")+"/").startswith(root+"/")
wss=set()
for env_k in ("IMPL_OWNER_JSON","CRITIC_OWNER_JSON"):
    a=load(os.environ.get(env_k,""),"result","agent")
    if isinstance(a,dict) and a.get("pane_id"):
        p=dict(a); p.update(by_id.get(a["pane_id"],{}))
        if p.get("workspace_id"): wss.add(p["workspace_id"])
for p in panes:
    if p.get("label") in labels and inroot(p) and p.get("workspace_id"):
        wss.add(p["workspace_id"])
wss=sorted(wss)
if len(wss)==1: print("ok\t"+wss[0])
elif len(wss)==0: print("none\t")
else: print("multi\t"+", ".join(wss))'

PANES_JSON=""
NO_MEMBER_PANE_MSG="CF 팀원 pane을 찾지 못했다; Herdr에서 작업공간과 label 「CF 구현 · agy」 빈 셸 pane을 먼저 만든다"
if [ "$EXT_LEAD" = 1 ]; then
	PANES_JSON="$(herdr pane list 2>/dev/null)" || die "herdr pane list 실패"
	impl_owner="$(herdr agent get "${SEAT_NAME[1]}" 2>/dev/null)" || impl_owner=""
	critic_owner="$(herdr agent get "${SEAT_NAME[2]}" 2>/dev/null)" || critic_owner=""
	ws_out="$(PANES_JSON="$PANES_JSON" IMPL_OWNER_JSON="$impl_owner" CRITIC_OWNER_JSON="$critic_owner" \
		python3 -c "$PY_FIND_WS" "$ROOT" "${SEAT_LABEL[1]}" "${SEAT_LABEL[2]}")" || die "작업공간 탐색 실패"
	IFS=$'\t' read -r ws_st ws_val <<<"$ws_out"
	case "$ws_st" in
	ok) WS="$ws_val" ;;
	none)
		if [ "$mode" = status ]; then
			WS=""
		else
			die "$NO_MEMBER_PANE_MSG"
		fi
		;;
	*)
		if [ "$mode" = status ]; then
			WS=""
		else
			die "CF 팀원 pane이 여러 작업공간에 있다: $ws_val; 아무것도 하지 않음"
		fi
		;;
	esac
else
	self_json="$(herdr pane get "$HERDR_PANE_ID" 2>/dev/null)" || die "현재 pane $HERDR_PANE_ID 를 읽지 못했다"
	self_cwd="$(printf '%s' "$self_json" | jget result.pane.foreground_cwd)"
	[ -n "$self_cwd" ] || self_cwd="$(printf '%s' "$self_json" | jget result.pane.cwd)"
	under_root "$self_cwd" || die "pane $HERDR_PANE_ID 의 cwd($self_cwd)가 $ROOT 밖이다; 아무것도 하지 않음"
	WS="$(printf '%s' "$self_json" | jget result.pane.workspace_id)"
	[ -n "$WS" ] || die "현재 pane의 작업공간을 알 수 없다"
fi

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
    asess=p.get("agent_session")
    sval=(asess.get("value") if isinstance(asess,dict) else "") or ""
    print("\x1f".join([status,p.get("pane_id") or "","1" if ws and p.get("workspace_id")==ws else "0",
        p.get("agent") or "",p.get("agent_status") or "",p.get("label") or "",note,sval,"_"]))
    sys.exit(0)
if owner and owner.get("pane_id"):
    p=dict(owner); p.update(next((x for x in panes if x.get("pane_id")==owner["pane_id"]),{}))
    if not inroot(p): out("conflict",p,"저장소 밖 pane이 이름 사용")
    if p.get("agent") and p.get("agent")!=kind: out("conflict",p,"다른 종류 agent("+p["agent"]+")가 이름 사용")
    if p.get("agent"): out("alive",p)
    if ws and p.get("workspace_id")==ws: out("shell",p)
    out("conflict",p,"다른 작업공간 pane이 이름 사용")
cand=[p for p in panes if ws and p.get("workspace_id")==ws and p.get("label")==label and inroot(p)]
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
S_SID=()
S_OPT_STATE=()
S_OPT_NOTE=()
S_OPT_ACT=()
S_OPT_EXP=()
S_OPT_REASON=()
opts_ok=1

# 점검·보고·기동 확인용: 팀원 pane의 실제 실행 옵션을 SEAT_CMD 기대 단위와 비교한다.
# 비밀 값 보호: 출력에는 기대 단위(SEAT_CMD에서 온 것)와 고정 사유만 쓰고, 실제 argv·cmdline·원문 JSON은 출력하지 않는다.
# shellcheck disable=SC2016
PY_CHECK_OPTS='import sys,os,json,shlex
kind,seat_cmd,astatus,recover,rc=sys.argv[1:6]
# 값 없는 깃발 뒤에 위치 인자가 오거나 값이 -로 시작하면 이 규칙은 틀린다 — SEAT_CMD를 바꾸면 스냅샷 테스트가 알려 준다.
words=shlex.split(seat_cmd)[1:]
units=[]; k=0
while k<len(words):
    if words[k].startswith("-") and k+1<len(words) and not words[k+1].startswith("-"):
        units.append((words[k],words[k+1])); k+=2
    else:
        units.append((words[k],)); k+=1
exp_summary=" ".join(" ".join(u) for u in units)
def emit(st,note,act_s,exp_s,reason):
    print("\x1f".join([st,note,act_s,exp_s,reason,"_"]))
    sys.exit(0 if st=="ok" else 1)
def unv(reason):
    suf="" if astatus in ("idle","done") else " (작업 중 — 다시 점검)"
    full=reason+suf
    emit("unknown","옵션 판정 불가: "+full,"",exp_summary,full)
if rc!="0": unv("process-info 실패")
try:
    d=json.loads(os.environ.get("PINFO_JSON",""))
    fg=d.get("result",{}).get("process_info",{}).get("foreground_processes") if isinstance(d,dict) else None
except Exception:
    fg=None
if not isinstance(fg,list) or any(not isinstance(p,dict) for p in fg):
    unv("JSON 오류")
procs=[p for p in fg if p.get("name")==kind]
if len(procs)==0: unv("agent 프로세스 0개")
if len(procs)>=2: unv("agent 프로세스 2개 이상")
argv=procs[0].get("argv")
if not isinstance(argv,list) or len(argv)<1 or any(not isinstance(x,str) for x in argv):
    unv("argv 없음")
act=[]
for w in argv[1:]:
    if w.startswith("--") and "=" in w: act.extend(w.split("=",1))
    else: act.append(w)
missing=[]; diff_val=[]; act_parts=[]
for u in units:
    if len(u)==1:
        if u[0] in act: act_parts.append(u[0])
        else: missing.append(u[0])
    else:
        flag,val=u
        if any(act[j]==flag and act[j+1]==val for j in range(len(act)-1)):
            act_parts.append("%s %s"%(flag,val))
            continue
        if any(act[j]==flag and not act[j+1].startswith("-") for j in range(len(act)-1)):
            diff_val.append("%s(기대 %s)"%(flag,val))
            act_parts.append("%s=<다름>"%flag)
        else:
            missing.append("%s %s"%(flag,val))
if not missing and not diff_val:
    emit("ok","",exp_summary,exp_summary,"")
parts=[]
if missing: parts.append("없음 "+", ".join(missing))
if diff_val: parts.append("다름 "+", ".join(diff_val))
diff_str="; ".join(parts)
act_summary=" ".join(act_parts) if act_parts else "없음"
emit("mismatch","옵션 불일치: "+diff_str+" ("+recover+")",act_summary,exp_summary,diff_str)'

check_member_opts() {
	local i pinfo rc recover note rec_id out _
	if [ "$EXT_LEAD" = 1 ]; then
		rec_id="$(read_ext_lead_id)"
		if [ -z "$rec_id" ]; then
			S_OPT_NOTE[0]="외부 팀장 기록: 없음"
		elif [ "$rec_id" != "$CLAUDE_CODE_SESSION_ID" ]; then
			case "$(classify_ext_lead_owner)" in
			gone) note="옛 주인 종료됨 — 바꾸는 명령 때 자동 회수" ;;
			alive) note="옛 주인 살아 있음" ;;
			*) note="판정 불가" ;;
			esac
			S_OPT_NOTE[0]="외부 팀장 기록: 다른 세션(${rec_id:0:8}…) — $note"
		fi
	fi
	for i in 1 2; do
		case "${S_STATUS[$i]}" in
		alive | unnamed) ;;
		shell)
			S_OPT_STATE[i]="unknown"
			S_OPT_REASON[i]="빈 셸"
			opts_ok=0
			continue
			;;
		missing)
			S_OPT_STATE[i]="unknown"
			S_OPT_REASON[i]="없음"
			opts_ok=0
			continue
			;;
		conflict)
			S_OPT_STATE[i]="unknown"
			S_OPT_REASON[i]="충돌(${S_NOTE[$i]})"
			opts_ok=0
			continue
			;;
		esac
		if [ "$i" = 1 ]; then
			recover="복구: idle·비포커스 확인 → /quit → scripts/team-up.sh --up <id>"
		else
			recover="복구: idle·비포커스 확인 → /quit → scripts/team-up.sh --up"
		fi
		pinfo="$(herdr pane process-info --pane "${S_PANE[$i]}" 2>/dev/null)"
		rc=$?
		out="$(PINFO_JSON="$pinfo" python3 -c "$PY_CHECK_OPTS" \
			"${SEAT_KIND[$i]}" "${SEAT_CMD[$i]}" "${S_ASTATUS[$i]}" "$recover" "$rc")"
		if [ "$?" != 0 ]; then
			opts_ok=0
		fi
		IFS=$'\x1f' read -r "S_OPT_STATE[i]" "S_OPT_NOTE[i]" "S_OPT_ACT[i]" "S_OPT_EXP[i]" "S_OPT_REASON[i]" _ <<<"$out"
		if [ "${S_STATUS[$i]}" = unnamed ] && [ "${S_OPT_STATE[$i]}" = ok ]; then
			S_OPT_STATE[i]="unknown"
			S_OPT_REASON[i]="이름 미확보(unnamed)"
			opts_ok=0
		fi
	done
}

classify_all() {
	local i owner_json out lead_pane _
	[ -n "$PANES_JSON" ] || PANES_JSON="$(herdr pane list 2>/dev/null)" || die "herdr pane list 실패"
	for i in 0 1 2; do
		if [ "$EXT_LEAD" = 1 ] && [ "$i" = 0 ]; then
			S_STATUS[0]=external
			S_PANE[0]=""
			S_INWS[0]=0
			S_AGENT[0]="${SEAT_KIND[0]}"
			S_ASTATUS[0]="이 세션"
			S_LABEL[0]=""
			S_NOTE[0]=""
			S_SID[0]="${CLAUDE_CODE_SESSION_ID:-}"
			lead_pane="$(herdr agent get "${SEAT_NAME[0]}" 2>/dev/null | jget result.agent.pane_id)"
			[ -z "$lead_pane" ] || S_NOTE[0]="Herdr 안 cf-lead($lead_pane)가 살아 있음 — 이관 중이면 한쪽만 팀원에게 입력한다"
			continue
		fi
		owner_json="$(herdr agent get "${SEAT_NAME[$i]}" 2>/dev/null)" || owner_json=""
		out="$(PANES_JSON="$PANES_JSON" OWNER_JSON="$owner_json" python3 -c "$PY_CLASSIFY" \
			"$ROOT" "$WS" "${SEAT_LABEL[$i]}" "${SEAT_KIND[$i]}")" || die "상태 분류 실패: ${SEAT_NAME[$i]}"
		IFS=$'\x1f' read -r "S_STATUS[i]" "S_PANE[i]" "S_INWS[i]" "S_AGENT[i]" "S_ASTATUS[i]" "S_LABEL[i]" "S_NOTE[i]" "S_SID[i]" _ <<<"$out"
	done
}

action_of() { # idx
	local i=$1
	if [ "$i" = 0 ]; then
		[ "$EXT_LEAD" = 1 ] && { echo "유지"; return; }
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
	echo "team-up 점검 — 저장소 $ROOT · 작업공간 $WS · 현재 pane ${HERDR_PANE_ID:-외부}"
	printf '%-7s %-11s %-7s %-7s %-17s %-20s %s\n' 석 이름 pane agent 상태 label "--up 조치"
	for i in 0 1 2; do
		st="${S_STATUS[$i]}"
		[ -n "${S_ASTATUS[$i]}" ] && st="$st(${S_ASTATUS[$i]})"
		printf '%-7s %-11s %-7s %-7s %-17s %-20s %s\n' "${SEAT_ROLE[$i]}" "${SEAT_NAME[$i]}" \
			"${S_PANE[$i]:--}" "${S_AGENT[$i]:--}" "$st" "${S_LABEL[$i]:--}" "$(action_of "$i")"
		[ -z "${S_NOTE[$i]}" ] || echo "        ↳ ${S_NOTE[$i]}"
		[ -z "${S_OPT_NOTE[$i]:-}" ] || echo "        ↳ ${S_OPT_NOTE[$i]}"
	done
}

# 표 아래에 팀원마다 공통 한 줄 출력:
# <이름> <pane> ok / <이름> <pane> mismatch 실제=<실제 옵션 요약> 기대=<기대 옵션 요약> / <이름> <pane|-> unknown <사유>
# cf-impl은 herdr 메타데이터에 agy 대화 id가 보이면 줄 끝에 " 대화=<id>"를 붙인다.
print_check_summary() {
	local i pane tail
	for i in 1 2; do
		pane="${S_PANE[$i]:--}"
		tail=""
		if [ "$i" = 1 ] && [ "${S_AGENT[1]:-}" = agy ] && [ -n "${S_SID[1]:-}" ]; then
			tail=" 대화=${S_SID[1]}"
		fi
		case "${S_OPT_STATE[$i]:-unknown}" in
		ok)
			echo "${SEAT_NAME[$i]} $pane ok$tail"
			;;
		mismatch)
			echo "${SEAT_NAME[$i]} $pane mismatch 실제=${S_OPT_ACT[$i]} 기대=${S_OPT_EXP[$i]}$tail"
			;;
		*)
			echo "${SEAT_NAME[$i]} $pane unknown ${S_OPT_REASON[$i]:-판정 불가}$tail"
			;;
		esac
	done
}

# 마탑 가이드 §3 보고 꼴 출력(--status, 읽기 전용)
print_status() {
	local now_ts lead_mode lead_sid lead_sid_short lock_st i name pane kind opt_field dialog_field st_field
	local branch wt_out wt_n wt_desc unv_str=""
	local -a unv_items=()
	now_ts="$(date '+%Y-%m-%d %H:%M:%S%z')"
	lock_st="$(ext_lock_state)"
	if [ "$EXT_LEAD" = 1 ]; then
		lead_mode="외부"
		lead_sid_short="${CLAUDE_CODE_SESSION_ID:0:8}"
	else
		lead_mode="Herdr 안"
		lead_sid="${S_SID[0]:-}"
		[ -n "$lead_sid" ] || lead_sid="$(printf '%s' "${self_json:-}" | jget result.pane.agent_session.value)"
		[ -n "$lead_sid" ] || lead_sid="${CLAUDE_CODE_SESSION_ID:-}"
		if [ -n "$lead_sid" ]; then
			lead_sid_short="${lead_sid:0:8}"
		else
			lead_sid_short="미확인"
			unv_items+=("팀장 세션 id")
		fi
	fi
	[ "$lock_st" != unknown ] || unv_items+=("잠금(unknown)")
	[ "$EXT_LEAD" != 1 ] || [ -n "$WS" ] || unv_items+=("작업공간")
	echo "[CF 팀장→마탑] 답: 팀 점검·구성($status_trigger, $now_ts)"
	echo "- 팀장 세션: $lead_sid_short, 팀장 모드 $lead_mode, 잠금 $lock_st"
	for i in 1 2; do
		name="${SEAT_NAME[$i]}"
		pane="${S_PANE[$i]:--}"
		kind="${SEAT_KIND[$i]}"
		case "${S_OPT_STATE[$i]:-unknown}" in
		ok) opt_field="○" ;;
		mismatch) opt_field="×(${S_OPT_REASON[$i]})" ;;
		*)
			opt_field="×(판정 불가: ${S_OPT_REASON[$i]:-미확인})"
			unv_items+=("$name 옵션(${S_OPT_REASON[$i]:-미확인})")
			;;
		esac
		if [ "${S_STATUS[$i]}" = alive ] || [ "${S_STATUS[$i]}" = unnamed ]; then
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
		echo "- 팀원: $name $pane $kind 옵션 일치 $opt_field 세션 id 기록 × 확인창 $dialog_field 상태 $st_field"
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
	local item
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

all_alive() {
	local i
	[ "$EXT_LEAD" = 1 ] || [ "${S_STATUS[0]}" = alive ] || return 1
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
	[ "$EXT_LEAD" = 0 ] || die "$NO_MEMBER_PANE_MSG"
	split_pane "$HERDR_PANE_ID" down "$LEAD_RATIO"
}

warn_member_opt_mismatch() { # idx
	local i=$1 name="${SEAT_NAME[$1]}"
	if [ "$i" = 1 ]; then
		warn "$name 옵션 불일치 — idle일 때 /quit 뒤 scripts/team-up.sh --up ${S_SID[1]:-<대화 id>}"
	else
		warn "$name 옵션 불일치 — idle일 때 /quit 뒤 scripts/team-up.sh --up"
	fi
}

# 팀원 한 석을 맞춘다. 살아 있으면 손대지 않고(옵션 불일치 시 한 줄 알림만), 충돌이면 건너뛴다.
ensure_member() { # idx command
	local i=$1 cmd=$2 name="${SEAT_NAME[$1]}" label="${SEAT_LABEL[$1]}" kind="${SEAT_KIND[$1]}" pane rc
	case "${S_STATUS[$i]}" in
	alive)
		echo "$name: 살아 있음(${S_PANE[$i]}); 그대로 둠"
		[ "${S_OPT_STATE[$i]:-}" != mismatch ] || warn_member_opt_mismatch "$i"
		return 0
		;;
	conflict)
		warn "$name: ${S_NOTE[$i]} (${S_PANE[$i]}); 건너뜀"
		return 1
		;;
	unnamed)
		pane="${S_PANE[$i]}"
		if [ "${S_OPT_STATE[$i]:-}" = mismatch ]; then
			warn_member_opt_mismatch "$i"
			return 0
		fi
		retry_claim "$pane" "$name" || { warn "$name: $pane 에 이름을 확보하지 못함"; return 1; }
		ensure_label "$pane" "$label"
		echo "$name: 실행 중인 $pane 에 이름 부여"
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
	if [ "$i" = 1 ] && [ -z "$resume_id" ]; then
		warn "대화 id 없음 — 새 대화로 띄움"
	fi
	S_STATUS[i]=spawned
	ensure_label "$pane" "$label"
	herdr pane run "$pane" "cd $(printf '%q' "$ROOT") && $cmd" >/dev/null 2>&1 ||
		{ warn "$name: $pane 에서 실행 실패"; return 1; }
	retry pane_has_agent "$pane" "$kind" || { warn "$name: $pane 에서 $kind 가 감지되지 않음"; return 1; }
	retry_claim "$pane" "$name"
	rc=$?
	[ "$rc" = 0 ] || { warn "$name: $pane 에 이름을 확보하지 못함(rc=$rc)"; return 1; }
	echo "$name: $pane 에서 실행 · 이름 확보"
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

# 같은 세션 id(접두어 포함)가 어느 pane에든 살아 있으면 그 pane id를 출력
# shellcheck disable=SC2016
session_alive_in() { # id
	PANES_JSON="$PANES_JSON" python3 -c 'import sys,os,json
sid=sys.argv[1]
try: panes=json.loads(os.environ["PANES_JSON"])["result"]["panes"]
except Exception: sys.exit(0)
for p in panes:
    if not p.get("agent"): continue
    x=(p.get("agent_session") or {}).get("value")
    if x and (x.startswith(sid) or sid.startswith(x)):
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

# 외부 모드 배치 상태 → "상태 줄비율 탭" (layout을 읽지 못하면 빈 값)
#   상태: ok(impl|critic이 같은 탭에서 좌우로 붙어 있고 사이에 다른 pane 없음) / away(다른 탭) / bad(그 밖의 모양)
# shellcheck disable=SC2016
ext_layout_state() { # impl critic
	herdr pane layout --pane "$1" 2>/dev/null | python3 -c 'import sys,json
impl,critic=sys.argv[1:3]
try:
    l=json.load(sys.stdin)["result"]["layout"]
    r={p["pane_id"]:p["rect"] for p in l["panes"]}
    splits=l.get("splits") or []
    tab=l.get("tab_id") or "-"
except Exception: sys.exit(0)
def box(q): return (q["x"],q["y"],q["width"],q["height"])
if impl not in r: sys.exit(0)
if not critic or critic not in r: print("away - "+tab); sys.exit(0)
M,C=box(r[impl]),box(r[critic])
right=None
if C[0]==M[0]+M[2] and C[1]==M[1] and C[3]==M[3]:
    for s in splits:
        if s.get("direction")=="right" and box(s["rect"])==(M[0],M[1],M[2]+C[2],M[3]):
            right=s["ratio"]; break
if right is None: print("bad - "+tab)
else: print("ok %s %s" % (right,tab))' "$1" "$2"
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

# 외부 모드 배치 보정: impl·critic이 같은 탭에서 좌우로 붙어 있을 때만 비율을 ROW_RATIO로 맞춘다.
# 그 밖의 모양(다른 탭, 섞인 pane, 한 석만 있음)은 아무것도 옮기지 않고 안내 후 1을 돌려준다.
apply_ext_layout() {
	local impl="" critic="" rc fail=0
	usable_anchor 1 && impl="${S_PANE[1]}"
	usable_anchor 2 && critic="${S_PANE[2]}"
	if [ -z "$impl" ] || [ -z "$critic" ]; then
		warn "배치: 외부 팀장 모드에서는 cf-impl과 cf-critic 두 석이 모두 있어야 배치를 맞출 수 있음; 아무것도 옮기지 않음"
		return 1
	fi
	# shellcheck disable=SC2046
	set -- $(ext_layout_state "$impl" "$critic")
	case "${1:-}" in
	ok) ;;
	away)
		warn "배치: cf-impl($impl)과 cf-critic($critic)이 다른 탭에 있어 옮기지 않음; 같은 탭에 좌우로 둔 뒤 CF_EXTERNAL_LEAD=1 scripts/team-up.sh --up"
		return 1
		;;
	bad)
		warn "배치: cf-impl($impl)과 cf-critic($critic)이 같은 탭에서 좌우로 붙어 있지 않아 옮기지 않음; 직접 정리한 뒤 CF_EXTERNAL_LEAD=1 scripts/team-up.sh --up"
		return 1
		;;
	*)
		warn "배치: 팀원 탭 layout을 읽지 못함; 아무것도 옮기지 않음"
		return 1
		;;
	esac
	set_ratio "$2" "$ROW_RATIO" "$impl" right "$critic" left
	rc=$?
	case $rc in
	1) fail=1 ;;
	3)
		# shellcheck disable=SC2046
		set -- $(ext_layout_state "$impl" "$critic")
		[ "${1:-}" = ok ] || { warn "resize 중 배치가 바뀌어 기준 모양이 아님"; return 1; }
		;;
	esac
	ratios_ok "$LEAD_RATIO" "$2" || fail=1
	if [ "$fail" != 0 ]; then
		warn "비율 미도달 또는 resize 실패: impl/critic $2 (기준 $ROW_RATIO ±0.01)"
		return 1
	fi
	if [ "$layout_status" != 0 ]; then
		warn "배치: 이동 단계에서 오류가 있었음; herdr pane layout 확인 뒤 CF_EXTERNAL_LEAD=1 scripts/team-up.sh --up"
		return 1
	fi
	echo "배치: 아래 impl $impl | critic $critic($ROW_RATIO)"
	return 0
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
		warn "배치: cf-impl($impl)이 팀장($lead)과 다른 탭에 있어 옮기지 않음; 같은 탭으로 옮긴 뒤 scripts/team-up.sh --up"
		return 4
		;;
	mixed)
		warn "배치: 팀 석 사이에 다른 pane이 섞여 있어 옮기지 않음(옮기면 그 pane 크기가 바뀜); 직접 정리한 뒤 scripts/team-up.sh --up"
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
			warn "배치: 이동 단계에서 오류가 있었음; herdr pane layout 확인 뒤 scripts/team-up.sh --up"
			return 1
		fi
		echo "배치: 팀장 $lead 위($LEAD_RATIO), 아래 impl $impl${critic:+ | critic $critic($ROW_RATIO)}"
		return 0
		;;
	2) warn "배치: 기준 모양이 되지 않음; herdr pane layout 확인 뒤 scripts/team-up.sh --up" ;;
	*) warn "배치: 자리는 맞지만 비율이 기준이 아님; herdr pane layout 확인 뒤 scripts/team-up.sh --up" ;;
	esac
	return 1
}

# --up 끝: 배치 실패는 기동 결과를 되돌리지 않고 종료 코드만 비0으로 만든다.
finish_layout() {
	local rc
	if [ "$EXT_LEAD" = 1 ]; then
		apply_ext_layout
		return $?
	fi
	layout_seats || return "$layout_status"
	apply_layout
	rc=$?
	[ "$rc" = 0 ] && [ "$layout_status" = 0 ]
}

# 점검(읽기 전용): 기준과 다르면 경고만 낸다. 종료 코드에 영향 없음.
check_layout() {
	local lead="${S_PANE[0]}" fix="고치려면 팀장 pane에서 scripts/team-up.sh --up" impl="" critic=""
	if [ "$EXT_LEAD" = 1 ]; then
		fix="고치려면 CF_EXTERNAL_LEAD=1 scripts/team-up.sh --up"
		usable_anchor 1 && impl="${S_PANE[1]}"
		usable_anchor 2 && critic="${S_PANE[2]}"
		if [ -z "$impl" ] || [ -z "$critic" ]; then
			warn "배치: cf-impl과 cf-critic 두 석이 모두 있어야 배치를 확인할 수 있음"
			warn "$fix"
			return 0
		fi
		# shellcheck disable=SC2046
		set -- $(ext_layout_state "$impl" "$critic")
		case "${1:-}" in
		ok)
			ratios_ok "$LEAD_RATIO" "$2" && return 0
			warn "배치 비율이 기준과 다름: impl/critic $2 (기준 $ROW_RATIO ±0.01)"
			;;
		away)
			fix="cf-impl과 cf-critic을 같은 탭에 좌우로 둔 뒤 CF_EXTERNAL_LEAD=1 scripts/team-up.sh --up"
			warn "배치: cf-impl($impl)과 cf-critic($critic)이 다른 탭에 있음"
			;;
		bad)
			fix="cf-impl과 cf-critic을 같은 탭에서 좌우로 붙인 뒤 CF_EXTERNAL_LEAD=1 scripts/team-up.sh --up"
			warn "배치가 기준(impl|critic 좌우 인접)과 다름"
			;;
		*) return 0 ;;
		esac
		warn "$fix"
		return 0
	fi
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
		fix="다른 pane을 팀 석 영역 밖으로 직접 옮긴 뒤 scripts/team-up.sh --up"
		warn "배치가 기준과 다르고 팀 석 사이에 다른 pane이 섞여 있음"
		;;
	away) fix="cf-impl을 팀장 탭으로 옮긴 뒤 scripts/team-up.sh --up"; warn "배치: cf-impl($L_IMPL)이 팀장과 다른 탭에 있음" ;;
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
	check_member_opts
	print_table
	print_check_summary
	check_layout
	all_alive && [ "$opts_ok" = 1 ]
	exit
	;;
status)
	check_member_opts
	print_status
	exit 0
	;;
up)
	if [ -n "$resume_id" ]; then
		case "$resume_id" in *[!0-9A-Fa-f-]*) die "세션 id 형식이 아니다: $resume_id" ;; esac
		[ "${#resume_id}" -ge 8 ] || die "세션 id가 너무 짧다(8자 이상): $resume_id"
		other="$(session_alive_in "$resume_id")"
		[ -z "$other" ] || die "세션 $resume_id 가 이미 $other 에 살아 있다; 복구하지 않음"
		case "${S_STATUS[1]}" in
		alive | unnamed) die "구현 agy가 이미 ${S_PANE[1]} 에 살아 있다; 복구하지 않음" ;;
		conflict) die "cf-impl: ${S_NOTE[1]} (${S_PANE[1]}); 복구하지 않음" ;;
		esac
	fi
	[ "$EXT_LEAD" = 0 ] || usable_anchor 1 || usable_anchor 2 || die "$NO_MEMBER_PANE_MSG"
	ensure_external_lead_lock
	[ "$EXT_LEAD" = 1 ] || secure_lead
	check_member_opts
	fail=0
	if [ -n "$resume_id" ]; then
		impl_cmd="agy --conversation $resume_id --model $IMPL_MODEL --mode accept-edits --sandbox"
	else
		impl_cmd="${SEAT_CMD[1]}"
	fi
	ensure_member 1 "$impl_cmd" || fail=1
	ensure_member 2 "${SEAT_CMD[2]}" || fail=1
	finish_layout || fail=1
	exit "$fail"
	;;
esac

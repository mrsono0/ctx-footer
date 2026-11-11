#!/usr/bin/env bash
# ctx-footer Herdr Core(hc) 외부 팀장 전용 감시·확인창 1회 허용·전송·critic 초기화 스크립트.
#   scripts/core-watch.sh --watch <회차 폴더> [--max <초>] [--interval <초>]
#   scripts/core-watch.sh --approve-once <cf-impl|cf-critic> [--allow-file <경로>]
#   scripts/core-watch.sh --send <cf-impl|cf-critic> <메시지>
#   scripts/core-watch.sh --critic-new
set -u

HC_BIN="${HC_BIN:-hc}"
RETRIES="${CF_RETRIES:-20}"
RETRY_SLEEP="${CF_RETRY_SLEEP:-0.5}"

die() { echo "core-watch: $*" >&2; exit 1; }
warn() { echo "core-watch: $*" >&2; }
usage() {
	cat >&2 <<'EOF'
사용법:
  scripts/core-watch.sh --watch <회차 폴더> [--max <초>] [--interval <초>]
  scripts/core-watch.sh --approve-once <cf-impl|cf-critic> [--allow-file <경로>]
  scripts/core-watch.sh --send <cf-impl|cf-critic> <메시지>
  scripts/core-watch.sh --critic-new
EOF
	exit 2
}

command -v "$HC_BIN" >/dev/null 2>&1 || die "hc 명령($HC_BIN)이 없다"
command -v python3 >/dev/null 2>&1 || die "python3 명령이 없다"

mode=""
round_dir=""
max_sec=3600
interval_sec=10
target_name=""
allow_file=""
send_msg=""

case "${1:-}" in
--watch)
	mode=watch
	[ "$#" -ge 2 ] || usage
	round_dir="${2:-}"
	[ -n "$round_dir" ] || usage
	shift 2
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--max)
			[ "$#" -ge 2 ] || usage
			max_sec="$2"
			case "$max_sec" in '' | *[!0-9]*) usage ;; esac
			shift 2
			;;
		--interval)
			[ "$#" -ge 2 ] || usage
			interval_sec="$2"
			case "$interval_sec" in '' | *[!0-9]*) usage ;; esac
			shift 2
			;;
		*)
			usage
			;;
		esac
	done
	;;
--approve-once)
	mode=approve
	[ "$#" -ge 2 ] || usage
	target_name="${2:-}"
	case "$target_name" in cf-impl | cf-critic) ;; *) usage ;; esac
	shift 2
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--allow-file)
			[ "$#" -ge 2 ] || usage
			allow_file="${2:-}"
			[ -n "$allow_file" ] || usage
			shift 2
			;;
		*)
			usage
			;;
		esac
	done
	;;
--send)
	mode=send
	[ "$#" -eq 3 ] || usage
	target_name="${2:-}"
	send_msg="${3:-}"
	case "$target_name" in cf-impl | cf-critic) ;; *) usage ;; esac
	[ -n "$send_msg" ] || usage
	;;
--critic-new)
	mode=critic_new
	[ "$#" -eq 1 ] || usage
	;;
-h | --help)
	cat <<'EOF'
사용법:
  scripts/core-watch.sh --watch <회차 폴더> [--max <초>] [--interval <초>]
  scripts/core-watch.sh --approve-once <cf-impl|cf-critic> [--allow-file <경로>]
  scripts/core-watch.sh --send <cf-impl|cf-critic> <메시지>
  scripts/core-watch.sh --critic-new
EOF
	exit 0
	;;
*)
	usage
	;;
esac

# hc get <이름> --json → "t_state \x1f s_state \x1f turn"
# shellcheck disable=SC2016
PY_PARSE_GET='import json, os, sys
raw = os.environ.get("HC_JSON", "")
rc = sys.argv[1]
if rc != "0" or not raw.strip():
    print("missing\x1fmissing\x1f0")
    sys.exit(0)
try:
    d = json.loads(raw)
    t_state = str(d.get("state") or "missing")
    st = d.get("status") if isinstance(d.get("status"), dict) else {}
    s_state = str(st.get("state") or "missing")
    turn_v = d.get("turn")
    turn_s = str(turn_v) if isinstance(turn_v, int) else "0"
    print("\x1f".join([t_state, s_state, turn_s]))
except Exception:
    print("error\x1ferror\x1f0")
'

# hc get <이름> --json에서 status.msg 전체(여러 줄 보존)를 그대로 출력
# shellcheck disable=SC2016
PY_PRINT_MSG='import json, os
raw = os.environ.get("HC_JSON", "")
try:
    d = json.loads(raw)
    st = d.get("status") if isinstance(d.get("status"), dict) else {}
    msg = st.get("msg")
    if isinstance(msg, str) and msg != "":
        print(msg)
    else:
        print("msg 없음")
except Exception:
    print("msg 없음")
'

query_member() {
	local name="$1" raw rc
	raw="$("$HC_BIN" get "$name" --json 2>/dev/null)"
	rc=$?
	HC_JSON="$raw" python3 -c "$PY_PARSE_GET" "$rc"
}

list_matching_to_lead() {
	local d="${round_dir%/}/to-lead"
	if [ -d "$d" ]; then
		D_PATH="$d" python3 -c '
import os, re
d = os.environ["D_PATH"]
pat = re.compile(r"(REPORT|BLOCKER|ASK|NEED)")
try:
    for name in sorted(os.listdir(d)):
        if not name.startswith(".") and pat.search(name):
            print(name)
except Exception:
    pass
'
	fi
}

run_watch() {
	local base_files cur_files new_file start_ts now name raw rc info t_state s_state _
	base_files="$(list_matching_to_lead)"
	start_ts="$(date +%s)"
	while :; do
		cur_files="$(list_matching_to_lead)"
		new_file="$(BASE_F="$base_files" CUR_F="$cur_files" python3 -c '
import os
base_set = set(x for x in os.environ["BASE_F"].splitlines() if x)
for name in os.environ["CUR_F"].splitlines():
    if name and name not in base_set:
        print(name)
        break
')"
		if [ -n "$new_file" ]; then
			printf 'EVENT to-lead %s/to-lead/%s\n' "${round_dir%/}" "$new_file"
			exit 0
		fi

		for name in cf-impl cf-critic; do
			raw="$("$HC_BIN" get "$name" --json 2>/dev/null)"
			rc=$?
			info="$(HC_JSON="$raw" python3 -c "$PY_PARSE_GET" "$rc")"
			IFS=$'\x1f' read -r t_state s_state _ <<<"$info"
			if [ "$t_state" != "live" ] || [ "$s_state" = "error" ]; then
				printf 'EVENT error %s state=%s status=%s\n' "$name" "$t_state" "$s_state"
				exit 0
			fi
			if [ "$s_state" = "blocked" ]; then
				printf 'EVENT blocked %s\n' "$name"
				HC_JSON="$raw" python3 -c "$PY_PRINT_MSG"
				exit 0
			fi
		done

		now="$(date +%s)"
		if [ $((now - start_ts)) -ge "$max_sec" ]; then
			printf 'EVENT timeout\n'
			exit 0
		fi

		if [ "$interval_sec" -gt 0 ]; then
			sleep "$interval_sec"
		fi
	done
}

# hc get <이름> --json 원문에서 status.state 및 status.msg 전체(개행 포함 원문)를
# 명령 파싱 없이 --allow-file <경로>(한 줄에 명령 한 줄)와 바이트 그대로 대조:
# 출력: ok | not-blocked(...) | msg-empty | allow-file-missing | allow-file-empty | disallowed-command
# shellcheck disable=SC2016
PY_CHECK_ALLOW='import json, os, sys

raw = os.environ.get("HC_JSON", "")
allow_path = os.environ.get("ALLOW_FILE", "")
rc = sys.argv[1]

if rc != "0" or not raw.strip():
    print("not-blocked(state=missing,status=missing)")
    sys.exit(1)

try:
    d = json.loads(raw)
except Exception:
    print("not-blocked(state=error,status=error)")
    sys.exit(1)

t_state = str(d.get("state") or "missing") if isinstance(d, dict) else "missing"
st = d.get("status") if isinstance(d, dict) and isinstance(d.get("status"), dict) else {}
s_state = str(st.get("state") or "missing")

if t_state != "live" or s_state != "blocked":
    print(f"not-blocked(state={t_state},status={s_state})")
    sys.exit(1)

raw_msg = st.get("msg")
if not isinstance(raw_msg, str) or not raw_msg.strip():
    print("msg-empty")
    sys.exit(1)

if not allow_path or not os.path.isfile(allow_path):
    print("allow-file-missing")
    sys.exit(1)

try:
    with open(allow_path, "rb") as f:
        allow_bytes = f.read()
except Exception:
    print("allow-file-missing")
    sys.exit(1)

allowed_lines = {line for line in allow_bytes.split(b"\n") if line.strip()}
if not allowed_lines:
    print("allow-file-empty")
    sys.exit(1)

msg_bytes = raw_msg.encode("utf-8")
if b"\n" in msg_bytes or b"\r" in msg_bytes:
    print("disallowed-command")
    sys.exit(1)

if msg_bytes in allowed_lines:
    print("ok")
    sys.exit(0)

print("disallowed-command")
sys.exit(1)
'

run_approve_once() {
	local raw rc verdict key_out
	raw="$("$HC_BIN" get "$target_name" --json 2>/dev/null)"
	rc=$?
	if ! verdict="$(HC_JSON="$raw" ALLOW_FILE="$allow_file" python3 -c "$PY_CHECK_ALLOW" "$rc")" || [ "$verdict" != "ok" ]; then
		printf 'EVENT blocked-unhandled %s %s\n' "$target_name" "${verdict:-disallowed-command}"
		exit 1
	fi
	key_out="$("$HC_BIN" keys "$target_name" enter --json 2>&1)" || {
		printf 'EVENT blocked-unhandled %s keys-failed(%s)\n' "$target_name" "$key_out"
		exit 1
	}
	printf 'APPROVED %s enter\n' "$target_name"
	exit 0
}

run_send() {
	local info t_state s_state _
	info="$(query_member "$target_name")"
	IFS=$'\x1f' read -r t_state s_state _ <<<"$info"
	if [ "$t_state" != "live" ]; then
		warn "$target_name: 살아 있지 않다(state=$t_state); 전송하지 않음"
		printf 'EVENT send-refused %s state=%s\n' "$target_name" "$t_state"
		exit 1
	fi
	case "$s_state" in
	idle)
		"$HC_BIN" send --if idle "$target_name" "$send_msg"
		exit $?
		;;
	done)
		"$HC_BIN" send "$target_name" "$send_msg"
		exit $?
		;;
	*)
		warn "$target_name: 현재 상태가 '$s_state'이므로 보내지 않음(idle·done일 때만 전송)"
		printf 'EVENT send-refused %s status=%s\n' "$target_name" "$s_state"
		exit 1
		;;
	esac
}

run_critic_new() {
	local info t_state s_state before_turn after_turn tries=0
	info="$(query_member cf-critic)"
	IFS=$'\x1f' read -r t_state s_state before_turn <<<"$info"
	if [ "$t_state" != "live" ]; then
		die "cf-critic: 살아 있지 않다(state=$t_state); /new를 보내지 않음"
	fi
	case "$s_state" in
	idle)
		"$HC_BIN" send --if idle cf-critic "/new" >/dev/null || die "cf-critic: /new 전송 실패"
		;;
	done)
		"$HC_BIN" send cf-critic "/new" >/dev/null || die "cf-critic: /new 전송 실패"
		;;
	*)
		die "cf-critic: 현재 상태가 '$s_state'이다(idle·done일 때만 /new 가능); 보내지 않음"
		;;
	esac

	while [ "$tries" -lt "$RETRIES" ]; do
		info="$(query_member cf-critic)"
		IFS=$'\x1f' read -r t_state s_state after_turn <<<"$info"
		if [ "$t_state" = "live" ] && [ "$s_state" = "idle" ] && [ "${after_turn:-0}" -gt "${before_turn:-0}" ] 2>/dev/null; then
			printf 'cf-critic: /new 완료 (turn %s→%s, status=idle)\n' "$before_turn" "$after_turn"
			exit 0
		fi
		tries=$((tries + 1))
		[ "$tries" -ge "$RETRIES" ] || sleep "$RETRY_SLEEP"
	done
	die "cf-critic: /new 뒤 idle 및 turn 증가 확인 실패(before=$before_turn, after=${after_turn:-?}, status=${s_state:-?})"
}

case "$mode" in
watch) run_watch ;;
approve) run_approve_once ;;
send) run_send ;;
critic_new) run_critic_new ;;
esac

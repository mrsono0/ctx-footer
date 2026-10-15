#!/usr/bin/env bash
# ctx-footer critic 비대화형 1회차 실행기 (docs/05 critic-exec-r1).
#   scripts/critic-run.sh <회차 폴더> <동결 사본 경로>
# 입력: <회차 폴더>/REQUEST.md, <동결 사본 경로>(저장소 밖·상위 경로 제외)
# 출력: <회차 폴더>/VERDICT.md(-o), <회차 폴더>/events.jsonl(--json), 한 줄 요약(종료 코드·VERDICT 첫 줄·걸린 시간)
set -u

CRITIC_MODEL="gpt-6.1-sol"
CRITIC_REASONING='model_reasoning_effort="high"'
# workspace-write + /tmp·TMPDIR·writable_roots 제외 설정으로 쓰기 루트를 동결 사본(-C)으로만 좁힌다(danger-full-access·--yolo 금지).
CRITIC_SANDBOX="workspace-write"

usage() {
	sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//' >&2
	exit 2
}
warn() { echo "critic-run: $*" >&2; }
die() { warn "$*"; exit 1; }

[ "$#" -eq 2 ] && [ -n "$1" ] && [ -n "$2" ] || usage

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
[ -d "$1" ] || die "회차 폴더가 없다: $1"
[ -d "$2" ] || die "동결 사본 경로가 없다: $2"

ROUND_DIR="$(cd "$1" && pwd -P)" || die "회차 폴더 경로 확인 실패: $1"
FROZEN_DIR="$(cd "$2" && pwd -P)" || die "동결 사본 경로 확인 실패: $2"

is_subpath() { case "${1%/}/" in "${2%/}"/*) return 0 ;; esac; return 1; }
is_subpath "$FROZEN_DIR" "$ROOT" && die "동결 사본($FROZEN_DIR)이 저장소($ROOT) 안이다; 거부"
is_subpath "$ROOT" "$FROZEN_DIR" && die "동결 사본($FROZEN_DIR)이 저장소($ROOT)를 포함하는 상위 경로다; 거부"
is_subpath "$ROUND_DIR" "$ROOT" && die "회차 폴더($ROUND_DIR)가 저장소($ROOT) 안이다; 거부"

REQUEST_FILE="$ROUND_DIR/REQUEST.md"
[ -f "$REQUEST_FILE" ] || die "REQUEST.md가 없다: $REQUEST_FILE"
command -v codex >/dev/null || die "codex 명령이 없다"

VERDICT_FILE="$ROUND_DIR/VERDICT.md"
EVENTS_FILE="$ROUND_DIR/events.jsonl"
STDERR_FILE="$ROUND_DIR/stderr.log"
rm -f "$VERDICT_FILE"

PROMPT="$REQUEST_FILE 를 읽고 동결 사본($FROZEN_DIR)만 점검해 판정하라. herdr 전송은 하지 말고 판정 전문을 최종 메시지로 출력하라. 첫 줄은 반드시 VERDICT: APPROVE | APPROVE_WITH_CHANGES | REJECT 형식이어야 한다."

SECONDS=0
codex exec \
	--disable worktrees \
	--skip-git-repo-check \
	-m "$CRITIC_MODEL" \
	-c "$CRITIC_REASONING" \
	-c 'sandbox_workspace_write.exclude_slash_tmp=true' \
	-c 'sandbox_workspace_write.exclude_tmpdir_env_var=true' \
	-c 'sandbox_workspace_write.writable_roots=[]' \
	-s "$CRITIC_SANDBOX" \
	-C "$FROZEN_DIR" \
	--json \
	-o "$VERDICT_FILE" \
	"$PROMPT" >"$EVENTS_FILE" 2>"$STDERR_FILE"
rc=$?
elapsed=$SECONDS

verdict_line="NONE"
if [ -f "$VERDICT_FILE" ]; then
	IFS= read -r verdict_line <"$VERDICT_FILE" || true
	verdict_line="${verdict_line%$'\r'}"
	[ -n "$verdict_line" ] || verdict_line="EMPTY"
fi

printf 'critic-run: rc=%d elapsed=%ds verdict=%s file=%s\n' "$rc" "$elapsed" "$verdict_line" "$VERDICT_FILE"
exit "$rc"

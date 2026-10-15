#!/usr/bin/env bash
# scripts/critic-run.sh 최소 모의 테스트. ci/mock/codex만 부르며 실제 Codex를 호출하지 않는다.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$ROOT/scripts/critic-run.sh"
MOCK_DIR="$ROOT/ci/mock"
CRITIC_RUN_BASH="${CRITIC_RUN_BASH:-${BASH:-bash}}"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/cf-critic-run-test.XXXXXX")" || exit 1
cleanup() { [ -n "$TMP" ] && [ -d "$TMP" ] && rm -rf -- "$TMP"; }
trap cleanup EXIT

export PATH="$MOCK_DIR:$PATH"
if [ "$(command -v codex)" != "$MOCK_DIR/codex" ]; then
	echo "FATAL: codex가 모의($MOCK_DIR/codex)가 아니다: $(command -v codex)" >&2
	exit 1
fi

LOG="$TMP/codex-calls.log"
ENV_LOG="$TMP/codex-env.log"
ROUND="$TMP/round"
FROZEN="$TMP/frozen"
mkdir -p "$ROUND" "$FROZEN"
echo "# test request" >"$ROUND/REQUEST.md"
ROUND_REAL="$(cd "$ROUND" && pwd -P)"
FROZEN_REAL="$(cd "$FROZEN" && pwd -P)"

PASS=0
FAIL=0
CASE=""

check() {
	local desc=$1
	shift
	if "$@"; then
		PASS=$((PASS + 1))
	else
		FAIL=$((FAIL + 1))
		echo "FAIL [$CASE] $desc" >&2
	fi
}
eq() { [ "$1" = "$2" ]; }
has() { grep -qF -- "$1" <<<"$2"; }

# 1. 정상 실행: 인자 구성·쓰기 경계 설정·VERDICT 파일 경로·종료 코드 0
CASE="정상 실행(APPROVE)"
: >"$LOG"
: >"$ENV_LOG"
OUT="$(MOCK_CODEX_LOG="$LOG" MOCK_CODEX_ENV_LOG="$ENV_LOG" "$CRITIC_RUN_BASH" "$SCRIPT" "$ROUND" "$FROZEN" 2>&1)"
RC=$?
CALL="$(cat "$LOG")"
ENV_VAL="$(tr -d '\r\n' <"$ENV_LOG")"
check "종료 코드 0" eq "$RC" 0
check "exec 서브커맨드" has $'exec\t' "$CALL"
check "모델 gpt-6.1-sol" has $'\t-m\tgpt-6.1-sol\t' "$CALL"
check "추론 강도 high" has $'\t-c\tmodel_reasoning_effort="high"\t' "$CALL"
check "/tmp 쓰기 제외" has $'\t-c\tsandbox_workspace_write.exclude_slash_tmp=true\t' "$CALL"
check "TMPDIR 쓰기 제외" has $'\t-c\tsandbox_workspace_write.exclude_tmpdir_env_var=true\t' "$CALL"
check "추가 writable_roots 빈 배열" has $'\t-c\tsandbox_workspace_write.writable_roots=[]\t' "$CALL"
check "sandbox workspace-write" has $'\t-s\tworkspace-write\t' "$CALL"
check "작업 디렉터리 -C 동결 사본" has $'\t-C\t'"$FROZEN_REAL"$'\t' "$CALL"
check "임시 디렉터리 --add-dir 전달" has $'\t--add-dir\t'"$ROUND_REAL/tmp"$'\t' "$CALL"
check "TMPDIR 환경변수 전달" eq "$ENV_VAL" "$ROUND_REAL/tmp"
check "회차 tmp 디렉터리 생성됨" test -d "$ROUND_REAL/tmp"
check "--json 플래그" has $'\t--json\t' "$CALL"
check "-o VERDICT 경로" has $'\t-o\t'"$ROUND_REAL/VERDICT.md"$'\t' "$CALL"
check "위험 플래그(--yolo/danger) 없음" "$CRITIC_RUN_BASH" -c '! grep -qE -- "--yolo|danger" "$1"' _ "$LOG"
check "VERDICT.md 생성됨" test -f "$ROUND_REAL/VERDICT.md"
check "events.jsonl 생성됨" test -s "$ROUND_REAL/events.jsonl"
check "요약 출력에 VERDICT 첫 줄 포함" has "verdict=VERDICT: APPROVE" "$OUT"
check "요약 출력에 VERDICT 파일 경로 포함" has "file=$ROUND_REAL/VERDICT.md" "$OUT"

# 2. 종료 코드 전달(비0)
CASE="실패 종료 코드 전달"
: >"$LOG"
OUT="$(MOCK_CODEX_LOG="$LOG" MOCK_CODEX_RC=7 "$CRITIC_RUN_BASH" "$SCRIPT" "$ROUND" "$FROZEN" 2>&1)"
RC=$?
check "종료 코드 7 전달" eq "$RC" 7
check "이전 VERDICT.md 제거됨" test ! -f "$ROUND_REAL/VERDICT.md"
check "요약 출력에 rc=7" has "rc=7" "$OUT"

# 3. 안전 가드: 저장소 안 경로를 동결 사본으로 주면 거부
CASE="저장소 안 -C 거부"
: >"$LOG"
OUT="$(MOCK_CODEX_LOG="$LOG" "$CRITIC_RUN_BASH" "$SCRIPT" "$ROUND" "$ROOT" 2>&1)"
RC=$?
check "종료 코드 1" eq "$RC" 1
check "codex 호출 없음" test ! -s "$LOG"

# 4. 안전 가드: 저장소를 포함하는 상위 경로를 동결 사본으로 주면 거부
CASE="저장소 상위 경로 -C 거부"
: >"$LOG"
ROOT_PARENT="$(cd "$ROOT/.." && pwd -P)"
OUT="$(MOCK_CODEX_LOG="$LOG" "$CRITIC_RUN_BASH" "$SCRIPT" "$ROUND" "$ROOT_PARENT" 2>&1)"
RC=$?
check "종료 코드 1" eq "$RC" 1
check "codex 호출 없음" test ! -s "$LOG"

# 5. 안전 가드: 회차 폴더나 tmp가 저장소·상위 경로를 가리키면 거부
CASE="회차 상위 경로 및 tmp 심볼릭 링크 거부"
: >"$LOG"
OUT="$(MOCK_CODEX_LOG="$LOG" "$CRITIC_RUN_BASH" "$SCRIPT" "$ROOT_PARENT" "$FROZEN" 2>&1)"
RC=$?
check "상위 회차 폴더 종료 코드 1" eq "$RC" 1
ROUND_SYM="$TMP/round-sym"
mkdir -p "$ROUND_SYM"
echo "# test request" >"$ROUND_SYM/REQUEST.md"
ln -s "$ROOT" "$ROUND_SYM/tmp"
OUT="$(MOCK_CODEX_LOG="$LOG" "$CRITIC_RUN_BASH" "$SCRIPT" "$ROUND_SYM" "$FROZEN" 2>&1)"
RC=$?
check "저장소 가리키는 tmp 종료 코드 1" eq "$RC" 1
check "codex 호출 없음" test ! -s "$LOG"

# shellcheck disable=SC2016
echo "critic-run 테스트: 통과 $PASS / 전체 $((PASS + FAIL)) (bash: $("$CRITIC_RUN_BASH" -c 'echo $BASH_VERSION'))"
[ "$FAIL" = 0 ]

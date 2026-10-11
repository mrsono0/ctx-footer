#!/usr/bin/env bash
# ctx-footer 개발 검사 — plugin/ 대상 (docs/05 P3, docs/03 §5).
#   ① claude plugin validate (마켓플레이스 루트 + plugin)
#   ② 버전 고정 bunx tsc (T1: package.json 없이 — docs/06 결정, M3)
#   ③ claude plugin test (plugin/ — 테스트 0개면 통과로 본다)
#   ④ 금지 API 검색 (docs/03 §5 정규식) 0건
set -u

TSC_VERSION="7.0.2" # bunx 고정 TypeScript(npm 배포 2026-07-08, 안정판)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PLUGIN="$ROOT/plugin"

die() { echo "dev-check: $*" >&2; exit 1; }
step() { printf '\n== %s ==\n' "$*"; }

# 엔진 생성 타입이 없으면 안내하고 실패 (claude --plugin-dir ./plugin 로 한 번 띄워 생성)
[ -f "$PLUGIN/.claude-plugin/types/tsconfig.json" ] ||
	die "엔진 생성 타입(plugin/.claude-plugin/types/)이 없다 — claude --plugin-dir ./plugin 으로 한 번 띄워 타입을 생성하라"

step "1/4 plugin validate (marketplace + plugin)"
claude plugin validate "$ROOT" || die "validate(마켓플레이스 루트) 실패"
claude plugin validate "$PLUGIN" || die "validate(plugin) 실패"

step "2/4 tsc (bunx, typescript@$TSC_VERSION 고정)"
(cd "$PLUGIN" && bunx -p "typescript@$TSC_VERSION" tsc -p .) || die "tsc 실패"

step "3/4 plugin test (테스트 0개면 통과)"
if ls "$PLUGIN"/tests/*.test.ts >/dev/null 2>&1; then
	(cd "$PLUGIN" && claude plugin test .) || die "plugin test 실패"
else
	echo "테스트 파일 없음(P4 예정) — 통과로 본다"
fi

step "4/4 금지 API 검색 (docs/03 §5)"
targets=("$PLUGIN/hooks")
[ -d "$PLUGIN/tests" ] && targets+=("$PLUGIN/tests")
if grep -REn '\$\.(process|fs|net|store)|session\.(send|append|authorize)|fetch\(' "${targets[@]}" 2>/dev/null; then
	die "금지 API 발견 (docs/01 N1)"
fi
echo "금지 API 0건"

echo
echo "dev-check 통과 — validate 2 · tsc@$TSC_VERSION · test · 금지 API 0건"

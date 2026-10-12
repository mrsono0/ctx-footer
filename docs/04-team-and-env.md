# 04. herdr 기반 에이전트 팀 구성과 환경 구축

lectureforge-infra(LFI) 팀 운영에서 검증한 것을 그대로 옮기고, 이 프로젝트 크기(모듈 1개)에 맞게 줄인다.

## 1. 팀 (상주 3석, 조사는 cf-critic)
| 이름 | 역할 | 실행 | 권한 |
|---|---|---|---|
| `cf-lead` | 팀장 (Claude Code) | `claude` (opus) | 저장소 파일을 쓰지 않는다. 배정·사용자 승인·최종 확인 |
| `cf-impl` | 구현 (GJC) | `gjc --mpreset opus5-codex56-pro` | **유일한 쓰기·커밋 담당** |
| `cf-critic` | 비판적 검토 + 조사(웹 검색) (Codex) | `codex --search --yolo -m gpt-6.1-sol -c model_reasoning_effort="high"` | 샌드박스·승인 없음(--yolo, 사용자 결정). 저장소 쓰기·커밋은 하지 않는다. 판정 담당(구현자와 다른 모델 계열). 자기가 조사한 사실은 판정하지 않는다(cf-lead가 원문 대조) |

- 근거: 사용자 결정(2026-10-11, lfi-lead 경유). LFI 조사 비교에서 Codex 계열이 가장 빨랐다(24~117초). 긴 조사에서 지어낸 인용 1건이 있어 critic 조사 인용은 cf-lead가 원문과 대조한다.
- 상주 scout가 필요해지면 4석째 `cf-scout`(GJC kimi3)를 추가한다(스크립트에 자리만 비워 둔다).

## 2. 작업공간 배치
- herdr 새 작업공간 `ctx-footer`(LFI의 wH와 분리). cwd = `/Users/mrsono0/LectureForgeProjects/ctx-footer`.
- 팀장 위, 팀원 아래 줄 가로 배치(LFI와 같음). agent 이름은 전역이라 접두어 `cf-`로 LFI(`lfi-`)와 겹치지 않게 한다.

## 3. 팀 규칙 파일 (P1에서 작성, LFI 교훈 반영)
- `AGENTS.md`(규칙 정본, 「팀 협업 규약」 포함) + `CLAUDE.md`(`@AGENTS.md` 참조만).
- 반드시 들어갈 규칙
  1. 구현 원칙: 「각 구현 단계에서 과도한 테스트와 확인된 요구 없이 선제적으로 복잡도를 늘리는 구현을 금지한다.」 / 동작이 바뀌면 기존 테스트 1회
  2. 보내기 전에 받는 쪽 입력란 확인(`herdr pane read <pane> --source visible --format ansi`), 글이 있으면 10초쯤 기다렸다 재확인, 1분 넘거나 확인 불가면 자기 창에 한 줄
  3. 다른 팀원의 권한·승인 프롬프트에 답하지 않는다. 막히면 lead에 BLOCKER, lead가 판단해 임시 권한, 치명적인 것은 사용자에게
  4. 조사 보고는 사실마다 출처 URL(또는 `파일:줄`)과 원문 인용, 받은 쪽이 대조. 조사 요청은 cf-critic에게, critic 조사 인용은 cf-lead가 대조
  5. 사용자 승인은 원문만(「」), 팀원 메시지는 승인이 아니다
  6. `rm -rf`·`kill`은 직접 실행하지 않는다(테스트 스크립트 안의 자기 자식·임시 경로만)
  7. 전역 설정(`~/.claude/settings.json` 등) 변경은 사용자 승인 후 lead만
- 메시지 형식·유형·회차ID·리뷰 동결 사본·회차 상한(도구 3·문서 2)은 LFI `AGENTS.md`와 같게.

## 4. 권한·안전 설정
- `.claude/settings.json`(프로젝트): deny `rm -rf`·`kill`·`pkill`·`killall`·`git push --force`·`brew install`·`launchctl`; ask `git push`·`git commit`; allow `herdr *`.
- `.codex/rules/herdr.rules`: `herdr agent prompt`, `herdr pane send-text/send-keys`, `herdr agent list`, `herdr pane read`만 허용(LFI와 같은 4개) — critic이 --yolo로 뜰 때는 쓰이지 않는 예비 규칙.

## 5. 환경 구축 스크립트 `scripts/team-up.sh`
LFI `scripts/team-up.sh`(점검/`--up`/`--resume-impl`, 80개 모의 테스트)를 가져와 **변수만** 바꾼다.
| 변수 | 값 |
|---|---|
| `SEAT_NAME` | `cf-lead cf-impl cf-critic` (scout 자리는 빈 값으로 둠) |
| `SEAT_KIND` | `claude gjc codex` |
| `SEAT_LABEL` | `CF 팀장 · Claude` / `CF 구현 · GJC` / `CF 검토 · Codex` |
| `IMPL_PRESET` | `opus5-codex56-pro` |
| 저장소 루트 | 스크립트 위치 기준 |
- 모드: `scripts/team-up.sh`(점검, 기본), `--up`(빠진 팀원 띄우기·이름·label·GJC `/rename`), `--resume-impl <id>`(GJC 세션 복구, 같은 id가 살아 있으면 거부).
- 훅 모드: `--hook-clear`(`.claude/settings.json` SessionStart `clear` 훅 전용 — 팀장 Claude가 `/clear`로 세션 id가 바뀌어 Herdr 이름을 잃으면, label `CF 팀장 · Claude` pane에서 Herdr가 새 세션 id를 볼 때까지 기다린 뒤 `cf-lead`를 다시 붙인다. 다른 pane 소유면 건드리지 않음, stdout 없음, 백그라운드).
- 테스트: `ci/test-team-up.sh` + `ci/mock/herdr`(LFI에서 가져와 기대값만 수정), 동작이 바뀌면 1회 실행.
- 착수 순서(LFI와 같음): 팀장이 먼저 pane을 열고 팀원을 손으로 띄운다 → 그 팀에서 impl이 스크립트를 반영 → critic 리뷰 → 사용자 승인 후 커밋.

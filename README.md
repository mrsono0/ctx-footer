# ctx-footer

Claude Code **바닥줄(prompt footer) 오른쪽 모드 표시 자리**에 컨텍스트 창 사용량을 한 줄로 덧붙이는 미니멀 mod.

```
-- INSERT -- ⏵⏵ auto mode on (shift+tab to cycle)      ctx 53% · 531k/1000k
```
넓은 화면에서는 긴 형식, 좁은 화면(기준 폭 96열 미만)에서는 `ctx 53%`로 줄어든다.

- 줄을 늘리지 않는다: 별도 상태줄(statusLine)·입력창 위 밴드 없이, 엔진이 이미 그리는 `SessionMode` 자리에 라벨 하나를 더한다.
- 안전: 셸·파일·네트워크를 쓰지 않는다. 엔진이 주는 `$.session.usage()` 수치만 읽는다.
- 차용: [dashband](https://github.com/EgonLeitner/dashband)(MIT)의 필요한 부분만(→ `third_party/dashband/`).

## 문서
| 문서 | 내용 |
|---|---|
| [docs/01-feature-definition.md](docs/01-feature-definition.md) | 기능 정의·요구사항·인수 기준 |
| [docs/02-spec-analysis.md](docs/02-spec-analysis.md) | API·문서 근거 분석, dashband 차용 범위, 미확인 |
| [docs/03-design.md](docs/03-design.md) | 설계(모듈·상태·렌더·형식)·스캐폴딩·테스트·배포 |
| [docs/04-team-and-env.md](docs/04-team-and-env.md) | herdr 기반 에이전트 팀 구성과 환경 구축 스크립트 설계 |
| [docs/05-work-plan.md](docs/05-work-plan.md) | 단계별 상세 작업계획서 |
| [docs/06-spike-results.md](docs/06-spike-results.md) | P2 스파이크 실측(U1–U5)·타입 시그니처 확정 |
| [docs/07-acceptance.md](docs/07-acceptance.md) | P5 실화면 검증(인수 기준 A1–A5)·기준 폭 96 확정 근거 |

## 상태
P0–P6 완료(2026-10-11, 0.1.0 설치 확인). 릴리스 태그 대기. 라이선스 MIT. 요구: Claude Code 2.1.287 이상(시험 환경 2.1.296).

## 설치
요구: Claude Code 2.1.287 이상(시험 환경 2.1.296). 아래 한 줄 설치 명령은 2.1.292 이상에서 동작한다.

셸에서 한 줄(user scope로 설치된다):
```
claude plugin install ctx-footer --marketplace mrsono0/ctx-footer
```
또는 Claude Code 세션 안에서:
```
/plugin marketplace add mrsono0/ctx-footer
/plugin install ctx-footer@ctx-footer
```
설치 뒤 새 세션(또는 `/reload-plugins`)부터 첫 응답이 끝나면 바닥줄 오른쪽에 라벨이 보인다.

공식 마켓플레이스 디렉터리에는 등록하지 않는다. GitHub 주소로만 설치한다.

**주의**: 커스텀 statusLine을 쓰고 있으면 라벨은 모드 줄이 아니라 statusLine 줄의 오른쪽 끝에 붙는다. 그러면 바닥줄은 한 줄이 아니게 된다(docs/06 U1).

## 업데이트
```
claude plugin marketplace update ctx-footer
claude plugin update ctx-footer@ctx-footer
```
업데이트 뒤에는 새 세션을 시작하거나 `/reload-plugins`로 새 버전을 적용한다.
자동 업데이트는 세션 안 `/plugin`의 Marketplaces 화면에서 `ctx-footer`에 대해 켠다.

## 되돌리기
```
claude plugin uninstall ctx-footer@ctx-footer
claude plugin marketplace remove ctx-footer
```
설치 전에 쓰던 커스텀 statusLine을 다시 쓰려면 `~/.claude/settings.json`의 `statusLine` 항목을 직접 되살린다. 이 플러그인은 statusLine을 바꾸지 않는다.

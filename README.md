# ctx-footer

Claude Code **바닥줄(prompt footer) 오른쪽 모드 표시 자리**에 컨텍스트 창 사용량을 한 줄로 덧붙이는 미니멀 mod.

```
-- INSERT -- ⏵⏵ auto mode on (shift+tab to cycle)            ctx 53% · 531k/1000k
```

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

## 상태
계획 확정(2026-10-11). P1(팀·환경 구축) 진행. 라이선스 MIT.

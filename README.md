# 두뇌풀가동 (Brain Overrun)

하이퍼캐주얼 생존 퀴즈 아케이드 · Roblox

제한 시간 안에 문제를 풀고 정답 구역으로 피신해 '파괴의 벽'을 피하는 배틀로얄.
전체 기획은 [CLAUDE.md](CLAUDE.md) 참고.

---

## 개발 환경 셋업

### 1. 툴체인 설치

이 저장소는 [Rokit](https://github.com/rojo-rbx/rokit)으로 툴 버전을 고정한다.
Rokit이 없다면 먼저 설치한 뒤:

```powershell
rokit install
```

`rokit.toml`에 명시된 Rojo 버전이 자동으로 설치된다.

### 2. Studio 플러그인 설치

```powershell
rojo plugin install
```

### 3. 동기화 시작

```powershell
rojo serve
```

Studio에서 **Plugins → Rojo → Connect** 를 누르면 연결된다.
이후 `src/` 아래 `.luau` 파일을 저장하면 Studio에 즉시 반영된다.

---

## 프로젝트 구조

```
src/
├── shared/     → ReplicatedStorage.Shared   (서버·클라이언트 공용)
│   ├── Config.luau     밸런싱 수치 단일 소스
│   ├── Tags.luau       CollectionService 태그 상수
│   ├── Types.luau      공유 타입 정의
│   ├── Remotes.luau    네트워크 채널 정의
│   └── MapLayout.luau  Config 파생 맵 좌표/크기 계산
├── server/     → ServerScriptService.Server
│   ├── Bootstrap.server.luau  서버 진입점 (초기화 순서 주의)
│   ├── MapBuilder.luau        맵 생성
│   ├── SessionService.luau    한 판 동안의 플레이어 상태 (생존/관전)
│   ├── Arena.luau             배치·텔레포트·탈락 감지
│   ├── WallController.luau    파괴의 벽 이동/파괴
│   └── RoundService.luau      라운드 상태머신
└── client/     → StarterPlayer.StarterPlayerScripts.Client
    ├── Bootstrap.client.luau  클라이언트 진입점
    └── StatusDisplay.luau     상태·타이머 임시 표시 (Phase 3에서 HUD로 교체)
```

## 시스템 문서

코드를 수정하기 전에 해당 시스템의 문서를 먼저 읽을 것.

| 문서 | 내용 |
|---|---|
| [docs/map-builder.md](docs/map-builder.md) | 맵 빌더 (Phase 1) — 좌표계, 생성물 목록, 설계 근거, 불변 조건 |
| [docs/round-loop.md](docs/round-loop.md) | 라운드 루프 (Phase 2) — 상태머신, 생존 판정, 벽 이동 함정 |

## 맵 좌표계

`MapLayout.luau`가 `Config.Map`에서 모든 좌표를 계산한다. 자세한 내용은
[docs/map-builder.md](docs/map-builder.md) 참고. 요약하면:

* **X축** — 레인 폭 방향. **A레인이 -X, B레인이 +X**이며 X=0에서 맞붙는다.
* **Z축** — 레인 길이 방향이자 벽의 진행 방향. 벽은 **+Z에서 출발해 -Z로 돌진**하고,
  오답 구역 플레이어를 -Z 끝단 밖으로 밀어낸다. **-Z 끝은 절대 막지 않는다.**
* **Y축** — 높이. `Config.Map.FloorY`는 메인 바닥의 *윗면* 높이다(중심이 아님).

기본 수치 기준 경기장은 80 × 220 studs, 벽 이동거리 228 studs(1라운드 약 4.15초)다.

## 라운드 루프

`RoundService`가 게임의 시간 축을 혼자 소유한다. 자세한 내용은
[docs/round-loop.md](docs/round-loop.md) 참고. 요약하면:

```
Lobby → Countdown → WallRush → Judge → Intermission → (반복) → GameOver → Lobby
```

* **생존 판정은 위치 스냅샷이 아니라 물리 결과다.** 오답 구역 벽에 밀려 맵 밖으로 떨어진
  사람이 탈락자이며, 벽이 오는 동안 옆 레인으로 다이브해도 살 수 있다.
* **정답 구역은 아직 무작위다.** Phase 3이 `RoundService.pickCorrectZone` 하나만 갈아끼운다.
* ⚠ `Config.Debug.RevealAnswer`가 켜져 있으면 정답이 전 클라이언트에 노출된다.
  Phase 3에서 진짜 문제가 붙는 순간 **제거**할 것.

## 코딩 규약

1. **모든 밸런싱 수치는 `Config.luau`에만 존재한다.** 다른 파일에 하드코딩된 상수가 보이면 버그다.
2. **서버 권위(Server Authority).** 정답 값은 클라이언트로 전송하지 않고, 쿨타임·사용 횟수·거리 판정은 전부 서버가 한다.
3. **맵 오브젝트는 이름이 아닌 태그로 찾는다.** (`Tags.luau`)
4. **맵은 빌더 스크립트로 생성한다.** `.rbxl`은 git에 추적하지 않으며 언제든 재생성 가능해야 한다.

## 구현 로드맵

| Phase | 내용 | 상태 |
|---|---|---|
| 0 | 프로젝트 골격 · 규약 · Config | ✅ |
| 1 | 맵 빌더 (레인/벽/관전장/킬플레인) | ✅ |
| 2 | 라운드 상태머신 · 생존 판정 · 관전 전환 | ✅ |
| 3 | 문제 시스템 · 바닥 SurfaceGui · HUD | ⬜ |
| 4 | 난이도 커브 · 벽 파괴 연출 | ⬜ |
| 5 | 대시 · 밀치기 | ⬜ |
| 6 | DataStore · 코인 경제 · 상점 | ⬜ |
| 7 | 부활권 (MarketplaceService) | ⬜ |
| 8 | 이미지형 문제 · 사운드 · QA | ⬜ |

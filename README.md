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
│   ├── MapBuilder.luau        맵 골격 생성/재정렬 ★ 에디터 전용 도구 ★
│   ├── MapService.luau        씬에 배치된 맵 탐색·검증 (런타임)
│   ├── SessionService.luau    한 판 동안의 플레이어 상태 (생존/관전)
│   ├── Arena.luau             배치·텔레포트·탈락 감지
│   ├── WallController.luau    파괴의 벽 이동/파괴
│   ├── ImageAssets.luau       이미지 문제의 사진과 그 이름 ★ 대응표 = 정답표. 서버 전용 ★
│   ├── QuestionBank.luau      문제 내용(생성기) ★ 정답이 있으므로 서버 전용 ★
│   ├── QuestionService.luau   문제 추첨 · 정답 구역 배정 · 페이로드 생성
│   ├── QuestionDisplay.luau   바닥 SurfaceGui · 공중 보드
│   ├── RoundService.luau      라운드 상태머신
│   └── CurveAudit.luau        난이도 커브 부팅 검산 ★ 수치는 없다. Config 를 읽을 뿐 ★
└── client/     → StarterPlayer.StarterPlayerScripts.Client
    ├── Bootstrap.client.luau  클라이언트 진입점
    ├── Hud.luau               상태·문제 지시문·타이머·알림 (상단 밴드)
    ├── WallEffects.luau       벽 파괴 폭발 ★ 로컬 전용. 아무것도 밀지 않는다 ★
    └── ImagePreload.luau      문제 이미지 미리 내려받기
```

## 시스템 문서

코드를 수정하기 전에 해당 시스템의 문서를 먼저 읽을 것.

| 문서 | 내용 |
|---|---|
| [docs/map-builder.md](docs/map-builder.md) | 맵 시스템 (Phase 1) — 좌표계, 배치물 목록, **꾸미는 방법**, 설계 근거, 불변 조건 |
| [docs/round-loop.md](docs/round-loop.md) | 라운드 루프 (Phase 2) — 상태머신, 생존 판정, 벽 이동 함정 |
| [docs/question-system.md](docs/question-system.md) | 문제 시스템 (Phase 3) — 정답 보안 경계, 문제 추가법, **바닥 스크린 캔버스 규약** |
| [docs/difficulty-curve.md](docs/difficulty-curve.md) | 난이도 커브 (Phase 4) — 세 축, **여유시간**, CurveAudit 읽는 법, 수치를 바꿀 때의 경계 |

## 맵 좌표계

`MapLayout.luau`가 `Config.Map`에서 모든 좌표를 계산한다. 자세한 내용은
[docs/map-builder.md](docs/map-builder.md) 참고. 요약하면:

* **X축** — 레인 폭 방향. **A레인이 +X, B레인이 -X**이며 X=0에서 맞붙는다.
  Roblox에서 +Z를 바라보면 왼쪽이 +X이므로, 플레이어가 벽을 볼 때 **A가 왼쪽, B가 오른쪽**이다.
  이 대응은 `MapLayout.LeftZone` 한 곳에서만 정한다 — 배치와 판정이 어긋나면 정답 구역에서 탈락한다.
* **Z축** — 레인 길이 방향이자 벽의 진행 방향. 벽은 **+Z에서 출발해 -Z로 돌진**하고,
  오답 구역 플레이어를 -Z 끝단 밖으로 밀어낸다. **-Z 끝은 절대 막지 않는다.**
* **Y축** — 높이. `Config.Map.FloorY`는 메인 바닥의 *윗면* 높이다(중심이 아님).

기본 수치 기준 경기장은 80 × 220 studs, 벽 이동거리 228 studs(1라운드 약 4.15초)다.

## 맵 꾸미기

맵은 **씬(`Workspace.Map`)에 미리 배치돼 있다.** Studio 에서 그냥 편집하고 Ctrl+S 하면 된다.
지켜야 할 세 가지와 `Config.Map` 변경 후 재정렬(`MapBuilder.align()`) 절차는
[docs/map-builder.md §8](docs/map-builder.md) 참고.

* 골격 파트의 **태그와 `LayoutKey` 어트리뷰트를 지우지 마라.** 부팅 시 `MapService` 가 잡아내 서버를 세운다.
* 장식은 **`Workspace.Map` 안에** 넣어라. 벽 장식은 **벽 파트의 자식으로** 넣어야 벽과 함께 움직인다.
* ⚠ `MapBuilder.build()` 는 **꾸며 둔 것을 전부 지우고** 골격을 새로 만든다. 리셋할 때만 쓸 것.

## 라운드 루프

`RoundService`가 게임의 시간 축을 혼자 소유한다. 자세한 내용은
[docs/round-loop.md](docs/round-loop.md) 참고. 요약하면:

```
Lobby → Countdown → WallRush → Judge → Intermission → (반복) → GameOver → Lobby
```

* **생존 판정은 위치 스냅샷이 아니라 물리 결과다.** 오답 구역 벽에 밀려 맵 밖으로 떨어진
  사람이 탈락자이며, 벽이 오는 동안 옆 레인으로 다이브해도 살 수 있다.
* **정답 구역은 문제가 정한다.** `QuestionService.next(round).answer` 가 곧 정답 구역이다.

## 문제 시스템

선택지는 **A/B 구역의 바닥 자체**가, 문제 본문과 본문 사진은 **공중 보드**가 보여준다.
HUD는 지시문과 타이머만 맡는다.
자세한 내용은 [docs/question-system.md](docs/question-system.md) 참고. 요약하면:

* **정답은 서버 밖으로 나가지 않는다.** 문제 DB(`QuestionBank`)와 이미지 대응표
  (`ImageAssets`)가 서버 전용이고, 클라이언트가 받는 건 `QuestionService.payloadOf()`가
  만든 페이로드뿐이다(`answer` 없음).
* **정답 구역(A/B)은 출제 시점에 무작위로 정해진다.** DB에는 '정답 보기/오답 보기'만 있다.
* **매체는 두 축이다.** 문제 본문(`promptKind`)과 선택지(`choiceKind`)가 각각 글자/사진이라,
  "사진 보고 이름 고르기"와 "이름 보고 사진 고르기"를 모두 표현한다.
* ⚠ **바닥 SurfaceGui의 캔버스 축은 직관과 다르다.** 가로가 레인 '길이' 방향이라 라벨을
  `-90°` 돌려야 바로 선다. 실측값이니 추측으로 바꾸지 말 것
  ([docs/question-system.md §5](docs/question-system.md)).
* ⚠ **이미지 에셋 ID↔이름 대응표는 절대 `Shared`로 옮기지 마라.** 바닥 사진을 이름으로
  역변환해 문제를 읽지 않고 정답을 찾을 수 있다. 클라이언트에는 이름표 없는 ID 배열만 나간다.

## 난이도 커브

라운드가 올라갈 때 조여지는 축은 셋이다 — **제한시간 · 문제 난이도 · 벽 속도.** 앞의 둘은
R8~R9에서 바닥(2초 / 난이도 5)에 닿으므로 **후반을 만드는 축은 벽 속도 하나뿐이다.**
자세한 내용은 [docs/difficulty-curve.md](docs/difficulty-curve.md) 참고. 요약하면:

* **진짜 지표는 제한시간이 아니라 '여유시간'이다.** 제한시간이 끝나도 벽이 도착할
  때까지는 계속 건너갈 수 있으므로, 실제로 문제를 읽고 판단할 시간은
  `제한시간 + 벽 도달 시간 − 레인 횡단 시간` 이다. 기본 커브 기준 R1 5.9초 → R20 0.9초.
* **`CurveAudit` 이 부팅 때 검산한다.** 여유시간이 하한 아래로 떨어지는 라운드, 커브가
  멈춰 버린 구간, 문제가 없는 난이도, 정답 구역인데 밀려 탈락하는 조합을 경고한다.
* ⚠ **커브 수치는 `Config` 에만 있다.** `CurveAudit` 에 숫자가 보이면 그게 버그다.
* ⚠ **여유시간 계산에 대시(Phase 5)를 넣지 마라.** 쿨타임이 도는 라운드에서 아무도 못 건넌다.

## 벽 파괴 연출

정답 구역 벽이 부서지는 순간 **각 클라이언트가 로컬로** 폭발을 만든다
(`WallEffects`). 서버는 `WallBroken` 으로 "언제, 어디서"만 알린다.
자세한 내용은 [docs/round-loop.md §5-1](docs/round-loop.md) 참고.

* ⚠ **연출은 절대 무언가를 밀면 안 된다.** 서버가 폭발·파편을 실물로 뿌리면 정답 구역에
  서 있던 사람이 밀려 탈락한다. `Explosion` 인스턴스도 쓰지 않고, 연출 파트는
  `CanCollide`/`CanQuery`/`CanTouch` 를 전부 끈다.
* ⚠ **파괴 예고(직전 깜빡임)를 넣지 마라.** 파괴는 `WallRush` 도중에 일어나고 그때도
  다이브가 가능하므로, 예고는 곧 '마지막 기회'를 통째로 앞당겨 주는 것이다.

## 코딩 규약

1. **모든 밸런싱 수치는 `Config.luau`에만 존재한다.** 다른 파일에 하드코딩된 상수가 보이면 버그다.
2. **서버 권위(Server Authority).** 정답 값은 클라이언트로 전송하지 않고, 쿨타임·사용 횟수·거리 판정은 전부 서버가 한다.
3. **맵 오브젝트는 이름이 아닌 태그로 찾는다.** (`Tags.luau`)
4. **맵은 씬에 미리 배치돼 있고, 런타임은 그것을 검증해서 쓴다.** 코드로 생성하지 않는다.
   골격은 `MapBuilder`(에디터 전용)로 언제든 재생성 가능하지만, **손으로 얹은 장식은 place 에만 존재한다.**
   `.rbxl`은 여전히 git에 추적하지 않으므로 장식이 쌓이면 백업 수단을 둘 것
   ([docs/map-builder.md §10](docs/map-builder.md)).

## 구현 로드맵

| Phase | 내용 | 상태 |
|---|---|---|
| 0 | 프로젝트 골격 · 규약 · Config | ✅ |
| 1 | 맵 (레인/벽/관전장/킬플레인) — 씬에 정적 배치 + 부팅 검증 | ✅ |
| 2 | 라운드 상태머신 · 생존 판정 · 관전 전환 | ✅ |
| 3 | 문제 시스템 · 바닥 SurfaceGui · HUD | ✅ |
| 4 | 난이도 커브 · 벽 파괴 연출 | ✅ |
| 5 | 대시 · 밀치기 | ⬜ |
| 6 | DataStore · 코인 경제 · 상점 | ⬜ |
| 7 | 부활권 (MarketplaceService) | ⬜ |
| 8 | 이미지형 문제 · 사운드 · QA | ⬜ |

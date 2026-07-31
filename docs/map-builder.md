# 맵 빌더 시스템 (Phase 1)

> 이 문서는 **코드를 읽기 전에 읽는 문서**다.
> `MapBuilder.luau` / `MapLayout.luau` 를 수정하거나, Phase 2 이후 맵 오브젝트를
> 참조하는 로직을 짤 때 필요한 배경·규약·함정을 담았다.

---

## 1. 세 줄 요약

1. 맵은 `.rbxl` 에 저장하지 않는다. 서버 부팅 때 **코드로 매번 생성**한다.
2. **숫자는 `Config.Map` 에만**, **좌표 계산은 `MapLayout` 에만**, **인스턴스 생성은 `MapBuilder` 에만** 있다.
3. 만들어진 오브젝트는 **이름이 아니라 `Tags.luau` 의 태그로 찾는다.**

---

## 2. 왜 코드로 맵을 만드는가

README 규약 4번의 이유를 풀어 쓰면:

- **밸런싱 반복이 빠르다.** 레인을 220 → 300 studs 로 늘리려면 `Config.Map.LaneLength` 한 줄만 고치면
  바닥·벽 출발점·측면 벽·관전장·킬플레인이 전부 따라 움직인다. Studio 에서 파트를 끌었다면 7군데를 고쳐야 한다.
- **`.rbxl` 을 git 에 넣지 않아도 된다.** 바이너리 place 파일은 diff·머지가 불가능하다.
- **맵이 언제나 재현 가능하다.** Studio 에서 실수로 파트를 지워도 다음 실행 때 원상복구된다.

대가: Studio 뷰포트에서 **Edit 모드에는 맵이 보이지 않는다.** 플레이를 눌러야 나타난다.
(Edit 모드에서 눈으로 보고 싶을 때는 §8 의 절차를 따를 것 — 그냥 `build()` 를 부르면 안 된다.)

---

## 3. 좌표계 — 가장 먼저 외울 것

```
                          +Z  (벽 출발 방향)
                           ▲
         ┌─────────┬─────────┐   Z = +118   벽 뒷면
         │  WallA  │  WallB  │              각 40 × 40 × 8
         ├─────────┼─────────┤   Z = +110   바닥 +Z 끝 (벽이 딱 밀착)
         │         │         │
         │  Zone A │  Zone B │
    ║    │  (파랑) │  (주황) │    ║          ZoneFloor 각 40 × 2 × 220
    ║    │         │         │    ║          ║ = SideBarrier (X = ±42)
-X ◄╫────┤         │         ├────╫─► +X
    ║    │ ┌─────┐ │ ┌─────┐ │    ║   Z = -40
    ║    │ │Spawn│ │ │Spawn│ │    ║          스폰밴드 깊이 50
    ║    │ └─────┘ │ └─────┘ │    ║   Z = -90
    ║    │         │         │    ║
         └─────────┴─────────┘   Z = -110   바닥 -Z 끝 ★ 열려 있음 ★
      X=-40      X=0      X=+40
                           ▼
                          -Z  (벽 도착 / 탈락자가 밀려나는 방향)
```

**단면 (Y축)**

```
  Y = +92  ┌┐                        ┌┐   난간 윗면 (SpectatorRail, 높이 12)
  Y = +80  ├┴────────────────────────┴┤   SpectatorFloor 윗면 (유리, 120 × 260)
  Y = +78  └──────────────────────────┘   SpectatorFloor 아랫면
                      ┊
                      ┊  SpectatorHeight = 80
                      ┊
  Y = +40   ┌───────┐                     Wall / SideBarrier 윗면
            │ Wall  │
  Y =   0  ─┴───────┴───────────────────  ★ FloorY = 바닥의 '윗면' ★
  Y =  -2  ────────────────────────────   바닥 아랫면 (FloorThickness = 2)
                      ┊
  Y = -60  ────────────────────────────   KillPlane (480 × 620, 충돌 없음)
```

### 규약 3줄

| 축 | 의미 | 규칙 |
|---|---|---|
| **X** | 레인 폭 방향 | **A레인이 -X, B레인이 +X.** `LaneGap = 0` 이라 X=0 에서 맞붙는다. |
| **Z** | 레인 길이 = **벽의 진행 방향** | 벽은 **+Z 에서 출발해 -Z 로 돌진**한다. 오답 구역 플레이어는 -Z 밖으로 밀려난다. |
| **Y** | 높이 | `Config.Map.FloorY` 는 바닥의 **윗면**이다. 중심이 아니다. |

> ### ⚠ -Z 끝은 절대 막지 마라
> 벽이 플레이어를 밀어내 탈락시키는 **유일한 출구**다. 여기에 벽·난간·경계를 세우면
> 게임의 코어 루프(생존 판정) 자체가 동작하지 않는다.
> `MapLayout.sideBarriers()` 가 ±X 두 장만 만들고 ±Z 를 만들지 않는 이유가 이것이다.

### 왜 두 벽이 같은 방향으로 가는가

기획서 원문은 "양 끝단에서 파괴의 벽이 돌진"이다. 이를 *벽 두 개가 서로 반대편에서 출발*하는
것으로 읽을 수도 있었으나, **둘 다 +Z 에서 출발**하도록 구현했다.

이유: 레인을 갈아탈 때마다 위험이 오는 방향이 뒤집히면 플레이어가 순간적으로 방향을 다시
읽어야 한다. 제한시간이 2초까지 줄어드는 하이퍼캐주얼 게임에서 이 인지 부하는 치명적이다.
위험 방향을 항상 "저 앞쪽(+Z)"으로 고정하면 플레이어는 **좌우 판단에만 집중**하면 된다.

바꾸고 싶다면 `MapLayout.wallStartCFrame` / `wallEndCFrame` 만 고치면 된다.
`MapBuilder` 와 Phase 2 의 벽 이동 로직은 이 함수만 보므로 나머지는 건드릴 필요가 없다.

---

## 4. 모듈 책임 분리

```
Config.luau          "숫자는 몇인가"      LaneLength = 220, WallHeight = 40, 색상 …
      │  (파생)
      ▼
MapLayout.luau       "어디에 얼마만큼"    floorCFrame("A") → CFrame(-20, -1, 0)
      │  (조회)                          WallTravelDistance → 228
      ▼
MapBuilder.luau      "실제로 만든다"      Instance.new("Part") + 태그 부착
      │
      ▼
Bootstrap.server     부팅 시 build() 1회 호출
```

### 이 분리를 지켜야 하는 이유

`MapLayout` 이 따로 있는 건 **Phase 2 때문**이다. 벽을 움직이는 로직은
"벽이 어디서 출발해서 어디까지 가는가"를 알아야 하는데, 그 값을 `MapBuilder` 안에
가둬 두면 Phase 2 가 좌표를 다시 계산하게 되고 → 두 곳의 숫자가 어긋나는 순간 버그가 된다.

그래서 `MapLayout` 에는 **Phase 2가 쓸 것을 미리 넣어 뒀다**:

| 함수 / 값 | Phase 2 에서의 용도 |
|---|---|
| `wallCFrameAtProgress(zone, alpha)` | 벽 이동 보간. `alpha` 0→1 로 돌리면 끝 |
| `WallTravelDistance` (= 228) | `÷ Config.getWallSpeed(round)` 로 라운드 소요시간 산출 |
| `wallStartCFrame(zone)` | 라운드 시작 시 벽 원위치 |
| `spawnZoneCFrame(zone)` / `SpawnZoneSize` | 플레이어 텔레포트 배치 범위 |
| `SpectatorY` | 탈락자 관전석 텔레포트 높이 |

**규칙: 좌표를 계산하고 싶어지면 `MapLayout` 에 함수를 추가하라. 호출부에서 산술하지 마라.**

### `MapLayout` 의 require 방식이 다른 이유

```lua
-- MapLayout.luau (ReplicatedStorage.Shared 내부)
local Config = require(script.Parent.Config)      -- ← script.Parent

-- MapBuilder.luau (ServerScriptService.Server — 컨테이너가 다름)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
```

같은 폴더 안에서는 `script.Parent` 를 쓴다. 타입 분석기가 경로를 따라갈 수 있어
`export type Zone = Types.Zone` 같은 타입 재수출이 살아있기 때문이다.
`WaitForChild` 는 반환 타입이 `Instance` 라 require 결과가 `any` 로 무너진다.
컨테이너를 넘나들 때만 `WaitForChild` 를 쓴다.

---

## 5. 생성물 전체 목록

`MapBuilder.build()` → `Workspace.Map` 폴더. **파트 17개 + SpawnLocation 1개.**

| 폴더 | 파트 | 크기 (X,Y,Z) | 중심 위치 | 태그 | 충돌 |
|---|---|---|---|---|---|
| Lanes | `ZoneFloorA` | 40, 2, 220 | -20, -1, 0 | `BO_ZoneA`, `BO_AnswerScreen` | ✔ |
| Lanes | `ZoneFloorB` | 40, 2, 220 | +20, -1, 0 | `BO_ZoneB`, `BO_AnswerScreen` | ✔ |
| Lanes | `SpawnZoneA` | 40, 8, 50 | -20, 4, -65 | `BO_SpawnZone` | ✘ |
| Lanes | `SpawnZoneB` | 40, 8, 50 | +20, 4, -65 | `BO_SpawnZone` | ✘ |
| Walls | `WallA` | 40, 40, 8 | -20, 20, **+114** | `BO_WallA` | ✔ |
| Walls | `WallB` | 40, 40, 8 | +20, 20, **+114** | `BO_WallB` | ✔ |
| Spectator | `SpectatorFloor` | 120, 2, 260 | 0, 79, 0 | `BO_SpectatorFloor` | ✔ |
| Spectator | `SpectatorRail1‥4` | 난간 4면 | Y 80‥92 | — | ✔ |
| Bounds | `SideBarrier1` | 4, 40, 220 | -42, 20, 0 | — | ✔ |
| Bounds | `SideBarrier2` | 4, 40, 220 | +42, 20, 0 | — | ✔ |
| Bounds | `KillPlane` | 480, 2, 620 | 0, -60, 0 | `BO_KillPlane` | ✘ |
| Spectator | `LobbySpawn` | SpawnLocation 40×1×40 | 0, 80.5, -65 | `BO_LobbySpawn` | ✘ |

### `Zone` 어트리뷰트

존에 속한 파트(`ZoneFloor*`, `SpawnZone*`, `Wall*`)에는 **`Zone` 어트리뷰트에 `"A"` / `"B"`** 가 들어있다.
태그로 여러 개를 한 번에 긁은 뒤 어느 존인지 구분할 때 쓴다.

```lua
for _, wall in CollectionService:GetTagged(Tags.WallA) do
    local zone = wall:GetAttribute("Zone")  -- "A"
end
```

`BO_WallA` / `BO_WallB` 처럼 태그가 이미 존별로 나뉜 경우엔 어트리뷰트가 중복이지만,
`BO_SpawnZone` / `BO_AnswerScreen` 처럼 **한 태그에 두 존이 걸리는 경우**에는 이게 유일한 구분 수단이다.

### 태그 현황

`Tags.luau` 의 10개 중 **9개가 부착돼 있다.** `BO_QuestionBoard` 만 0개인데,
`Tags.luau` 주석에 "(선택)"으로 표시된 **Phase 3 항목**이라 의도적으로 만들지 않았다.
태그 스캔 결과가 9/10 인 것은 정상이며 버그가 아니다.

---

## 6. 설계 결정과 근거

### 바닥 파트가 곧 선택지 디스플레이다

기획서 3장: "A구역과 B구역의 **바닥 자체**가 거대한 디스플레이가 되어 선택지를 출력".
그래서 `ZoneFloorA/B` 에 `BO_ZoneA/B` 와 `BO_AnswerScreen` **두 개를 같이 붙였다.**
Phase 3 은 별도 파트를 만들지 말고 이 파트의 `Top` 면에 `SurfaceGui` 를 붙이면 된다.

바닥 위에 얇은 스크린 파트를 따로 얹지 않은 이유: 파트가 겹치면 Z-fighting 이 나고,
플레이어 충돌 판정에 미세한 턱이 생긴다.

### 측면 벽 (`SideBarrier`) — 기획서에 없지만 넣은 것

레인 좌우로 **실수로** 떨어져 탈락하는 것을 막는다. 이 게임에서 탈락은 오직 오답 선택의
결과여야 하며, 조작 미스로 옆으로 굴러떨어지는 건 플레이어가 납득하지 못하는 죽음이다.

- 완전 투명(`Transparency = 1`)이라 시야를 가리지 않는다. **디버그 모드에서만 0.9 로 살짝 보인다.**
- ±X 두 장뿐. **-Z 출구는 열어 둔다** (§3 경고 참조).

### 관전장 난간 (`SpectatorRail`)

같은 이유. 탈락해서 관전석에 올라간 유저가 실수로 떨어지면 이탈로 직결된다.
기획 의도가 "탈락자 이탈률 방어"이므로 관전석은 안전해야 한다.
난간 4면은 모서리에 틈이 없도록 ±X 난간이 Z 방향으로 더 길게(268) 뻗어 코너를 덮는다.

### `LobbySpawn` 이 관전장 위에 있는 이유

맵 전체에서 `SpawnLocation` 은 이것 하나뿐이고, 경기장이 아니라 **관전장 유리 바닥 위**에 있다.
(Phase 1 의 레인별 `TempSpawns` 는 Phase 2 에서 이것으로 교체됐다.)

접속·리스폰의 기본 위치를 관전장으로 두면 **진행 중인 라운드에 난입할 수 없다.** 중간 접속자는
자연스럽게 구경하다가 다음 게임의 참가자 명단에 들어간다. 경기장 안에 스폰을 두면 라운드
도중 벽 뒤에 사람이 튀어나오는 상황을 매번 걸러내야 한다.

라운드 중의 실제 배치는 `SpawnLocation` 이 아니라 `RoundService` 가 텔레포트로 한다
(`MapLayout.spawnPointCFrame`). `Duration = 0` 이라 포스필드는 생기지 않는다.

### `Config.Theme` 가 따로 있는 이유

README 규약 1은 "밸런싱 수치는 Config 에만"이다. 색상·재질·투명도는 밸런싱이 아니지만
**하드코딩 상수인 것은 똑같다.** `MapBuilder` 안에 색을 박아두면 리스킨할 때 로직 파일을
열어야 한다. 그래서 `Config.Theme` 으로 분리했다.
**밸런싱 값과 섞지 마라** — `Config.Map` 은 게임성, `Config.Theme` 은 외형이다.

---

## 7. 불변 조건 (깨면 게임이 망가진다)

1. **-Z 끝단(Z = -110)에 충돌체를 두지 않는다.** 탈락 경로다.
2. **`Config.Map.FloorY` 는 윗면이다.** 파트 중심은 `FloorY - FloorThickness/2`.
   좌표 버그의 1순위 원인. 새 계산을 넣을 때 반드시 확인하라.
3. **벽은 바닥 끝에 밀착해 출발한다.** `WallStartZ = LaneLength/2 + WallThickness/2`.
   이 값이 커지면 벽과 바닥 사이에 틈이 생겨 +Z 로 도망칠 수 있다.
4. **`MapBuilder.build()` 는 멱등이어야 한다.** 새 오브젝트를 추가할 때 반드시
   `Workspace.Map` 하위에 넣어라. 밖에 두면 `clear()` 가 못 지워서 재호출 시 중복된다.
5. **맵 오브젝트는 태그로만 찾는다.** `workspace.Map.Walls.WallA` 같은 경로 참조 금지.
   폴더 구조를 바꾸는 순간 조용히 깨진다.
6. **`Instance.new` 후 속성을 다 설정한 뒤 마지막에 `Parent` 를 지정한다.**
   `createPart` 가 이미 그렇게 돼 있다. 순서를 바꾸면 리플리케이션 비용이 늘어난다.

---

## 8. ⚠ Edit 모드에서 `build()` 를 직접 부르지 마라

`MapBuilder.build()` 는 내부에서 `removeDefaultBaseplate()` 를 호출해
`Workspace.Baseplate` 를 **`Destroy()`** 한다. 기본 템플릿 Baseplate 가 Y=0 에서
우리 바닥과 겹치기 때문이다.

- **Play 모드**에서는 안전하다. 런타임 변경은 place 파일에 저장되지 않는다.
- **Edit 모드**에서 부르면 **저장 파일의 Baseplate 가 실제로 삭제된다.**

Edit 모드에서 맵을 눈으로 봐야 한다면 Baseplate 를 잠시 피신시켰다가 되돌린다:

```lua
-- 1) 세우기
local ServerStorage = game:GetService("ServerStorage")
local baseplate = workspace:FindFirstChild("Baseplate")
if baseplate then baseplate.Parent = ServerStorage end
require(game.ServerScriptService.Server.MapBuilder).build()

-- 2) 되돌리기
require(game.ServerScriptService.Server.MapBuilder).clear()
local bp = ServerStorage:FindFirstChild("Baseplate")
if bp then bp.Parent = workspace end
```

> 참고: `ServerStorage.__Rojo_SessionLock` 은 Rojo 가 만든 것이다. 지우지 마라.

---

## 9. 검증 방법

### 부팅 로그

Play 를 누르면 다음이 찍혀야 한다. 숫자가 다르면 `Config.Map` 이 바뀐 것이다.

```
[MapBuilder] 맵 생성 완료 | 80x220 studs | 벽 이동거리 228 studs (1R 4.15s)
```

### 태그 전수 점검 (Server datamodel)

```lua
local CollectionService = game:GetService("CollectionService")
local Tags = require(game.ReplicatedStorage.Shared.Tags)
for key, tag in Tags do
    print(key, tag, #CollectionService:GetTagged(tag))
end
-- BO_QuestionBoard 만 0, 나머지 8개는 1 이상이어야 정상
```

### 기하 점검

```lua
for _, p in workspace.Map:GetDescendants() do
    if p:IsA("BasePart") then
        print(p.Name, p.Size, p.Position)
    end
end
```

§5 의 표와 대조한다.

### 확인된 기준값

| 항목 | 값 |
|---|---|
| 경기장 | 80 × 220 studs |
| 벽 이동거리 | 228 studs |
| 1라운드 벽 소요시간 | 4.15초 (55 studs/s) |
| 최대속도 시 소요시간 | 1.34초 (170 studs/s) |
| 정답 벽 파괴 지점 | z = +34.2 (진행률 0.35) |
| 로비 스폰 실측 | `(0, 80.5, -65)` — 관전장 유리 바닥 위 |

---

## 10. Phase 2 연동 현황 (완료)

맵 쪽에서 해야 했던 일은 전부 끝났다. 구현 내용은 [round-loop.md](round-loop.md) 참고.

- [x] `buildTemporarySpawns` 제거 → `LobbySpawn` 하나로 교체, 배치는 `RoundService` 가 텔레포트로 수행
- [x] `BO_WallA/B` 를 태그로 찾아 `wallCFrameAtProgress(zone, alpha)` 로 이동 (`WallController`)
- [x] 라운드 시작 시 `wallStartCFrame(zone)` 으로 원위치 (`WallController.reset`)
- [x] `BO_KillPlane` 에 `Touched` 연결 → 탈락 처리 (`Arena`, Y 폴링 백스톱 포함)
- [x] 탈락자를 `MapLayout.SpectatorY` 위로 텔레포트 (`Arena.sendToSpectator`)
- [x] 정답 구역 벽은 `Config.Round.CorrectWallBreakProgress` 지점에서 파괴 (연출은 Phase 4)

Phase 2 가 `MapLayout` 에 추가한 함수(다음 Phase 도 이걸 쓸 것):

| 함수 | 용도 |
|---|---|
| `spawnPointCFrame(zone, rng)` | 스폰밴드 안 무작위 배치 지점 (+Z 를 바라봄) |
| `spectatorPointCFrame(rng)` | 관전장 무작위 배치 지점 |
| `lobbySpawnCFrame()` / `LobbySpawnSize` | 로비 `SpawnLocation` |
| `zoneAtPosition(position)` | 이 위치가 어느 레인인가 (경기장 밖이면 `nil`) |
| `oppositeZone(zone)` | 오답 구역 |
| `wallFrontZ(wallCenterZ)` | 벽 선단면 Z — 관통 판정용 |

`MapLayout` 에 이미 있는 것을 다시 계산하지 말 것. §4 의 표를 먼저 확인하라.

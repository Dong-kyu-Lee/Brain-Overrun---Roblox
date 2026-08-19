# 맵 시스템 (Phase 1 · 정적 배치로 개정)

> 이 문서는 **코드를 읽기 전에 읽는 문서**다.
> `MapBuilder.luau` / `MapService.luau` / `MapLayout.luau` 를 수정하거나, 맵 오브젝트를
> 참조하는 로직을 짤 때 필요한 배경·규약·함정을 담았다.

---

## 1. 세 줄 요약

1. 맵은 **place(씬)에 미리 배치돼 있다.** 런타임은 만들지 않고 `MapService` 로 **찾아서 검증**만 한다.
2. **숫자는 `Config.Map` 에만**, **좌표 계산은 `MapLayout` 에만**, **인스턴스 생성은 `MapBuilder` 에만** 있다.
   `MapBuilder` 는 **에디터 전용 도구**이며 런타임에서 호출하면 에러가 난다.
3. 맵 오브젝트는 **이름이 아니라 `Tags.luau` 의 태그로 찾는다.**

---

## 2. 왜 씬에 미리 배치하는가

원래는 부팅 때마다 코드로 맵을 만들었다. 그 방식은 **맵을 손으로 꾸밀 수 없다** —
Studio 에서 얹은 장식이 다음 실행 때 통째로 사라지기 때문이다. 맵 외형이 게임의
첫인상을 좌우하는 이상, 눈으로 보면서 꾸미는 편익이 재생성의 편익보다 크다고 판단했다.

**얻은 것**

- Edit 모드에서 맵이 그냥 보인다. 파트를 끌고, 재질을 바꾸고, 소품을 얹으면 그대로 남는다.
- 부팅이 하는 일이 줄었다.

**잃은 것과 그 대책**

| 잃은 것 | 대책 |
|---|---|
| `Config.Map` 을 고쳐도 씬의 파트가 따라오지 않는다 | `MapBuilder.align()` — 장식은 두고 골격만 재정렬 (§8) |
| 손으로 꾸미다 태그를 지우거나 바닥을 옮겨도 조용히 깨진다 | `MapService.ensureReady()` 가 부팅 때 전수 점검, 치명이면 서버를 세운다 (§9) |
| place 가 바이너리라 맵 변경이 git diff 에 안 남는다 | 골격은 `MapBuilder.build()` 로 언제든 재생성 가능. 장식은 place 에만 존재한다 (§10) |

> ### ⚠ 맵을 고쳤으면 Ctrl+S
> Studio 편집은 저장해야 남는다. `build()` / `align()` 실행 후에도 마찬가지다.

---

## 3. 좌표계 — 가장 먼저 외울 것

```
                          +Z  (벽 출발 방향 — 플레이어가 바라보는 쪽)
                           ▲
         ┌─────────┬─────────┐   Z = +118   벽 뒷면
         │  WallA  │  WallB  │              각 40 × 40 × 8
         ├─────────┼─────────┤   Z = +110   바닥 +Z 끝 (벽이 딱 밀착)
         │         │         │
         │  Zone A │  Zone B │
    ║    │  (파랑) │  (주황) │    ║          ZoneFloor 각 40 × 2 × 220
    ║    │         │         │    ║          ║ = SideBarrier (X = ±42)
+X ◄╫────┤         │         ├────╫─► -X
    ║    │ ┌─────┐ │ ┌─────┐ │    ║   Z = -40
    ║    │ │Spawn│ │ │Spawn│ │    ║          스폰밴드 깊이 50
    ║    │ └─────┘ │ └─────┘ │    ║   Z = -90
    ║    │         │         │    ║
         └─────────┴─────────┘   Z = -110   바닥 -Z 끝 ★ 열려 있음 ★
      X=+40      X=0      X=-40
                           ▼
                          -Z  (벽 도착 / 탈락자가 밀려나는 방향)
```

> ★ **이 그림은 플레이어 시점이다** — 스폰(-Z)에 서서 벽이 오는 +Z 를 바라본 좌우.
> 그래서 X축이 그림 왼쪽으로 증가한다. Roblox 에서 `+Z` 를 바라보면 `RightVector` 가
> `-X` 라서 **+X 가 왼쪽에 보이기** 때문이다.
> Studio 의 위에서 내려다보는 뷰와는 좌우가 뒤집혀 보이니 주의할 것.

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
| **X** | 레인 폭 방향 | **A레인이 +X, B레인이 -X** = 플레이어가 벽을 바라볼 때 **A가 왼쪽, B가 오른쪽**. `LaneGap = 0` 이라 X=0 에서 맞붙는다. |
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
MapBuilder.luau      "골격을 만든다"      ★ 에디터 전용 ★ specs() / build() / align()
      │                                  런타임에서 부르면 assertEditMode 가 막는다
      ├──────────────► Workspace.Map      ← 여기서 손으로 꾸민다. place 에 저장된다.
      │                     │
      │  (specs 를 빌려)     │ (찾는다)
      ▼                     ▼
MapService.luau      "쓸 수 있는 맵인가"  ensureReady() → 태그·기하 전수 점검
      │
      ▼
Bootstrap.server     부팅 시 ensureReady() 1회 호출 (생성하지 않는다)
```

`MapService` 가 `MapBuilder` 를 `require` 하는 건 **`specs()` 하나 때문**이다. 검증에 쓸
"원래 크기·위치"를 다시 적어두면 두 곳의 숫자가 어긋나는 순간 검증이 거짓말을 하게 된다.
`require` 자체에는 부작용이 없고, `build()`/`align()` 은 에디터 가드에 막혀 런타임에서 실행되지 않는다.

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

## 5. 씬에 배치된 것 전체 목록

`Workspace.Map` (폴더, 태그 `BO_MapRoot`). **폴더 5개 + 파트 15개 + SpawnLocation 1개.**
실측으로 확인된 값이며, `MapService` 가 부팅 때 이 표와 같은 내용을 검증한다.

| 폴더 | 파트 | 크기 (X,Y,Z) | 중심 위치 | 태그 | 충돌 |
|---|---|---|---|---|---|
| Lanes | `ZoneFloorA` | 40, 2, 220 | **+20**, -1, 0 | `BO_ZoneA`, `BO_AnswerScreen` | ✔ |
| Lanes | `ZoneFloorB` | 40, 2, 220 | **-20**, -1, 0 | `BO_ZoneB`, `BO_AnswerScreen` | ✔ |
| Lanes | `SpawnZoneA` | 40, 8, 50 | **+20**, 4, -65 | `BO_SpawnZone` | ✘ |
| Lanes | `SpawnZoneB` | 40, 8, 50 | **-20**, 4, -65 | `BO_SpawnZone` | ✘ |
| Walls | `WallA` | 40, 40, 8 | **+20**, 20, **+114** | `BO_WallA` | ✔ |
| Walls | `WallB` | 40, 40, 8 | **-20**, 20, **+114** | `BO_WallB` | ✔ |
| Display | `QuestionBoard` | 80, 32, 2 | 0, **60**, **+127** | `BO_QuestionBoard` | ✘ |
| Spectator | `SpectatorFloor` | 120, 2, 260 | 0, 79, 0 | `BO_SpectatorFloor` | ✔ |
| Spectator | `SpectatorRail1‥4` | 난간 4면 | Y 80‥92 | — | ✔ |
| Spectator | `LobbySpawn` | SpawnLocation 40×1×40 | 0, 80.5, -65 | `BO_LobbySpawn` | ✘ |
| Bounds | `SideBarrier1` | 4, 40, 220 | -42, 20, 0 | `BO_SideBarrier` | ✔ |
| Bounds | `SideBarrier2` | 4, 40, 220 | +42, 20, 0 | `BO_SideBarrier` | ✔ |
| Bounds | `KillPlane` | 480, 2, 620 | 0, -60, 0 | `BO_KillPlane` | ✘ |

기본 템플릿의 `Baseplate` 는 **삭제했다.** Y=0 에서 우리 바닥과 겹칠 뿐 아니라,
-Z 로 밀려난 플레이어를 받아버려 탈락 자체를 막는다. 다시 만들지 말 것.

### `LayoutKey` 어트리뷰트 — 골격의 신분증

골격 파트에는 전부 `LayoutKey` 문자열 어트리뷰트가 있다 (`"ZoneFloorA"`, `"WallB"`, …).
`MapBuilder.align()` 이 이 값으로 짝을 찾고, `MapService` 가 이 값으로 기하 드리프트를 검사한다.

- **꾸미려고 얹은 장식에는 `LayoutKey` 를 붙이지 마라.** 붙는 순간 정렬·검증 대상이 되어
  `align()` 이 엉뚱한 자리로 끌고 간다.
- **골격 파트를 복제할 때는 `LayoutKey` 와 태그를 지워라.** 안 지우면 키가 중복돼
  `align()` 이 둘 중 하나만 맞추고, `MapService` 가 태그 개수 초과 경고를 낸다.

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

`Tags.luau` 의 12개가 **전부 부착돼 있다.**

`BO_QuestionBoard` 는 원래 "선택" 항목이었으나 **Phase 3 개정에서 골격으로 승격했다.**
문제 본문의 사진을 띄울 곳이 여기뿐이기 때문이다 — 보드가 없으면 `QuestionService` 가
사진 문제를 후보에서 통째로 뺀다(question-system.md §6). 없어도 서버는 뜨지만
`QuestionDisplay` 가 경고를 남기고 사진 문제가 나오지 않는다.

> ### ⚠ 이 문서보다 오래된 place 를 쓰고 있다면
> `QuestionBoard` 는 나중에 추가된 골격 파트라, 그 전에 저장한 place 에는 없다.
> `build()` 는 장식을 전부 지우므로 쓰면 안 된다. **`addMissing()`** 이 빠진 골격만
> 새로 만든다 (§8).

어느 면에 그릴지는 파트의 `Face` 어트리뷰트(`"Front"`, `"Back"`, …)로 정하며,
없으면 `Front` 를 쓴다. 기본 배치(Z = +127)에서는 `Front` 의 법선이 -Z, 즉 스폰 쪽을
향하므로 어트리뷰트를 붙일 필요가 없다.

---

## 6. 설계 결정과 근거

### 바닥 파트가 곧 선택지 디스플레이다

기획서 3장: "A구역과 B구역의 **바닥 자체**가 거대한 디스플레이가 되어 선택지를 출력".
그래서 `ZoneFloorA/B` 에 `BO_ZoneA/B` 와 `BO_AnswerScreen` **두 개를 같이 붙였다.**
Phase 3 의 `QuestionDisplay` 가 이 파트의 `Top` 면에 `SurfaceGui` 를 붙인다(별도 파트 없음).

바닥 위에 얇은 스크린 파트를 따로 얹지 않은 이유: 파트가 겹치면 Z-fighting 이 나고,
플레이어 충돌 판정에 미세한 턱이 생긴다.

> ⚠ `Top` 면 SurfaceGui 의 캔버스 축은 **직관과 다르다** — 가로가 레인 '길이' 방향이다.
> 바닥에 무언가를 그릴 일이 생기면 반드시 question-system.md §5 를 먼저 읽을 것.

### A가 왼쪽인 이유 — 그리고 좌우를 바꾸는 방법

플레이어가 벽을 바라볼 때 **A가 왼쪽, B가 오른쪽**이어야 한다. "A/B" 는 사람이 좌우로 읽는
선택지이고, 바닥에 A·B 선택지가 그려지는 이 게임에서 왼쪽이 B면 매 라운드 인지 부하가 생긴다.

좌표 부호로 외우면 반드시 틀린다. Roblox 에서 `+Z` 를 바라볼 때 `RightVector` 는 `-X` 이므로
**왼쪽이 `+X`** 다. 그래서 A레인이 `+X` 에 있다. 이 대응은 `MapLayout.LeftZone` 한 곳에만 있다:

```lua
MapLayout.LeftZone = "A" :: Zone   -- ← 좌우를 바꾸려면 이 한 줄만
```

`laneCenterX`(배치) 와 `zoneAtPosition`(판정) 이 **둘 다 이 값에서 파생**된다.
어느 한쪽에 `"A"`/`"B"` 를 직접 적으면, 배치는 바뀌었는데 판정만 옛 좌우로 남아
**정답 구역에 서 있는데 탈락하는** 최악의 버그가 된다. 절대 하드코딩하지 마라.

바꾼 뒤에는 씬의 파트도 옮겨야 한다 — `MapBuilder.align()` 실행 후 Ctrl+S (§8).

### 측면 벽 (`SideBarrier`) — 기획서에 없지만 넣은 것

레인 좌우로 **실수로** 떨어져 탈락하는 것을 막는다. 이 게임에서 탈락은 오직 오답 선택의
결과여야 하며, 조작 미스로 옆으로 굴러떨어지는 건 플레이어가 납득하지 못하는 죽음이다.

- 완전 투명(`Transparency = 1`)이라 시야를 가리지 않는다. **디버그 모드에서만 0.9 로 살짝 보인다.**
  씬에 어떤 투명도로 저장돼 있든 `MapService` 가 부팅 때 `Config.Debug.Enabled` 기준으로 덮어쓴다
  (`SpawnZone` 도 동일). **정적 맵이 Config 를 따라오는 몇 안 되는 지점이다.**
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
4. **골격 파트를 지우거나 태그를 떼지 않는다.** 부팅 시 `MapService` 가 잡아내 서버를 세운다.
   꾸미다가 실수했다면 `MapBuilder.align()` 이 아니라 태그·`LayoutKey` 를 직접 복구하라.
5. **맵 오브젝트는 태그로만 찾는다.** `workspace.Map.Walls.WallA` 같은 경로 참조 금지.
   폴더 구조를 바꾸는 순간 조용히 깨진다. **꾸미면서 폴더를 재배치해도 되는 이유가 이것이다.**
6. **장식은 반드시 `Workspace.Map` 안에 넣는다.** 밖에 두면 `MapService` 의 점검 범위를 벗어나고,
   `clear()` 가 못 지운다.
7. **벽(`WallA/B`)에 붙이는 장식은 벽 파트의 자식으로 넣는다.** `WallController` 가 벽을 옮길 때
   자식 파트를 같은 상대 위치로 함께 옮기고, 파괴될 때 함께 숨긴다. 벽 옆에 형제로 두면
   벽만 돌진하고 장식은 제자리에 남는다.
8. **공중 보드(`QuestionBoard`)는 `40 < 아랫변`, `윗변 < 78` 안에 둔다.**
   - 아랫변이 벽 높이(40) 아래로 내려가면 **라운드 시작 순간 벽에 가려** 문제가 안 보인다.
     두 레인의 벽을 합치면 맵 폭 전체(X = -40 ~ +40)를 덮으므로 "벽 사이로 보이겠지"는 틀렸다.
   - 윗변이 관전장 높이(80) 위로 올라가면 유리 바닥을 뚫는다.
   - 기본값은 아랫변 44 / 윗변 76 이며, 조정은 `Config.Map.QuestionBoardBottomY`·`Height` 로 한다.
     손으로 끌어 옮겨 이 범위를 벗어나면 `MapService` 가 부팅 때 경고를 낸다.

---

## 8. 맵을 꾸미는 방법

맵은 `Workspace.Map` 에 실물로 들어있다. **그냥 Studio 에서 편집하고 Ctrl+S 하면 된다.**
아래 세 가지만 지키면 로직이 깨지지 않는다.

1. 골격 파트의 **태그와 `LayoutKey` 를 지우지 않는다** (§5).
2. 장식은 **`Workspace.Map` 안에** 넣는다. 벽 장식은 **벽 파트의 자식으로** (§7-7).
3. **-Z 끝단(Z = -110)을 막지 않는다** (§3).
4. **레인 바닥 재질은 조용한 것으로** — 아래 「바닥 재질」 참고.

### 외형은 씬이 단일 소스다

**재질·색을 손으로 바꾸면 런타임에 그대로 유지된다.** 코드를 고칠 필요가 없다.
런타임이 파트 외형을 만지는 곳은 두 군데뿐이고 **둘 다 투명도만** 건드린다.

| 어디 | 무엇을 |
|---|---|
| `MapService.applyDebugVisibility` | `SpawnZone`·`SideBarrier` 투명도 (`Config.Debug` 기준, 매 부팅) |
| `WallController.setBroken` | 벽 파괴 시 투명도·충돌 — 단 **씬의 값을 스냅샷해 뒀다가 되돌린다**(`rememberLook`) |

즉 벽 투명도를 0.2 로 칠해 두면 파괴 후 복구도 0.2 로 돌아온다. 재질·색은 아무도 안 만진다.
판정 강조도 파트 색이 아니라 SurfaceGui 의 Tint 로 한다 — 손으로 꾸민 외형을 라운드마다
덮어쓰지 않으려고 그렇게 설계했다(question-system.md §5).

> `Config.Theme` 은 **`build()`/`addMissing()` 이 파트를 새로 만들 때의 기본값**이다.
> 이미 씬에 있는 파트에는 아무 영향이 없다 — `align()` 도 크기·위치만 맞추고 외형은 안 건드린다.
> 손으로 확정한 외형을 새 place 에서도 재현하고 싶으면, 그때 `Config.Theme` 을 같은 값으로
> 맞춰 두면 된다.

### 바닥 재질 — 여기만 제약이 있다

`ZoneFloorA/B` 의 `Top` 면이 곧 선택지 스크린이고, 선택지 라벨은 배경이 투명이라
**바닥 표면이 글자 뒤로 그대로 비친다.** 바닥 글자는 이미 시선각 약 8° 로 눕혀 보이므로
(question-system.md §5) 표면이 시끄러우면 2~5초 안에 못 읽는다.

- ✅ `Plastic`(클래식 로블록스 플라스틱) · `SmoothPlastic` · `Neon` — 조용한 표면
- ❌ `Concrete` · `Pebble` · `Slate` · `Grass` — 노이즈가 글자를 갉아먹는다
- ❌ **`TopSurface = Studs`(레고 돌기)** — 같은 이유. 돌기 격자가 선택지 뒤에 깔린다

레고 돌기를 원하면 **글자가 올라가지 않는 파트**에 주면 된다 — 벽(`WallA/B`), 관전장 난간,
측면 장식. 벽은 제약이 없으니 마음껏 바꿔도 된다.

### `Config.Map` 을 고친 뒤 — `align()`

정적 맵의 유일한 대가는 `Config` 변경이 자동으로 따라오지 않는다는 것이다.
`align()` 이 **장식은 그대로 두고** `LayoutKey` 가 붙은 골격만 재정렬한다.

```lua
-- Studio Edit 모드 명령 바
require(game.ServerScriptService.Server.MapBuilder).align()
-- → [MapBuilder] 정렬 완료 | N개 이동/리사이즈, 문제 0건 — Ctrl+S 로 저장할 것
```

⚠ 장식은 따라오지 않는다. 레인 길이를 바꿨다면 장식은 손으로 옮겨야 한다.

### 골격에 파트가 추가됐을 때 — `addMissing()`

`align()` 은 **이미 있는** 파트만 맞춘다. 골격 목록에 새 파트가 생기면(예: Phase 3 개정의
`QuestionBoard`) 만들어 주지 못하고 `누락:` 경고만 낸다. 그렇다고 `build()` 를 쓰면
꾸며 둔 장식이 전부 날아간다. 그 사이를 메우는 것이 `addMissing()` 이다.

```lua
require(game.ServerScriptService.Server.MapBuilder).addMissing()
-- → [MapBuilder] 골격 파트 1개 추가: QuestionBoard — Ctrl+S 로 저장할 것
```

**빠진 것만 새로 만들고, 기존 파트와 장식은 건드리지 않는다.** 이미 다 있으면
"빠진 골격 파트가 없다" 를 찍고 아무것도 하지 않으므로 여러 번 실행해도 안전하다.

### 처음부터 다시 만들기 — `build()`

```lua
require(game.ServerScriptService.Server.MapBuilder).build()
```

**`Workspace.Map` 을 통째로 지우고 새로 만든다. 꾸며 둔 장식도 전부 사라진다.**
쓸 일은 두 가지뿐이다: 맵이 아예 없는 place 를 처음 세팅할 때, 또는 골격을 포기하고 리셋할 때.
`Workspace.Baseplate` 도 함께 삭제된다(§5).

> `build()` / `align()` / `addMissing()` / `clear()` 는 **Edit 모드 전용**이다. 런타임에서
> 부르면 `assertEditMode` 가 에러를 낸다 — 실수로 게임 중 맵이 리셋되는 사고를 막기 위함이다.

> ### ⚠ Edit 모드에서 모듈이 옛날 코드로 실행될 때
> Studio 의 Edit 세션은 `require` 결과를 **인스턴스 단위로 캐시**한다. Rojo 가 소스를
> 갱신해도 이미 한 번 require 한 모듈은 옛 코드가 돈다. 사본을 만들면 새로 실행된다:
>
> ```lua
> local mb = game.ServerScriptService.Server.MapBuilder:Clone()
> mb.Parent = game:GetService("ServerStorage")
> require(mb).align()
> mb:Destroy()
> ```
>
> 가장 확실한 방법은 place 를 닫았다 다시 여는 것이다.

> 참고: `ServerStorage.__Rojo_SessionLock` 은 Rojo 가 만든 것이다. 지우지 마라.

---

## 9. 검증 방법

### 부팅 로그

Play 를 누르면 다음이 찍혀야 한다. 숫자가 다르면 `Config.Map` 이 바뀐 것이고,
**경고 건수가 0 이 아니면 맵이 Config 와 어긋난 것이다** — 출력창에서 어떤 파트인지 확인하라.

```
[MapService] 맵 확인 | 80x220 studs | 벽 이동거리 228 studs (1R 4.15s) | 경고 0건
```

맵이 없거나 필수 태그가 빠졌으면 **부팅이 에러로 멈춘다.** 이건 의도된 동작이다 —
반쯤 망가진 맵으로 게임을 돌리면 원인을 알 수 없는 판정 버그로 나타난다.

### 태그 전수 점검 (Server datamodel)

```lua
local CollectionService = game:GetService("CollectionService")
local Tags = require(game.ReplicatedStorage.Shared.Tags)
for key, tag in Tags do
    print(key, tag, #CollectionService:GetTagged(tag))
end
-- BO_QuestionBoard 만 0, 나머지 11개는 1 이상이어야 정상
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
| 최대속도 시 소요시간 | 1.11초 (205 studs/s) |
| 정답 벽 파괴 지점 | z = -34.0 (진행률 0.649 — 스폰밴드 앞 2 studs) |
| 로비 스폰 실측 | `(0, 80.5, -65)` — 관전장 유리 바닥 위 |

---

## 10. 맵과 버전 관리

**맵이 place 로 옮겨가면서 git 이 추적하는 범위가 줄었다.** 정확히 알고 있어야 한다.

| 대상 | 어디에 있나 | git 추적 |
|---|---|---|
| 골격의 **정의** (크기·위치·색) | `Config.Map` / `Config.Theme` / `MapLayout` / `MapBuilder.specs()` | ✔ |
| 골격의 **실물** | place 파일 (`Workspace.Map`) | ✘ — `build()` 로 재생성 가능 |
| **장식** | place 파일 (`Workspace.Map` 안) | ✘ — **재생성 불가. 여기서 사라지면 끝이다.** |

장식이 쌓이기 시작하면 백업 수단을 하나 두는 게 좋다. 둘 중 하나면 충분하다.

- **place 자체를 백업**한다 (Roblox 클라우드 저장 / 로컬 `.rbxl` 사본).
- `Workspace.Map` 을 선택 → **File → Export Selection** → `assets/Map.rbxmx` 로 저장하고 커밋한다.
  `.gitignore` 는 `*.rbxm` 만 무시하므로 `.rbxmx` 는 그대로 추적된다.

---

## 11. Phase 2 연동 현황 (완료)

맵 쪽에서 해야 했던 일은 전부 끝났다. 구현 내용은 [round-loop.md](round-loop.md) 참고.

- [x] `buildTemporarySpawns` 제거 → `LobbySpawn` 하나로 교체, 배치는 `RoundService` 가 텔레포트로 수행
- [x] `BO_WallA/B` 를 태그로 찾아 `wallCFrameAtProgress(zone, alpha)` 로 이동 (`WallController`)
- [x] 라운드 시작 시 `wallStartCFrame(zone)` 으로 원위치 (`WallController.reset`)
- [x] `BO_KillPlane` 에 `Touched` 연결 → 탈락 처리 (`Arena`, Y 폴링 백스톱 포함)
- [x] 탈락자를 `MapLayout.SpectatorY` 위로 텔레포트 (`Arena.sendToSpectator`)
- [x] 정답 구역 벽은 스폰밴드 코앞(`MapLayout.CorrectWallBreakProgress`)에서 파괴
      (폭발 연출은 [round-loop.md §5-1](round-loop.md) — 벽 파트 자체는 건드리지 않는다)

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

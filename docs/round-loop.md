# 라운드 루프 시스템 (Phase 2)

> 이 문서는 **코드를 읽기 전에 읽는 문서**다.
> `RoundService` / `WallController` / `Arena` / `SessionService` 를 수정하거나,
> Phase 3 이후 라운드 흐름에 끼어드는 로직을 짤 때 필요한 배경·규약·함정을 담았다.
>
> 맵 좌표계는 [map-builder.md](map-builder.md) 를 먼저 읽을 것. 여기서는 다 안다고 가정한다.

---

## 1. 세 줄 요약

1. **시간 축을 소유한 건 `RoundService` 하나다.** 상태를 바꾸는 코드는 그 파일의 `setState` 뿐이다.
2. **생존 판정은 위치 스냅샷이 아니라 물리 결과다.** 벽에 밀려 맵 밖으로 떨어진 사람이 탈락자다.
3. **정답 구역은 문제가 정한다.** `QuestionService.next(round).answer` 가 곧 정답 구역이다
   (Phase 3 — [question-system.md](question-system.md)).

---

## 2. 상태 흐름

```
        ┌──────────────────────── 게임 1판 ────────────────────────┐
        │                                                          │
 Lobby ─┼─▶ Countdown ─▶ WallRush ─▶ Judge ─┬─▶ Intermission ──┐  │
   ▲    │      ▲                             │                 │  │
   │    │      └─────────────────────────────│─────────────────┘  │
   │    │                                    │                     │
   │    │                                    └─▶ (종료 조건)       │
   │    └──────────────────────────────────────────┬──────────────┘
   │                                               ▼
   └───────────────────────────────────────── GameOver
```

| 상태 | 길이 | 하는 일 |
|---|---|---|
| `Lobby` | `LobbyTime` (15s) | 인원이 `MinPlayersToStart` 이상 모일 때까지 대기 |
| `Countdown` | `getCountdown(round)` (5→2s) | 벽 원위치·생존자 배치 완료. 플레이어가 구역을 고른다 |
| `WallRush` | `WallTravelDistance / getWallSpeed(round)` (4.15→1.11s) | 벽 돌진. **블로킹** |
| `Judge` | `ResultDisplayTime` (2s) | 낙하 정산 후 생존자 확정·보상 |
| `Intermission` | `IntermissionTime` (3s) | 다음 라운드 준비 |
| `GameOver` | `GameOverTime` (5s) | 우승자 발표, 전원 관전장 복귀 |

`WallRush` 앞에는 `FallGraceTime`(1.5s)이 더 붙는다. 벽이 밀어낸 플레이어가 Y=-30 까지
떨어지는 데 시간이 걸리므로, 이걸 기다리지 않고 생존자를 세면 **탈락자가 생존자로 집계된다.**

### 상태 알림 페이로드

`RoundStateChanged(state, round, payload)` 의 `payload.endsAt` 은
`workspace:GetServerTimeNow()` 기준 절대 시각이다. 클라이언트가 남은 시간을 스스로 세면
지연·프레임드랍만큼 어긋나므로, **타이머는 항상 `endsAt - GetServerTimeNow()` 로 그린다.**

---

## 3. 모듈 책임 분리

```
SessionService   "이 사람은 살아있나"    alive / spectating / roundsSurvived
      ▲                                  맵도 라운드도 모른다
      │
   Arena         "어디에 세우고 언제 떨군다"  텔레포트 · KillPlane · 탈락 확정
      ▲                                      라운드 진행은 모른다
      │
 WallController  "벽을 움직인다"          rush() / reset() / 관통 방지
      ▲
      │
 RoundService    "언제 무슨 일이 일어난다"  상태머신. 여기만 시간을 안다
```

require 방향은 위에서 아래로만 흐른다(순환 없음). **아래쪽 모듈이 `RoundService` 를
require 하고 싶어지면 설계가 틀어진 것이다** — 필요한 값을 인자로 받도록 바꿔라.

`Arena.Eliminated` 이벤트가 있는 이유도 이것이다. `Arena` 는 탈락 사실만 방송하고,
그걸로 무엇을 할지(게임 종료 판정 등)는 `RoundService` 가 정한다.

---

## 4. 생존 판정 — 가장 중요한 설계 결정

### 위치 스냅샷으로 판정하지 않는다

제한시간이 끝난 순간의 X 좌표로 정답/오답을 확정하는 방법도 있었다. **쓰지 않았다.**

벽이 오는 4초 동안 옆 레인으로 뛰어드는 마지막 몸부림이 게임에서 가장 재미있는
순간인데, 스냅샷 판정은 그걸 통째로 없앤다. 대신 판정을 물리에 맡겼다:

> **오답 구역 벽이 밀어내 맵 밖으로 떨어진 사람이 탈락자다.**
> 늦게라도 정답 구역에 도착했으면 산다.

그래서 `RoundService` 에는 "누가 정답을 맞혔나"를 계산하는 코드가 없다.
`Judge` 시점에 살아있는 사람이 곧 생존자다.

### 탈락 감지가 두 겹인 이유

| 경로 | 특성 |
|---|---|
| `BO_KillPlane` 의 `Touched` | 즉각적. 고속 낙하 시 프레임을 건너뛰면 놓칠 수 있다 |
| Y < `FallEliminationY` 폴링 (`FallCheckInterval` 마다) | 느리지만 절대 놓치지 않는다 |

**하나라도 놓치면 라운드가 끝나지 않는다.** 죽은 사람이 생존자로 남아 최후의 1인
조건이 영원히 성립하지 않기 때문이다. 둘 다 `Arena.eliminate` 를 부르고, 이 함수는
멱등이라 두 경로가 동시에 걸려도 안전하다.

같은 이유로 `RoundService.placeSurvivors` 는 **캐릭터가 없어 배치에 실패한 플레이어를
그 자리에서 탈락시킨다.** 살아있는 채로 두면 관전장에 떠 있어 벽이 영영 닿지 않는다.

### `Judge` 의 `eliminateZone` 은 안전망일 뿐이다

정상 동작에서는 오답 구역에 생존자가 남아있을 수 없다. 이 줄이 실제로 사람을 잡고
있다면 벽 밀어내기가 새고 있다는 뜻이므로, **지우지 말고 원인을 찾아라.**

---

## 5. 벽 이동 — 함정 모음

### `PreSimulation` 에서 움직인다

벽은 `Anchored` 다. 앵커된 파트가 캐릭터를 밀어내려면 **물리 스텝 이전에** 위치가
바뀌어 있어야 한다. `Heartbeat`(= PostSimulation)에서 옮기면 한 프레임 늦게 반영돼
밀어내는 힘이 약해지고 캐릭터가 벽에 파묻힌다.

### 물리만 믿으면 안 된다 — `shoveTrapped`

프레임이 튀면 벽이 캐릭터를 지나칠 수 있다. 그러면 **랙 걸린 플레이어가 벽을 통과해
오답인데도 살아남는다.** `shoveTrapped()` 가 매 프레임 벽 선단면(`MapLayout.wallFrontZ`)
안쪽으로 들어온 생존자를 앞으로 끌어낸다.

이미 벽보다 앞(-Z)에 있는 플레이어는 건드리지 않는다. 전부 강제 이동시키면 점프·이동이
씹혀서 조작감이 무너진다. **관통했을 때만 개입하는 것이 핵심이다.**

### "파괴"는 `Destroy` 가 아니다

맵은 부팅 때 한 번만 만든다(map-builder.md §2). 벽을 실제로 지우면 다음 라운드에
되살릴 수 없으므로, `setBroken()` 이 `CanCollide` / `CanTouch` / `Transparency` 만 토글한다.
파괴된 벽은 그 자리에 멈추고, 다음 `reset()` 에서 출발 위치로 복귀한다.

---

## 5-1. 벽 파괴 폭발 (Phase 4)

`setBroken(zone, wall, true)` 이 **파괴로 바뀌는 순간에만** `WallBroken` 을 쏘고,
실제 폭발은 각 클라이언트가 로컬로 만든다([`src/client/WallEffects.luau`](../src/client/WallEffects.luau)).
서버가 하는 일은 "언제, 어디서 부서졌는가"를 알리는 것뿐이다.

### ⚠ 연출은 절대 무언가를 밀면 안 된다

서버가 폭발이나 파편을 실물로 뿌리면 그 힘이 캐릭터를 민다. **정답 구역에 서 있던 사람이
밀려 -Z 밖으로 떨어지면 오답도 아닌데 탈락한다** — §4의 판정이 통째로 무너진다.
그래서 세 겹의 방어를 둔다.

1. 폭발은 **클라이언트 로컬**이다. 서버로 복제되지 않으므로 판정에 닿을 수 없다.
2. `Explosion` 인스턴스를 쓰지 않는다. `BlastPressure = 0` 으로 둘 수는 있지만, 로컬
   캐릭터는 클라이언트가 직접 시뮬레이션하므로 언젠가 누가 압력을 되돌리는 순간
   **내 화면에서만 밀려나는** 서버와 어긋난 위치가 생긴다. 입자·빛·화면 흔들림뿐이다.
3. 연출용 파트는 `CanCollide` / `CanQuery` / `CanTouch` 를 전부 끈다. 하나만 빠뜨려도
   연출용 물건이 게임에 개입하기 시작한다.

`Config.Theme.WallBreak` 에도 **미는 수치가 없다.** 있으면 그게 버그다.

### ⚠ 파괴 예고(직전 깜빡임)를 넣지 않는 이유

하이퍼캐주얼의 정석은 "부서지기 직전 벽이 붉게 깜빡인다" 지만, 이 게임에서는 넣으면 안 된다.
**파괴 자체가 정답 공개이기 때문이다.** 그래서 파괴 지점을 스폰 코앞까지 늦춰 뒀는데
(아래 절), 예고를 주면 그 늦춘 만큼을 그대로 되돌려 준다 — 문제를 읽지 않고 '깜빡이지 않는
쪽'에서 도망치면 되는 게임이 된다. 예고 시간은 곧 무료 정답 열람 시간이다.

### 위치를 이벤트에 실어 보내는 이유

`WallBroken` 은 `(zone, cframe, size)` 를 함께 보낸다. 클라이언트가 복제된 벽 파트를 직접
읽으면 복제 지연만큼 폭발이 엉뚱한 곳에서 터진다. 벽은 이 게임에서 유일하게 빠르게
움직이는 오브젝트라 그 오차가 눈에 띈다.

### 연출 수명

`Config.Theme.WallBreak.Lifetime`(기본 2초) 안에 전부 사라져야 한다. 파괴는 `WallRush`
도중에 일어나므로 뒤에 남은 돌진 시간 + `FallGraceTime` + `ResultDisplayTime` +
`IntermissionTime` 이 전부 버퍼다. 이 값을 크게 키우면 **다음 라운드가 시작된 뒤에도
연기가 남아** 새 벽이 이미 출발선에 서 있는 화면과 겹친다.

### 관전자도 본다

`FireAllClients` 로 나가므로 탈락자 화면에서도 재생된다. 화면 흔들림은 폭발까지의 거리로
감쇠하므로(`Shake.Falloff`) 상공 관전장에서는 약하게만 흔들린다. **흔들림은 짧고 약하게
유지할 것 — 과하면 그대로 멀미가 된다.**

### ⚠ 정답 벽은 '스폰 코앞'에서 부서진다 — 파괴가 곧 정답 공개이기 때문이다

파괴 지점은 진행률이 아니라 **스폰밴드와의 거리**로 정한다.
`Config.Round.CorrectWallBreakMargin`(기본 2 studs)이 유일한 손잡이이고, 실제 진행률은
`MapLayout.CorrectWallBreakProgress` 가 맵 치수에서 파생시킨다.

```
파괴 선단면 z = 스폰밴드 +Z 끝(-40) + CorrectWallBreakMargin(2) = -38
진행률       = (WallReachDistance 150 − 2) ÷ WallTravelDistance 228 = 0.649
```

**이 지점을 앞당기면 게임이 무너진다.** 예전 값(진행률 0.35, z=+34)은 벽이 아직 레인
한복판에 있을 때 정답 쪽이 사라지는 장면을 보여줬다 — 문제를 읽지 않고 **부서지는 쪽으로
달려도 여유 있게 살 수 있었다.** 지금은 두 벽이 나란히 스폰 코앞까지 온 뒤에야 한쪽이
부서지므로, 그 장면이 보일 때는 오답 구역 사람이 이미 벽에 밀리고 있다.

반대로 너무 늦추면(= `CorrectWallBreakMargin` 을 음수로) 벽이 스폰밴드 안까지 밀고 들어와
**자기 구역에서 꼼짝도 안 한 정답 구역 플레이어를 밀기 시작한다.** 두 경계 모두
`CurveAudit` 이 부팅 때 검사한다.

경계 계산: 정답 구역에서 가장 +Z 에 붙어 있던 플레이어가 밀려나는 최대 거리는
`WallTravelDistance × 진행률`(= 148 studs)이다. 이 값이 `LaneLength`(220)에 근접하면
정답 구역인데도 -Z 밖으로 밀려 탈락한다.

---

## 6. 참가자 / 로비 규약

- **참가자는 게임 시작 순간 접속해 있던 전원**이다(`buildRoster`). 중간 접속자는 관전만 하고
  다음 게임부터 참가한다. 라운드 도중 벽 뒤에서 사람이 튀어나오는 상황을 원천 차단한다.
- 맵의 유일한 `SpawnLocation` 은 **관전장 위**에 있다(`BO_LobbySpawn`). 접속·리스폰의
  기본 위치가 경기장 밖이라는 뜻이다. 자세한 이유는 map-builder.md §6.

### ⚠ 솔로 예외 규칙

```lua
-- isGameOver()
if aliveCount == 0 then return true end
return participantCount >= 2 and aliveCount <= 1
```

`participantCount >= 2` 조건이 없으면 **혼자 테스트할 때 1라운드마다 게임이 끝나서
난이도 커브를 확인할 수 없다.** `Config.Round.MinPlayersToStart = 1` 인 개발 환경
전용 배려이며, 실제 서비스(2인 이상)에서는 아무 영향이 없다.

---

## 7. Phase 3 연동 현황 (완료)

라운드 흐름 자체는 바뀌지 않았다. 상태·시간 축은 그대로이고, 아래 네 가지만 붙었다.
자세한 내용은 [question-system.md](question-system.md) 참고.

- [x] **정답 구역 결정** — `pickCorrectZone()`(동전 던지기) 삭제.
      `QuestionService.next(round).answer` 가 정답 구역이 됐다.
- [x] **문제 노출** — `runRound` ② 단계에서 `QuestionShown` 을 쏜다.
      페이로드는 `QuestionService.payloadOf()` 가 만들며 **`answer` 가 없다**(README 규약 2).
- [x] **바닥 스크린** — `QuestionDisplay.show()` 가 `BO_AnswerScreen` 바닥 두 장에 선택지를 그린다.
      `Judge` 에서 `reveal(correctZone)`, 로비·게임 종료에서 `clear()`.
- [x] **HUD** — `StatusDisplay` → `Hud` 로 교체(문제 본문·타이머·상태·알림).
- [x] **`Config.Debug.RevealAnswer` 제거** — 정답을 전 클라이언트에 뿌리던 물건이라
      진짜 문제가 생긴 순간 존재 이유가 사라졌다. 서버 콘솔 전용 `LogQuestions` 로 대체.

### `beginTimedState` 가 생긴 이유

`QuestionShown.deadline` 과 `RoundStateChanged.endsAt` 은 **같은 값이어야 한다.**
각자 `now() + seconds` 를 계산하면 두 호출 사이의 시간만큼 어긋나 HUD 타이머가 튄다.
그래서 상태를 알리고 **종료 시각을 반환하는**(대기하지 않는) 함수를 분리했다.
`timedState` 는 이제 그 위에 `task.wait` 만 얹은 얇은 껍데기다.

---

## 7-1. Phase 4 연동 현황 (완료)

라운드 흐름은 여기서도 바뀌지 않았다. 상태·시간 축은 그대로다.

- [x] **난이도 커브 검산** — `CurveAudit.report()` 를 부팅에 추가. 커브 수치는 `Config` 에
      그대로 있고, 검산기는 표를 합쳐 읽기만 한다. 자세한 내용은
      [difficulty-curve.md](difficulty-curve.md).
- [x] **`WallSpeedMax` 170 → 205** — 후반의 유일한 축이 R16에 멈춰 R16~R20이 같은
      라운드였다. 205는 R20에서야 걸린다.
- [x] **커브 조회 규칙 통일** — `Config` 안의 `curveAt(list, round)` 하나로 모았다.
      예전에는 `getCountdown` 이 `math.min`, `getMaxDifficulty` 가 `math.clamp` 을 썼다.
- [x] **벽 파괴 폭발** — `setBroken` 이 `WallBroken` 을 쏘고 클라이언트가 로컬로 재생(§5-1).
- [x] **파괴 지점을 스폰 코앞으로** — `Config.Round.CorrectWallBreakProgress`(0.35, 레인 한복판)를
      `CorrectWallBreakMargin`(스폰밴드 앞 2 studs)으로 바꾸고 진행률은 `MapLayout` 이 파생시킨다.
      **파괴가 곧 정답 공개이므로 이 지점이 이르면 문제를 안 읽어도 이긴다**(§5-1).
- [x] **`MapLayout` 에 커브용 거리 두 개** — `WallReachDistance` / `LaneCrossDistance`.

Phase 5(대시)가 들어와도 **`CurveAudit` 의 횡단 시간은 걷는 속도 그대로 둘 것**
([difficulty-curve.md §2](difficulty-curve.md)).

---

## 8. 검증 방법

### 부팅 로그

```
[MapService] 맵 확인 | 80x220 studs | 벽 이동거리 228 studs (1R 4.15s) | 경고 0건
[CurveAudit] 커브 20라운드 | 레인 횡단 1.82s (40 studs ÷ 22 studs/s) | 벽 도달 150 studs
[CurveAudit]  R1  제한 5.0s | 벽속도  55 | 난이도 ≤1 | 여유 5.91s
   ... (계단이 움직인 라운드만 — difficulty-curve.md §3)
[CurveAudit] 정답 벽 파괴 z=-38.0 (진행률 0.65 · 스폰밴드 앞 2 studs) | 밀림 최대 148 / 레인 220 studs | 경고 0건
[QuestionDisplay] 바닥 스크린 2개 | 공중 보드 1개
[Round] Lobby | R0 | 생존 0
[BrainOverrun] 서버 부팅 완료
[BrainOverrun] 디버그 모드 | 1R 제한시간 5s, 1R 벽속도 55 studs/s | 문제 16종(텍스트 10, 이미지 6)
```

### 라운드 진행 로그

`Config.Debug.ShowStateInConsole` 이 켜져 있으면 상태 전이가 전부 찍힌다.
라운드가 올라가는데 `생존` 수가 줄지 않으면 §4 의 탈락 감지를 의심하라.

```
[Round] R2 출제: 14 - 6 = ? | A=9 B=8 → 정답 B (난이도 2)
[Round] Countdown | R2 | 생존 1
[Round] WallRush  | R2 | 생존 1
[Arena] 탈락: <name> (fall)
[Round] Judge     | R2 | 생존 0
```

출제 로그는 `Config.Debug.LogQuestions` 로 켜고 끈다. **서버 콘솔에만** 찍히므로
켜 둔 채 테스트해도 정답이 클라이언트로 새지 않는다.

### 벽 파괴 지점 확인 (Server datamodel)

```lua
local CollectionService = game:GetService("CollectionService")
local Tags = require(game.ReplicatedStorage.Shared.Tags)
local RunService = game:GetService("RunService")
local A = CollectionService:GetTagged(Tags.WallA)[1]
local prev = A.CanCollide
RunService.Heartbeat:Connect(function()
    if A.CanCollide ~= prev then
        prev = A.CanCollide
        print(("WallA collide=%s @ z=%.1f"):format(tostring(prev), A.Position.Z))
    end
end)
-- 파괴 시 z = -34.0 (스폰밴드 앞 2 studs · 진행률 0.649) 이면 정상
```

### 확인된 실측값

| 항목 | 값 |
|---|---|
| 정답 벽 파괴 지점 | z = -34.0 (선단면 -38 = 스폰밴드 앞 2 studs) |
| 오답 벽 최종 위치 | z = -114.0 (= `MapLayout.WallEndZ`) |
| 정답 구역 생존율 | 7/7 (다이브 포함) |
| 탈락자 관전장 Y | 85 (= `SpectatorY` + 캐릭터 높이) |
| R1 라운드 총 길이 | 약 15.7초 |
| R9 라운드 총 길이 | 약 11초 (제한시간 2s, 벽속도 119 studs/s) |

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
3. **정답 구역은 아직 무작위다.** Phase 3 이 `RoundService.pickCorrectZone` 만 갈아끼운다.

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
| `WallRush` | `WallTravelDistance / getWallSpeed(round)` (4.15→1.34s) | 벽 돌진. **블로킹** |
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

**Phase 4 의 파편 연출은 `setBroken` 안에 얹으면 된다.** 다른 곳을 고칠 필요가 없다.

### `CorrectWallBreakProgress` 를 올릴 때 주의

기본값 0.35 는 벽이 z=+114 → z=+34.2 까지 온 뒤 부서진다는 뜻이다.
이 값을 크게 하면 연출은 더 아슬아슬해지지만, **정답 구역 플레이어가 -Z 밖으로
밀려나 오답도 아닌데 탈락하는 순간** 게임이 망가진다.

경계 계산: 정답 구역에서 가장 +Z 에 붙어 있던 플레이어가 밀려나는 최대 거리는
`WallTravelDistance × 진행률` 이다. 이 값이 `LaneLength`(220)에 근접하면 위험하다.

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

## 7. Phase 3 이 갈아끼울 곳

라운드 흐름은 건드릴 필요가 없다. **딱 두 군데다.**

### ① 정답 구역 결정

```lua
-- RoundService.luau
local function pickCorrectZone(): Zone
    return if rng:NextInteger(0, 1) == 0 then "A" else "B"   -- ← 여기
end
```

`QuestionService.next()` 가 문제를 뽑고 그 `answer` 를 반환하도록 바꾼다.
`Types.Question.answer` 가 이미 `Zone` 타입이라 그대로 맞는다.

### ② 문제 노출

`runRound` 의 ② 단계, `timedState("Countdown", ...)` 직전에
`Remotes.event("QuestionShown"):FireAllClients(payload)` 를 넣는다.
**`payload` 는 `Types.QuestionPayload` 여야 한다 — `answer` 필드가 들어가면 안 된다**
(README 규약 2). 선택지 텍스트는 `BO_AnswerScreen` 태그가 붙은 바닥 파트의
`SurfaceGui` 로 그린다.

### ③ 그리고 지울 것

- `Config.Debug.RevealAnswer` — Phase 3 전까지 루프를 손으로 테스트하기 위한 정답 힌트다.
  진짜 문제가 나오는 순간 존재 이유가 사라진다. **출시 전이 아니라 Phase 3 에서 지워라.**
- `src/client/StatusDisplay.luau` — 상태머신 확인용 임시 UI. 정식 HUD 로 교체한다.

---

## 8. 검증 방법

### 부팅 로그

```
[MapService] 맵 확인 | 80x220 studs | 벽 이동거리 228 studs (1R 4.15s) | 경고 0건
[Round] Lobby | R0 | 생존 0
[BrainOverrun] 서버 부팅 완료
[BrainOverrun] Debug.RevealAnswer = true — 정답이 전 클라이언트에 노출됩니다. 출시 전 끌 것.
```

### 라운드 진행 로그

`Config.Debug.ShowStateInConsole` 이 켜져 있으면 상태 전이가 전부 찍힌다.
라운드가 올라가는데 `생존` 수가 줄지 않으면 §4 의 탈락 감지를 의심하라.

```
[Round] Countdown | R2 | 생존 1
[Round] WallRush  | R2 | 생존 1
[Arena] 탈락: <name> (fall)
[Round] Judge     | R2 | 생존 0
```

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
-- 파괴 시 z = +34.2 (기본 CorrectWallBreakProgress = 0.35) 이면 정상
```

### 확인된 실측값

| 항목 | 값 |
|---|---|
| 정답 벽 파괴 지점 | z = +34.2 |
| 오답 벽 최종 위치 | z = -114.0 (= `MapLayout.WallEndZ`) |
| 정답 구역 생존율 | 7/7 (다이브 포함) |
| 탈락자 관전장 Y | 85 (= `SpectatorY` + 캐릭터 높이) |
| R1 라운드 총 길이 | 약 15.7초 |
| R9 라운드 총 길이 | 약 11초 (제한시간 2s, 벽속도 119 studs/s) |

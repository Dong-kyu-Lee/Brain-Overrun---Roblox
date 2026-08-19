# 능력 시스템 (Phase 5) — 대시 · 밀치기

기획서 4장(특수 이동)과 6장(밀치기 스킬)의 구현.
관련 문서: [round-loop.md](round-loop.md) · [difficulty-curve.md](difficulty-curve.md) · [map-builder.md](map-builder.md)

---

## 1. 세 줄 요약

1. **클라이언트는 요청만 보낸다.** 쿨타임·횟수·사거리·각도·라운드 상태는 전부 서버가 다시 판정한다.
2. **대시는 수평 전용이다.** Y 성분을 남기면 그 순간 비행이 되고, 비행은 곧 벽 위와 맵 밖이다.
3. **커브는 대시를 모른다.** `CurveAudit` 의 횡단 시간은 앞으로도 걷는 속도다. 대시 기하는
   형제 모듈 `MovementAudit` 이 따로 검산한다.

---

## 2. 모듈 구성

| 파일 | 어디서 도는가 | 책임 |
|---|---|---|
| [src/server/AbilityService.luau](../src/server/AbilityService.luau) | 서버 | 두 능력의 게이트·판정·물리 |
| [src/server/MovementAudit.luau](../src/server/MovementAudit.luau) | 서버(부팅) | 능력 수치 × 맵 기하 검산 |
| [src/client/AbilityState.luau](../src/client/AbilityState.luau) | 클라이언트 | 서버 세션의 읽기 전용 사본 |
| [src/client/DashInput.luau](../src/client/DashInput.luau) | 클라이언트 | 대시 키 → 방향 계산 → 요청 |
| [src/client/PushInput.luau](../src/client/PushInput.luau) | 클라이언트 | 밀치기 키 → 요청(인자 없음) |
| [src/client/AbilityHud.luau](../src/client/AbilityHud.luau) | 클라이언트 | 우측 상단 배지 2개 |

서버가 한 모듈인 이유는 두 능력이 **게이트를 100% 공유**하기 때문이다 — 생존 중 +
`Countdown`/`WallRush` + 캐릭터 존재 + 요청 간격. 그 게이트가 두 파일로 갈라지면
한쪽만 고치는 날이 온다. 입력은 키도 의미도 달라 클라이언트만 나눠 뒀다.

---

## 3. 데이터 흐름

```
[키 입력]  DashInput / PushInput
    │  (스스로 한 번 거른다 — 어차피 거절될 요청을 네트워크에 안 보내려고)
    ▼
DashRequest(direction) / PushRequest()        ← 클라이언트가 보내는 전부
    ▼
[AbilityService]  요청 상한 → 생존 → 라운드 상태 → 쿨타임 → (밀치기: 보유·횟수·대상)
    ▼
물리 적용 (LinearVelocity / ApplyImpulse)  +  SessionService 기록
    ▼
SessionStateChanged(session)                  ← 서버가 알려 주는 전부
    ▼
[AbilityState] 사본 갱신 → [AbilityHud] 배지
```

**새 리모트를 만들지 않았다.** 세션에 이미 `lastDashAt`/`lastPushAt`/`pushUsesLeft` 가
있으므로, 성공했을 때 `SessionService.sync()` 한 번이면 클라이언트가 남은 쿨타임을
스스로 정확히 계산한다.

### ★ 시각은 서버 시각이다

`lastDashAt` 은 `Workspace:GetServerTimeNow()` 로 찍는다. 클라이언트가 같은
`GetServerTimeNow()` 로 빼야 지연과 무관하게 남은 쿨타임이 맞는다. `os.clock()` 이나
`tick()` 을 섞으면 게이지가 사람마다 다르게 찬다 — HUD 타이머가 `deadline` 을 쓰는 것과
같은 이유다([question-system.md §7](question-system.md)).

---

## 4. 대시

### 서버가 물리를 건다 — 대신 왕복지연만큼 늦다

클라이언트가 자기 캐릭터를 직접 밀면, 서버가 거절한 요청도 화면에서는 성공한 것처럼
보이고 서버가 같은 대시를 또 걸어 주면 두 배 속도로 날아간다. 그래서 **물리는 서버만**
건다. 반응이 왕복지연만큼 늦지만 하이퍼캐주얼 기준으로 견딜 만하다.

체감이 굼뜨면 그때 클라이언트 선반영을 얹으면 된다. 그때는 **서버가 건 구속을 클라이언트가
중복으로 걸지 않도록** 반드시 한쪽만 적용해야 한다.

### `LinearVelocity` Plane 모드 — 중력을 살려 두기 위한 선택

```lua
velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
velocity.PrimaryTangentAxis = Vector3.xAxis
velocity.SecondaryTangentAxis = Vector3.zAxis
velocity.PlaneVelocity = Vector2.new(dir.X, dir.Z) * Config.Movement.DashSpeed
```

* ★ **Vector 모드로 Y 까지 고정하지 마라.** 대시 중 공중부양이 되고, 그건 곧 벽 위다.
  Plane 모드는 X/Z 만 구속하므로 중력·점프·낙하가 그대로 산다.
* ★ **Plane 모드에 `MaxPlanarForce` 같은 속성은 없다** (Studio 실측). 힘 상한은
  `MaxForce` 하나이고 `ForceLimitMode = Magnitude` 와 함께 쓴다. 기본값 1000 을 그대로 두면
  대시가 '조금 빨리 걷기' 가 되므로 `Config.Movement.DashMaxForce` 로 올려 둔다.
  반대로 무한대로 두면 벽에 낀 채 밀어붙여 캐릭터가 떨린다.
* 인스턴스는 `Debris` 로 `DashDuration` 뒤 사라진다. 남으면 영구 가속이다.

### 클라이언트가 보낸 방향을 믿지 않는 방법

`sanitizeDirection()` 이 세 가지를 한다.

1. **NaN/무한대 차단** — NaN 은 자기 자신과 같지 않다는 성질로 거른다.
2. **Y 성분 제거** — 대시는 수평 이동 수단이다.
3. **정규화** — 길이를 믿으면 "10배짜리 방향 벡터"로 대시 거리를 늘리는 조작이 통한다.

셋 다 실패해 방향이 남지 않으면 **바라보는 방향**으로 나간다. 요청을 버리는 것보다
"눌렀는데 아무 일도 안 일어나는" 순간을 없애는 편이 낫다.

### 이동거리 — 세 수치를 곱해서 봐야 한다

```
대시 이동거리 = DashSpeed × DashDuration = 95 × 0.18 = 17.1 studs
레인 횡단 40 studs : 걷기 1.82s → 대시 1회 포함 1.22s
```

두 개의 경계가 있고 둘 다 `MovementAudit` 이 부팅 때 잰다.

| 경계 | 넘으면 | 기본값 여유 |
|---|---|---|
| 레인 폭 (40) | 대시 한 번에 반대 레인 착지 → **문제를 안 읽어도 이긴다** | 22.9 studs |
| 스폰선 뒤 여유 (24 = 인셋 20 + 가장자리 4) | 스폰 직후 뒤로 대시하면 열린 -Z 밖으로 즉사 | 6.9 studs |

★ 뒤쪽 여유가 더 빡빡하다. 대시 속도나 지속시간을 올릴 때는 반드시 부팅 로그를 볼 것.

---

## 5. 밀치기

### 판정 순서

```
요청 상한 → 생존/상태 → 보유 → 쿨타임 → 남은 횟수 → 대상 탐색 → 소모 → 넉백
```

* **대상 탐색이 소모보다 앞에 있다.** 헛손질은 횟수를 소모하지 않는다 —
  게임당 3회뿐인 자원을 허공에 버리게 두면 스킬이 아니라 벌칙이 된다.
* **원뿔은 '전체' 각도다.** `ConeAngle = 60` 은 반각 30° 와 비교한다(`dot ≥ cos(30°)`).
* **거리는 수평으로 잰다.** 점프한 사람이 사거리에서 빠지면 판정이 운에 좌우된다.
  다만 수직 차이도 사거리로 재서, 상공 관전장에 있는 사람이 '바로 위' 라는 이유로 맞는 일은 없앤다.
* 대상은 `SessionService.alivePlayers()` 에서만 고른다 — 관전자와 자기 자신은 자동으로 빠진다.

### ★ 넉백은 네트워크 소유권을 잠깐 뺏어야 한다

캐릭터는 평소 **그 플레이어의 클라이언트**가 시뮬레이션한다. 서버가 그냥 `ApplyImpulse`
하면 다음 복제 프레임에 피해자 클라이언트의 상태가 덮어써서 임펄스가 **조용히 사라진다.**
증상은 "미는 사람 화면에서만 밀리는" 불일치다.

```lua
root:SetNetworkOwner(nil)     -- 서버가 쥔다
root:ApplyImpulse(impulse)
task.delay(Config.Push.OwnershipHoldTime, function() root:SetNetworkOwner(target) end)
```

★ **돌려주는 것을 잊지 마라.** 소유권이 서버에 남으면 그 사람의 조작감이 눈에 띄게
무거워진다. 그 사이 캐릭터가 사라질 수 있어 양쪽 다 `pcall` 로 감싼다.

★ **대시는 정반대다** — 소유권을 건드리지 않는다. 쓰는 사람이 곧 자기 캐릭터의 주인이라
구속이 그 클라이언트에서 즉시 시뮬레이션돼 반응이 빠르다. 두 방향이 다른 것은 의도된 것이다.

### `Force` 는 힘이 아니라 속도 증분이다

`Config.Push.Force = 75`, `UpwardForce = 15` 는 **studs/s** 다. `AbilityService` 가
`AssemblyMass` 를 곱해 임펄스로 넣는다(Δv = Force). 여기서 질량을 또 고려하면 두 번 곱하는 셈이다.

### 보유 게이트 — Phase 6 이 갈아끼우는 함수는 하나다

```lua
local function ownsPushSkill(_player: Player): boolean
	return Config.Debug.GrantPushSkill   -- Phase 6: PlayerData.ownsPushSkill 을 읽는다
end
```

호출부는 바뀌지 않는다. ★ `Config.Debug.GrantPushSkill` 은 출시 전 반드시 `false` —
아니면 500코인 상품이 공짜다.

---

## 6. 게이트 네 겹

| 겹 | 무엇을 막나 | 실패하면 |
|---|---|---|
| 요청 상한 (`Input.MinRequestInterval`) | 초당 수백 번의 스크립트 스팸 | 조용히 버림 |
| 생존 + 라운드 상태 | 관전자의 대시(유리 바닥 탈출), 판정 끝난 뒤의 조작 | 조용히 버림 |
| 쿨타임 | 연타 | 조용히 버림 |
| 보유·남은 횟수 (밀치기) | 미보유자 사용, 4회째 | `Notify` (쿨타임 간격으로 묶음) |

★ **쿨타임 거절은 알리지 않는다.** 연타할 때마다 알림이 뜨면 상단 밴드의 알림 줄이
라운드 내내 튄다. 사유를 알려 줄 가치가 있는 것은 "미보유"와 "소진" 둘뿐이다.

★ **요청 상한은 쿨타임이 아니다.** 실패하는 요청은 `lastPushAt` 을 움직이지 않으므로
쿨타임만으로는 연타를 못 막는다. 그래서 성공·실패와 무관한 상한을 따로 둔다.

---

## 7. 클라이언트 세 층

**`AbilityState` 하나만 서버 상태를 안다.** 입력 둘과 배지 하나가 전부 이 사본을 읽는다.
셋이 각자 `SessionStateChanged` 를 듣게 두면 같은 값이 세 벌 생기고, 언젠가 한 벌만
갱신되는 날이 온다.

입력 모듈이 사본을 보는 이유는 두 가지뿐이다 — 배지를 그리고, 어차피 거절될 요청을
보내지 않기 위해. **판정이 아니다.** 여기가 뚫려도 서버에서 다시 막힌다.

### 배지 위치 — 인셋 규칙이 상단 밴드와 반대다

* `Hud` 의 상단 밴드: `IgnoreGuiInset = true` (화면 폭 전체를 쓰는 오버레이라 맞다)
* `AbilityHud` 의 배지: **`IgnoreGuiInset = false`**

★ 배지는 우측 '상단' 이라 인셋을 무시하면 로블록스 상단바(`GuiService:GetGuiInset()` 기준
58px) 영역에 걸린다. **구석에 붙는 작은 UI 는 인셋 아래에서 시작해야 한다.**

⚠ **`AbsolutePosition` 으로 검증하지 마라.** Studio 플레이 창에서는 상단바 유무에 따라
이 값이 인셋만큼 음수로 보고되고, `IgnoreGuiInset` 을 껐는데도 두 ScreenGui 의
`AbsoluteSize` 가 똑같이 나오는 창도 있다. 숫자로는 겹침 여부를 알 수 없으니 눈으로 볼 것.

배지는 `SizeConstraint = RelativeYY` 로 두 축을 모두 화면 높이 기준으로 잡는다. 기본값이면
화면이 넓어질수록 가로로 늘어난 직사각형이 된다.

★ **화면 아래로 내리지 마라.** 아래쪽은 바닥 선택지를 보는 영역이다(기획서 3장).
모바일 터치 버튼만 예외로 `ContextActionService` 가 우측 하단에 만든다 — 그건 조작부다.

### 키는 `Config.Input` 한 곳에

배지의 안내문(`대시 · Shift/Q`)도 그 목록에서 파생된다. 키를 바꾸면 안내도 함께 바뀐다.
★ 서버는 키를 모른다 — 어느 키였는지는 판정에 아무 영향이 없다.

---

## 8. `MovementAudit` 읽는 법

```
[MovementAudit] 대시 17.1 studs (95 studs/s × 0.18s, 쿨타임 2.0s) | 레인 횡단 걷기 1.82s → 대시 1.22s
[MovementAudit] 스폰선 뒤 여유 24 studs (인셋 20 + 가장자리 4) | 밀치기 사거리 12 / 레인 폭 40 · 원뿔 60° · 3회 (개발용 전원 지급) | 경고 0건
```

경고가 뜨는 조합은 넷이다.

| 경고 | 뜻 |
|---|---|
| 대시 ≥ 레인 폭 | 대시 한 번에 반대 레인 — 문제를 안 읽어도 이긴다 |
| 대시 ≥ 스폰선 뒤 여유 | 스폰 직후 뒤로 대시 = 즉사 |
| 밀치기 사거리 ≥ 레인 폭 | 옆 레인의 정답 구역 플레이어까지 민다 |
| 원뿔 ≥ 180° | 옆·뒤도 맞는다 — '전방' 스킬이 아니게 된다 |

참고로만 찍는 줄도 있다(후반 라운드의 행동 시간이 대시 쿨타임보다 짧을 때, 밀치기 비활성일 때).

★ **`CurveAudit` 에 대시를 들여놓지 마라.** 여유시간은 걷는 속도만 가정한다
([difficulty-curve.md §2](difficulty-curve.md)). 대시는 쿨타임이 있어 매 라운드 보장되지
않으므로, 대시를 전제로 커브를 조이면 쿨타임이 도는 라운드에서 아무도 못 건넌다.

---

## 9. 검증 방법

### 부팅 로그

§8 의 두 줄이 `[CurveAudit]` 다음에 나오고 **경고 0건**이면 정상이다.

### 실측 기록 (Studio, 기본 수치)

| 시험 | 결과 | 판정 |
|---|---|---|
| 정상 대시 | 최고 수평속도 96.1, 최고 Y속도 0.1, ΔX 19.7 | ✅ 수평 전용 |
| 거대 벡터 `(1000, 5000, 0)` | 수평 95.4, \|Y\| 2.8 | ✅ 정규화·Y 제거 |
| 쿨타임 중 재요청 | 수평 0.0, 서버 로그 없음 | ✅ 거절 |
| `NaN` 벡터 | 수평 95.6 (정면으로 대체) | ✅ 방어 |
| `Judge` 중 대시 | 수평 0.0, 로그 없음 | ✅ 상태 게이트 |
| 대상 없는 밀치기 3회 | `[Ability] 밀치기` 로그 없음 | ✅ 헛손질은 미소모 |

`Config.Debug.VerboseLogging` 이 켜져 있으면 성공한 사용만 `[Ability] 대시 / 밀치기` 로 찍힌다.
**거절은 로그가 없다** — 로그가 안 보이면 거절된 것이다.

### 2인 테스트 (넉백)

넉백은 혼자서는 확인할 수 없다. Studio **Test → Clients and Servers → 2 Players** 로 띄우고,
한쪽이 다른 쪽 정면 12 studs 안에서 `F`.

* 양쪽 화면에서 **같은 방향으로** 밀려야 한다. 한쪽에서만 밀리면 소유권 처리(§5)를 의심하라.
* 배지의 잔여 횟수가 3 → 2 로 줄어야 한다. 4회째에는 `Notify` 가 뜬다.
* 사거리 밖·등 뒤에서는 아무 일도 없어야 한다(횟수도 그대로).

### ⚠ Studio 검증에서 두 번 속기 쉬운 것

1. **명령 바/실행 도구는 모듈 캐시가 따로다.** 거기서 `require(...SessionService)` 하면
   실행 중인 것이 아니라 **새 인스턴스**가 나온다. `alive=false, push=3` 같은 초기값이
   보이면 그건 진짜 상태가 아니다. 서버 상태는 **콘솔 로그**로 확인하라.
2. **창이 포커스를 잃으면 `RenderStepped` 가 멈춘다.** 배지가 안 변하고 HUD 타이머까지
   같이 얼어 있으면 코드가 아니라 렌더링이 멈춘 것이다. 둘 중 하나만 얼었을 때가 진짜 버그다.

---

## 10. 불변 조건 (깨면 게임이 망가진다)

1. **클라이언트는 요청만 보낸다.** 대상·거리·쿨타임을 클라이언트가 정하는 순간 끝이다.
2. **대시는 수평 전용이다.** Y 를 남기면 비행이고, 비행이면 벽 위다.
3. **대시가 벽을 통과하게 만들지 마라.** 벽 충돌과 `shoveTrapped`(round-loop.md §5)가 이긴다.
4. **능력은 `Countdown`/`WallRush` 에서만 돈다.** 관전자에게 열어 주면 유리 바닥을 벗어난다.
5. **밀치기 횟수는 게임 단위다.** 채워지는 곳은 `SessionService.reset()` 하나뿐이다.
6. **헛손질은 소모하지 않는다.**
7. **넉백 뒤 소유권을 반드시 돌려준다.**
8. **`CurveAudit` 의 횡단 시간은 걷는 속도다.** 영원히.
9. **연출은 아무것도 밀지 않는다.** 대시 트레일·밀치기 이펙트를 넣더라도 로컬 전용이고
   `CanCollide`/`CanQuery`/`CanTouch` 를 전부 끈다([round-loop.md §5-1](round-loop.md)).

---

## 11. 다음 Phase 가 건드릴 곳

| Phase | 무엇을 | 상태 |
|---|---|---|
| 6 | `ownsPushSkill()` 을 DataStore 조회로 교체하고 `Config.Debug.GrantPushSkill` 제거. 상점에서 500코인 구매 | |
| 7 | 부활권. 세션의 `revivesLeft` 가 이미 자리를 잡고 있다 | |
| 8 | 대시·밀치기 사운드와 로컬 이펙트(불변 조건 9를 지킬 것) | |

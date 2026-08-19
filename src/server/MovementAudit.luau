--!strict
--[[
	MovementAudit — 대시·밀치기 수치를 맵 기하와 대조해 부팅 때 한 번 검산한다. (Phase 5)

	★ 여기에도 수치가 없다 (CurveAudit 과 같은 성격이다)
	  값은 전부 Config 에 있고 거리는 MapLayout 이 파생시킨다. 이 모듈은 서로를 모르는
	  두 표 — 능력 수치(Config.Movement/Config.Push)와 맵 치수(Config.Map) — 를 겹쳐 보고
	  위험한 조합을 부팅 로그 한 줄로 보이게 만든다.

	★ 왜 CurveAudit 에 넣지 않았는가
	  CurveAudit 의 여유시간은 '걷는 속도만' 가정한다. 대시는 쿨타임이 있어 매 라운드
	  보장되지 않으므로 대시를 전제로 커브를 조이면 쿨타임이 도는 라운드에서 아무도 못
	  건넌다(docs/difficulty-curve.md §2). 그 파일에 대시 수치를 들여놓으면 언젠가
	  누군가 그걸 여유시간 계산에 넣는다. 그래서 형제 모듈로 떼어 놓았다.
	  ★ CurveAudit 의 횡단 시간은 앞으로도 걷는 속도다 ★

	★ 여기서 잡는 것은 '조합'이다
	  대시 속도만 봐서는 아무 문제가 없다. 대시 이동거리가 레인 폭을 넘거나 스폰밴드
	  인셋을 넘는 순간 게임 규칙이 조용히 무너지는데, 증상은 "왜 다들 문제를 안 읽지"
	  같은 형태로 한참 뒤에야 보인다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapLayout = require(Shared:WaitForChild("MapLayout"))

local MovementAudit = {}

--- 대시 한 번의 이동거리. 세 수치 중 하나만 바뀌어도 이 값이 움직인다.
local function dashDistance(): number
	return Config.Movement.DashSpeed * Config.Movement.DashDuration
end

--- 스폰 가능한 가장 뒤쪽 지점에서 레인의 열린 -Z 끝단까지의 거리.
--- ★ -Z 끝은 의도적으로 막혀 있지 않다 ★ 오답 구역 플레이어를 밀어내는 출구이므로
---   막을 수 없고, 그래서 뒤로 대시하면 그대로 나간다.
local function backEdgeDistance(): number
	return Config.Map.SpawnBandInset + Config.Map.SpawnEdgeMargin
end

--- 반대편 레인까지 걸어서 건너가는 시간 (CurveAudit 과 같은 정의).
local function walkCrossTime(): number
	return MapLayout.LaneCrossDistance / Config.Movement.WalkSpeed
end

--- 대시를 한 번 섞어 건너가는 시간. 참고용이며 커브 계산에는 절대 쓰지 않는다.
local function dashCrossTime(): number
	local distance = MapLayout.LaneCrossDistance
	local dash = dashDistance()
	if dash >= distance then
		-- 대시만으로 도착하는 경우. 남는 거리가 없으므로 이동한 비율만큼의 시간이다.
		return Config.Movement.DashDuration * (distance / dash)
	end
	return Config.Movement.DashDuration + (distance - dash) / Config.Movement.WalkSpeed
end

--- 마지막 라운드에서 한 라운드 동안 실제로 움직일 수 있는 시간.
--- 제한시간이 끝나도 벽이 도착할 때까지는 계속 움직일 수 있다(round-loop.md §3).
local function lastRoundActionTime(): number
	local round = Config.Round.MaxRounds
	return Config.getCountdown(round) + MapLayout.WallReachDistance / Config.getWallSpeed(round)
end

--- 능력 수치를 검산하고 경고 건수를 반환한다.
function MovementAudit.report(): number
	local warnings = 0
	local dash = dashDistance()
	local lane = MapLayout.LaneCrossDistance

	-- ★ %d 가 아니라 %.0f/%.1f 로 찍는다. Config 를 손대다 값이 소수가 되는 순간
	--   %d 는 "no integer representation" 으로 터지는데, 하필 그게 검산기라 부팅이 죽는다.
	print(
		("[MovementAudit] 대시 %.1f studs (%.0f studs/s × %.2fs, 쿨타임 %.1fs) | 레인 횡단 걷기 %.2fs → 대시 %.2fs"):format(
			dash,
			Config.Movement.DashSpeed,
			Config.Movement.DashDuration,
			Config.Movement.DashCooldown,
			walkCrossTime(),
			dashCrossTime()
		)
	)

	-- ① 대시 한 번에 반대 레인 착지 = 문제를 안 읽어도 되는 게임
	--    벽이 부서지는 쪽을 보고 나서 출발해도 늦지 않게 되면 코어 루프가 통째로 무너진다.
	if dash >= lane then
		warn(
			("[MovementAudit] 대시 %.1f studs ≥ 레인 폭 %.0f studs — 대시 한 번에 반대 레인에 착지한다. 문제를 안 읽고 벽이 부서지는 쪽을 보고 달려도 이긴다. Movement.DashSpeed 또는 DashDuration 을 줄일 것."):format(
				dash,
				lane
			)
		)
		warnings += 1
	end

	-- ② 스폰선에서 뒤로 대시 한 번 = 즉사
	--    방향키 없이 누르면 바라보는 방향(+Z)으로 나가므로 사고는 드물지만, 뒤로 물러서려던
	--    입력이 그대로 낙하가 된다. 여유가 0 에 가까워지면 조작 실수가 곧 탈락이다.
	local backEdge = backEdgeDistance()
	if dash >= backEdge then
		warn(
			("[MovementAudit] 대시 %.1f studs ≥ 스폰선 뒤 여유 %.0f studs — 스폰 직후 뒤로 대시하면 열린 -Z 끝단 밖으로 나가 즉사한다. Map.SpawnBandInset 을 키우거나 대시 거리를 줄일 것."):format(
				dash,
				backEdge
			)
		)
		warnings += 1
	end

	-- ③ 밀치기가 옆 레인까지 닿으면 "정답 구역에 서 있으면 안전하다"가 깨진다
	if Config.Push.Range >= lane then
		warn(
			("[MovementAudit] 밀치기 사거리 %.0f studs ≥ 레인 폭 %.0f studs — 옆 레인의 정답 구역 플레이어까지 밀 수 있다. Push.Range 를 줄일 것."):format(
				Config.Push.Range,
				lane
			)
		)
		warnings += 1
	end

	-- ④ 원뿔 각도. 0 이하면 아무도 못 맞고, 180 이상이면 뒤에 있는 사람까지 맞는다.
	if Config.Push.ConeAngle <= 0 or Config.Push.ConeAngle >= 360 then
		warn(
			("[MovementAudit] 밀치기 원뿔 %.0f° — 전방 판정이 성립하지 않는다. Push.ConeAngle 은 0 초과 360 미만이어야 한다."):format(
				Config.Push.ConeAngle
			)
		)
		warnings += 1
	elseif Config.Push.ConeAngle >= 180 then
		warn(
			("[MovementAudit] 밀치기 원뿔 %.0f° — 반각이 90° 이상이라 옆·뒤에 있는 사람도 맞는다. '전방' 스킬이 아니게 된다."):format(
				Config.Push.ConeAngle
			)
		)
		warnings += 1
	end

	-- ⑤ 후반 라운드에서 대시가 사실상 사라지는지. 치명적이지는 않지만 체감이 크게 달라진다.
	local actionTime = lastRoundActionTime()
	if Config.Movement.DashCooldown > actionTime then
		print(
			("[MovementAudit]  참고: R%d 의 행동 시간 %.2fs < 대시 쿨타임 %.1fs — 후반에는 라운드당 대시 1회다."):format(
				Config.Round.MaxRounds,
				actionTime,
				Config.Movement.DashCooldown
			)
		)
	end

	-- ⑥ 밀치기가 꺼져 있는 상태(횟수 0)는 버그가 아니라 설정이지만, 조용하면 오해를 부른다.
	if Config.Push.MaxUsesPerGame <= 0 then
		print("[MovementAudit]  참고: Push.MaxUsesPerGame 이 0 이라 밀치기가 비활성이다.")
	end

	print(
		("[MovementAudit] 스폰선 뒤 여유 %.0f studs (인셋 %.0f + 가장자리 %.0f) | 밀치기 사거리 %.0f / 레인 폭 %.0f · 원뿔 %.0f° · %d회 %s | 경고 %d건"):format(
			backEdge,
			Config.Map.SpawnBandInset,
			Config.Map.SpawnEdgeMargin,
			Config.Push.Range,
			lane,
			Config.Push.ConeAngle,
			Config.Push.MaxUsesPerGame,
			if Config.Debug.GrantPushSkill then "(개발용 전원 지급)" else "(보유자만)",
			warnings
		)
	)

	return warnings
end

return MovementAudit

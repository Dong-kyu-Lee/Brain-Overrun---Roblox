--!strict
--[[
	AbilityService — 대시와 밀치기의 판정·물리. 전부 서버. (Phase 5)

	★ 클라이언트는 "요청"만 보낸다 (README 규약 2)
	  DashRequest 가 싣고 오는 것은 방향 하나뿐이고, PushRequest 는 아무것도 싣지 않는다.
	  쿨타임·남은 횟수·사거리·각도·라운드 상태는 전부 여기서 다시 판정한다. 클라이언트가
	  보낸 값 중 그대로 믿는 것은 하나도 없다 — 방향 벡터조차 평탄화하고 정규화해서 쓴다.

	★ 왜 두 능력이 한 모듈인가
	  대시와 밀치기는 "지금 이 사람이 능력을 쓸 수 있는 상태인가"를 100% 공유한다
	  (생존 중 + Countdown/WallRush + 캐릭터 존재 + 요청 간격). 그 게이트가 두 파일로
	  갈라지면 한쪽만 고치는 날이 온다. 입력은 키도 의미도 달라 클라이언트만 나눠 뒀다.

	★ 능력이 도는 시간대는 Countdown 과 WallRush 뿐이다
	  Judge/Intermission/GameOver 는 판정이 끝난 뒤라 움직여 봐야 의미가 없고, 무엇보다
	  관전자가 대시로 유리 바닥을 벗어나는 길을 막아야 한다. Lobby 도 같은 이유로 막는다.

	★ 네트워크 소유권을 다루는 방향이 둘이 서로 반대다 — 의도된 것이다
	  · 대시  : 소유권을 건드리지 않는다. 쓰는 사람이 곧 자기 캐릭터의 주인이라
	            LinearVelocity 가 그 클라이언트에서 즉시 시뮬레이션돼 반응이 빠르다.
	  · 밀치기: 피해자의 소유권을 잠깐 서버로 가져온다. 안 그러면 서버가 준 임펄스가
	            피해자 클라이언트의 복제 상태에 덮여 조용히 사라진다.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Arena = require(script.Parent.Arena)
local RoundService = require(script.Parent.RoundService)
local SessionService = require(script.Parent.SessionService)

local AbilityService = {}

--- 능력을 쓸 수 있는 라운드 상태. 여기 없는 상태에서 온 요청은 조용히 버린다.
local ABILITY_STATES = {
	Countdown = true,
	WallRush = true,
}

local DASH_VELOCITY_NAME = "BO_DashVelocity"
local DASH_ATTACHMENT_NAME = "BO_DashAttachment"

--- 마지막 '요청' 시각. 성공/실패와 무관하게 찍힌다 — 쿨타임이 아니라 통신 상한이다.
local lastRequestAt: { [Player]: { dash: number, push: number } } = {}
--- 마지막 실패 알림 시각. 같은 사유를 초당 몇 번씩 띄우지 않기 위한 것이다.
local lastNotifyAt: { [Player]: number } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function flatten(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

--- 실패 사유를 알린다. 쿨타임 간격으로 묶어 스팸을 막는다.
--- ★ 쿨타임 때문에 거절된 요청은 아예 알리지 않는다 ★ 연타할 때마다 알림이 뜨면
---   그게 더 시끄럽고, 상단 밴드의 알림 줄이 라운드 내내 튄다.
local function notifyFailure(player: Player, message: string)
	local at = now()
	if at - (lastNotifyAt[player] or 0) < Config.Push.Cooldown then
		return
	end
	lastNotifyAt[player] = at
	Remotes.event("Notify"):FireClient(player, message, "warn")
end

--- 이 플레이어의 요청을 지금 받아도 되는가 (통신 상한).
local function acceptRequest(player: Player, kind: string): boolean
	local record = lastRequestAt[player]
	if not record then
		record = { dash = 0, push = 0 }
		lastRequestAt[player] = record
	end

	local at = now()
	if at - record[kind] < Config.Input.MinRequestInterval then
		return false
	end
	record[kind] = at
	return true
end

--- 지금 능력을 쓸 수 있는 상태면 루트 파트를, 아니면 nil.
--- 여기서 걸러지는 요청은 알림 없이 버린다 — 정상 플레이에서는 생기지 않고,
--- 생긴다면 그건 조작하는 쪽이 보낸 것이라 굳이 사유를 알려 줄 이유가 없다.
local function actorRoot(player: Player): BasePart?
	if not SessionService.isAlive(player) then
		return nil
	end

	local state = RoundService.getState()
	if not ABILITY_STATES[state] then
		return nil
	end

	return Arena.rootPart(player)
end

-- ─────────────────────────────────────────────
-- 대시
-- ─────────────────────────────────────────────

--- 클라이언트가 보낸 방향을 쓸 수 있는 형태로 만든다.
--- ★ Y 를 반드시 버린다 ★ 위 성분을 남기면 대시가 비행이 되고, 벽 위로 올라타거나
---   측면 벽을 넘어 맵을 벗어나는 경로가 열린다. 대시는 수평 이동 수단이다.
local function sanitizeDirection(direction: any, root: BasePart): Vector3?
	local flat = Vector3.zero

	if typeof(direction) == "Vector3" then
		local vector = direction :: Vector3
		-- NaN/무한대 차단. NaN 은 자기 자신과 같지 않다는 성질로 걸러진다.
		local finite = vector.X == vector.X
			and vector.Y == vector.Y
			and vector.Z == vector.Z
			and math.abs(vector.X) ~= math.huge
			and math.abs(vector.Y) ~= math.huge
			and math.abs(vector.Z) ~= math.huge
		if finite then
			flat = flatten(vector)
		end
	end

	-- 입력이 없거나 못 쓸 값이면 바라보는 방향으로 나간다. 요청을 버리는 것보다
	-- "눌렀는데 아무 일도 안 일어나는" 순간을 없애는 편이 낫다.
	if flat.Magnitude < 1e-3 then
		flat = flatten(root.CFrame.LookVector)
	end
	if flat.Magnitude < 1e-3 then
		return nil
	end

	-- ★ 길이는 클라이언트에게 맡기지 않는다 ★ 정규화해야 "10배짜리 방향 벡터"로
	--   대시 거리를 늘리는 조작이 통하지 않는다.
	return flat.Unit
end

--- 수평면에만 걸리는 속도 구속. 중력과 점프는 그대로 살려 둔다.
--- ★ Vector 모드로 Y 까지 고정하지 말 것 ★ 대시 중 공중부양이 되고, 그건 곧 벽 위다.
local function applyDash(root: BasePart, direction: Vector3)
	local previous = root:FindFirstChild(DASH_VELOCITY_NAME)
	if previous then
		previous:Destroy() -- 쿨타임 덕에 거의 없지만, 겹치면 두 배로 빨라진다
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = DASH_ATTACHMENT_NAME
	attachment.Parent = root

	local velocity = Instance.new("LinearVelocity")
	velocity.Name = DASH_VELOCITY_NAME
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	velocity.PrimaryTangentAxis = Vector3.xAxis
	velocity.SecondaryTangentAxis = Vector3.zAxis
	velocity.PlaneVelocity = Vector2.new(direction.X, direction.Z) * Config.Movement.DashSpeed
	-- ★ Plane 모드에도 MaxPlanarForce 같은 속성은 없다 ★ 힘 상한은 MaxForce 하나다(Studio 실측).
	velocity.ForceLimitMode = Enum.ForceLimitMode.Magnitude
	velocity.ForceLimitsEnabled = true
	velocity.MaxForce = Config.Movement.DashMaxForce
	velocity.Parent = root

	Debris:AddItem(velocity, Config.Movement.DashDuration)
	Debris:AddItem(attachment, Config.Movement.DashDuration)
end

local function onDashRequest(player: Player, direction: any)
	if not acceptRequest(player, "dash") then
		return
	end

	local root = actorRoot(player)
	if not root then
		return
	end

	local session = SessionService.get(player)
	if now() - session.lastDashAt < Config.Movement.DashCooldown then
		return -- 쿨타임 거절은 조용히. 클라이언트도 같은 값으로 스스로를 막고 있다.
	end

	local heading = sanitizeDirection(direction, root)
	if not heading then
		return
	end

	SessionService.markDash(player, now())
	applyDash(root, heading :: Vector3)

	if Config.Debug.VerboseLogging then
		print(`[Ability] 대시: {player.Name}`)
	end
end

-- ─────────────────────────────────────────────
-- 밀치기
-- ─────────────────────────────────────────────

--- 밀치기 스킬 보유 여부.
--- ★ Phase 6 이 갈아끼우는 함수는 여기 하나다 ★ 지금은 개발용 플래그를 보지만,
---   DataStore 가 붙으면 PlayerData.ownsPushSkill 을 읽게 된다. 호출부는 바뀌지 않는다.
local function ownsPushSkill(_player: Player): boolean
	return Config.Debug.GrantPushSkill
end

type Target = { player: Player, root: BasePart, direction: Vector3 }

--- 전방 원뿔 안의 생존자들. 자기 자신과 관전자는 제외된다(alivePlayers 가 이미 걸러 준다).
--- 거리는 수평으로 잰다 — 점프한 사람이 사거리에서 빠지면 판정이 운에 좌우된다.
local function findTargets(pusher: Player, root: BasePart): { Target }
	local origin = root.Position
	local facing = flatten(root.CFrame.LookVector)
	if facing.Magnitude < 1e-3 then
		return {}
	end
	facing = facing.Unit

	-- ConeAngle 은 원뿔의 '전체' 각도다. 반각과 비교해야 한다.
	local minDot = math.cos(math.rad(Config.Push.ConeAngle / 2))
	local range = Config.Push.Range
	local targets: { Target } = {}

	for _, other in SessionService.alivePlayers() do
		if other ~= pusher then
			local otherRoot = Arena.rootPart(other)
			if otherRoot then
				local offset = otherRoot.Position - origin
				local flat = flatten(offset)
				local distance = flat.Magnitude
				-- 수직 차이도 사거리로 잰다. 상공 관전장에 있는 사람이 '바로 위'에
				-- 있다는 이유로 맞는 일이 없어야 한다.
				if distance > 1e-3 and distance <= range and math.abs(offset.Y) <= range then
					local heading = flat.Unit
					if facing:Dot(heading) >= minDot then
						table.insert(targets, { player = other, root = otherRoot, direction = heading })
					end
				end
			end
		end
	end

	return targets
end

--- 넉백. Force/UpwardForce 는 '속도 증분(studs/s)' 이라 질량을 곱해 임펄스로 넣는다.
local function knockback(target: Target)
	local root = target.root
	local impulse = (target.direction * Config.Push.Force + Vector3.yAxis * Config.Push.UpwardForce)
		* root.AssemblyMass

	-- ★ 소유권을 잠깐 서버로 ★ 그러지 않으면 임펄스가 피해자 클라이언트의 복제 상태에
	--   덮여 사라진다. pcall 인 이유는 그 사이 캐릭터가 사라질 수 있어서다.
	pcall(function()
		root:SetNetworkOwner(nil)
	end)

	root:ApplyImpulse(impulse)

	task.delay(Config.Push.OwnershipHoldTime, function()
		-- 돌려주지 못하면 그 캐릭터는 계속 서버가 시뮬레이션한다 — 조작감이 눈에 띄게 무거워진다.
		if root.Parent and target.player.Parent and target.player.Character == root.Parent then
			pcall(function()
				root:SetNetworkOwner(target.player)
			end)
		end
	end)
end

local function onPushRequest(player: Player)
	if not acceptRequest(player, "push") then
		return
	end

	local root = actorRoot(player)
	if not root then
		return
	end

	if not ownsPushSkill(player) then
		notifyFailure(player, `밀치기 스킬 미보유 ({Config.Economy.PushSkillPrice} 코인)`)
		return
	end

	local session = SessionService.get(player)
	if now() - session.lastPushAt < Config.Push.Cooldown then
		return
	end
	if session.pushUsesLeft <= 0 then
		notifyFailure(player, `밀치기를 모두 썼습니다 (게임당 {Config.Push.MaxUsesPerGame}회)`)
		return
	end

	local targets = findTargets(player, root)
	if #targets == 0 then
		return -- 헛손질은 횟수를 소모하지 않는다. 게임당 3회뿐인 자원을 허공에 버리게 두지 않는다.
	end

	if not SessionService.consumePush(player, now()) then
		return -- 위에서 이미 봤지만, 횟수를 줄이는 판단의 최종 권한은 SessionService 다
	end

	for _, target in targets do
		knockback(target)
	end

	if Config.Debug.VerboseLogging then
		print(`[Ability] 밀치기: {player.Name} → {#targets}명 (남은 {SessionService.get(player).pushUsesLeft}회)`)
	end
end

-- ─────────────────────────────────────────────
-- 시작
-- ─────────────────────────────────────────────

--- SessionService.start() / Arena.start() 이후에 호출할 것.
function AbilityService.start()
	Remotes.event("DashRequest").OnServerEvent:Connect(onDashRequest)
	Remotes.event("PushRequest").OnServerEvent:Connect(onPushRequest)

	Players.PlayerRemoving:Connect(function(player)
		lastRequestAt[player] = nil
		lastNotifyAt[player] = nil
	end)
end

return AbilityService

--!strict
--[[
	Arena — 캐릭터를 맵 위에 배치하고, 맵 밖으로 떨어진 캐릭터를 탈락시킨다. (Phase 2)

	책임 경계
	  · 좌표를 "계산"하지 않는다. 전부 MapLayout 에 물어본다(docs/map-builder.md §4).
	  · 라운드 진행을 모른다. 언제 배치·탈락시킬지는 RoundService 가 정한다.
	  · 탈락 사실만 Arena.Eliminated 로 알리고, 그 뒤 처리(보상·게임 종료 판정)는 관여하지 않는다.

	★ 탈락 감지가 두 겹인 이유
	  1) KillPlane 의 Touched — 즉각적이지만 고속 낙하 시 프레임을 건너뛰면 놓칠 수 있다.
	  2) Y 좌표 폴링 백스톱 — 느리지만 절대 놓치지 않는다.
	  하나라도 놓치면 죽은 플레이어가 살아있는 것으로 집계돼 라운드가 끝나지 않는다.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapLayout = require(Shared:WaitForChild("MapLayout"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tags = require(Shared:WaitForChild("Tags"))

local SessionService = require(script.Parent.SessionService)

type Zone = "A" | "B" -- Types.luau 참조. 컨테이너를 넘는 require 는 타입이 살아남지 않는다.

local Arena = {}

local rng = Random.new()

-- 탈락 알림: (player, reason) — reason 은 "fall" | "sweep" | "died"
local eliminatedEvent = Instance.new("BindableEvent")
Arena.Eliminated = eliminatedEvent.Event

-- ─────────────────────────────────────────────
-- 캐릭터 조회 / 이동
-- ─────────────────────────────────────────────

function Arena.rootPart(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

--- 캐릭터를 순간이동시킨다. 남아 있던 속도를 지우지 않으면 도착하자마자
--- 이전 낙하 속도로 다시 튀어나가므로 반드시 함께 0 으로 만든다.
local function teleport(player: Player, cframe: CFrame): boolean
	local character = player.Character
	local root = Arena.rootPart(player)
	if not character or not root then
		return false
	end

	character:PivotTo(cframe)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

--- 라운드 시작 배치. 같은 지점에 겹치지 않도록 스폰밴드 안에서 흩어 놓는다.
function Arena.placeAtSpawn(player: Player, zone: Zone): boolean
	return teleport(player, MapLayout.spawnPointCFrame(zone, rng))
end

--- 관전장(상공 유리 바닥)으로 올려보낸다.
function Arena.sendToSpectator(player: Player): boolean
	return teleport(player, MapLayout.spectatorPointCFrame(rng))
end

--- 이 플레이어가 지금 서 있는 레인. 경기장 밖이면 nil.
function Arena.zoneOf(player: Player): Zone?
	local root = Arena.rootPart(player)
	if not root then
		return nil
	end
	return MapLayout.zoneAtPosition(root.Position)
end

-- ─────────────────────────────────────────────
-- 탈락 처리
-- ─────────────────────────────────────────────

--- 생존자를 탈락시키고 관전장으로 올린다. 이미 탈락했으면 아무것도 하지 않는다(멱등).
function Arena.eliminate(player: Player, reason: string)
	if not SessionService.isAlive(player) then
		return
	end

	SessionService.setAlive(player, false)
	Arena.sendToSpectator(player)
	Remotes.event("Notify"):FireClient(player, "탈락! 관전석에서 지켜보세요.", "warn")

	if Config.Debug.VerboseLogging then
		print(`[Arena] 탈락: {player.Name} ({reason})`)
	end

	eliminatedEvent:Fire(player, reason)
end

--- 해당 구역에 남아 있는 생존자를 전부 탈락시킨다.
--- 벽이 지나갔는데도 어떤 이유로든 오답 구역에 살아남은 케이스를 위한 안전망이다.
function Arena.eliminateZone(zone: Zone)
	for _, player in SessionService.alivePlayers() do
		if Arena.zoneOf(player) == zone then
			Arena.eliminate(player, "sweep")
		end
	end
end

local function playerFromDescendant(instance: Instance): Player?
	local character = instance:FindFirstAncestorOfClass("Model")
	while character do
		local player = Players:GetPlayerFromCharacter(character)
		if player then
			return player
		end
		character = character:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function bindKillPlane(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	part.Touched:Connect(function(hit)
		local player = playerFromDescendant(hit)
		if player then
			Arena.eliminate(player, "fall")
		end
	end)
end

-- ─────────────────────────────────────────────
-- 캐릭터 셋업
-- ─────────────────────────────────────────────

local function setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.WalkSpeed = Config.Movement.WalkSpeed
		humanoid.UseJumpPower = true
		humanoid.JumpPower = Config.Movement.JumpPower

		-- 어떤 이유로든 캐릭터가 죽으면 탈락으로 간주한다.
		-- (정상 루프에서는 낙하 중 탈락 처리 후 관전장으로 올라가므로 죽지 않는다.)
		humanoid.Died:Connect(function()
			Arena.eliminate(player, "died")
		end)
	end

	-- 리스폰 직후의 기본 위치는 LobbySpawn(관전장)이다.
	-- 생존자가 여기로 들어오는 경우는 사고이므로, 관전 상태로만 위치를 보정한다.
	if not SessionService.isAlive(player) then
		Arena.sendToSpectator(player)
	end
end

-- ─────────────────────────────────────────────
-- 시작
-- ─────────────────────────────────────────────

--- MapService.ensureReady() 가 끝난 뒤에 호출해야 한다(KillPlane 태그를 찾기 때문).
function Arena.start()
	for _, part in CollectionService:GetTagged(Tags.KillPlane) do
		bindKillPlane(part)
	end
	-- 맵을 다시 만들어도 새 KillPlane 에 자동으로 다시 붙는다.
	CollectionService:GetInstanceAddedSignal(Tags.KillPlane):Connect(bindKillPlane)

	local function onCharacter(player: Player, character: Model)
		task.defer(setupCharacter, player, character)
	end

	local function onPlayer(player: Player)
		SessionService.get(player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
		if player.Character then
			onCharacter(player, player.Character)
		end
	end

	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)

	-- 낙하 탈락 백스톱. Touched 를 놓쳐도 여기서 반드시 걸린다.
	local sinceLastCheck = 0
	RunService.Heartbeat:Connect(function(deltaTime)
		sinceLastCheck += deltaTime
		if sinceLastCheck < Config.Round.FallCheckInterval then
			return
		end
		sinceLastCheck = 0

		for _, player in SessionService.alivePlayers() do
			local root = Arena.rootPart(player)
			if root and root.Position.Y < Config.Map.FallEliminationY then
				Arena.eliminate(player, "fall")
			end
		end
	end)
end

return Arena

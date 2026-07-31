--!strict
--[[
	WallController — 파괴의 벽을 움직인다. (Phase 2)

	★ PreSimulation 에서 움직이는 이유
	  벽은 Anchored 다. 앵커된 파트가 캐릭터를 밀어내려면 물리 스텝 '이전'에 위치가
	  바뀌어 있어야 한다. Heartbeat(PostSimulation)에서 옮기면 한 프레임 늦게 반영돼
	  밀어내는 힘이 약해지고 캐릭터가 벽에 파묻힌다.

	★ 그래도 관통하면
	  프레임이 튀면 벽이 캐릭터를 지나칠 수 있다. shoveTrapped() 가 매 프레임
	  벽 안에 들어온 캐릭터를 선단면 앞으로 끌어내 이를 막는다. 물리에만 맡기면
	  랙이 걸린 플레이어가 벽을 통과해 살아남는 버그가 된다.

	★ "파괴"는 Destroy 가 아니다
	  맵은 씬에 미리 배치된 실물이다(MapService). 벽을 실제로 지우면 다음 라운드에
	  되살릴 수 없고, 손으로 꾸며 둔 벽 장식까지 함께 날아간다. 그래서 안 보이고
	  안 부딪히는 상태로 껐다 켠다. Phase 4 가 여기에 파편 연출을 얹는다.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapLayout = require(Shared:WaitForChild("MapLayout"))
local Tags = require(Shared:WaitForChild("Tags"))

local Arena = require(script.Parent.Arena)
local SessionService = require(script.Parent.SessionService)

type Zone = "A" | "B" -- Types.luau 참조

local WallController = {}

local function wallOf(zone: Zone): BasePart?
	local tag = if zone == "A" then Tags.WallA else Tags.WallB
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsA("BasePart") then
			return instance
		end
	end
	return nil
end

-- ─────────────────────────────────────────────
-- 벽에 매달린 장식 다루기
--
-- 맵을 씬에서 손으로 꾸미게 되면서 벽 파트 아래에 장식 파트가 붙는다.
-- 벽은 이 게임에서 유일하게 '움직이는' 오브젝트라, 장식을 따로 챙기지 않으면
--   · 앵커된 장식은 제자리에 남아 벽만 빠져나간다
--   · 정답 벽이 파괴될 때 장식만 공중에 떠 있게 된다
-- 두 증상 모두 조용히 생기고 눈에 띄면 이미 늦다. 그래서 여기서 함께 옮기고 함께 숨긴다.
--
-- 캐시는 서버 수명 중 처음 보는 순간에 채워진다. 그 시점은 1라운드 reset() 이고,
-- 맵은 아직 씬에 저장된 원본 그대로이므로 캐시된 값이 곧 '정상 상태'다.
-- ─────────────────────────────────────────────

type Look = { transparency: number, canCollide: boolean }

local attachedCache: { [BasePart]: { BasePart } } = {}
local offsetFromWall: { [BasePart]: CFrame } = {}
local originalLook: { [BasePart]: Look } = {}

--- 벽 아래의 장식 파트 목록(벽 자신은 제외). 맵은 런타임에 바뀌지 않으므로 한 번만 훑는다.
local function attachedParts(wall: BasePart): { BasePart }
	local cached = attachedCache[wall]
	if cached then
		return cached
	end

	local parts: { BasePart } = {}
	for _, descendant in wall:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	attachedCache[wall] = parts
	return parts
end

local function rememberLook(part: BasePart): Look
	local existing = originalLook[part]
	if existing then
		return existing
	end
	local look: Look = { transparency = part.Transparency, canCollide = part.CanCollide }
	originalLook[part] = look
	return look
end

--- 벽을 옮기고 장식을 같은 상대 위치로 따라오게 한다.
--- 장식이 앵커돼 있어도 동작한다(앵커된 파트는 부모를 따라가지 않으므로 직접 옮겨야 한다).
local function setWallCFrame(wall: BasePart, cframe: CFrame)
	for _, part in attachedParts(wall) do
		local offset = offsetFromWall[part]
		if not offset then
			offset = wall.CFrame:ToObjectSpace(part.CFrame) -- 아직 옮기기 전의 벽 기준
			offsetFromWall[part] = offset
		end
		part.CFrame = cframe * offset
	end
	wall.CFrame = cframe
end

local function setBroken(wall: BasePart, broken: boolean)
	local wallLook = rememberLook(wall)
	wall.CanCollide = if broken then false else wallLook.canCollide
	wall.CanTouch = not broken
	wall.Transparency = if broken then 1 else wallLook.transparency

	for _, part in attachedParts(wall) do
		local look = rememberLook(part)
		part.CanCollide = if broken then false else look.canCollide
		part.CanTouch = not broken
		part.Transparency = if broken then 1 else look.transparency
	end
end

--- 벽 안에 끼인 생존자를 선단면 바로 앞으로 끌어낸다(관통 방지).
--- 이미 벽보다 앞(-Z)에 있는 플레이어는 건드리지 않는다 — 물리에 맡겨야 자연스럽다.
local function shoveTrapped(zone: Zone, wall: BasePart)
	local frontZ = MapLayout.wallFrontZ(wall.Position.Z)
	local margin = Config.Map.WallShoveMargin

	for _, player in SessionService.alivePlayers() do
		local root = Arena.rootPart(player)
		if not root then
			continue
		end

		local position = root.Position
		-- 레인 밖(이미 -Z 로 밀려났거나 낙하 중)이면 벽의 관심사가 아니다.
		if MapLayout.zoneAtPosition(position) ~= zone then
			continue
		end
		if position.Z <= frontZ then
			continue
		end

		root.CFrame = root.CFrame.Rotation + Vector3.new(position.X, position.Y, frontZ - margin)
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

--- 해당 라운드의 벽 돌진 소요 시간. 상태 알림의 타이머를 미리 채우는 데도 쓴다.
function WallController.rushDuration(round: number): number
	return MapLayout.WallTravelDistance / Config.getWallSpeed(round)
end

--- 두 벽을 출발 위치로 되돌리고 파괴 상태를 해제한다.
function WallController.reset()
	for _, zone in MapLayout.Zones do
		local wall = wallOf(zone)
		if wall then
			setBroken(wall, false)
			setWallCFrame(wall, MapLayout.wallStartCFrame(zone))
		end
	end
end

--- 벽 돌진. 끝날 때까지 블로킹하므로 라운드 코루틴에서 호출한다.
--- 정답 구역 벽은 CorrectWallBreakProgress 지점에서 파괴되고 그 자리에 멈춘다.
--- 오답 구역 벽은 -Z 끝까지 밀고 나가 그 구역 플레이어를 맵 밖으로 떨어뜨린다.
function WallController.rush(correctZone: Zone, round: number)
	local duration = WallController.rushDuration(round)
	local breakAt = Config.Round.CorrectWallBreakProgress

	local walls: { [string]: BasePart } = {}
	for _, zone in MapLayout.Zones do
		local wall = wallOf(zone)
		if wall then
			walls[zone] = wall
		end
	end

	local correctBroken = false
	local elapsed = 0

	while elapsed < duration do
		local deltaTime = RunService.PreSimulation:Wait()
		elapsed = math.min(elapsed + deltaTime, duration)
		local alpha = elapsed / duration

		for _, zone in MapLayout.Zones do
			local wall = walls[zone]
			if not wall then
				continue
			end

			if zone == correctZone then
				if correctBroken then
					continue -- 파괴된 벽은 더 이상 움직이지 않는다
				end
				if alpha >= breakAt then
					correctBroken = true
					setBroken(wall, true)
					continue
				end
			end

			setWallCFrame(wall, MapLayout.wallCFrameAtProgress(zone, alpha))
			shoveTrapped(zone, wall)
		end
	end
end

return WallController

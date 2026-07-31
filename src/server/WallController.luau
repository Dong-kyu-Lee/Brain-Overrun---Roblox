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
	  맵은 부팅 때 한 번만 만든다(MapBuilder). 벽을 실제로 지우면 다음 라운드에
	  되살릴 수 없으므로, 안 보이고 안 부딪히는 상태로 껐다 켠다.
	  Phase 4 가 여기에 파편 연출을 얹는다.
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

local function setBroken(wall: BasePart, broken: boolean)
	wall.CanCollide = not broken
	wall.CanTouch = not broken
	wall.Transparency = if broken then 1 else 0
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
			wall.CFrame = MapLayout.wallStartCFrame(zone)
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

			wall.CFrame = MapLayout.wallCFrameAtProgress(zone, alpha)
			shoveTrapped(zone, wall)
		end
	end
end

return WallController

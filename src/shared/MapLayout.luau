--!strict
--[[
	MapLayout — Config.Map 수치로부터 맵의 모든 좌표/크기를 계산한다.

	★ 좌표계 규약
	  · X축 = 레인 폭 방향. A레인이 -X, B레인이 +X.
	  · Z축 = 레인 길이 방향이자 벽의 진행 방향.
	          벽은 +Z(먼 쪽) 에서 출발해 -Z(스폰 쪽) 로 돌진하며, 오답 구역 플레이어를
	          -Z 끝단 밖으로 밀어낸다. 따라서 -Z 끝은 절대 막지 않는다.
	  · Y축 = 높이. Config.Map.FloorY 는 메인 바닥의 '윗면' 높이다(중심이 아님).

	맵을 만드는 MapBuilder 와 벽을 움직이는 Phase 2 로직이 같은 값을 쓰도록
	좌표 계산은 전부 여기에만 둔다. 여기에도 하드코딩 숫자는 없다 — 전부 Config 파생값이다.
]]

-- 같은 폴더(ReplicatedStorage.Shared) 안이므로 script.Parent 로 바로 참조한다.
-- WaitForChild 와 달리 타입 분석기가 경로를 따라갈 수 있어 타입이 살아있다.
local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

export type Zone = Types.Zone

local M = Config.Map

local MapLayout = {}

--- 두 레인을 합친 전체 맵 폭
MapLayout.MapWidth = M.LaneWidth * 2 + M.LaneGap
MapLayout.MapLength = M.LaneLength

--- 순회용 존 목록
MapLayout.Zones = { "A", "B" } :: { Zone }

--- 존 중심의 X 좌표. A는 음수, B는 양수.
function MapLayout.laneCenterX(zone: Zone): number
	local offset = (M.LaneWidth + M.LaneGap) / 2
	return if zone == "A" then -offset else offset
end

-- ─────────────────────────────────────────────
-- 레인 바닥 (SurfaceGui 를 붙일 거대 디스플레이)
-- ─────────────────────────────────────────────
MapLayout.FloorSize = Vector3.new(M.LaneWidth, M.FloorThickness, M.LaneLength)

function MapLayout.floorCFrame(zone: Zone): CFrame
	-- FloorY 는 윗면이므로 중심은 두께의 절반만큼 아래.
	return CFrame.new(MapLayout.laneCenterX(zone), M.FloorY - M.FloorThickness / 2, 0)
end

-- ─────────────────────────────────────────────
-- 파괴의 벽
-- ─────────────────────────────────────────────
MapLayout.WallSize = Vector3.new(M.LaneWidth, M.WallHeight, M.WallThickness)

--- 출발 지점: 바닥 +Z 끝단에 딱 붙는다(= 그 방향 통로를 막는다).
MapLayout.WallStartZ = M.LaneLength / 2 + M.WallThickness / 2
--- 종료 지점: 바닥 -Z 끝단을 완전히 통과한 위치.
MapLayout.WallEndZ = -MapLayout.WallStartZ
--- 벽이 한 라운드에 이동하는 총 거리 (Config.getWallSpeed 로 나누면 소요 시간)
MapLayout.WallTravelDistance = MapLayout.WallStartZ - MapLayout.WallEndZ

function MapLayout.wallCFrameAtZ(zone: Zone, z: number): CFrame
	return CFrame.new(MapLayout.laneCenterX(zone), M.FloorY + M.WallHeight / 2, z)
end

function MapLayout.wallStartCFrame(zone: Zone): CFrame
	return MapLayout.wallCFrameAtZ(zone, MapLayout.WallStartZ)
end

function MapLayout.wallEndCFrame(zone: Zone): CFrame
	return MapLayout.wallCFrameAtZ(zone, MapLayout.WallEndZ)
end

--- 진행률 alpha(0=출발, 1=종료) 에 해당하는 벽 CFrame
function MapLayout.wallCFrameAtProgress(zone: Zone, alpha: number): CFrame
	local z = MapLayout.WallStartZ + (MapLayout.WallEndZ - MapLayout.WallStartZ) * math.clamp(alpha, 0, 1)
	return MapLayout.wallCFrameAtZ(zone, z)
end

-- ─────────────────────────────────────────────
-- 스폰 영역
-- ─────────────────────────────────────────────
MapLayout.SpawnZoneSize = Vector3.new(M.LaneWidth, M.SpawnBandHeight, M.SpawnBandDepth)
MapLayout.SpawnZoneCenterZ = -M.LaneLength / 2 + M.SpawnBandInset + M.SpawnBandDepth / 2

function MapLayout.spawnZoneCFrame(zone: Zone): CFrame
	return CFrame.new(
		MapLayout.laneCenterX(zone),
		M.FloorY + M.SpawnBandHeight / 2,
		MapLayout.SpawnZoneCenterZ
	)
end

-- ─────────────────────────────────────────────
-- 관전장 (메인 맵 상공의 투명 유리 바닥)
-- ─────────────────────────────────────────────
MapLayout.SpectatorY = M.FloorY + M.SpectatorHeight
MapLayout.SpectatorFloorSize = Vector3.new(
	MapLayout.MapWidth + M.SpectatorMargin * 2,
	M.FloorThickness,
	M.LaneLength + M.SpectatorMargin * 2
)

function MapLayout.spectatorFloorCFrame(): CFrame
	return CFrame.new(0, MapLayout.SpectatorY - M.FloorThickness / 2, 0)
end

export type BoxSpec = { size: Vector3, cframe: CFrame }

--- 관전자가 떨어지지 않도록 관전장 사방을 두르는 난간 4개
function MapLayout.spectatorRails(): { BoxSpec }
	local floor = MapLayout.SpectatorFloorSize
	local h = M.SpectatorRailHeight
	local t = M.SideBarrierThickness
	local y = MapLayout.SpectatorY + h / 2
	local halfX = floor.X / 2 + t / 2
	local halfZ = floor.Z / 2 + t / 2

	return {
		{ size = Vector3.new(t, h, floor.Z + t * 2), cframe = CFrame.new(-halfX, y, 0) },
		{ size = Vector3.new(t, h, floor.Z + t * 2), cframe = CFrame.new(halfX, y, 0) },
		{ size = Vector3.new(floor.X, h, t), cframe = CFrame.new(0, y, -halfZ) },
		{ size = Vector3.new(floor.X, h, t), cframe = CFrame.new(0, y, halfZ) },
	}
end

-- ─────────────────────────────────────────────
-- 경계 / 판정
-- ─────────────────────────────────────────────

--- 레인 좌우 바깥으로 실수로 떨어지는 것만 막는다. ±X 두 장뿐이며 -Z 출구는 열어 둔다.
function MapLayout.sideBarriers(): { BoxSpec }
	local h = M.SideBarrierHeight
	local t = M.SideBarrierThickness
	local x = MapLayout.MapWidth / 2 + t / 2
	local y = M.FloorY + h / 2

	return {
		{ size = Vector3.new(t, h, M.LaneLength), cframe = CFrame.new(-x, y, 0) },
		{ size = Vector3.new(t, h, M.LaneLength), cframe = CFrame.new(x, y, 0) },
	}
end

MapLayout.KillPlaneSize = Vector3.new(
	MapLayout.MapWidth + M.KillPlanePadding,
	M.FloorThickness,
	M.LaneLength + M.KillPlanePadding
)

function MapLayout.killPlaneCFrame(): CFrame
	return CFrame.new(0, M.KillPlaneY, 0)
end

return MapLayout

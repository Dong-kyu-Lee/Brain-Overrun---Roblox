--!strict
--[[
	MapLayout — Config.Map 수치로부터 맵의 모든 좌표/크기를 계산한다.

	★ 좌표계 규약
	  · X축 = 레인 폭 방향. A레인이 +X, B레인이 -X.
	          ★ 기준은 좌표 부호가 아니라 '플레이어가 보는 좌우'다. 벽이 오는 +Z 를 바라보면
	            Roblox 의 RightVector 가 -X 라서 +X 가 왼쪽에 보인다. 그래서 A가 왼쪽이다.
	            존↔X 대응은 LeftZone 한 곳에서만 정한다(§laneCenterX / zoneAtPosition).
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

--- 벽이 오는 +Z 를 바라봤을 때 '왼쪽'에 보이는 존.
--- +Z 를 보면 RightVector 가 -X 이므로 왼쪽 = +X 다. 즉 LeftZone 이 +X 레인이다.
--- ★ 좌우를 바꾸고 싶으면 이 한 줄만 고친다. laneCenterX 와 zoneAtPosition 이 둘 다
---   이 값에서 파생되므로 배치와 판정이 어긋날 수 없다. (고친 뒤 MapBuilder.align() 실행)
MapLayout.LeftZone = "A" :: Zone

--- 존 중심의 X 좌표. LeftZone 이 양수(+X = 화면 왼쪽), 반대편이 음수.
function MapLayout.laneCenterX(zone: Zone): number
	local offset = (M.LaneWidth + M.LaneGap) / 2
	return if zone == MapLayout.LeftZone then offset else -offset
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

--- 벽의 선단면(-Z 쪽 면) Z 좌표. 이 값보다 Z 가 큰 캐릭터는 벽 안에 끼어 있는 것이다.
function MapLayout.wallFrontZ(wallCenterZ: number): number
	return wallCenterZ - M.WallThickness / 2
end

--- 벽의 윗면 높이. 공중 보드가 이 위로 올라와야 벽에 가리지 않는다.
--- ★ 두 레인의 벽을 합치면 맵 폭 전체(X = -40 ~ +40)를 덮는다. 즉 X=0 에 세운 보드는
---   '두 벽 사이로 비켜갈' 수 없다 — 반드시 높이로 피해야 한다.
MapLayout.WallTopY = M.FloorY + M.WallHeight

-- ─────────────────────────────────────────────
-- 공중 문제 보드 (Phase 3 — BO_QuestionBoard)
--
-- 두 레인 중앙(X=0) 상공, 벽 출발선 바깥(+Z)에 세운다. 이미지 본문 문제의 주 표시 장치다.
--
-- ★ 왜 레인 안이 아니라 '벽 뒤'인가
--   스폰(Z≈-65)에서 보드까지 거리가 멀수록 올려다보는 각이 작아진다. 보드는 벽 높이(40)를
--   넘겨야 하는데, 레인 한가운데(Z=0)에 두면 올려다보는 각이 약 40° 라 바닥 선택지를
--   보는 시선과 정면으로 충돌한다. 벽 뒤(Z≈127)로 밀면 약 16° 가 되어 두 시선이 겹친다.
--   경기장 끝의 대형 스코어보드와 같은 배치다.
-- ─────────────────────────────────────────────
MapLayout.QuestionBoardSize = Vector3.new(MapLayout.MapWidth, M.QuestionBoardHeight, M.QuestionBoardThickness)
MapLayout.QuestionBoardCenterY = M.QuestionBoardBottomY + M.QuestionBoardHeight / 2
MapLayout.QuestionBoardCenterZ = MapLayout.WallStartZ
	+ M.WallThickness / 2
	+ M.QuestionBoardGap
	+ M.QuestionBoardThickness / 2

--- 보드는 회전하지 않는다. Roblox 의 Front 면 법선이 -Z 라서, 그대로 두면 스폰(-Z)을 향한다.
function MapLayout.questionBoardCFrame(): CFrame
	return CFrame.new(0, MapLayout.QuestionBoardCenterY, MapLayout.QuestionBoardCenterZ)
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

--- 스폰밴드 안의 무작위 배치 지점. 캐릭터는 벽이 오는 방향(+Z)을 바라본다.
--- 여러 명을 한 점에 텔레포트하면 서로 밀려 튕겨나가므로 반드시 흩어 놓아야 한다.
function MapLayout.spawnPointCFrame(zone: Zone, rng: Random): CFrame
	local half = MapLayout.SpawnZoneSize / 2
	local margin = M.SpawnEdgeMargin
	local center = MapLayout.spawnZoneCFrame(zone).Position

	local position = Vector3.new(
		center.X + rng:NextNumber(-1, 1) * math.max(half.X - margin, 0),
		M.FloorY + M.CharacterSpawnHeight,
		center.Z + rng:NextNumber(-1, 1) * math.max(half.Z - margin, 0)
	)
	return CFrame.lookAt(position, position + Vector3.zAxis)
end

-- ─────────────────────────────────────────────
-- 바닥 스크린 캔버스 (Phase 3)
--
-- ★ 아래는 Studio 에서 실측한 규약이다. 추측하지 말 것 — 직관과 다르다.
--
--   바닥 파트(40 × 220) Top 면 SurfaceGui 의 캔버스는 1760 × 320 px 다. 즉
--     캔버스 가로(X) = 레인 '길이' 방향(월드 Z)   ← 긴 쪽
--     캔버스 세로(Y) = 레인 '폭' 방향(월드 X)
--     캔버스 x = 0 이 +Z 끝(벽 쪽), x = 1 이 -Z 끝(스폰 쪽)
--
--   그래서 글자를 그대로 놓으면 레인을 따라 옆으로 눕는다. 플레이어가 +Z 를 보며 읽으려면
--   라벨을 -90° 돌려야 한다 (Config.Theme.Screen.LabelRotation — 이 값도 실측했다).
--
--   돌린 라벨은 가로·세로가 맞바뀐다. 그래서 아래 함수들은 '회전 전' 크기를 돌려주되,
--   회전 후에  가로 = 레인 폭 전체,  세로 = 원하는 레인 방향 깊이  가 되도록 미리 뒤집어 뒀다.
--
-- 호출부에서 Z↔캔버스 산술을 하지 말 것 — 규약이 바뀌면 여기만 고치면 되도록 모아 뒀다.
-- ─────────────────────────────────────────────

--- 회전된 라벨 하나의 배치. width/height 는 '회전 전' 스케일이다.
export type ScreenBand = {
	centerX: number, -- 캔버스 가로 중심(0~1). AnchorPoint (0.5, 0.5) 로 여기에 놓는다.
	width: number, -- 회전 전 Size.X.Scale → 회전 후 레인 폭을 덮는다
	height: number, -- 회전 전 Size.Y.Scale → 회전 후 레인 방향 깊이가 된다
}

--- 레인 Z 좌표 → 캔버스 가로 스케일 (0 = +Z 끝, 1 = -Z 끝)
function MapLayout.floorCanvasX(z: number): number
	return (M.LaneLength / 2 - z) / M.LaneLength
end

--- 레인 위 Z 지점을 중심으로, 깊이 depth 만큼을 쓰는 라벨의 배치
local function screenBand(centerZ: number, depth: number): ScreenBand
	return {
		centerX = MapLayout.floorCanvasX(centerZ),
		width = M.LaneWidth / M.LaneLength, -- 회전 후 레인 폭(40 studs)을 꽉 채운다
		height = depth / M.LaneWidth, -- 회전 후 레인 방향 깊이(studs)가 된다. 1 을 넘어도 정상.
	}
end

--- 선택지(텍스트 또는 이미지) 배치
function MapLayout.answerBand(): ScreenBand
	return screenBand(M.AnswerBandCenterZ, M.AnswerBandDepth)
end

--- 존 이름(A/B) 표기 배치. 스폰 지점 발밑이다.
function MapLayout.zoneLabelBand(): ScreenBand
	return screenBand(MapLayout.SpawnZoneCenterZ, M.ZoneLabelDepth)
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

--- 바닥 스크린이 보여야 하는 최대 거리 (SurfaceGui.MaxDistance).
--- 최악의 시야는 관전장 한쪽 구석에서 반대편 레인 끝을 내려다보는 경우다. 카메라는 캐릭터보다
--- 뒤에 있으므로 그 대각선에 Theme.Screen.ViewDistanceSlack 배의 여유를 둔다.
--- ★ 기본값(1000)에 맡기지 않는 이유: 맵이 커지면 조용히 스크린이 사라진다.
MapLayout.ScreenViewDistance = Vector3.new(
	MapLayout.SpectatorFloorSize.X,
	M.SpectatorHeight,
	MapLayout.SpectatorFloorSize.Z
).Magnitude * Config.Theme.Screen.ViewDistanceSlack

--- 관전장 유리 바닥 위의 무작위 배치 지점. 탈락자 텔레포트에 쓴다.
function MapLayout.spectatorPointCFrame(rng: Random): CFrame
	local half = MapLayout.SpectatorFloorSize / 2
	local margin = M.SpectatorEdgeMargin

	local position = Vector3.new(
		rng:NextNumber(-1, 1) * math.max(half.X - margin, 0),
		MapLayout.SpectatorY + M.CharacterSpawnHeight,
		rng:NextNumber(-1, 1) * math.max(half.Z - margin, 0)
	)
	return CFrame.lookAt(position, position + Vector3.zAxis)
end

--- 로비 SpawnLocation. 접속 직후·리스폰 직후의 기본 위치를 관전장으로 두어
--- 진행 중인 게임에 난입하지 않고 구경하다가 다음 게임에 참가하게 한다.
MapLayout.LobbySpawnSize = Vector3.new(M.LobbySpawnSize, 1, M.LobbySpawnSize)

function MapLayout.lobbySpawnCFrame(): CFrame
	local position = Vector3.new(0, MapLayout.SpectatorY + MapLayout.LobbySpawnSize.Y / 2, MapLayout.SpawnZoneCenterZ)
	return CFrame.lookAt(position, position + Vector3.zAxis)
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

--- 이 위치가 어느 레인 위인가. 경기장 밖(-Z 로 밀려났거나 낙하 중)이면 nil.
--- Y 는 보지 않는다 — 관전장에 있는 탈락자도 X/Z 만 보면 레인 위에 있기 때문에,
--- 호출부에서 반드시 "생존자만" 대상으로 물어야 한다.
function MapLayout.zoneAtPosition(position: Vector3): Zone?
	if math.abs(position.Z) > M.LaneLength / 2 then
		return nil
	end
	local x = position.X
	if math.abs(x) > MapLayout.MapWidth / 2 then
		return nil
	end
	if math.abs(x) < M.LaneGap / 2 then
		return nil -- 두 레인 사이의 틈 (LaneGap = 0 이면 발생하지 않음)
	end
	-- laneCenterX 와 같은 근원(LeftZone)에서 파생시킨다.
	-- 여기에 "A"/"B" 를 직접 적으면 배치는 바뀌었는데 판정만 옛 좌우로 남는 사고가 난다.
	return if x > 0 then MapLayout.LeftZone else MapLayout.oppositeZone(MapLayout.LeftZone)
end

--- 정답 구역의 반대편
function MapLayout.oppositeZone(zone: Zone): Zone
	return if zone == "A" then "B" else "A"
end

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

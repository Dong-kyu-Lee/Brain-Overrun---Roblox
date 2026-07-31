--!strict
--[[
	MapBuilder — 맵 전체를 코드로 생성한다. (Phase 1)

	README 규약 4: 맵은 .rbxl 에 저장하지 않고 매번 여기서 만든다.
	README 규약 3: 만든 오브젝트는 전부 Tags.luau 의 태그를 붙여서, 이후 로직이
	               이름/경로가 아닌 태그로 찾을 수 있게 한다.

	build() 는 멱등이다 — 다시 호출하면 이전 맵을 지우고 새로 만든다.

	생성물 (Workspace.Map)
	  Lanes/      ZoneFloorA·B      바닥 겸 선택지 디스플레이 (Phase 3 에서 SurfaceGui 부착)
	              SpawnZoneA·B      라운드 시작 스폰 영역 (충돌 없는 마커 볼륨)
	  Walls/      WallA·B           파괴의 벽. 배치만 하고 이동은 WallController(Phase 2).
	  Spectator/  SpectatorFloor    상공 투명 유리 관전장 + 난간
	              LobbySpawn        접속/리스폰 기본 위치 (관전장 위)
	  Bounds/     SideBarrier       좌우 추락 방지 (-Z 출구는 열려 있음)
	              KillPlane         낙하 탈락 판정면
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapLayout = require(Shared:WaitForChild("MapLayout"))
local Tags = require(Shared:WaitForChild("Tags"))

local Theme = Config.Theme

local ROOT_NAME = "Map"

local MapBuilder = {}

-- ─────────────────────────────────────────────
-- 내부 헬퍼
-- ─────────────────────────────────────────────

type PartSpec = {
	name: string,
	size: Vector3,
	cframe: CFrame,
	parent: Instance,

	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
	canCollide: boolean?,
	castShadow: boolean?,
	tags: { string }?,
	zone: string?, -- 존 소속 파트에 "Zone" 어트리뷰트로 기록
}

local function createPart(spec: PartSpec): Part
	local part = Instance.new("Part")
	part.Name = spec.name
	part.Size = spec.size
	part.CFrame = spec.cframe
	part.Anchored = true
	part.CanCollide = if spec.canCollide == nil then true else spec.canCollide
	part.Material = spec.material or Theme.ZoneMaterial
	part.Color = spec.color or Color3.fromRGB(200, 200, 200)
	part.Transparency = spec.transparency or 0
	part.CastShadow = if spec.castShadow == nil then true else spec.castShadow
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	if spec.zone then
		part:SetAttribute("Zone", spec.zone)
	end

	-- Parent 는 속성 설정이 끝난 뒤 마지막에 지정한다(리플리케이션 비용 절감).
	part.Parent = spec.parent

	for _, tag in spec.tags or {} do
		CollectionService:AddTag(part, tag)
	end

	return part
end

local function createFolder(name: string, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

--- 기본 템플릿의 Baseplate 는 Y=0 에서 우리 바닥과 겹친다.
--- 런타임에서만 치우므로 Studio 에 저장된 place 파일은 건드리지 않는다.
local function removeDefaultBaseplate()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate:Destroy()
	end
end

-- ─────────────────────────────────────────────
-- 구역별 빌드
-- ─────────────────────────────────────────────

local function buildLanes(root: Folder)
	local folder = createFolder("Lanes", root)

	for _, zone in MapLayout.Zones do
		local isA = zone == "A"

		-- 바닥 자체가 선택지 디스플레이다(기획서 3장). AnswerScreen 태그를 같이 붙여
		-- Phase 3 의 SurfaceGui 가 이 파트를 호스트로 잡는다.
		createPart({
			name = `ZoneFloor{zone}`,
			size = MapLayout.FloorSize,
			cframe = MapLayout.floorCFrame(zone),
			parent = folder,
			color = if isA then Theme.ZoneAColor else Theme.ZoneBColor,
			material = Theme.ZoneMaterial,
			tags = { if isA then Tags.ZoneA else Tags.ZoneB, Tags.AnswerScreen },
			zone = zone,
		})

		-- 스폰 위치 판정용 볼륨. 충돌·그림자 없이 영역만 표시한다.
		createPart({
			name = `SpawnZone{zone}`,
			size = MapLayout.SpawnZoneSize,
			cframe = MapLayout.spawnZoneCFrame(zone),
			parent = folder,
			color = Theme.SpawnZoneColor,
			transparency = if Config.Debug.Enabled then Theme.SpawnZoneDebugTransparency else 1,
			canCollide = false,
			castShadow = false,
			tags = { Tags.SpawnZone },
			zone = zone,
		})
	end
end

local function buildWalls(root: Folder)
	local folder = createFolder("Walls", root)

	for _, zone in MapLayout.Zones do
		createPart({
			name = `Wall{zone}`,
			size = MapLayout.WallSize,
			cframe = MapLayout.wallStartCFrame(zone),
			parent = folder,
			color = Theme.WallColor,
			material = Theme.WallMaterial,
			tags = { if zone == "A" then Tags.WallA else Tags.WallB },
			zone = zone,
		})
	end
end

local function buildSpectator(root: Folder)
	local folder = createFolder("Spectator", root)

	createPart({
		name = "SpectatorFloor",
		size = MapLayout.SpectatorFloorSize,
		cframe = MapLayout.spectatorFloorCFrame(),
		parent = folder,
		color = Theme.SpectatorColor,
		material = Theme.SpectatorMaterial,
		transparency = Theme.SpectatorTransparency,
		castShadow = false, -- 아래 경기장에 그림자를 드리우면 안 된다
		tags = { Tags.SpectatorFloor },
	})

	for index, rail in MapLayout.spectatorRails() do
		createPart({
			name = `SpectatorRail{index}`,
			size = rail.size,
			cframe = rail.cframe,
			parent = folder,
			color = Theme.RailColor,
			material = Theme.SpectatorMaterial,
			transparency = Theme.RailTransparency,
			castShadow = false,
		})
	end

	-- 접속·리스폰의 기본 위치를 관전장으로 둔다.
	-- 진행 중인 라운드에 난입하지 못하고, 다음 게임 시작 때 RoundService 가 아래로 내려보낸다.
	local lobbySpawn = Instance.new("SpawnLocation")
	lobbySpawn.Name = "LobbySpawn"
	lobbySpawn.Size = MapLayout.LobbySpawnSize
	lobbySpawn.CFrame = MapLayout.lobbySpawnCFrame()
	lobbySpawn.Anchored = true
	lobbySpawn.CanCollide = false
	lobbySpawn.Transparency = 1
	lobbySpawn.Neutral = true
	lobbySpawn.Duration = 0 -- 포스필드 없음
	lobbySpawn.Parent = folder
	CollectionService:AddTag(lobbySpawn, Tags.LobbySpawn)
end

local function buildBounds(root: Folder)
	local folder = createFolder("Bounds", root)

	for index, barrier in MapLayout.sideBarriers() do
		createPart({
			name = `SideBarrier{index}`,
			size = barrier.size,
			cframe = barrier.cframe,
			parent = folder,
			transparency = if Config.Debug.Enabled
				then Theme.BarrierDebugTransparency
				else Theme.BarrierTransparency,
			castShadow = false,
		})
	end

	-- 벽에 밀려 -Z 밖으로 떨어진 플레이어를 받아내는 판정면.
	-- 실제 탈락 처리는 Phase 2 에서 이 태그를 찾아 붙인다.
	createPart({
		name = "KillPlane",
		size = MapLayout.KillPlaneSize,
		cframe = MapLayout.killPlaneCFrame(),
		parent = folder,
		transparency = 1,
		canCollide = false,
		castShadow = false,
		tags = { Tags.KillPlane },
	})
end

-- ─────────────────────────────────────────────
-- 공개 API
-- ─────────────────────────────────────────────

--- 이미 생성된 맵을 제거한다.
function MapBuilder.clear()
	local existing = Workspace:FindFirstChild(ROOT_NAME)
	if existing then
		existing:Destroy()
	end
end

--- 맵을 생성하고 루트 폴더를 반환한다. 여러 번 호출해도 안전하다.
function MapBuilder.build(): Folder
	MapBuilder.clear()
	removeDefaultBaseplate()

	local root = Instance.new("Folder")
	root.Name = ROOT_NAME

	buildLanes(root)
	buildWalls(root)
	buildSpectator(root)
	buildBounds(root)

	root.Parent = Workspace

	if Config.Debug.Enabled then
		print(
			("[MapBuilder] 맵 생성 완료 | %dx%d studs | 벽 이동거리 %d studs (1R %.2fs)"):format(
				MapLayout.MapWidth,
				MapLayout.MapLength,
				MapLayout.WallTravelDistance,
				MapLayout.WallTravelDistance / Config.getWallSpeed(1)
			)
		)
	end

	return root
end

return MapBuilder

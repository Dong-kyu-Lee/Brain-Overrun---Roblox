--!strict
--[[
	MapBuilder — 맵 '골격'을 만드는 에디터 도구. ★ 런타임에서 호출하지 않는다 ★

	★ 왜 런타임 생성을 그만뒀나 (Phase 1 개정)
	  맵을 손으로 꾸미려면 place 파일 안에 실물이 있어야 한다. 부팅마다 코드가 맵을 다시
	  만들면 Studio 에서 얹은 장식이 매번 사라진다. 그래서 골격은 이 도구로 '한 번' 만들어
	  씬에 저장해 두고, 런타임에는 MapService 가 그것을 찾아 검증하고 쓰기만 한다.

	★ 대신 잃은 것과 그 보상
	  Config.Map 을 고쳐도 이미 씬에 놓인 파트는 따라오지 않는다. align() 이 그 간극을 메운다 —
	  장식은 건드리지 않고, LayoutKey 어트리뷰트가 붙은 골격 파트의 크기/위치만 다시 맞춘다.

	★ 사용법 (Studio 명령 바, Edit 모드)
	  local MapBuilder = require(game.ServerScriptService.Server.MapBuilder)
	  MapBuilder.build()      -- 최초 1회. 기존 Map 폴더와 Baseplate 를 지우고 새로 만든다 (장식도 함께 삭제)
	  MapBuilder.align()      -- Config.Map 을 고친 뒤. 장식을 유지한 채 골격만 재정렬
	  MapBuilder.addMissing() -- 골격에 '새 파트가 추가됐을 때'. 기존 파트와 장식은 그대로 둔다
	  MapBuilder.clear()      -- Map 폴더 통째로 제거
	  ⚠ 실행 후 반드시 Ctrl+S 로 place 를 저장해야 결과가 남는다.

	생성물 (Workspace.Map)
	  Lanes/      ZoneFloorA·B      바닥 겸 선택지 디스플레이 (Phase 3 에서 SurfaceGui 부착)
	              SpawnZoneA·B      라운드 시작 스폰 영역 (충돌 없는 마커 볼륨)
	  Walls/      WallA·B           파괴의 벽. 배치만 하고 이동은 WallController.
	  Display/    QuestionBoard     공중 문제 보드. 본문과 '본문 사진'을 띄운다 (Phase 3)
	  Spectator/  SpectatorFloor    상공 투명 유리 관전장 + 난간
	              LobbySpawn        접속/리스폰 기본 위치 (관전장 위)
	  Bounds/     SideBarrier       좌우 추락 방지 (-Z 출구는 열려 있음)
	              KillPlane         낙하 탈락 판정면
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapLayout = require(Shared:WaitForChild("MapLayout"))
local Tags = require(Shared:WaitForChild("Tags"))

local Theme = Config.Theme

local ROOT_NAME = "Map"

--- 골격 파트를 식별하는 어트리뷰트. 이름·경로가 아니라 이 값으로 align() 이 짝을 찾는다.
--- (사용자가 파트 이름을 바꾸거나 폴더를 재배치해도 정렬이 계속 동작한다.)
local LAYOUT_KEY = "LayoutKey"

local MapBuilder = {}
MapBuilder.LayoutKeyAttribute = LAYOUT_KEY
MapBuilder.RootName = ROOT_NAME

-- ─────────────────────────────────────────────
-- 맵 정의 — build() 와 align() 이 공유하는 단일 소스
-- ─────────────────────────────────────────────

export type ElementSpec = {
	key: string, -- LayoutKey 어트리뷰트 값 (맵 안에서 유일)
	name: string,
	folder: string, -- Map 아래 폴더 이름
	isSpawnLocation: boolean?,
	movesAtRuntime: boolean?, -- 런타임에 위치가 바뀌는 파트(벽) — 위치 검증 대상에서 제외

	size: Vector3,
	cframe: CFrame,

	color: Color3?,
	material: Enum.Material?,
	transparency: number?,
	canCollide: boolean?,
	castShadow: boolean?,
	tags: { string }?,
	zone: string?, -- 존 소속 파트에 "Zone" 어트리뷰트로 기록
}

--- 디버그 모드에서만 살짝 보이는 파트들의 투명도.
--- 씬에 구워진 값이 어떻든 런타임에는 MapService 가 이 값으로 다시 덮는다.
function MapBuilder.debugTransparency(kind: "SpawnZone" | "Barrier"): number
	local debugOn = Config.Debug.Enabled
	if kind == "SpawnZone" then
		return if debugOn then Theme.SpawnZoneDebugTransparency else 1
	end
	return if debugOn then Theme.BarrierDebugTransparency else Theme.BarrierTransparency
end

--- 맵을 구성하는 모든 골격 파트의 명세. Config → MapLayout 파생값만 사용한다.
function MapBuilder.specs(): { ElementSpec }
	local specs: { ElementSpec } = {}

	for _, zone in MapLayout.Zones do
		local isA = zone == "A"

		-- 바닥 자체가 선택지 디스플레이다(기획서 3장). AnswerScreen 태그를 같이 붙여
		-- Phase 3 의 SurfaceGui 가 이 파트를 호스트로 잡는다.
		table.insert(specs, {
			key = `ZoneFloor{zone}`,
			name = `ZoneFloor{zone}`,
			folder = "Lanes",
			size = MapLayout.FloorSize,
			cframe = MapLayout.floorCFrame(zone),
			color = if isA then Theme.ZoneAColor else Theme.ZoneBColor,
			material = Theme.ZoneMaterial,
			tags = { if isA then Tags.ZoneA else Tags.ZoneB, Tags.AnswerScreen },
			zone = zone,
		})

		-- 스폰 위치 판정용 볼륨. 충돌·그림자 없이 영역만 표시한다.
		table.insert(specs, {
			key = `SpawnZone{zone}`,
			name = `SpawnZone{zone}`,
			folder = "Lanes",
			size = MapLayout.SpawnZoneSize,
			cframe = MapLayout.spawnZoneCFrame(zone),
			color = Theme.SpawnZoneColor,
			transparency = MapBuilder.debugTransparency("SpawnZone"),
			canCollide = false,
			castShadow = false,
			tags = { Tags.SpawnZone },
			zone = zone,
		})

		table.insert(specs, {
			key = `Wall{zone}`,
			name = `Wall{zone}`,
			folder = "Walls",
			movesAtRuntime = true, -- WallController 가 매 라운드 옮긴다
			size = MapLayout.WallSize,
			cframe = MapLayout.wallStartCFrame(zone),
			color = Theme.WallColor,
			material = Theme.WallMaterial,
			tags = { if isA then Tags.WallA else Tags.WallB },
			zone = zone,
		})
	end

	-- 공중 문제 보드. 문제 본문과 '본문 사진'을 띄우는 유일한 장치다(docs/question-system.md §6).
	-- 벽이 통과하는 경로 밖(+Z, 벽 높이 위)에 세우므로 CanCollide 를 꺼도 충돌 걱정이 없지만,
	-- 플레이어가 여기까지 올 일이 없으니 물리 비용을 아예 없앤다.
	table.insert(specs, {
		key = "QuestionBoard",
		name = "QuestionBoard",
		folder = "Display",
		size = MapLayout.QuestionBoardSize,
		cframe = MapLayout.questionBoardCFrame(),
		color = Theme.Board.BackgroundColor,
		material = Theme.Board.Material,
		canCollide = false,
		castShadow = false,
		tags = { Tags.QuestionBoard },
	})

	table.insert(specs, {
		key = "SpectatorFloor",
		name = "SpectatorFloor",
		folder = "Spectator",
		size = MapLayout.SpectatorFloorSize,
		cframe = MapLayout.spectatorFloorCFrame(),
		color = Theme.SpectatorColor,
		material = Theme.SpectatorMaterial,
		transparency = Theme.SpectatorTransparency,
		castShadow = false, -- 아래 경기장에 그림자를 드리우면 안 된다
		tags = { Tags.SpectatorFloor },
	})

	for index, rail in MapLayout.spectatorRails() do
		table.insert(specs, {
			key = `SpectatorRail{index}`,
			name = `SpectatorRail{index}`,
			folder = "Spectator",
			size = rail.size,
			cframe = rail.cframe,
			color = Theme.RailColor,
			material = Theme.SpectatorMaterial,
			transparency = Theme.RailTransparency,
			castShadow = false,
		})
	end

	-- 접속·리스폰의 기본 위치를 관전장으로 둔다.
	-- 진행 중인 라운드에 난입하지 못하고, 다음 게임 시작 때 RoundService 가 아래로 내려보낸다.
	table.insert(specs, {
		key = "LobbySpawn",
		name = "LobbySpawn",
		folder = "Spectator",
		isSpawnLocation = true,
		size = MapLayout.LobbySpawnSize,
		cframe = MapLayout.lobbySpawnCFrame(),
		transparency = 1,
		canCollide = false,
		castShadow = false,
		tags = { Tags.LobbySpawn },
	})

	for index, barrier in MapLayout.sideBarriers() do
		table.insert(specs, {
			key = `SideBarrier{index}`,
			name = `SideBarrier{index}`,
			folder = "Bounds",
			size = barrier.size,
			cframe = barrier.cframe,
			transparency = MapBuilder.debugTransparency("Barrier"),
			castShadow = false,
			tags = { Tags.SideBarrier },
		})
	end

	-- 벽에 밀려 -Z 밖으로 떨어진 플레이어를 받아내는 판정면.
	table.insert(specs, {
		key = "KillPlane",
		name = "KillPlane",
		folder = "Bounds",
		size = MapLayout.KillPlaneSize,
		cframe = MapLayout.killPlaneCFrame(),
		transparency = 1,
		canCollide = false,
		castShadow = false,
		tags = { Tags.KillPlane },
	})

	return specs
end

-- ─────────────────────────────────────────────
-- 내부 헬퍼
-- ─────────────────────────────────────────────

local function createPart(spec: ElementSpec, parent: Instance): BasePart
	local part: BasePart
	if spec.isSpawnLocation then
		local spawn = Instance.new("SpawnLocation")
		spawn.Neutral = true
		spawn.Duration = 0 -- 포스필드 없음
		part = spawn
	else
		part = Instance.new("Part")
	end

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

	part:SetAttribute(LAYOUT_KEY, spec.key)
	if spec.zone then
		part:SetAttribute("Zone", spec.zone)
	end

	-- Parent 는 속성 설정이 끝난 뒤 마지막에 지정한다(리플리케이션 비용 절감).
	part.Parent = parent

	for _, tag in spec.tags or {} do
		CollectionService:AddTag(part, tag)
	end

	return part
end

local function folderIn(parent: Instance, name: string): Folder
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

--- 기본 템플릿의 Baseplate 는 Y=0 에서 우리 바닥과 겹치고, -Z 로 밀려난 플레이어를
--- 받아버려 탈락 자체를 막는다. 맵이 씬에 상주하게 된 이상 영구히 치운다.
local function removeDefaultBaseplate()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate:Destroy()
	end
end

--- LayoutKey 어트리뷰트로 골격 파트를 색인한다. 이름·경로가 바뀌어도 짝을 찾을 수 있다.
local function indexByLayoutKey(root: Folder): { [string]: BasePart }
	local byKey: { [string]: BasePart } = {}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			local key = descendant:GetAttribute(LAYOUT_KEY)
			if typeof(key) == "string" then
				byKey[key] = descendant
			end
		end
	end
	return byKey
end

local function assertEditMode(action: string)
	if RunService:IsRunning() then
		error(
			`[MapBuilder] {action}() 는 에디터 전용이다. 맵은 씬에 미리 배치돼 있으며 `
				.. `런타임은 MapService 로 찾아 쓴다. (docs/map-builder.md §2)`,
			2
		)
	end
end

-- ─────────────────────────────────────────────
-- 공개 API
-- ─────────────────────────────────────────────

--- 씬에 배치된 맵 루트 폴더. 태그로 찾고, 없으면 이름으로 한 번 더 찾는다.
function MapBuilder.findRoot(): Folder?
	for _, instance in CollectionService:GetTagged(Tags.MapRoot) do
		if instance:IsA("Folder") and instance:IsDescendantOf(Workspace) then
			return instance
		end
	end
	local byName = Workspace:FindFirstChild(ROOT_NAME)
	return if byName and byName:IsA("Folder") then byName else nil
end

--- 맵을 통째로 제거한다. ★ 얹어 둔 장식도 같이 사라진다 ★
function MapBuilder.clear()
	assertEditMode("clear")
	local existing = MapBuilder.findRoot()
	if existing then
		existing:Destroy()
	end
end

--- 골격을 처음부터 다시 만든다. ★ 기존 Map 폴더와 장식이 전부 삭제된다 ★
--- 이미 꾸며 둔 맵이 있다면 build() 가 아니라 align() 을 쓸 것.
function MapBuilder.build(): Folder
	assertEditMode("build")
	MapBuilder.clear()
	removeDefaultBaseplate()

	local root = Instance.new("Folder")
	root.Name = ROOT_NAME

	for _, spec in MapBuilder.specs() do
		createPart(spec, folderIn(root, spec.folder))
	end

	root.Parent = Workspace
	CollectionService:AddTag(root, Tags.MapRoot)

	print(
		("[MapBuilder] 맵 생성 완료 | %dx%d studs | 벽 이동거리 %d studs (1R %.2fs) — Ctrl+S 로 저장할 것"):format(
			MapLayout.MapWidth,
			MapLayout.MapLength,
			MapLayout.WallTravelDistance,
			MapLayout.WallTravelDistance / Config.getWallSpeed(1)
		)
	)

	return root
end

--- Config.Map 을 고친 뒤, 이미 배치된 골격 파트의 크기/위치만 다시 맞춘다.
--- 장식(LayoutKey 가 없는 파트)은 손대지 않는다 — 따라서 레인 길이를 바꾸면
--- 장식은 직접 옮겨야 한다. 그게 손으로 꾸미는 대가다.
function MapBuilder.align(): { string }
	assertEditMode("align")

	local root = MapBuilder.findRoot()
	if not root then
		error("[MapBuilder] Workspace 에 Map 이 없다. 먼저 build() 로 골격을 만들 것.", 2)
	end

	local byKey = indexByLayoutKey(root)

	local problems: { string } = {}
	local aligned = 0

	for _, spec in MapBuilder.specs() do
		local part = byKey[spec.key]
		if not part then
			table.insert(problems, `누락: {spec.key} — addMissing() 으로 채울 것`)
			continue
		end

		if part.Size ~= spec.size or part.CFrame ~= spec.cframe then
			part.Size = spec.size
			part.CFrame = spec.cframe
			aligned += 1
		end
		part.Anchored = true
	end

	print(`[MapBuilder] 정렬 완료 | {aligned}개 이동/리사이즈, 문제 {#problems}건 — Ctrl+S 로 저장할 것`)
	for _, problem in problems do
		warn(`[MapBuilder] {problem}`)
	end

	return problems
end

--- 씬에 없는 골격 파트만 새로 만든다. ★ 기존 파트와 장식은 손대지 않는다 ★
---
--- ★ 왜 build() 로 안 되는가
---   build() 는 Map 폴더를 통째로 지우고 다시 만든다. 이미 꾸며 둔 맵에서는 장식이 전부
---   날아가므로 쓸 수 없다. 그렇다고 align() 은 '이미 있는' 파트만 맞추므로 새로 추가된
---   골격(예: Phase 3 개정의 QuestionBoard)을 만들어 주지 못한다. 그 사이를 메운다.
function MapBuilder.addMissing(): { string }
	assertEditMode("addMissing")

	local root = MapBuilder.findRoot()
	if not root then
		error("[MapBuilder] Workspace 에 Map 이 없다. 먼저 build() 로 골격을 만들 것.", 2)
	end

	local byKey = indexByLayoutKey(root)
	local added: { string } = {}

	for _, spec in MapBuilder.specs() do
		if not byKey[spec.key] then
			createPart(spec, folderIn(root, spec.folder))
			table.insert(added, spec.key)
		end
	end

	if #added == 0 then
		print("[MapBuilder] 빠진 골격 파트가 없다 — 아무것도 만들지 않았다")
	else
		print(`[MapBuilder] 골격 파트 {#added}개 추가: {table.concat(added, ", ")} — Ctrl+S 로 저장할 것`)
	end

	return added
end

return MapBuilder

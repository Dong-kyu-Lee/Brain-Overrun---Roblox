--!strict
--[[
	MapService — 씬에 미리 배치된 맵을 찾아 검증한다. (Phase 1 개정)

	맵은 더 이상 부팅할 때 생성하지 않는다. place 파일 안에 상주하는 실물을 쓴다.
	이유와 규약은 docs/map-builder.md §2 참고. 골격을 만들거나 재정렬하는 것은
	에디터 도구 MapBuilder 의 일이고, 여기서는 절대 만들지 않는다.

	★ 왜 검증이 필요한가
	  맵을 손으로 꾸미다 보면 태그를 지우거나, 바닥을 끌어 옮기거나, 파트를 복제하게 된다.
	  전부 조용히 게임을 망가뜨린다 — 태그가 없으면 벽이 안 움직이고, 바닥이 어긋나면
	  zoneAtPosition 이 엉뚱한 답을 내서 생존 판정이 뒤집힌다.
	  그래서 부팅 시 한 번 전수 점검하고, 치명적인 결손이면 즉시 크게 실패한다.
	  (조용히 build() 로 되살리지 않는다. 그러면 꾸민 게 다 날아간다.)

	★ 치명(error) / 경고(warn) 의 기준
	  · 없으면 게임이 진행 불가 → error. 벽·킬플레인·바닥·스폰영역·로비스폰.
	  · 어긋났지만 굴러는 간다 → warn. 위치 드리프트, 중복 태그, 앵커 해제.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapLayout = require(Shared:WaitForChild("MapLayout"))
local Tags = require(Shared:WaitForChild("Tags"))

-- MapBuilder 를 require 해도 아무것도 만들지 않는다. 맵 명세(specs) 를 빌리기 위함이며,
-- build()/align() 은 에디터 전용 가드가 걸려 있어 런타임에서는 호출조차 되지 않는다.
local MapBuilder = require(script.Parent.MapBuilder)

local POSITION_TOLERANCE = 0.05 -- studs. 손으로 옮긴 것과 부동소수 오차를 가르는 선

local MapService = {}

-- ─────────────────────────────────────────────
-- 검증
-- ─────────────────────────────────────────────

type TagRule = { tag: string, count: number, label: string }

--- 게임이 돌아가려면 반드시 이만큼 있어야 하는 태그들.
local REQUIRED_TAGS: { TagRule } = {
	{ tag = Tags.ZoneA, count = 1, label = "A구역 바닥" },
	{ tag = Tags.ZoneB, count = 1, label = "B구역 바닥" },
	{ tag = Tags.AnswerScreen, count = 2, label = "선택지 디스플레이(바닥)" },
	{ tag = Tags.SpawnZone, count = 2, label = "라운드 시작 스폰 영역" },
	{ tag = Tags.WallA, count = 1, label = "A레인 파괴의 벽" },
	{ tag = Tags.WallB, count = 1, label = "B레인 파괴의 벽" },
	{ tag = Tags.SpectatorFloor, count = 1, label = "관전장 유리 바닥" },
	{ tag = Tags.LobbySpawn, count = 1, label = "로비 스폰" },
	{ tag = Tags.KillPlane, count = 1, label = "낙하 탈락 판정면" },
}

local function taggedInMap(root: Folder, tag: string): { Instance }
	local result = {}
	for _, instance in CollectionService:GetTagged(tag) do
		if instance:IsDescendantOf(root) then
			table.insert(result, instance)
		end
	end
	return result
end

export type Report = { fatal: { string }, warnings: { string } }

--- 맵을 전수 점검한다. 고치지는 않는다.
function MapService.inspect(root: Folder): Report
	local report: Report = { fatal = {}, warnings = {} }

	for _, rule in REQUIRED_TAGS do
		local found = #taggedInMap(root, rule.tag)
		if found == 0 then
			table.insert(report.fatal, `{rule.label}({rule.tag}) 가 맵에 없다`)
		elseif found < rule.count then
			table.insert(report.fatal, `{rule.label}({rule.tag}) 가 {rule.count}개여야 하는데 {found}개다`)
		elseif found > rule.count then
			table.insert(
				report.warnings,
				`{rule.label}({rule.tag}) 가 {found}개다 ({rule.count}개여야 함) — 복제한 파트에서 태그를 지울 것`
			)
		end
	end

	-- 골격 파트의 기하 드리프트. 꾸미다가 바닥을 끌어 옮기면 생존 판정이 어긋난다.
	local byKey: { [string]: BasePart } = {}
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			local key = descendant:GetAttribute(MapBuilder.LayoutKeyAttribute)
			if typeof(key) == "string" then
				byKey[key] = descendant
			end
		end
	end

	for _, spec in MapBuilder.specs() do
		local part = byKey[spec.key]
		if not part then
			-- 태그 검사에서 이미 치명으로 잡히는 것들이 있으므로 여기서는 경고까지만.
			table.insert(
				report.warnings,
				`골격 파트 {spec.key} 를 찾을 수 없다 — Edit 모드에서 MapBuilder.addMissing() 실행 `
					.. "(LayoutKey 어트리뷰트가 지워진 것일 수도 있다)"
			)
			continue
		end

		if not part.Anchored then
			table.insert(report.warnings, `{spec.key} 의 Anchored 가 꺼져 있다 — 켤 것`)
		end
		if (part.Size - spec.size).Magnitude > POSITION_TOLERANCE then
			table.insert(
				report.warnings,
				`{spec.key} 크기가 Config 기준과 다르다 ({part.Size} ≠ {spec.size}) — MapBuilder.align() 으로 맞출 것`
			)
		end
		if
			not spec.movesAtRuntime
			and (part.Position - spec.cframe.Position).Magnitude > POSITION_TOLERANCE
		then
			table.insert(
				report.warnings,
				`{spec.key} 위치가 Config 기준과 다르다 ({part.Position} ≠ {spec.cframe.Position}) — MapBuilder.align() 으로 맞출 것`
			)
		end
	end

	-- 공중 보드는 '있으면 되는' 파트가 아니라 '보여야 하는' 파트다. 손으로 끌어 내려서
	-- 벽 높이 아래로 들어가면 라운드 시작 순간 벽에 가려 이미지 문제를 아예 못 읽는다.
	-- 태그가 아니라 실물 기하를 본다 — 태그만 맞고 위치가 틀린 경우가 실제로 자주 난다.
	for _, instance in taggedInMap(root, Tags.QuestionBoard) do
		if not instance:IsA("BasePart") then
			continue
		end
		local bottom = instance.Position.Y - instance.Size.Y / 2
		if bottom < MapLayout.WallTopY then
			table.insert(
				report.warnings,
				`{instance.Name} 아랫변({bottom})이 벽 높이({MapLayout.WallTopY})보다 낮다 — `
					.. "라운드 시작 때 벽에 가려 문제가 안 보인다 (Config.Map.QuestionBoardBottomY)"
			)
		end
	end

	return report
end

-- ─────────────────────────────────────────────
-- 런타임 보정
-- ─────────────────────────────────────────────

--- 스폰 영역·측면 벽은 평소 보이면 안 되고 디버그 때만 보여야 한다.
--- 씬에 어떤 투명도로 저장돼 있든 Config.Debug 를 기준으로 매 부팅 다시 덮는다.
--- (정적 맵이 Config 를 따라올 수 있는 몇 안 되는 지점이라 여기서 처리한다.)
local function applyDebugVisibility(root: Folder)
	local pairsToApply = {
		{ tag = Tags.SpawnZone, transparency = MapBuilder.debugTransparency("SpawnZone") },
		{ tag = Tags.SideBarrier, transparency = MapBuilder.debugTransparency("Barrier") },
	}

	for _, entry in pairsToApply do
		for _, instance in taggedInMap(root, entry.tag) do
			if instance:IsA("BasePart") then
				instance.Transparency = entry.transparency
			end
		end
	end
end

-- ─────────────────────────────────────────────
-- 공개 API
-- ─────────────────────────────────────────────

--- 씬에 배치된 맵 루트. 없으면 nil.
function MapService.root(): Folder?
	return MapBuilder.findRoot()
end

--- 맵이 쓸 수 있는 상태인지 확인하고 루트를 반환한다.
--- 쓸 수 없으면 에러로 서버를 세운다 — 반쯤 망가진 맵으로 게임을 돌리면
--- 원인을 알 수 없는 판정 버그로 나타나므로, 부팅 때 크게 실패하는 편이 낫다.
function MapService.ensureReady(): Folder
	local root = MapService.root()
	if not root then
		error(
			"[MapService] Workspace 에 맵이 없다. 맵은 씬에 미리 배치돼 있어야 한다.\n"
				.. "  Studio Edit 모드 명령 바에서:\n"
				.. "    require(game.ServerScriptService.Server.MapBuilder).build()\n"
				.. "  실행 후 Ctrl+S 로 place 를 저장할 것. (docs/map-builder.md §2)"
		)
	end

	local report = MapService.inspect(root)

	for _, warning in report.warnings do
		warn(`[MapService] {warning}`)
	end

	if #report.fatal > 0 then
		error(
			`[MapService] 맵 검증 실패 {#report.fatal}건:\n  · `
				.. table.concat(report.fatal, "\n  · ")
				.. "\n  태그를 복구하거나 MapBuilder.build() 로 골격을 다시 만들 것. (docs/map-builder.md §5)"
		)
	end

	applyDebugVisibility(root)

	if Config.Debug.Enabled then
		print(
			("[MapService] 맵 확인 | %dx%d studs | 벽 이동거리 %d studs (1R %.2fs) | 경고 %d건"):format(
				MapLayout.MapWidth,
				MapLayout.MapLength,
				MapLayout.WallTravelDistance,
				MapLayout.WallTravelDistance / Config.getWallSpeed(1),
				#report.warnings
			)
		)
	end

	return root
end

return MapService

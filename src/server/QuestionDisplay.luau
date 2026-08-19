--!strict
--[[
	QuestionDisplay — 문제를 '월드에' 그린다. (Phase 3)

	  · 바닥 스크린 (BO_AnswerScreen ×2) — 기획서 3장의 핵심.
	    A/B 구역의 바닥 자체가 거대한 디스플레이가 되어 선택지를 출력한다.
	  · 공중 문제 보드 (BO_QuestionBoard) — 문제 본문과 '본문 사진'을 띄운다.

	★ 본문 사진은 보드에만 그린다 (HUD 에는 없다)
	  기획서 3장의 UI 원칙은 "화면을 가리는 UI 로 시야를 뺏지 않는다" 이고, 그래서 HUD 는
	  상단 밴드(화면 세로 30%) 안에 갇혀 있다. 그 안의 본문 칸은 화면 세로의 14% 밖에 안 돼
	  동물 사진을 알아보기엔 작다. 그래서 사진은 월드에 크게 띄우고 HUD 는 지시문만 맡는다.
	  ★ 보드가 없는 맵에서는 본문이 사진인 문제가 아예 출제되지 않는다 —
	    QuestionService.poolFor() 가 hasBoard() 를 보고 후보에서 뺀다.

	★ 왜 서버가 만드는가
	  어떤 선택지가 어느 바닥에 그려지는가가 곧 정답 배치다. 클라이언트가 그리면
	  조작 가능한 표시가 된다. SurfaceGui 는 Workspace 안에 있으면 자동 복제되므로,
	  서버가 부팅 때 한 번 만들고 라운드마다 텍스트만 갈아 끼우는 편이 단순하고 안전하다.

	★ 정답을 월드에 남기지 않는다 (README 규약 2)
	  show() 는 어느 쪽이 정답인지 파트·GUI·어트리뷰트 어디에도 기록하지 않는다.
	  Countdown 중에 어트리뷰트 하나만 남아도 클라이언트가 읽어서 정답을 알아낸다.
	  정답 강조(reveal)는 판정이 끝난 뒤에만 호출한다.

	★ 라벨이 -90° 돌아가 있는 이유
	  바닥 파트 Top 면의 캔버스는 '가로가 레인 길이 방향'이다(Studio 실측 — MapLayout 의
	  「바닥 스크린 캔버스」 주석 참고). 그래서 글자를 그대로 놓으면 레인을 따라 옆으로 눕는다.
	  -90° 가 플레이어(+Z 를 봄) 기준으로 글자를 바로 세운다.
	  회전하면 가로·세로가 맞바뀌므로 크기 계산은 전부 MapLayout.answerBand() 에 맡긴다 —
	  여기서 스케일 산술을 하면 규약이 바뀔 때 조용히 어긋난다.

	★ 왜 매 부팅 다시 만드는가
	  스크린은 코드가 만든 것이고 place 에 저장되지 않는다. 남아 있던 구버전 GUI 를
	  재사용하면 구조를 바꾼 날 조용히 옛 레이아웃이 뜬다. 지우고 새로 만든다.
	  ★ 손으로 얹은 장식은 바닥 파트의 다른 자식이므로 영향받지 않는다.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapLayout = require(Shared:WaitForChild("MapLayout"))
local Tags = require(Shared:WaitForChild("Tags"))

type Zone = "A" | "B" -- Types.luau 참조
type MediaKind = "text" | "image"

--- MapLayout.ScreenBand 와 같은 모양. 컨테이너를 넘는 require 는 타입이 살아남지 않는다.
--- width/height 는 '회전 전' 스케일이다.
type ScreenBand = { centerX: number, width: number, height: number }

export type Shown = {
	prompt: string,
	promptImage: string?,
	choiceKind: MediaKind,
	choices: { A: string, B: string },
}

local Screen = Config.Theme.Screen
local BoardTheme = Config.Theme.Board

local SCREEN_NAME = "BO_AnswerScreenGui"
local BOARD_NAME = "BO_QuestionBoardGui"

local QuestionDisplay = {}

type FloorScreen = {
	tint: Frame,
	choiceText: TextLabel,
	choiceImage: ImageLabel,
}

--- 공중 보드 하나. 지시문과 본문 사진을 함께 들고 있다.
type Board = {
	prompt: TextLabel,
	image: ImageLabel,
}

local floors: { [Zone]: FloorScreen } = {}
local boards: { Board } = {}

-- ─────────────────────────────────────────────
-- 생성
-- ─────────────────────────────────────────────

--- 아직 부모가 없는 SurfaceGui. 호출부가 내용을 다 채운 뒤 마지막에 파트에 붙인다
--- (MapBuilder 와 같은 규칙 — 리플리케이션 비용을 아낀다).
local function newSurfaceGui(part: BasePart, name: string, face: Enum.NormalId, pixelsPerStud: number, light: number): SurfaceGui
	local existing = part:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = name
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.LightInfluence = light
	gui.AlwaysOnTop = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- 기본값(1000)에 맡기면 맵이 커졌을 때 조용히 스크린이 사라진다. 맵에서 파생시킨다.
	gui.MaxDistance = MapLayout.ScreenViewDistance
	return gui
end

--- 회전된 요소를 레인 위 한 지점에 앉힌다. band 는 '회전 전' 크기다(MapLayout 주석 참고).
--- AnchorPoint 를 중앙에 두면 회전 후에도 중심이 그대로라 위치 계산이 필요 없다.
local function placeRotated(object: GuiObject, band: ScreenBand, padding: number)
	object.AnchorPoint = Vector2.new(0.5, 0.5)
	object.Size = UDim2.fromScale(band.width * (1 - padding * 2), band.height)
	object.Position = UDim2.fromScale(band.centerX, 0.5)
	object.Rotation = Screen.LabelRotation
end

local function newText(parent: Instance, name: string, font: Enum.Font, color: Color3, stroke: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = stroke
	label.ZIndex = 2 -- Tint 위
	label.Text = ""
	label.Parent = parent
	return label
end

local function buildFloorScreen(part: BasePart): FloorScreen
	local gui = newSurfaceGui(part, SCREEN_NAME, Enum.NormalId.Top, Screen.PixelsPerStud, Screen.LightInfluence)

	-- 판정 순간 바닥 전체를 물들이는 판. 평소에는 완전 투명이다.
	-- 색 판이라 회전이 필요 없다 — 캔버스를 그대로 덮는다.
	local tint = Instance.new("Frame")
	tint.Name = "Tint"
	tint.Size = UDim2.fromScale(1, 1)
	tint.BackgroundColor3 = Screen.CorrectTint
	tint.BackgroundTransparency = 1
	tint.BorderSizePixel = 0
	tint.ZIndex = 1
	tint.Parent = gui

	local answerBand = MapLayout.answerBand()

	local choiceText = newText(gui, "ChoiceText", Screen.Font, Screen.TextColor, Screen.StrokeTransparency)
	placeRotated(choiceText, answerBand, Screen.ChoicePadding)

	local choiceImage = Instance.new("ImageLabel")
	choiceImage.Name = "ChoiceImage"
	choiceImage.BackgroundTransparency = 1
	choiceImage.ScaleType = Enum.ScaleType.Fit
	choiceImage.Visible = false
	choiceImage.ZIndex = 2
	placeRotated(choiceImage, answerBand, Screen.ChoicePadding)
	choiceImage.Parent = gui

	-- 발밑 존 표기. 어느 레인에 서 있는지는 항상 알 수 있어야 한다.
	local zoneLabel = newText(gui, "ZoneLabel", Screen.Font, Screen.TextColor, Screen.StrokeTransparency)
	placeRotated(zoneLabel, MapLayout.zoneLabelBand(), Screen.ZoneLabelPadding)
	zoneLabel.TextTransparency = Screen.ZoneLabelTransparency
	zoneLabel.Text = tostring(part:GetAttribute("Zone"))

	gui.Parent = part
	return { tint = tint, choiceText = choiceText, choiceImage = choiceImage }
end

--- 보드는 장식이라 어느 면을 쓸지 맵 제작자가 정한다. 파트에 Face 어트리뷰트로 적어 두면
--- 그 면을 쓰고, 없으면 Front 를 쓴다.
local function boardFace(part: BasePart): Enum.NormalId
	local named = part:GetAttribute("Face")
	if typeof(named) == "string" then
		local face = (Enum.NormalId :: any)[named]
		if face then
			return face
		end
		warn(`[QuestionDisplay] {part:GetFullName()} 의 Face 어트리뷰트 '{named}' 는 NormalId 가 아니다 — Front 를 쓴다`)
	end
	return Enum.NormalId.Front
end

local function buildBoard(part: BasePart): Board
	local gui = newSurfaceGui(part, BOARD_NAME, boardFace(part), BoardTheme.PixelsPerStud, BoardTheme.LightInfluence)

	local frame = Instance.new("Frame")
	frame.Name = "Root"
	frame.Size = UDim2.fromScale(1 - BoardTheme.Padding * 2, 1 - BoardTheme.Padding * 2)
	frame.Position = UDim2.fromScale(BoardTheme.Padding, BoardTheme.Padding)
	frame.BackgroundTransparency = 1
	frame.Parent = gui

	-- 보드는 회전이 필요 없다(수직면이므로 캔버스가 이미 사람이 읽는 방향이다).
	-- 위치와 크기는 문제마다 달라지므로 layoutBoard() 가 정한다.
	local prompt = newText(frame, "Prompt", BoardTheme.Font, BoardTheme.TextColor, BoardTheme.StrokeTransparency)

	local image = Instance.new("ImageLabel")
	image.Name = "PromptImage"
	image.BackgroundTransparency = 1
	image.ScaleType = Enum.ScaleType.Fit -- 원본 비율 유지. 사진이 찌그러지면 알아보기 어렵다.
	image.Visible = false
	image.ZIndex = 2
	image.Parent = frame

	gui.Parent = part
	return { prompt = prompt, image = image }
end

--- 본문에 사진이 있느냐에 따라 보드 안을 다시 나눈다.
--- 사진이 있으면 좌우로 쪼개고(지시문 왼쪽 / 사진 오른쪽), 없으면 지시문이 보드를 다 쓴다.
--- 좌우로 나누는 이유는 Config.Theme.Board.ImageCaptionWidth 주석 참고.
local function layoutBoard(board: Board, hasImage: boolean)
	board.image.Visible = hasImage

	if not hasImage then
		board.prompt.Position = UDim2.fromScale(0, 0)
		board.prompt.Size = UDim2.fromScale(1, 1)
		return
	end

	local captionWidth = BoardTheme.ImageCaptionWidth
	local gap = BoardTheme.ImageGap

	board.prompt.Position = UDim2.fromScale(0, 0)
	board.prompt.Size = UDim2.fromScale(captionWidth, 1)

	board.image.Position = UDim2.fromScale(captionWidth + gap, 0)
	board.image.Size = UDim2.fromScale(1 - captionWidth - gap, 1)
end

-- ─────────────────────────────────────────────
-- 공개 API
-- ─────────────────────────────────────────────

--- 이번 라운드의 문제를 월드에 띄운다. ★ 어느 쪽이 정답인지는 남기지 않는다 ★
--- 선택지는 두 바닥에, 본문(지시문 + 사진)은 공중 보드에 그린다.
function QuestionDisplay.show(question: Shown)
	local choiceIsImage = question.choiceKind == "image"

	for zone, screen in floors do
		local choice = if zone == "A" then question.choices.A else question.choices.B

		screen.choiceText.Visible = not choiceIsImage
		screen.choiceText.Text = if choiceIsImage then "" else choice

		screen.choiceImage.Visible = choiceIsImage
		screen.choiceImage.Image = if choiceIsImage then choice else ""

		screen.tint.BackgroundTransparency = 1
	end

	local promptImage = question.promptImage
	for _, board in boards do
		board.prompt.Text = question.prompt
		board.image.Image = promptImage or ""
		layoutBoard(board, promptImage ~= nil)
	end
end

--- 본문 사진을 띄울 보드가 있는가. QuestionService 가 후보를 고를 때 본다.
--- ★ start() 이후에만 의미 있는 값이다.
function QuestionDisplay.hasBoard(): boolean
	return #boards > 0
end

--- 판정이 끝난 뒤 정답 구역을 물들인다. ★ Judge 이전에 호출하면 정답이 새어나간다 ★
function QuestionDisplay.reveal(correctZone: Zone)
	for zone, screen in floors do
		screen.tint.BackgroundColor3 = if zone == correctZone then Screen.CorrectTint else Screen.WrongTint
		screen.tint.BackgroundTransparency = Screen.TintTransparency
	end
end

--- 라운드 밖(로비·게임 종료)에서 스크린을 비운다.
function QuestionDisplay.clear()
	for _, screen in floors do
		screen.choiceText.Visible = true
		screen.choiceText.Text = ""
		screen.choiceImage.Visible = false
		screen.choiceImage.Image = ""
		screen.tint.BackgroundTransparency = 1
	end

	for _, board in boards do
		board.prompt.Text = ""
		board.image.Image = ""
		layoutBoard(board, false)
	end
end

--- MapService.ensureReady() 이후에 호출한다(태그로 바닥을 찾기 때문).
function QuestionDisplay.start()
	table.clear(floors)
	table.clear(boards)

	-- 태그로 찾고, Zone 어트리뷰트로 A/B 를 가른다 (README 규약 3 · map-builder.md §5).
	-- BO_AnswerScreen 은 한 태그에 두 존이 걸리므로 어트리뷰트가 유일한 구분 수단이다.
	for _, instance in CollectionService:GetTagged(Tags.AnswerScreen) do
		if not instance:IsA("BasePart") then
			continue
		end
		local zone = instance:GetAttribute("Zone")
		if zone ~= "A" and zone ~= "B" then
			warn(`[QuestionDisplay] {instance:GetFullName()} 에 Zone 어트리뷰트가 없다 — 스크린을 건너뛴다`)
			continue
		end
		floors[zone :: Zone] = buildFloorScreen(instance)
	end

	for _, zone in MapLayout.Zones do
		assert(
			floors[zone],
			`[QuestionDisplay] {zone}구역 바닥 스크린을 만들지 못했다. `
				.. `BO_AnswerScreen 태그와 Zone 어트리뷰트를 확인할 것 (docs/map-builder.md §5).`
		)
	end

	-- 공중 보드가 없어도 서버는 뜬다. 대신 본문이 사진인 문제가 출제되지 않을 뿐이다.
	-- 그래서 여기서 세우지 않고 경고만 남긴다 — 맵 검증은 MapService 의 일이다.
	for _, instance in CollectionService:GetTagged(Tags.QuestionBoard) do
		if instance:IsA("BasePart") then
			table.insert(boards, buildBoard(instance))
		end
	end

	QuestionDisplay.clear()

	if #boards == 0 then
		warn(
			"[QuestionDisplay] 공중 보드(BO_QuestionBoard)가 없다 — 사진 문제가 출제되지 않는다. "
				.. "Edit 모드에서 MapBuilder.addMissing() 실행 (docs/map-builder.md §7)"
		)
	end

	if Config.Debug.Enabled then
		print(`[QuestionDisplay] 바닥 스크린 2개 | 공중 보드 {#boards}개`)
	end
end

return QuestionDisplay

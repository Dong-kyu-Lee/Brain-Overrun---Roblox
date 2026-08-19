--!strict
--[[
	AbilityHud — 대시 쿨타임과 밀치기 잔여 횟수 배지. (Phase 5)

	★ 상단 밴드에도, 화면 아래에도 넣지 않는다 (기획서 3장의 UI 원칙)
	  밴드(Hud.luau)는 문제 본문과 타이머의 자리라 배지가 끼어들면 글자가 밀린다.
	  화면 아래쪽은 바닥 선택지를 보는 영역이라 더더욱 안 된다. 그래서 우측 상단
	  구석에 작은 사각형 두 개만 띄운다. 모바일 터치 버튼은 ContextActionService 가
	  반대편 구석에 만든다.

	★ 여기서 판정하지 않는다
	  값은 전부 AbilityState 가 들고 있는 서버 세션의 사본이다. 배지가 '준비'라고
	  떠 있어도 서버가 거절하면 거절이다.

	★ 관전 중에는 숨긴다
	  탈락자에게 쿨타임 게이지는 의미가 없고, 관전 화면은 경기장을 보는 화면이다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local AbilityState = require(script.Parent.AbilityState)

local Theme = Config.Theme.Hud
local Badge = Theme.Ability

local AbilityHud = {}

type BadgeParts = {
	frame: Frame,
	fill: Frame,
	value: TextLabel,
}

--- 키 이름을 사람이 읽는 형태로. Config 의 키 목록이 곧 배지에 뜨는 안내문이라
--- 키를 바꾸면 안내도 함께 바뀐다 — 두 곳을 따로 고칠 일이 없다.
local function keyHint(keys: { any }): string
	local seen: { [string]: boolean } = {}
	local names: { string } = {}

	for _, key in keys do
		local name = (key :: EnumItem).Name
		name = name:gsub("^Left", ""):gsub("^Right", "")
		if name ~= "" and not seen[name] then
			seen[name] = true
			table.insert(names, name)
		end
	end

	return table.concat(names, "/")
end

local function makeBadge(parent: Instance, index: number, title: string, hint: string): BadgeParts
	local frame = Instance.new("Frame")
	frame.Name = title
	frame.AnchorPoint = Vector2.new(1, 0)
	-- ★ RelativeYY ★ 두 축을 모두 화면 '높이' 기준으로 잡아야 배지가 정사각형으로 남는다.
	--   기본값(RelativeXY)이면 화면이 넓어질수록 가로로 늘어난 직사각형이 된다.
	frame.SizeConstraint = Enum.SizeConstraint.RelativeYY
	frame.Size = UDim2.fromScale(Badge.Size, Badge.Size)
	frame.Position = UDim2.fromScale(1 - Badge.Margin, Badge.Margin + index * (Badge.Size + Badge.Gap))
	frame.BackgroundColor3 = Badge.BackgroundColor
	frame.BackgroundTransparency = Badge.BackgroundTransparency
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(Badge.CornerRadius, 0)
	corner.Parent = frame

	-- 쿨타임 게이지. 아래에서 위로 차오른다(= 남은 시간이 줄면 게이지가 준다).
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)
	fill.BackgroundColor3 = Badge.FillColor
	fill.BackgroundTransparency = Badge.FillTransparency
	fill.BorderSizePixel = 0
	fill.ZIndex = 1
	fill.Parent = frame

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 0.34)
	label.Position = UDim2.fromScale(0, 0.08)
	label.BackgroundTransparency = 1
	label.Font = Theme.Font
	label.TextSize = Badge.LabelSize
	label.TextColor3 = Badge.ReadyColor
	label.TextStrokeTransparency = Theme.StrokeTransparency
	label.Text = if hint ~= "" then `{title} · {hint}` else title
	label.ZIndex = 2
	label.Parent = frame

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.Size = UDim2.fromScale(1, 0.5)
	value.Position = UDim2.fromScale(0, 0.42)
	value.BackgroundTransparency = 1
	value.Font = Theme.PromptFont
	value.TextSize = Badge.ValueSize
	value.TextColor3 = Badge.ReadyColor
	value.TextStrokeTransparency = Theme.StrokeTransparency
	value.Text = ""
	value.ZIndex = 2
	value.Parent = frame

	return { frame = frame, fill = fill, value = value }
end

function AbilityHud.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "BO_AbilityHud"
	gui.ResetOnSpawn = false -- 탈락해서 리스폰해도 유지돼야 한다
	-- ★ 여기는 인셋을 무시하지 않는다 (Hud 의 상단 밴드와 반대다) ★
	--   배지가 우측 '상단'이라 인셋을 무시하면 로블록스 상단바(GetGuiInset 기준 58px) 영역에
	--   걸린다. 밴드는 화면 폭 전체를 쓰는 오버레이라 무시가 맞지만, 구석에 붙는 작은 UI 는
	--   인셋 아래에서 시작해야 한다.
	--   ★ AbsolutePosition 으로 검증하지 말 것 ★ Studio 플레이 창에서는 이 값이 상단바만큼
	--     음수로 보고되기도 한다(두 ScreenGui 의 AbsoluteSize 가 같게 나오는 창도 있다).
	--     눈으로 보고 판단하라 (docs/abilities.md §7).
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local dash = makeBadge(gui, 0, "대시", keyHint(Config.Input.DashKeys))
	local push = makeBadge(gui, 1, "밀치기", keyHint(Config.Input.PushKeys))

	gui.Parent = playerGui

	RunService.RenderStepped:Connect(function()
		local alive = AbilityState.isAlive()
		dash.frame.Visible = alive
		push.frame.Visible = alive
		if not alive then
			return
		end

		local dashRemaining = AbilityState.dashRemaining()
		dash.fill.Size = UDim2.fromScale(1, dashRemaining / Config.Movement.DashCooldown)
		dash.value.Text = if dashRemaining > 0 then string.format("%.1f", dashRemaining) else "준비"
		dash.value.TextColor3 = if dashRemaining > 0 then Badge.CooldownColor else Badge.ReadyColor

		local uses = AbilityState.pushUsesLeft()
		local pushRemaining = AbilityState.pushRemaining()
		push.fill.Size = UDim2.fromScale(1, pushRemaining / Config.Push.Cooldown)
		push.value.Text = `{uses}회`
		push.value.TextColor3 = if uses <= 0
			then Badge.EmptyColor
			elseif pushRemaining > 0 then Badge.CooldownColor
			else Badge.ReadyColor
	end)
end

return AbilityHud

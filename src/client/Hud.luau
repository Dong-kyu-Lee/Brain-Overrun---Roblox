--!strict
--[[
	Hud — 라운드 상태·문제 본문·타이머·알림. (Phase 3)

	Phase 2 의 임시 StatusDisplay 를 대체한다.

	★ 화면 중앙을 비운다 — 기획서 3장
	  "유저가 화면을 가리는 UI 때문에 시야를 뺏기지 않도록" 이 이 게임의 UI 원칙이다.
	  선택지는 바닥이 보여주므로 HUD 는 절대 보여주지 않는다. HUD 가 아는 것은
	  '문제 본문'과 '남은 시간'뿐이고, 전부 상단 밴드 안에 있다.
	  ★ 상단 밴드 밖으로 UI 를 넓히지 말 것. 특히 화면 아래쪽은 바닥을 보는 영역이다.

	★ 정답은 클라이언트에 오지 않는다
	  QuestionShown 페이로드에는 answer 가 없다(README 규약 2). 선택지 두 개는 어차피
	  바닥에 떠 있으므로 페이로드에 있어도 새는 정보가 아니지만, 어느 쪽이 정답인지는
	  서버만 안다. 판정 결과는 RoundResult 로 '사후에' 온다.

	★ 타이머를 서버 시각으로 계산하는 이유
	  payload.endsAt / payload.deadline 은 GetServerTimeNow() 기준 절대 시각이다.
	  남은 시간을 클라이언트가 스스로 세면 지연·프레임드랍만큼 어긋나 "0초인데 안 끝남"이 된다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Theme = Config.Theme.Hud

local STATE_LABEL = {
	Lobby = "대기 중",
	Countdown = "정답 구역으로 이동!",
	WallRush = "벽이 온다!",
	Judge = "판정",
	Intermission = "다음 라운드 준비",
	GameOver = "게임 종료",
}

--- 문제를 계속 띄워 두는 상태. 벽이 오는 동안에도 옆 레인으로 다이브할 수 있으므로
--- WallRush 에서 문제를 지우면 마지막 판단 근거가 사라진다.
local QUESTION_VISIBLE = {
	Countdown = true,
	WallRush = true,
}

local Hud = {}

local endsAt: number? = nil

--- 밴드 안에서의 세로 배치(비율). 합이 1 이 되도록 유지할 것.
local ROWS = {
	state = { y = 0, height = 0.16, size = 24 },
	prompt = { y = 0.16, height = 0.46, size = 64 },
	timer = { y = 0.62, height = 0.24, size = 44 },
	notify = { y = 0.86, height = 0.14, size = 20 },
}

local function makeLabel(parent: Instance, name: string, row: { y: number, height: number, size: number }, font: Enum.Font): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.fromScale(1, row.height)
	label.Position = UDim2.fromScale(0, row.y)
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextSize = row.size
	label.TextColor3 = Theme.TextColor
	label.TextStrokeTransparency = Theme.StrokeTransparency
	label.Text = ""
	label.Parent = parent
	return label
end

function Hud.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "BO_Hud"
	gui.ResetOnSpawn = false -- 탈락해서 리스폰해도 HUD 는 유지돼야 한다
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local band = Instance.new("Frame")
	band.Name = "Band"
	band.Size = UDim2.fromScale(1, Theme.BandHeight)
	band.Position = UDim2.fromScale(0, Theme.BandTop)
	band.BackgroundTransparency = 1
	band.Parent = gui

	local stateLabel = makeLabel(band, "State", ROWS.state, Theme.Font)
	local promptLabel = makeLabel(band, "Prompt", ROWS.prompt, Theme.PromptFont)
	local timerLabel = makeLabel(band, "Timer", ROWS.timer, Theme.Font)
	local notifyLabel = makeLabel(band, "Notify", ROWS.notify, Theme.Font)

	gui.Parent = playerGui

	Remotes.event("QuestionShown").OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then
			return
		end
		promptLabel.Text = payload.prompt
		-- deadline 은 서버가 RoundStateChanged 와 같은 값으로 보낸다. 둘 중 뭐가 먼저 와도
		-- 타이머가 튀지 않도록 여기서도 받아 둔다.
		endsAt = payload.deadline
	end)

	Remotes.event("RoundStateChanged").OnClientEvent:Connect(function(state: string, round: number, payload)
		local title = STATE_LABEL[state] or state
		stateLabel.Text = if round > 0 then `ROUND {round} — {title}` else title

		endsAt = if typeof(payload) == "table" then payload.endsAt else nil
		if not endsAt then
			timerLabel.Text = ""
		end

		if not QUESTION_VISIBLE[state] then
			promptLabel.Text = ""
		end
	end)

	Remotes.event("RoundResult").OnClientEvent:Connect(function(correctZone: string, survivors: { number })
		notifyLabel.TextColor3 = Theme.NotifyColor.info
		notifyLabel.Text = `정답: {correctZone} 구역 · 생존 {#survivors}명`
	end)

	Remotes.event("Notify").OnClientEvent:Connect(function(message: string, kind: string)
		notifyLabel.TextColor3 = Theme.NotifyColor[kind] or Theme.NotifyColor.info
		notifyLabel.Text = message
	end)

	RunService.RenderStepped:Connect(function()
		local deadline = endsAt
		if not deadline then
			return
		end
		local remaining = math.max(deadline - Workspace:GetServerTimeNow(), 0)
		timerLabel.Text = string.format("%.1f", remaining)
		timerLabel.TextColor3 = if remaining <= Theme.TimerWarnAt then Theme.TimerWarnColor else Theme.TimerColor
	end)
end

return Hud

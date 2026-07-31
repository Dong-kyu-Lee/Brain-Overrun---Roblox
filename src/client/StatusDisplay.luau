--!strict
--[[
	StatusDisplay — 라운드 상태·타이머·알림을 화면 상단에 띄우는 임시 UI. (Phase 2)

	★ 이건 정식 HUD 가 아니다
	  Phase 3 이 문제 텍스트·선택지가 들어간 진짜 HUD 를 만든다. 여기서는 상태머신이
	  제대로 도는지 눈으로 확인할 최소한만 그린다. Phase 3 에서 통째로 교체할 것.

	★ 타이머를 서버 시각으로 계산하는 이유
	  서버가 보내주는 payload.endsAt 은 GetServerTimeNow() 기준이다. 남은 시간을
	  클라이언트가 스스로 세면 지연·프레임드랍만큼 어긋나 "0초인데 안 끝남"이 된다.

	★ 화면 중앙을 비워 두는 이유
	  기획서 3장의 핵심은 "UI 가 시야를 뺏지 않는다"이다. 정답 선택지는 바닥이 보여준다.
	  상단 밴드 밖으로 UI 를 넓히지 말 것.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local StatusDisplay = {}

local STATE_LABEL = {
	Lobby = "대기 중",
	Countdown = "정답 구역으로 이동!",
	WallRush = "벽이 온다!",
	Judge = "판정",
	Intermission = "다음 라운드 준비",
	GameOver = "게임 종료",
}

local NOTIFY_COLOR = {
	info = Color3.fromRGB(230, 230, 230),
	warn = Color3.fromRGB(255, 130, 110),
	good = Color3.fromRGB(140, 240, 160),
}

local endsAt: number? = nil

local function makeLabel(parent: Instance, name: string, size: UDim2, position: UDim2, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.Parent = parent
	return label
end

function StatusDisplay.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "BO_StatusDisplay"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = Instance.new("Frame")
	root.Name = "Band"
	root.Size = UDim2.fromScale(1, 0.22)
	root.Position = UDim2.fromScale(0, 0.02)
	root.BackgroundTransparency = 1
	root.Parent = gui

	local stateLabel = makeLabel(root, "State", UDim2.fromScale(1, 0.3), UDim2.fromScale(0, 0), 28)
	local timerLabel = makeLabel(root, "Timer", UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0.3), 52)
	local notifyLabel = makeLabel(root, "Notify", UDim2.fromScale(1, 0.3), UDim2.fromScale(0, 0.7), 22)

	gui.Parent = playerGui

	Remotes.event("RoundStateChanged").OnClientEvent:Connect(function(state: string, round: number, payload)
		local title = STATE_LABEL[state] or state
		stateLabel.Text = if round > 0 then `ROUND {round} — {title}` else title
		endsAt = if typeof(payload) == "table" then payload.endsAt else nil
		if not endsAt then
			timerLabel.Text = ""
		end
	end)

	Remotes.event("RoundResult").OnClientEvent:Connect(function(correctZone: string, survivors: { number })
		notifyLabel.TextColor3 = NOTIFY_COLOR.info
		notifyLabel.Text = `정답: {correctZone} 구역 · 생존 {#survivors}명`
	end)

	Remotes.event("Notify").OnClientEvent:Connect(function(message: string, kind: string)
		notifyLabel.TextColor3 = NOTIFY_COLOR[kind] or NOTIFY_COLOR.info
		notifyLabel.Text = message
	end)

	RunService.RenderStepped:Connect(function()
		if not endsAt then
			return
		end
		local remaining = math.max(endsAt - Workspace:GetServerTimeNow(), 0)
		timerLabel.Text = string.format("%.1f", remaining)
	end)
end

return StatusDisplay

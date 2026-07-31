--!strict
--[[
	Bootstrap — 클라이언트 진입점.

	Phase 2: 라운드 상태·타이머를 보여주는 임시 표시(StatusDisplay).
	Phase 3 이 StatusDisplay 를 정식 HUD 로 교체하고, Phase 5 가 DashInput/PushInput 을 붙인다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local StatusDisplay = require(script.Parent.StatusDisplay)

local _ = Remotes

StatusDisplay.start()

print("[BrainOverrun] 클라이언트 부팅 완료")

if Config.Debug.Enabled then
	print(("[BrainOverrun] 대시 쿨타임 %.1fs | 밀치기 %d회/게임"):format(
		Config.Movement.DashCooldown,
		Config.Push.MaxUsesPerGame
	))
end

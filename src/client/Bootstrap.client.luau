--!strict
--[[
	Bootstrap — 클라이언트 진입점.

	Phase 0: 공유 모듈 로딩만 확인한다.
	Phase 3 이후 HUD, ScreenRenderer, DashInput, PushInput 을 여기에 연결한다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local _ = Remotes

print("[BrainOverrun] 클라이언트 부팅 완료")

if Config.Debug.Enabled then
	print(("[BrainOverrun] 대시 쿨타임 %.1fs | 밀치기 %d회/게임"):format(
		Config.Movement.DashCooldown,
		Config.Push.MaxUsesPerGame
	))
end

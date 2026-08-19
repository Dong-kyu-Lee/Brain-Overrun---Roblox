--!strict
--[[
	Bootstrap — 클라이언트 진입점.

	Phase 3: 문제·타이머 HUD(Hud). Phase 4: 벽 파괴 폭발(WallEffects).
	Phase 5 가 DashInput/PushInput 을 붙인다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Hud = require(script.Parent.Hud)
local ImagePreload = require(script.Parent.ImagePreload)
local WallEffects = require(script.Parent.WallEffects)

local _ = Remotes

Hud.start()
WallEffects.start() -- 서버의 WallBroken 알림을 기다린다. 연출뿐이라 판정에 영향이 없다.
ImagePreload.start() -- 비동기다. 실패해도 게임은 그대로 돌아간다.

print("[BrainOverrun] 클라이언트 부팅 완료")

if Config.Debug.Enabled then
	print(("[BrainOverrun] 대시 쿨타임 %.1fs | 밀치기 %d회/게임"):format(
		Config.Movement.DashCooldown,
		Config.Push.MaxUsesPerGame
	))
end

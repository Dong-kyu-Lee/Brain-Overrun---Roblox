--!strict
--[[
	Bootstrap — 클라이언트 진입점.

	Phase 3: 문제·타이머 HUD(Hud). Phase 4: 벽 파괴 폭발(WallEffects).
	Phase 5: 능력 상태 사본(AbilityState) → 입력(DashInput/PushInput) → 배지(AbilityHud).

	★ AbilityState 를 가장 먼저 켠다 ★ 입력과 배지가 둘 다 그 사본을 읽는다.
	  순서가 뒤집히면 접속 직후 몇 프레임 동안 "관전 중"으로 보여 입력이 막힌다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local AbilityHud = require(script.Parent.AbilityHud)
local AbilityState = require(script.Parent.AbilityState)
local DashInput = require(script.Parent.DashInput)
local Hud = require(script.Parent.Hud)
local ImagePreload = require(script.Parent.ImagePreload)
local PushInput = require(script.Parent.PushInput)
local WallEffects = require(script.Parent.WallEffects)

local _ = Remotes

Hud.start()
WallEffects.start() -- 서버의 WallBroken 알림을 기다린다. 연출뿐이라 판정에 영향이 없다.
ImagePreload.start() -- 비동기다. 실패해도 게임은 그대로 돌아간다.

AbilityState.start() -- 세션 사본. 아래 셋이 전부 이걸 읽는다.
DashInput.start()
PushInput.start()
AbilityHud.start()

print("[BrainOverrun] 클라이언트 부팅 완료")

if Config.Debug.Enabled then
	print(("[BrainOverrun] 대시 쿨타임 %.1fs | 밀치기 %d회/게임"):format(
		Config.Movement.DashCooldown,
		Config.Push.MaxUsesPerGame
	))
end

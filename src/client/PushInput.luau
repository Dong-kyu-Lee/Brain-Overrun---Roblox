--!strict
--[[
	PushInput — 밀치기 입력을 받아 서버에 '요청'만 보낸다. (Phase 5)

	★ 아무것도 싣지 않는다
	  대상도, 방향도, 거리도 보내지 않는다. 누구를 밀 수 있는지는 서버가 자기 월드에서
	  찾는다(AbilityService.findTargets). 클라이언트가 대상을 지목하면 사거리 밖의 사람을
	  지목하는 조작이 곧바로 가능해진다 — 그래서 이 리모트에는 인자가 없다.

	★ 보유 여부·남은 횟수도 여기서 판정하지 않는다
	  남은 횟수는 AbilityState 로 알 수 있지만 그건 배지를 그리기 위한 사본이다. 0 이어도
	  요청은 보낸다 — 서버가 사유를 알려 주는 편이 "눌렀는데 아무 반응이 없다"보다 낫다.
	  알림 폭주는 서버가 묶어서 막는다(AbilityService.notifyFailure).
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local AbilityState = require(script.Parent.AbilityState)

local ACTION_NAME = "BO_Push"

local PushInput = {}

local lastSentAt = 0

local function tryPush()
	if not AbilityState.isAlive() then
		return
	end
	if AbilityState.pushRemaining() > 0 then
		return
	end

	-- ★ 이 상한은 쿨타임이 아니다 ★ 실패하는 요청(횟수 0 등)은 lastPushAt 을 움직이지
	--   않으므로 쿨타임만으로는 연타를 못 막는다. 그래서 성공·실패와 무관한 상한을 둔다.
	local at = os.clock()
	if at - lastSentAt < Config.Input.MinRequestInterval then
		return
	end

	lastSentAt = at
	Remotes.event("PushRequest"):FireServer()
end

local function onAction(_actionName: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		tryPush()
	end
	return Enum.ContextActionResult.Pass
end

function PushInput.start()
	local keys: { any } = {}
	for _, key in Config.Input.PushKeys do
		table.insert(keys, key)
	end
	for _, key in Config.Input.PushGamepadKeys do
		table.insert(keys, key)
	end

	ContextActionService:BindAction(ACTION_NAME, onAction, Config.Input.TouchButtons, table.unpack(keys))
	ContextActionService:SetTitle(ACTION_NAME, "밀치기")
end

return PushInput

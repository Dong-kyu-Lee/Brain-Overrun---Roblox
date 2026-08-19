--!strict
--[[
	DashInput — 대시 입력을 받아 서버에 '요청'만 보낸다. (Phase 5)

	★ 여기서 캐릭터를 움직이지 않는다 (README 규약 2)
	  대시의 물리는 서버(AbilityService)가 건다. 클라이언트가 자기 캐릭터를 직접 밀면
	  서버가 거절한 요청까지 화면에서는 성공한 것처럼 보이고, 서버가 같은 대시를 또
	  걸어 주는 순간 두 배 속도로 날아간다.
	  ★ 대신 반응이 왕복지연만큼 늦다 ★ 캐릭터의 주인은 이 클라이언트라 서버가 건
	    LinearVelocity 는 곧바로 이 기기에서 시뮬레이션되지만, 요청이 서버에 닿는 시간은
	    그대로 남는다. 하이퍼캐주얼 기준으로 견딜 만해서 이렇게 뒀다.

	★ 방향은 '입력'이지 위치가 아니다
	  Humanoid.MoveDirection 은 카메라 기준으로 이미 변환된 월드 방향이라 그대로 쓸 수 있다.
	  아무 키도 안 누른 상태면 카메라 정면으로 나간다 — 눌렀는데 아무 일도 없는 순간을
	  만들지 않기 위해서다. ★ 서버는 이 값을 그대로 믿지 않는다 ★ 평탄화·정규화를 다시 한다.

	★ 스스로를 막는 이유
	  쿨타임 판정의 주인은 서버다. 그래도 클라이언트가 먼저 걸러 두면 어차피 버려질
	  요청이 네트워크에 나가지 않는다. 여기가 뚫려도 서버에서 다시 막힌다.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local AbilityState = require(script.Parent.AbilityState)

local ACTION_NAME = "BO_Dash"

local DashInput = {}

local player = Players.LocalPlayer
local lastSentAt = 0

local function flatten(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

--- 지금 눌린 이동 입력의 방향. 없으면 카메라 정면. 둘 다 못 구하면 nil.
local function dashDirection(): Vector3?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	if humanoid then
		local move = flatten(humanoid.MoveDirection)
		if move.Magnitude > 1e-3 then
			return move.Unit
		end
	end

	local camera = Workspace.CurrentCamera
	if camera then
		local look = flatten(camera.CFrame.LookVector)
		if look.Magnitude > 1e-3 then
			return look.Unit
		end
	end

	return nil
end

local function tryDash()
	if not AbilityState.isAlive() then
		return
	end
	if AbilityState.dashRemaining() > 0 then
		return
	end

	-- 요청 자체의 상한. 서버도 같은 값으로 막는다(Config.Input.MinRequestInterval).
	local at = os.clock()
	if at - lastSentAt < Config.Input.MinRequestInterval then
		return
	end

	local direction = dashDirection()
	if not direction then
		return
	end

	lastSentAt = at
	Remotes.event("DashRequest"):FireServer(direction)
end

local function onAction(_actionName: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		tryDash()
	end
	-- ★ Sink 하지 않는다 ★ Shift 는 시프트락 등 다른 조작과 겹칠 수 있고, 이동 입력을
	--   가로채면 대시를 누르는 순간 걷기가 멈춘다.
	return Enum.ContextActionResult.Pass
end

function DashInput.start()
	local keys: { any } = {}
	for _, key in Config.Input.DashKeys do
		table.insert(keys, key)
	end
	for _, key in Config.Input.DashGamepadKeys do
		table.insert(keys, key)
	end

	ContextActionService:BindAction(ACTION_NAME, onAction, Config.Input.TouchButtons, table.unpack(keys))
	ContextActionService:SetTitle(ACTION_NAME, "대시")
end

return DashInput

--!strict
--[[
	AbilityState — 서버 세션의 '읽기 전용 사본'. (Phase 5)

	★ 왜 별도 모듈인가
	  대시 입력·밀치기 입력·능력 배지 셋이 전부 같은 것을 알아야 한다 — 남은 쿨타임과
	  남은 밀치기 횟수. 세 모듈이 각자 SessionStateChanged 를 듣고 각자 세션을 들고 있으면
	  같은 값이 세 벌 생기고, 언젠가 한 벌만 갱신되는 날이 온다.

	★ 여기 있는 값은 판정이 아니다
	  전부 서버가 보내 준 사실의 사본일 뿐이고, 클라이언트가 이걸 고쳐도 아무 일도
	  일어나지 않는다. 서버는 요청이 올 때마다 자기 세션으로 다시 판정한다(README 규약 2).
	  입력 모듈이 이 값을 보는 이유는 오직 두 가지다 — 배지를 그리고, 어차피 거절될
	  요청을 굳이 보내지 않기 위해서.

	★ 시각은 서버 시각으로 비교한다
	  lastDashAt 은 서버의 Workspace:GetServerTimeNow() 기준이다. 클라이언트도 같은
	  GetServerTimeNow() 로 빼야 지연과 무관하게 남은 쿨타임이 맞는다. os.clock() 을 섞는
	  순간 게이지가 사람마다 다르게 찬다 (Hud 의 타이머와 같은 이유).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local AbilityState = {}

type Mirror = {
	alive: boolean,
	pushUsesLeft: number,
	lastDashAt: number,
	lastPushAt: number,
}

--- 기본값은 "관전 중, 능력 없음". 서버 응답이 오기 전에는 아무것도 못 하는 쪽이 안전하다.
local mirror: Mirror = {
	alive = false,
	pushUsesLeft = 0,
	lastDashAt = 0,
	lastPushAt = 0,
}

local changedEvent = Instance.new("BindableEvent")
AbilityState.Changed = changedEvent.Event

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function apply(session: any)
	if typeof(session) ~= "table" then
		return
	end

	mirror.alive = session.alive == true
	mirror.pushUsesLeft = tonumber(session.pushUsesLeft) or 0
	mirror.lastDashAt = tonumber(session.lastDashAt) or 0
	mirror.lastPushAt = tonumber(session.lastPushAt) or 0

	changedEvent:Fire()
end

function AbilityState.isAlive(): boolean
	return mirror.alive
end

function AbilityState.pushUsesLeft(): number
	return mirror.pushUsesLeft
end

--- 남은 대시 쿨타임(초). 0 이면 지금 쓸 수 있다.
function AbilityState.dashRemaining(): number
	return math.max(mirror.lastDashAt + Config.Movement.DashCooldown - serverNow(), 0)
end

--- 남은 밀치기 쿨타임(초).
function AbilityState.pushRemaining(): number
	return math.max(mirror.lastPushAt + Config.Push.Cooldown - serverNow(), 0)
end

function AbilityState.start()
	Remotes.event("SessionStateChanged").OnClientEvent:Connect(apply)

	-- 접속 직후 한 번 당겨온다. 이후로는 서버가 바뀔 때마다 밀어 준다.
	task.spawn(function()
		local ok, session = pcall(function()
			return Remotes.func("GetSessionState"):InvokeServer()
		end)
		if ok then
			apply(session)
		end
	end)
end

return AbilityState

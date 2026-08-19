--!strict
--[[
	SessionService — 게임 한 판 동안만 유효한 플레이어 상태. (Phase 2)

	여기에 있는 값은 전부 휘발성이다. 코인·보유 아이템 같은 영구 데이터는
	Phase 6 의 DataStore 가 따로 담당하며 이 모듈은 저장을 하지 않는다.

	★ 서버 권위(README 규약 2)
	  클라이언트는 GetSessionState 로 "읽기"만 할 수 있다. 값을 바꾸는 경로는 없다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

-- 컨테이너를 넘는 require 는 타입이 any 로 무너진다(docs/map-builder.md §4).
-- 아래 타입은 Types.luau 의 SessionState 와 같은 모양이며 함께 고쳐야 한다.
export type Session = {
	alive: boolean,
	spectating: boolean,
	pushUsesLeft: number,
	revivesLeft: number,
	lastDashAt: number,
	lastPushAt: number,
	roundsSurvived: number,
}

local SessionService = {}

local sessions: { [Player]: Session } = {}

local function newSession(): Session
	return {
		-- 기본값은 "관전 중". 게임에 참가할 때만 RoundService 가 alive 로 바꾼다.
		alive = false,
		spectating = true,
		pushUsesLeft = Config.Push.MaxUsesPerGame, -- AbilityService 가 소모한다 (게임 단위)
		revivesLeft = 0, -- Phase 7 에서 구매분 반영
		lastDashAt = 0,
		lastPushAt = 0,
		roundsSurvived = 0,
	}
end

--- 플레이어 세션. 없으면 만든다.
function SessionService.get(player: Player): Session
	local session = sessions[player]
	if not session then
		session = newSession()
		sessions[player] = session
	end
	return session
end

--- 세션 상태를 해당 클라이언트에 밀어 준다.
function SessionService.sync(player: Player)
	if not player.Parent then
		return
	end
	Remotes.event("SessionStateChanged"):FireClient(player, SessionService.get(player))
end

--- 새 게임 시작 시 세션을 초기화한다.
function SessionService.reset(player: Player)
	sessions[player] = newSession()
	SessionService.sync(player)
end

function SessionService.isAlive(player: Player): boolean
	return SessionService.get(player).alive
end

--- 생존 여부를 바꾼다. alive 와 spectating 은 항상 반대여야 하므로 함께 관리한다.
function SessionService.setAlive(player: Player, alive: boolean)
	local session = SessionService.get(player)
	if session.alive == alive then
		return
	end
	session.alive = alive
	session.spectating = not alive
	SessionService.sync(player)
end


-- ─────────────────────────────────────────────
-- 능력 사용 기록 (Phase 5)
--
-- ★ 시각은 반드시 Workspace:GetServerTimeNow() 다 ★
--   이 값은 SessionStateChanged 로 클라이언트에 그대로 나가고, 클라이언트는 자기
--   GetServerTimeNow() 와 빼서 남은 쿨타임을 그린다(HUD 타이머가 deadline 을 쓰는 방식과 같다).
--   os.clock() 이나 tick() 을 넣으면 서버·클라이언트 기준이 달라 게이지가 엉뚱하게 찬다.
--
-- ★ 판정은 여기서 하지 않는다 ★ 쿨타임이 남았는지·횟수가 있는지 '묻는' 쪽은
--   AbilityService 다. 이 파일은 상태를 바꾸고 알릴 뿐이다.
-- ─────────────────────────────────────────────

--- 대시 사용 시각을 찍고 클라이언트에 알린다.
function SessionService.markDash(player: Player, at: number)
	SessionService.get(player).lastDashAt = at
	SessionService.sync(player)
end

--- 밀치기 1회 소모. 남은 횟수가 없으면 아무것도 바꾸지 않고 false.
--- 횟수는 '게임' 단위다 — 라운드마다 채우면 기획서의 "1게임 당 최대 3회"가 무너진다.
--- 채워지는 곳은 SessionService.reset() 하나뿐이고, 그건 게임 시작 시 buildRoster() 가 부른다.
function SessionService.consumePush(player: Player, at: number): boolean
	local session = SessionService.get(player)
	if session.pushUsesLeft <= 0 then
		return false
	end
	session.pushUsesLeft -= 1
	session.lastPushAt = at
	SessionService.sync(player)
	return true
end

function SessionService.addRoundSurvived(player: Player)
	SessionService.get(player).roundsSurvived += 1
	SessionService.sync(player)
end

--- 현재 살아 있는 플레이어 목록. 접속이 끊긴 플레이어는 포함되지 않는다.
function SessionService.alivePlayers(): { Player }
	local result = {}
	for _, player in Players:GetPlayers() do
		if SessionService.isAlive(player) then
			table.insert(result, player)
		end
	end
	return result
end

function SessionService.aliveCount(): number
	return #SessionService.alivePlayers()
end

function SessionService.start()
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
	end)

	Remotes.func("GetSessionState").OnServerInvoke = function(player: Player)
		return SessionService.get(player)
	end
end

return SessionService

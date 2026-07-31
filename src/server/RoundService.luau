--!strict
--[[
	RoundService — 라운드 상태머신. 게임의 시간 축을 혼자서 소유한다. (Phase 2)

	Lobby ─(인원 충족)─▶ Countdown ─▶ WallRush ─▶ Judge ─┬─▶ Intermission ─┐
	                        ▲                             │                 │
	                        └─────────────────────────────│─────────────────┘
	                                                       └─▶ GameOver ─▶ Lobby

	★ 왜 코루틴 1개인가
	  상태 전이가 전부 "몇 초 뒤"로 이어지는 선형 흐름이라, 상태별 콜백을 등록하는
	  구조보다 while 루프 + task.wait 가 읽기 쉽다. 상태를 바꾸는 코드가 이 파일
	  한 곳뿐이라 "지금 무슨 상태인가"를 추적할 필요도 없다.

	★ 생존 판정을 위치 스냅샷으로 하지 않는 이유
	  제한시간이 끝난 순간의 위치로 정답/오답을 확정하면, 벽이 오는 동안 옆 레인으로
	  뛰어드는 마지막 몸부림이 무의미해진다. 대신 판정은 전적으로 물리 결과다 —
	  오답 구역 벽이 밀어내 맵 밖으로 떨어진 사람이 탈락자다(Arena 가 감지).
	  Judge 단계의 eliminateZone 은 그걸 놓쳤을 때를 위한 안전망일 뿐이다.

	★ 정답 구역은 Phase 3 이 정한다
	  지금은 pickCorrectZone() 이 무작위로 고른다. Phase 3 에서 QuestionService 가
	  문제를 뽑고 그 answer 를 넘겨주도록 이 함수만 갈아끼우면 된다.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapLayout = require(Shared:WaitForChild("MapLayout"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Arena = require(script.Parent.Arena)
local SessionService = require(script.Parent.SessionService)
local WallController = require(script.Parent.WallController)

type Zone = "A" | "B" -- Types.luau 참조

local RoundService = {}

local rng = Random.new()

local currentState = "Lobby"
local currentRound = 0

-- 이번 게임에 참가한 인원 수(중간 접속자 제외). 최후의 1인 판정에 쓴다.
local participantCount = 0

-- ─────────────────────────────────────────────
-- 상태 전파
-- ─────────────────────────────────────────────

local function now(): number
	return Workspace:GetServerTimeNow()
end

--- 상태를 바꾸고 전 클라이언트에 알린다.
--- payload.endsAt 은 서버 시각 기준이라 클라이언트가 자기 지연과 무관하게 타이머를 그린다.
local function setState(state: string, round: number, payload: { [string]: any }?)
	currentState = state
	currentRound = round
	Remotes.event("RoundStateChanged"):FireAllClients(state, round, payload)

	if Config.Debug.ShowStateInConsole then
		print(`[Round] {state} | R{round} | 생존 {SessionService.aliveCount()}`)
	end
end

local function notifyAll(message: string, kind: string)
	Remotes.event("Notify"):FireAllClients(message, kind)
end

local function timedState(state: string, round: number, seconds: number, extra: { [string]: any }?)
	local payload: { [string]: any } = { duration = seconds, endsAt = now() + seconds }
	for key, value in extra or {} do
		payload[key] = value
	end
	setState(state, round, payload)
	task.wait(seconds)
end

-- ─────────────────────────────────────────────
-- 라운드 구성 요소
-- ─────────────────────────────────────────────

--- Phase 3 에서 QuestionService.next().answer 로 교체된다.
local function pickCorrectZone(): Zone
	return if rng:NextInteger(0, 1) == 0 then "A" else "B"
end

--- 참가자 확정. 지금 접속해 있는 전원이 참가한다.
local function buildRoster(): number
	local count = 0
	for _, player in Players:GetPlayers() do
		SessionService.reset(player)
		SessionService.setAlive(player, true)
		count += 1
	end
	return count
end

--- 생존자를 A/B 무작위로 나눠 배치한다(기획서 2장: "A/B 구역 중 무작위 스폰").
--- 캐릭터가 아직 없어 배치에 실패한 플레이어는 그 자리에서 탈락시킨다.
--- 살아있는 것으로 두면 관전장에 떠 있어 벽이 닿지 않고, 라운드가 영원히 끝나지 않는다.
local function placeSurvivors()
	for _, player in SessionService.alivePlayers() do
		local zone: Zone = if rng:NextInteger(0, 1) == 0 then "A" else "B"
		if not Arena.placeAtSpawn(player, zone) then
			Arena.eliminate(player, "no-character")
		end
	end
end

--- 게임을 끝내야 하는가.
--- 참가자가 1명뿐인 개발/솔로 상황에서는 "최후의 1인" 조건이 1라운드 만에 성립해
--- 루프를 검증할 수 없으므로, 이때는 탈락할 때까지 계속 진행한다.
local function isGameOver(aliveCount: number): boolean
	if aliveCount == 0 then
		return true
	end
	return participantCount >= 2 and aliveCount <= 1
end

local function awardSurvivors(survivors: { Player })
	for _, player in survivors do
		SessionService.addRoundSurvived(player)
		-- Phase 6 에서 여기서 실제 코인을 적립한다(DataStore).
		Remotes.event("Notify"):FireClient(
			player,
			`생존! +{Config.Economy.CoinsPerRoundSurvived} 코인`,
			"good"
		)
	end
end

local function userIdsOf(players: { Player }): { number }
	local ids = {}
	for _, player in players do
		table.insert(ids, player.UserId)
	end
	return ids
end

-- ─────────────────────────────────────────────
-- 라운드 1회
-- ─────────────────────────────────────────────

--- 한 라운드를 끝까지 진행하고, 게임을 계속해도 되는지 반환한다.
local function runRound(round: number): boolean
	local correctZone = pickCorrectZone()

	-- ① 준비: 벽 원위치 + 생존자 무작위 배치
	WallController.reset()
	placeSurvivors()

	-- ② 문제 노출 & 이동 (Phase 3 이 여기서 QuestionShown 을 함께 쏜다)
	if Config.Debug.RevealAnswer then
		-- Phase 3 전까지 루프를 손으로 테스트하기 위한 힌트. 출시 전 Config.Debug 에서 끈다.
		notifyAll(`[디버그] 정답 구역: {correctZone}`, "info")
	end
	timedState("Countdown", round, Config.getCountdown(round))

	-- ③ 벽 돌진. rush() 가 블로킹하므로 상태 알림은 먼저 보낸다.
	local rushDuration = WallController.rushDuration(round)
	setState("WallRush", round, { duration = rushDuration, endsAt = now() + rushDuration })
	WallController.rush(correctZone, round)

	-- ④ 낙하가 끝나길 기다린 뒤 판정
	task.wait(Config.Round.FallGraceTime)
	Arena.eliminateZone(MapLayout.oppositeZone(correctZone)) -- 안전망

	local survivors = SessionService.alivePlayers()
	Remotes.event("RoundResult"):FireAllClients(correctZone, userIdsOf(survivors))
	awardSurvivors(survivors)

	timedState("Judge", round, Config.Round.ResultDisplayTime, {
		correctZone = correctZone,
		survivors = #survivors,
	})

	if isGameOver(#survivors) then
		return false
	end

	timedState("Intermission", round, Config.Round.IntermissionTime)
	return true
end

-- ─────────────────────────────────────────────
-- 게임 1판
-- ─────────────────────────────────────────────

local function runGame()
	participantCount = buildRoster()
	notifyAll(`게임 시작! 참가자 {participantCount}명`, "info")

	for round = 1, Config.Round.MaxRounds do
		-- 전원이 나가버린 경우 즉시 중단
		if #Players:GetPlayers() == 0 then
			return
		end
		if not runRound(round) then
			break
		end
	end

	local survivors = SessionService.alivePlayers()
	local winner = if #survivors == 1 then survivors[1] else nil

	if winner then
		-- Phase 6 에서 여기서 우승 보너스를 적립한다.
		notifyAll(`🏆 {winner.DisplayName} 우승! +{Config.Economy.CoinsForWin} 코인`, "good")
	else
		notifyAll("생존자 없음 — 무승부", "warn")
	end

	setState("GameOver", currentRound, {
		winnerUserId = if winner then winner.UserId else nil,
	})

	-- 다음 게임을 위해 전원 관전장으로 되돌린다.
	for _, player in Players:GetPlayers() do
		SessionService.setAlive(player, false)
		Arena.sendToSpectator(player)
	end
	WallController.reset()

	task.wait(Config.Round.GameOverTime)
end

-- ─────────────────────────────────────────────
-- 로비
-- ─────────────────────────────────────────────

local function waitForPlayers()
	setState("Lobby", 0)

	while #Players:GetPlayers() < Config.Round.MinPlayersToStart do
		task.wait(1)
	end

	-- 로비 카운트다운. 도중에 인원이 빠지면 처음부터 다시 기다린다.
	local remaining = Config.Round.LobbyTime
	setState("Lobby", 0, { duration = remaining, endsAt = now() + remaining })

	while remaining > 0 do
		task.wait(1)
		remaining -= 1
		if #Players:GetPlayers() < Config.Round.MinPlayersToStart then
			return false
		end
	end
	return true
end

-- ─────────────────────────────────────────────
-- 공개 API
-- ─────────────────────────────────────────────

function RoundService.getState(): (string, number)
	return currentState, currentRound
end

--- 게임 루프를 시작한다. Arena.start() / SessionService.start() 이후에 호출할 것.
function RoundService.start()
	-- 탈락자가 나올 때마다 로그만 남긴다. 게임 종료 판정은 라운드 끝에서 일괄 처리하므로
	-- 여기서 루프를 건드리지 않는다(상태를 바꾸는 곳은 이 파일의 setState 하나뿐이어야 한다).
	Arena.Eliminated:Connect(function(player: Player, reason: string)
		if Config.Debug.VerboseLogging then
			print(`[Round] {player.Name} 탈락({reason}) | 남은 생존자 {SessionService.aliveCount()}`)
		end
	end)

	task.spawn(function()
		while true do
			if waitForPlayers() then
				runGame()
			end
		end
	end)
end

return RoundService

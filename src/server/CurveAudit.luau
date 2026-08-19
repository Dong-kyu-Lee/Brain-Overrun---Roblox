--!strict
--[[
	CurveAudit — 난이도 커브를 부팅 때 한 번 검산하고 표로 찍는다. (Phase 4)

	★ 여기에는 수치가 없다
	  커브 값은 전부 Config 에 있다(README 규약 1). 이 모듈은 흩어져 있는 표를 '합쳐서'
	  읽고 위험한 조합을 부팅 시점에 잡아낸다 — MapService.ensureReady() 와 같은 성격이다.

	★ 왜 검산기가 따로 필요한가
	  커브는 서로를 모르는 독립된 세 축이다 — 제한시간(Round.CountdownByRound),
	  벽 속도(Round.WallSpeed*), 문제 난이도(Question.DifficultyByRound). 한 축만 만져도
	  조합이 조용히 무너지는데, 증상은 "R14 부터 아무도 못 건넌다" 처럼 게임을 열네 판
	  돌려야 보인다. 그래서 부팅 로그 한 장으로 커브 전체를 보이게 만든다.

	★ 여유시간 — 이 파일의 핵심 지표
	    여유시간 = 제한시간 + 벽이 스폰밴드에 닿기까지의 시간 − 레인 횡단 시간
	  플레이어가 '문제를 읽고 판단하는 데' 실제로 쓸 수 있는 시간이다. 제한시간이 끝나도
	  벽이 도착할 때까지는 계속 건너갈 수 있으므로(round-loop.md §3), 제한시간만 보면
	  실제보다 빡빡해 보인다. 이 값이 0 에 가까워지면 정답을 알아도 못 건너는 라운드다.
	  ★ 걷는 속도만 가정한다 — 대시(Phase 5)는 쿨타임이 있어 매 라운드 보장되지 않는다.
	    대시를 전제로 커브를 조이면 쿨타임이 도는 라운드에서 아무도 못 건넌다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapLayout = require(Shared:WaitForChild("MapLayout"))

local QuestionBank = require(script.Parent.QuestionBank)

local CurveAudit = {}

type Row = {
	round: number,
	countdown: number,
	speed: number,
	difficulty: number,
	margin: number,
}

--- 반대편 레인으로 걸어서 건너가는 데 걸리는 시간
local function crossTime(): number
	return MapLayout.LaneCrossDistance / Config.Movement.WalkSpeed
end

local function rowOf(round: number): Row
	local speed = Config.getWallSpeed(round)
	local countdown = Config.getCountdown(round)
	return {
		round = round,
		countdown = countdown,
		speed = speed,
		difficulty = Config.getMaxDifficulty(round),
		margin = countdown + MapLayout.WallReachDistance / speed - crossTime(),
	}
end

--- 세 축이 전부 같은가 (= 앞 라운드와 완전히 같은 라운드인가)
local function sameCurve(a: Row, b: Row): boolean
	return a.countdown == b.countdown and a.speed == b.speed and a.difficulty == b.difficulty
end

--- 계단식으로 움직이는 두 축만 같은가.
--- 벽 속도는 매 라운드 바뀌므로 그것까지 보면 20줄이 전부 찍혀 정작 중요한
--- '제한시간이 줄고 난이도가 오르는 지점'이 묻힌다.
local function sameSteps(a: Row, b: Row): boolean
	return a.countdown == b.countdown and a.difficulty == b.difficulty
end

--- 정답 구역 플레이어가 파괴 직전까지 밀릴 수 있는 최대 거리.
--- 이 값이 레인 길이에 근접하면 정답 구역에 있었는데도 -Z 밖으로 밀려나 탈락한다
--- (round-loop.md §5 의 경계 계산).
local function correctPushDistance(): number
	return MapLayout.WallTravelDistance * MapLayout.CorrectWallBreakProgress
end

--- 스폰밴드의 +Z 끝. 정답 벽은 이 앞에서 멈춰야 한다 — 넘어오면 제자리에 서 있던
--- 정답 구역 플레이어를 밀기 시작한다.
local function spawnBandFrontZ(): number
	return MapLayout.SpawnZoneCenterZ + MapLayout.SpawnZoneSize.Z / 2
end

--- 커브 표를 찍고 경고 건수를 반환한다.
--- 표는 '값이 바뀐 라운드'만 찍는다 — 20줄을 다 찍으면 정작 중요한 변화 지점이 묻힌다.
function CurveAudit.report(): number
	local maxRounds = Config.Round.MaxRounds
	local minMargin = Config.Round.MinReactionMargin
	local warnings = 0

	print(
		-- ★ 거리·속도는 %d 가 아니라 %.0f 로 찍는다. Config 를 손대다 값이 소수가 되는 순간
		--   %d 는 "no integer representation" 으로 터지는데, 하필 그게 검산기라 부팅이 죽는다.
		("[CurveAudit] 커브 %d라운드 | 레인 횡단 %.2fs (%.0f studs ÷ %.0f studs/s) | 벽 도달 %.0f studs"):format(
			maxRounds,
			crossTime(),
			MapLayout.LaneCrossDistance,
			Config.Movement.WalkSpeed,
			MapLayout.WallReachDistance
		)
	)

	local previous: Row? = nil
	local frozenSince: number? = nil
	local tightFrom: number? = nil

	for round = 1, maxRounds do
		local row = rowOf(round)

		if previous == nil or not sameCurve(row, previous :: Row) then
			frozenSince = nil
		elseif frozenSince == nil then
			frozenSince = round -- 이 라운드부터 앞 라운드와 완전히 같다
		end

		-- 계단이 움직인 라운드와 마지막 라운드만 찍는다.
		if previous == nil or not sameSteps(row, previous :: Row) or round == maxRounds then
			print(
				("[CurveAudit]  R%-2d 제한 %.1fs | 벽속도 %3.0f | 난이도 ≤%d | 여유 %.2fs%s"):format(
					round,
					row.countdown,
					row.speed,
					row.difficulty,
					row.margin,
					if row.margin < minMargin then "  ← 부족" else ""
				)
			)
		end

		if row.margin < minMargin and tightFrom == nil then
			tightFrom = round
		end

		-- 그 난이도에 낼 문제가 실제로 있는지. 없으면 QuestionService 가 라운드 도중에
		-- assert 로 서버를 세운다 — 그건 부팅 때 잡아야 할 문제다.
		-- ★ 최악의 경우(공중 보드가 없어 본문 사진 문제를 못 쓰는 맵)로 검사한다.
		--   보드가 있는지는 QuestionDisplay 가 알지만, 그걸 물어보면 검산기가 표시 계층에
		--   의존하게 된다. 더 엄한 조건으로 재는 편이 낫다.
		if #QuestionBank.sources({ maxDifficulty = row.difficulty, allowImagePrompt = false }) == 0 then
			warn(`[CurveAudit] R{round}: 난이도 ≤{row.difficulty} 에 낼 문제가 하나도 없다. QuestionBank 를 채울 것.`)
			warnings += 1
		end

		previous = row
	end

	if tightFrom then
		warn(
			("[CurveAudit] R%d 부터 여유시간이 하한(%.2fs) 아래다 — 정답을 알아도 못 건너는 라운드가 된다. Round.WallSpeedMax 또는 CountdownByRound 를 볼 것."):format(
				tightFrom,
				minMargin
			)
		)
		warnings += 1
	end

	-- 커브가 마지막 몇 라운드 전에 멈춰 버리면 그 구간은 전부 같은 라운드다.
	-- 치명적이지는 않지만 "왜 후반이 안 어려워지지"의 답이 여기 있다.
	if frozenSince and maxRounds - frozenSince >= 3 then
		warn(
			("[CurveAudit] R%d~R%d 커브 정지 — 세 축이 모두 상한이라 %d개 라운드가 같은 난이도다."):format(
				frozenSince,
				maxRounds,
				maxRounds - frozenSince + 1
			)
		)
		warnings += 1
	end

	-- 정답 벽이 스폰밴드 안까지 밀고 들어오면, 자기 구역에서 꼼짝 안 한 사람이 밀리기 시작한다.
	-- 파괴가 '충돌 직전'이려면 코앞이어야 하지만 안으로 들어와서는 안 된다.
	local breakFront = MapLayout.CorrectWallBreakFrontZ
	if breakFront < spawnBandFrontZ() then
		warn(
			("[CurveAudit] 정답 벽이 스폰밴드(z=%.0f)를 %.0f studs 파고든다 — 제자리에 서 있던 정답 구역 플레이어가 밀린다. Round.CorrectWallBreakMargin 을 0 이상으로 둘 것."):format(
				spawnBandFrontZ(),
				spawnBandFrontZ() - breakFront
			)
		)
		warnings += 1
	end

	local push = correctPushDistance()
	if push >= MapLayout.MapLength then
		warn(
			("[CurveAudit] 정답 벽 밀림 %.0f studs ≥ 레인 %.0f studs — 정답 구역인데 밀려 탈락한다. Round.CorrectWallBreakMargin 을 키울 것."):format(
				push,
				MapLayout.MapLength
			)
		)
		warnings += 1
	end

	print(
		("[CurveAudit] 정답 벽 파괴 z=%.1f (진행률 %.2f · 스폰밴드 앞 %.0f studs) | 밀림 최대 %.0f / 레인 %.0f studs | 경고 %d건"):format(
			breakFront,
			MapLayout.CorrectWallBreakProgress,
			breakFront - spawnBandFrontZ(),
			push,
			MapLayout.MapLength,
			warnings
		)
	)

	return warnings
end

return CurveAudit

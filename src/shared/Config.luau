--!strict
--[[
	Config — 게임 전체 밸런싱 수치의 단일 소스(Single Source of Truth).

	원칙: 기획서에 등장하는 모든 숫자는 이 파일에만 존재한다.
	      다른 스크립트에 하드코딩된 상수가 보이면 그건 버그다.
]]

local Config = {}

-- ─────────────────────────────────────────────
-- 맵 (studs 단위)
-- ─────────────────────────────────────────────
Config.Map = {
	LaneLength = 220, -- 레인 길이 (벽이 돌진하는 방향)
	LaneWidth = 40, -- 레인 하나의 폭
	LaneGap = 0, -- A/B 레인 사이 간격 (0 = 맞붙음)
	FloorThickness = 2,
	FloorY = 0, -- 메인 바닥 상면 높이

	WallHeight = 40,
	WallThickness = 8,

	SpectatorHeight = 80, -- 메인 맵 위 관전장 높이
	KillPlaneY = -60, -- 이 아래로 떨어지면 탈락 확정

	-- 라운드 시작 스폰 영역: 벽 반대편(-Z) 끝에 두어 벽이 다가오는 걸 길게 보여준다.
	SpawnBandDepth = 50, -- 스폰 영역의 Z 길이
	SpawnBandInset = 20, -- 레인 -Z 끝단에서 띄우는 거리
	SpawnBandHeight = 8, -- 스폰 판정용 볼륨 높이 (충돌 없음)

	-- 관전장
	SpectatorMargin = 20, -- 메인 맵보다 사방으로 넓힐 거리
	SpectatorRailHeight = 12, -- 관전자 추락 방지 난간 높이

	-- 레인 바깥으로 실수로 떨어지지 않게 막는 측면 벽 (±X). -Z 출구는 막지 않는다.
	SideBarrierHeight = 40,
	SideBarrierThickness = 4,

	KillPlanePadding = 400, -- 킬플레인을 맵보다 얼마나 넓게 깔지
}

-- ─────────────────────────────────────────────
-- 라운드 진행
-- ─────────────────────────────────────────────
Config.Round = {
	MaxRounds = 20,

	-- 라운드별 정답 선택 제한시간(초). 기획서: 5초 → 3초 → 2초로 단축.
	-- 목록 범위를 넘어가면 마지막 값을 유지한다.
	CountdownByRound = { 5, 5, 4, 4, 3, 3, 3, 2 },
	MinCountdown = 2,

	-- 파괴의 벽 이동 속도 (studs/sec). 라운드마다 가산되며 상한에서 고정.
	WallSpeedBase = 55,
	WallSpeedPerRound = 8,
	WallSpeedMax = 170,

	IntermissionTime = 3, -- 라운드 사이 대기
	ResultDisplayTime = 2, -- 생존/탈락 결과 노출 시간
	LobbyTime = 15, -- 게임 시작 전 로비 대기
	MinPlayersToStart = 1, -- 개발 중에는 1, 출시 시 2로 올릴 것
}

-- ─────────────────────────────────────────────
-- 플레이어 조작
-- ─────────────────────────────────────────────
Config.Movement = {
	WalkSpeed = 22,
	JumpPower = 50,

	DashCooldown = 2, -- 기획서 명시
	DashSpeed = 95,
	DashDuration = 0.18,
}

-- ─────────────────────────────────────────────
-- 밀치기 스킬 (전술 아이템)
-- ─────────────────────────────────────────────
Config.Push = {
	MaxUsesPerGame = 3, -- 기획서 명시: 트롤링 과열 방지
	Cooldown = 1.5,
	Range = 12,
	ConeAngle = 60, -- 전방 판정 각도(도)
	Force = 75,
	UpwardForce = 15,
}

-- ─────────────────────────────────────────────
-- 경제
-- ─────────────────────────────────────────────
Config.Economy = {
	StartingCoins = 0,
	CoinsPerRoundSurvived = 10, -- 기획서 명시
	CoinsForWin = 100, -- 기획서 명시: 최후의 1인 보너스
	PushSkillPrice = 500, -- 기획서 명시: 10~15판이면 무과금 구매 가능
}

-- ─────────────────────────────────────────────
-- 수익화 (Phase 7에서 실제 ID로 교체)
-- ─────────────────────────────────────────────
Config.Products = {
	ReviveTicket = 0, -- 개발자 상품: 1회 부활권
	PushSkillRobux = 0, -- 개발자 상품: 밀치기 스킬 즉시 해금
}

-- ─────────────────────────────────────────────
-- 맵 외형 (밸런싱과 무관 — 리스킨은 여기만 고친다)
-- ─────────────────────────────────────────────
Config.Theme = {
	ZoneAColor = Color3.fromRGB(56, 132, 222), -- A구역: 파랑
	ZoneBColor = Color3.fromRGB(240, 148, 52), -- B구역: 주황
	ZoneMaterial = Enum.Material.SmoothPlastic,

	WallColor = Color3.fromRGB(196, 40, 28),
	WallMaterial = Enum.Material.DiamondPlate,

	SpectatorColor = Color3.fromRGB(180, 220, 255),
	SpectatorTransparency = 0.75, -- 아래 경기장이 보여야 한다
	SpectatorMaterial = Enum.Material.Glass,

	RailColor = Color3.fromRGB(120, 160, 200),
	RailTransparency = 0.5,

	-- 측면 벽은 시야를 가리면 안 되므로 완전 투명. 디버그 시에만 살짝 보인다.
	BarrierTransparency = 1,
	BarrierDebugTransparency = 0.9,

	-- 스폰 영역 마커는 평소 안 보이고 디버그에서만 보인다.
	SpawnZoneDebugTransparency = 0.85,
	SpawnZoneColor = Color3.fromRGB(255, 255, 255),
}

-- ─────────────────────────────────────────────
-- 저장 / 디버그
-- ─────────────────────────────────────────────
Config.DataStore = {
	Name = "BrainOverrun_PlayerData_v1",
	AutoSaveInterval = 120,
	MaxRetries = 3,
	RetryDelay = 2,
}

Config.Debug = {
	Enabled = true, -- 출시 전 false
	VerboseLogging = true,
	ShowStateInConsole = true,
}

-- ─────────────────────────────────────────────
-- 파생값 헬퍼
-- ─────────────────────────────────────────────

--- 해당 라운드의 정답 선택 제한시간
function Config.getCountdown(round: number): number
	local list = Config.Round.CountdownByRound
	local value = list[math.min(round, #list)] or Config.Round.MinCountdown
	return math.max(value, Config.Round.MinCountdown)
end

--- 해당 라운드의 벽 속도
function Config.getWallSpeed(round: number): number
	local r = Config.Round
	return math.min(r.WallSpeedBase + (round - 1) * r.WallSpeedPerRound, r.WallSpeedMax)
end

return Config

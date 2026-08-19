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
	SpawnEdgeMargin = 4, -- 스폰 영역 가장자리에서 띄우는 여유(벽에 끼는 것 방지)
	CharacterSpawnHeight = 5, -- 텔레포트 시 바닥 위로 띄우는 높이

	-- 관전장
	SpectatorMargin = 20, -- 메인 맵보다 사방으로 넓힐 거리
	SpectatorRailHeight = 12, -- 관전자 추락 방지 난간 높이
	SpectatorEdgeMargin = 10, -- 관전자 배치 시 난간에서 띄우는 여유
	LobbySpawnSize = 40, -- 관전장 위 로비 SpawnLocation 한 변 길이

	-- 레인 바깥으로 실수로 떨어지지 않게 막는 측면 벽 (±X). -Z 출구는 막지 않는다.
	SideBarrierHeight = 40,
	SideBarrierThickness = 4,

	KillPlanePadding = 400, -- 킬플레인을 맵보다 얼마나 넓게 깔지
	FallEliminationY = -30, -- 킬플레인 Touched 를 놓쳤을 때의 낙하 탈락 백스톱 높이

	-- 벽이 캐릭터를 관통(clip)했을 때 강제로 밀어내는 여유 거리
	WallShoveMargin = 2,

	-- 바닥 스크린에 선택지를 그리는 위치 (Phase 3).
	--
	-- ★ 스폰밴드(-90~-40) 바로 앞에 붙인다. 멀리 두면 못 읽는다 — 바닥 글자는 눈높이에서
	--   거의 눕혀 보이므로(시선각 약 8°) 거리가 두 배가 되면 체감 크기는 네 배로 줄어든다.
	--   Z=+10 에 뒀을 때 스폰 지점에서 화면 세로의 2.5% 밖에 안 됐다(Studio 실측).
	AnswerBandCenterZ = -30,
	-- 선택지가 레인 방향으로 쓸 수 있는 최대 깊이 = 글자 높이 상한(studs).
	-- 실제 크기는 보통 레인 폭(40)에 먼저 걸리므로 여유만 주면 된다.
	AnswerBandDepth = 70,

	-- 발밑 A/B 존 표기. 선택지보다 눈에 띄면 안 된다 — 발밑이라 카메라에 훨씬 가까워서
	-- 같은 크기로 두면 선택지를 압도한다. 중심 Z 는 스폰밴드와 같으므로 깊이만 정한다.
	ZoneLabelDepth = 10,

	-- 공중 문제 보드 (BO_QuestionBoard).
	-- 두 레인 중앙(X=0) 상공에 한 장 세우고, 여기에 문제 본문과 '본문 사진'을 띄운다.
	-- 폭은 MapLayout 이 맵 폭(80)에서 파생시킨다 — 경기장을 액자처럼 감싸는 형태다.
	--
	-- ★ 두 개의 기하 제약이 있다. 어기면 조용히 안 보이게 된다 (docs/map-builder.md §7)
	--   1) 보드 아랫변 > 벽 높이(WallHeight=40).
	--      낮으면 라운드 시작 순간 벽(양 레인 합쳐 맵 폭 전체를 덮는다)이 보드를 가린다.
	--   2) 보드 윗변 < 관전장 높이(SpectatorHeight=80).
	--      넘으면 관전장 유리 바닥을 뚫고 올라간다.
	QuestionBoardHeight = 32,
	QuestionBoardThickness = 2,
	QuestionBoardBottomY = 44, -- 제약 1 (벽 높이 40 + 여유 4)
	QuestionBoardGap = 8, -- 벽 뒷면에서 +Z 로 더 띄우는 거리. 벽이 보드를 스치지 않게 한다.
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

	-- 정답 구역의 벽이 파괴되는 시점(이동 진행률 0~1).
	-- 기획서 "충돌 직전 파괴" — 눈앞까지 오되 플레이어를 맵 밖으로 밀어낼 수는 없는 값이어야 한다.
	CorrectWallBreakProgress = 0.35,

	FallGraceTime = 1.5, -- 벽 통과 후 낙하가 끝나길 기다리는 시간
	FallCheckInterval = 0.25, -- 낙하 탈락 백스톱 폴링 주기

	IntermissionTime = 3, -- 라운드 사이 대기
	ResultDisplayTime = 2, -- 생존/탈락 결과 노출 시간
	GameOverTime = 5, -- 우승자 발표 후 다음 게임까지 대기
	LobbyTime = 15, -- 게임 시작 전 로비 대기
	MinPlayersToStart = 1, -- 개발 중에는 1, 출시 시 2로 올릴 것
}

-- ─────────────────────────────────────────────
-- 문제 출제
--
-- 문제의 '내용'(연산 종류·숫자 범위·보기 문구)은 여기 없다. 서버 전용 모듈
-- QuestionBank 가 갖고 있다 — 이유는 docs/question-system.md §3.
-- 여기 있는 것은 전부 "언제 무엇을 뽑는가"를 정하는 밸런싱 손잡이다.
-- ─────────────────────────────────────────────
Config.Question = {
	-- 라운드별 난이도 상한(1~5). 이 값 '이하'의 문제 중에서 뽑으므로 쉬운 문제도 계속 나온다.
	-- 목록 범위를 넘어가면 마지막 값을 유지한다. (커브 정밀 조정은 Phase 4)
	DifficultyByRound = { 1, 1, 2, 2, 3, 3, 4, 4, 5 },

	-- 최근 N개 문제는 다시 내지 않는다. 같은 문제가 다시 나오면 앞 라운드의 정답 구역을
	-- 기억한 사람이 문제를 읽지 않고 달린다 — 코어 루프가 통째로 무의미해진다.
	RecentHistorySize = 10,

	-- 중복 회피 재추첨 한계. 넘어가면 중복을 허용한다.
	-- 라운드를 멈추는 것보다 같은 문제가 한 번 더 나오는 편이 낫다.
	MaxDrawAttempts = 12,

	-- 이미지형 문제가 뽑힐 확률. 이미지 문제가 하나도 없으면 무시된다(Phase 8).
	-- ★ 문제 하나가 아니라 '풀'을 고르는 확률이다. 1.0 으로 두면 해당 난이도에 이미지
	--   문제가 하나라도 있는 한 텍스트 문제가 아예 안 나온다 (QuestionService.poolFor).
	ImageChance = 0.3,
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

	-- 바닥 선택지 스크린 (Phase 3 — BO_AnswerScreen)
	Screen = {
		PixelsPerStud = 8, -- 캔버스 해상도. 올리면 선명해지지만 메모리를 더 쓴다.
		LightInfluence = 0, -- 0 = 조명 무시. 벽 그림자에 들어가도 선택지는 또렷해야 한다.

		-- Top 면 SurfaceGui 의 캔버스는 가로가 '레인 길이' 방향이라, 글자를 그대로 놓으면
		-- 레인을 따라 옆으로 눕는다. -90° 가 플레이어(+Z 를 봄) 기준으로 바로 선다.
		-- ★ Studio 에서 실측한 값이다. 추측으로 바꾸지 말 것 (docs/question-system.md §5).
		--   +90 을 넣으면 정확히 180° 뒤집힌 글자가 나온다.
		LabelRotation = -90,

		Font = Enum.Font.GothamBlack,
		TextColor = Color3.fromRGB(255, 255, 255),
		StrokeTransparency = 0.2,
		ChoicePadding = 0.06, -- 선택지 영역 안쪽 여백(스케일)

		ZoneLabelTransparency = 0.75, -- 발밑 A/B 표기는 선택지보다 흐리게
		ZoneLabelPadding = 0.35,

		-- 판정 순간 바닥 전체를 물들이는 색. ★ Countdown 중에는 절대 쓰지 않는다 ★
		CorrectTint = Color3.fromRGB(70, 220, 120),
		WrongTint = Color3.fromRGB(230, 70, 60),
		TintTransparency = 0.45,

		-- 관전장 구석에서 반대편 레인 끝을 내려다보는 최악의 경우까지 덮는 여유 배수.
		-- MapLayout.ScreenViewDistance 가 이 값을 써서 SurfaceGui.MaxDistance 를 계산한다.
		ViewDistanceSlack = 2,
	},

	-- 공중 문제 보드 (BO_QuestionBoard).
	-- ★ 이미지 본문 문제의 '주' 표시 장치다. 보드가 없으면 이미지 본문 문제는
	--   아예 출제되지 않는다(QuestionService.poolFor). docs/question-system.md §6.
	Board = {
		PixelsPerStud = 12,
		LightInfluence = 0,
		Font = Enum.Font.GothamBlack,
		TextColor = Color3.fromRGB(255, 255, 255),
		StrokeTransparency = 0.2,
		Padding = 0.08,

		-- 보드 파트 자체의 외형. 사진 뒤가 밝으면 대비가 죽으므로 어둡게 둔다.
		BackgroundColor = Color3.fromRGB(18, 20, 28),
		Material = Enum.Material.SmoothPlastic,

		-- 이미지 본문일 때 지시문("이 동물은?")이 가져가는 가로 비율. 나머지를 사진이 쓴다.
		-- ★ 위아래가 아니라 좌우로 나누는 이유: 보드가 80×32 로 가로가 2.5배 길어서,
		--   위아래로 자르면 사진의 한 변이 세로에 먼저 걸려 작아진다(ScaleType.Fit).
		--   좌우로 나누면 사진이 보드 높이를 그대로 쓴다.
		ImageCaptionWidth = 0.34,
		ImageGap = 0.03, -- 지시문과 사진 사이 여백(가로 비율)
	},

	-- HUD (Phase 3). 화면 중앙은 비운다 — 선택지는 바닥이 보여준다.
	Hud = {
		BandHeight = 0.3, -- 화면 상단에서 차지하는 세로 비율
		BandTop = 0.015,

		Font = Enum.Font.GothamBold,
		PromptFont = Enum.Font.GothamBlack,
		TextColor = Color3.fromRGB(255, 255, 255),
		StrokeTransparency = 0.35,

		TimerColor = Color3.fromRGB(255, 255, 255),
		TimerWarnColor = Color3.fromRGB(255, 110, 90),
		TimerWarnAt = 1.5, -- 남은 시간이 이 값 이하로 떨어지면 경고색

		NotifyColor = {
			info = Color3.fromRGB(230, 230, 230),
			warn = Color3.fromRGB(255, 130, 110),
			good = Color3.fromRGB(140, 240, 160),
		},
	},
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

	-- 출제된 문제와 정답 구역을 '서버 콘솔에만' 찍는다. 클라이언트로는 나가지 않으므로
	-- 켜 둔 채 테스트해도 정답이 새지 않는다. (Phase 2 의 RevealAnswer 는 전 클라이언트에
	-- 뿌리는 물건이었고, 진짜 문제가 생긴 지금 존재 이유가 없어져 제거했다.)
	LogQuestions = true,
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

--- 해당 라운드에 출제 가능한 난이도 상한. QuestionBank 는 이 값 이하의 문제만 후보로 삼는다.
function Config.getMaxDifficulty(round: number): number
	local list = Config.Question.DifficultyByRound
	return list[math.clamp(round, 1, #list)]
end

return Config

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
	--
	-- ★ 상한은 '커브가 멈추는 지점'이다 (Phase 4)
	--   제한시간은 R8 에 2초, 난이도는 R9 에 5 로 상한에 닿아 그 뒤로는 움직이지 않는다.
	--   즉 후반 라운드를 서로 다르게 만드는 축은 이 속도 하나뿐이다. 170 이면 R16 에
	--   상한에 걸려 R16~R20 이 완전히 같은 라운드가 됐다 — 5라운드가 통째로 같은 난이도다.
	--   205 는 R20(55+19×8=207)에서야 걸리는 값이라 마지막까지 커브가 살아 있다.
	--   ★ 올릴 때는 반드시 MinReactionMargin 을 함께 볼 것. CurveAudit 이 부팅 때 검산한다.
	WallSpeedBase = 55,
	WallSpeedPerRound = 8,
	WallSpeedMax = 205,

	-- 커브 검증 하한(초). "여유시간"이 이 값 아래로 내려가면 CurveAudit 이 경고한다.
	--   여유시간 = 제한시간 + 벽이 스폰밴드에 닿기까지의 시간 − 레인 횡단 시간
	-- 곧 플레이어가 '문제를 읽고 판단하는 데' 실제로 쓸 수 있는 시간이다. 제한시간이 끝나도
	-- 벽이 올 때까지는 계속 건너갈 수 있으므로(round-loop.md §3) 제한시간만 보면 실제보다
	-- 빡빡해 보인다. 반대로 이 값이 0 에 가까워지면 정답을 알아도 못 건너는 라운드가 된다.
	MinReactionMargin = 0.8,

	-- 정답 구역의 벽이 파괴되는 지점. 벽 '선단면'이 스폰밴드 앞 이 거리(studs)에 닿는 순간이다.
	-- 실제 진행률은 MapLayout.CorrectWallBreakProgress 가 맵 치수에서 파생시킨다.
	--
	-- ★ 진행률(0~1)이 아니라 거리로 적는 이유
	--   예전에는 0.35 라는 진행률이었고, 벽이 z=+34 — 레인 한복판 — 에서 부서졌다.
	--   그러면 벽이 아직 멀리 있을 때 '정답 쪽이 사라지는' 장면이 먼저 보여서,
	--   문제를 안 읽고 부서지는 쪽으로 달려도 여유 있게 살 수 있었다. 파괴가 곧 정답 공개다.
	--   ★ 파괴는 반드시 '이미 늦은 시점'에 일어나야 한다 ★ 그 시점은 진행률이 아니라
	--   스폰 지점과의 거리로 정의되는 값이라, 맵 길이가 바뀌면 진행률은 따라 바뀌어야 한다.
	--
	-- ★ 0 보다 작게 두지 말 것. 벽이 스폰밴드 안까지 밀고 들어와 제자리에 서 있던
	--   정답 구역 플레이어를 밀기 시작한다. CurveAudit 이 부팅 때 경고한다.
	CorrectWallBreakMargin = 2,

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
	-- 목록 범위를 넘어가면 마지막 값을 유지한다.
	--
	-- ★ 하한은 두지 않는다 (Phase 4 결정)
	--   R20 에서도 난이도 1("더 큰 수는?")이 나올 수 있다. 이건 버그가 아니라 커브 형태다 —
	--   후반의 압박은 문제가 아니라 벽 속도가 담당한다(Round.WallSpeedMax 주석).
	--   여유시간이 1초 남짓인 라운드에서 난이도 5 만 낸다면 실력이 아니라 운으로 갈린다.
	--   하한이 필요해지면 여기에 MinDifficultyByRound 를 만들고 QuestionBank.Filter 에
	--   minDifficulty 를 추가하면 된다. 그때는 풀이 비었을 때 하한을 낮추는 대비가 필수다.
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

	-- 벽 파괴 폭발 (Phase 4 — 클라이언트 WallEffects 가 로컬로 재생한다).
	--
	-- ★ 여기 있는 것은 전부 '보이는 것'뿐이다. 폭발이 무언가를 밀어내는 수치는 없고,
	--   있어서도 안 된다. 정답 구역에 서 있던 사람이 폭발에 밀려 -Z 밖으로 떨어지면
	--   오답도 아닌데 탈락한다 (src/client/WallEffects.luau 헤더).
	WallBreak = {
		-- 벽 앞면을 따라 몇 군데서 터뜨리는가. 벽은 레인 폭(40 studs)만큼 넓어서
		-- 한 점에서만 터뜨리면 눈앞을 가로막던 물건이 사라지는 느낌이 나지 않는다.
		BurstPoints = 3,
		BurstSpread = 0.6, -- 폭발 지점을 벽 폭의 몇 %에 걸쳐 배치할지 (1 = 양 끝까지)

		-- 이펙트 인스턴스가 사라지기까지(초).
		-- ★ 다음 라운드 WallController.reset() 전에 반드시 끝나야 한다. 파괴는 WallRush
		--   도중에 일어나므로 남은 돌진 시간 + FallGraceTime + ResultDisplayTime +
		--   IntermissionTime 이 전부 뒤에 남아 있다 — 2초는 넉넉하다.
		Lifetime = 2,

		-- 입자 세 겹. 불꽃이 순간을, 연기가 잔상을, 불티가 방향감을 만든다.
		Fire = {
			Texture = "rbxasset://textures/particles/fire_main.dds",
			Count = 55, -- 한 지점당 입자 수
			SpeedMin = 30,
			SpeedMax = 70,
			SizeStart = 6,
			SizeEnd = 14,
			LifeMin = 0.25,
			LifeMax = 0.55,
			ColorStart = Color3.fromRGB(255, 232, 150),
			ColorEnd = Color3.fromRGB(255, 88, 30),
			Spread = 140, -- 거의 구형으로 퍼뜨린다(방향 의존을 없앤다)
			LightEmission = 0.9,
		},
		Smoke = {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Count = 35,
			SpeedMin = 10,
			SpeedMax = 28,
			SizeStart = 8,
			SizeEnd = 26,
			LifeMin = 0.6,
			LifeMax = 1.2,
			ColorStart = Color3.fromRGB(96, 96, 102),
			ColorEnd = Color3.fromRGB(38, 38, 44),
			Spread = 180,
			LightEmission = 0,
		},
		Spark = {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Count = 40,
			SpeedMin = 45,
			SpeedMax = 110,
			SizeStart = 1.6,
			SizeEnd = 0.2,
			LifeMin = 0.3,
			LifeMax = 0.8,
			ColorStart = Color3.fromRGB(255, 240, 190),
			ColorEnd = Color3.fromRGB(255, 150, 60),
			Spread = 180,
			LightEmission = 1,
		},

		-- 섬광. 벽이 사라지는 순간을 한 프레임에 알아채게 만드는 장치다.
		Flash = {
			Color = Color3.fromRGB(255, 190, 120),
			Brightness = 6,
			Range = 70,
			Time = 0.25,
		},

		-- 카메라 흔들림. ★ 과하면 그대로 멀미가 된다 ★ 짧고 약하게, 거리로 감쇠시킨다.
		Shake = {
			Intensity = 1.6, -- studs
			Time = 0.35,
			Falloff = 140, -- 이 거리에서 0. 상공 관전장(높이 80)에서는 약하게 흔들린다.
		},

		-- 사운드는 Phase 8 담당이다. 여기는 자리만 있고, 비어 있으면 재생하지 않는다.
		SoundId = "",
		SoundVolume = 0.6,
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

--- 라운드별 커브 표 조회. 표 범위를 넘어가면 마지막 값을 유지한다.
--- ★ 커브 표를 읽는 규칙은 이 함수 하나뿐이어야 한다. 예전에는 getCountdown 이 math.min,
---   getMaxDifficulty 가 math.clamp 을 써서 함수마다 규칙이 미묘하게 달랐다 — 그런 차이는
---   표 길이가 달라지는 날 조용히 어긋난다.
local function curveAt(list: { number }, round: number): number
	return list[math.clamp(round, 1, #list)]
end

--- 해당 라운드의 정답 선택 제한시간
function Config.getCountdown(round: number): number
	return math.max(curveAt(Config.Round.CountdownByRound, round), Config.Round.MinCountdown)
end

--- 해당 라운드의 벽 속도
function Config.getWallSpeed(round: number): number
	local r = Config.Round
	return math.min(r.WallSpeedBase + (round - 1) * r.WallSpeedPerRound, r.WallSpeedMax)
end

--- 해당 라운드에 출제 가능한 난이도 상한. QuestionBank 는 이 값 이하의 문제만 후보로 삼는다.
function Config.getMaxDifficulty(round: number): number
	return curveAt(Config.Question.DifficultyByRound, round)
end

return Config

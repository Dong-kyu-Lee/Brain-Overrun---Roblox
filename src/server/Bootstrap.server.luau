--!strict
--[[
	Bootstrap — 서버 진입점.

	초기화 순서가 중요하다.
	  1) Remotes  — 클라이언트가 WaitForChild 로 기다리므로 가장 먼저.
	  2) 맵 검증   — 아래 서비스들이 태그로 맵 오브젝트를 찾는다.
	  3) 서비스    — SessionService → Arena → QuestionDisplay → RoundService → AbilityService
	                (뒤가 앞을 require 한다).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local AbilityService = require(script.Parent.AbilityService)
local CurveAudit = require(script.Parent.CurveAudit)
local MapService = require(script.Parent.MapService)
local MovementAudit = require(script.Parent.MovementAudit)
local SessionService = require(script.Parent.SessionService)
local Arena = require(script.Parent.Arena)
local ImageAssets = require(script.Parent.ImageAssets)
local QuestionBank = require(script.Parent.QuestionBank)
local QuestionDisplay = require(script.Parent.QuestionDisplay)
local RoundService = require(script.Parent.RoundService)

-- Remotes 를 서버에서 먼저 require 해야 클라이언트가 기다리지 않는다.
local _ = Remotes

-- 클라이언트가 문제 이미지를 미리 받아 둘 수 있게 ID 목록을 준다.
-- ★ assetIds() 는 '이름표 없는' 평탄한 배열이다. ImageAssets 테이블 자체를 넘기면
--   ID↔이름 대응표가 통째로 새어나가 정답이 공개된다 (README 규약 2).
Remotes.func("GetImageAssets").OnServerInvoke = function()
	return ImageAssets.assetIds()
end

-- 맵은 씬(place)에 미리 배치돼 있다(README 규약 4). 여기서는 만들지 않고 검증만 한다.
-- 맵이 없거나 필수 태그가 빠졌으면 여기서 서버를 세운다 — 반쯤 망가진 맵으로 돌리지 않는다.
MapService.ensureReady()

-- 난이도 커브 검산(Phase 4). 맵 치수에서 파생되는 지표가 있으므로 ensureReady() 다음이다.
-- 여기서 경고가 뜨면 게임은 돌아가지만 특정 라운드가 사람이 못 푸는 상태라는 뜻이다.
CurveAudit.report()

-- 능력 수치 검산(Phase 5). 대시 거리와 밀치기 사거리를 맵 치수와 대조한다.
-- 경고가 뜨면 게임은 돌아가지만 대시 한 번에 반대 레인에 착지하거나 스폰선에서
-- 뒤로 대시하면 즉사하는 상태라는 뜻이다.
MovementAudit.report()

SessionService.start()
Arena.start() -- KillPlane 태그를 찾으므로 ensureReady() 이후여야 한다
QuestionDisplay.start() -- BO_AnswerScreen 태그를 찾으므로 ensureReady() 이후여야 한다
RoundService.start()
AbilityService.start() -- 대시/밀치기 요청 수신. RoundService 의 상태를 읽으므로 그 뒤다.

print("[BrainOverrun] 서버 부팅 완료")

if Config.Debug.Enabled then
	local textSources, imageSources = QuestionBank.count()
	local sets, entries = ImageAssets.count()
	print(
		("[BrainOverrun] 디버그 모드 | 1R 제한시간 %ds, 1R 벽속도 %d studs/s | 문제 %d종(텍스트 %d, 이미지 %d)"):format(
			Config.getCountdown(1),
			Config.getWallSpeed(1),
			textSources + imageSources,
			textSources,
			imageSources
		)
	)
	print(
		("[BrainOverrun] 이미지 에셋 %d세트 %d항목 | 공중 보드 %s"):format(
			sets,
			entries,
			if QuestionDisplay.hasBoard() then "있음" else "없음(사진 문제 비활성)"
		)
	)
end

--!strict
--[[
	QuestionService — 문제를 뽑고, 정답을 어느 바닥에 놓을지 정한다. ★ 서버 전용 ★ (Phase 3)

	Phase 2 의 RoundService.pickCorrectZone() 자리를 대신한다. 라운드 흐름은 그대로다 —
	정답 구역이 '동전 던지기'에서 '문제의 답'으로 바뀌었을 뿐이다.

	★ 정답 구역은 문제가 아니라 여기서 정한다
	  QuestionBank 의 make() 는 정답 보기와 오답 보기만 만든다. 둘 중 어느 쪽이 A 바닥에
	  놓이는지는 매 출제마다 여기서 무작위로 뒤집는다. 문제 DB 에 존이 박혀 있으면
	  같은 문제를 두 번 본 사람이 문제를 읽지 않고 정해진 쪽으로 달린다.

	★ 클라이언트로 나가는 것은 payloadOf() 가 만든 것뿐이다
	  Question 에는 answer 가 있다. 이 테이블을 통째로 FireAllClients 에 넘기면 그 순간
	  게임이 끝난다(README 규약 2). payloadOf 는 필드를 하나씩 옮겨 적는다 —
	  table.clone 후 answer 만 지우는 방식은 나중에 필드가 늘 때 조용히 새어나간다.

	★ 왜 표시 모듈(QuestionDisplay)을 require 하는가
	  본문이 사진인 문제는 공중 보드가 있어야만 띄울 수 있다. 보드가 없는 맵에서 그런
	  문제를 뽑으면 지시문("이 동물은?")만 뜨고 사진이 어디에도 없는 — 아무도 풀 수 없는
	  라운드가 된다. 그래서 '무엇을 뽑을 수 있는가'가 '무엇을 그릴 수 있는가'에 달려 있다.
	  QuestionDisplay 는 QuestionService 를 참조하지 않으므로 순환은 없다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local QuestionBank = require(script.Parent.QuestionBank)
local QuestionDisplay = require(script.Parent.QuestionDisplay)

-- Types.luau 참조. 컨테이너를 넘는 require 는 타입이 살아남지 않는다(map-builder.md §4).
type Zone = "A" | "B"
type MediaKind = "text" | "image"

export type Question = {
	id: string,
	prompt: string,
	promptImage: string?,
	choiceKind: MediaKind,
	choices: { A: string, B: string },
	answer: Zone,
	difficulty: number,
}

--- 클라이언트로 나가는 형태. answer 가 없다.
--- ★ promptImage 도 없다 — 본문 사진은 월드(공중 보드)가 그리므로 HUD 가 알 필요가 없다.
export type Payload = {
	id: string,
	prompt: string,
	choiceKind: MediaKind,
	choices: { A: string, B: string },
	deadline: number,
}

local QuestionService = {}

local rng = Random.new()

--- 최근 출제한 문제의 '중복 키'. 링 버퍼로 Config.Question.RecentHistorySize 개만 유지한다.
--- ★ 본문 문자열이 아니라 키를 쓴다. 이미지 문제는 본문이 항상 "이 동물은?" 으로 같아서
---   본문으로 판정하면 첫 출제 직후 그 유형이 통째로 막힌다(docs/question-system.md §4).
local recentKeys: { string } = {}
local recentCursor = 0

--- 직전 라운드에 쓴 문제 종류. 같은 유형이 연달아 나오면 문제를 읽는 재미가 없다.
local lastSourceId: string? = nil

--- 출제 일련번호. 같은 본문이 다시 나와도 payload.id 는 항상 달라야
--- 클라이언트가 "새 문제가 왔다"를 오해 없이 판단한다.
local serial = 0

--- 같은 문제를 두 번 냈는지 가리는 키. Draft.key 가 있으면 그것을, 없으면 본문을 쓴다.
local function dedupeKey(draft: QuestionBank.Draft): string
	return draft.key or draft.prompt
end

local function isRecent(key: string): boolean
	return table.find(recentKeys, key) ~= nil
end

local function remember(key: string)
	local size = Config.Question.RecentHistorySize
	recentCursor = recentCursor % size + 1
	recentKeys[recentCursor] = key
end

--- 후보 중에서 '최근에 안 나온' 문제를 뽑는다.
--- 재추첨 한계를 넘으면 중복을 허용한다 — 라운드를 멈추는 것보다 낫다.
local function drawFrom(pool: { QuestionBank.Source }): (QuestionBank.Source, QuestionBank.Draft)
	for _ = 1, Config.Question.MaxDrawAttempts do
		local source = pool[rng:NextInteger(1, #pool)]
		if #pool > 1 and source.id == lastSourceId then
			continue
		end
		local draft = source.make(rng)
		if not isRecent(dedupeKey(draft)) then
			return source, draft
		end
	end

	local source = pool[rng:NextInteger(1, #pool)]
	return source, source.make(rng)
end

--- 이번 라운드의 후보 풀.
--- 이미지 문제가 하나도 없으면(에셋 미등록) 조용히 텍스트로 돌아간다 — 정상 동작이다.
local function poolFor(round: number): { QuestionBank.Source }
	local maxDifficulty = Config.getMaxDifficulty(round)
	-- 보드가 없는 맵에서는 본문이 사진인 문제를 아예 후보에서 뺀다. 선택지가 사진인
	-- 문제는 바닥이 그리므로 보드와 무관하게 계속 나온다.
	local allowImagePrompt = QuestionDisplay.hasBoard()

	if rng:NextNumber() < Config.Question.ImageChance then
		local images = QuestionBank.sources({
			maxDifficulty = maxDifficulty,
			usesImage = true,
			allowImagePrompt = allowImagePrompt,
		})
		if #images > 0 then
			return images
		end
	end

	return QuestionBank.sources({
		maxDifficulty = maxDifficulty,
		usesImage = false,
		allowImagePrompt = allowImagePrompt,
	})
end

--- 이번 라운드의 문제. answer 가 곧 정답 구역이다.
function QuestionService.next(round: number): Question
	local pool = poolFor(round)
	assert(
		#pool > 0,
		`[QuestionService] R{round}(난이도 ≤{Config.getMaxDifficulty(round)}) 에 낼 문제가 없다. `
			.. "QuestionBank 에 해당 난이도의 Source 를 추가할 것."
	)

	local source, draft = drawFrom(pool)

	-- ★ 정답이 A 에 갈지 B 에 갈지는 여기서, 매번 새로 정한다.
	local answer: Zone = if rng:NextInteger(0, 1) == 0 then "A" else "B"

	remember(dedupeKey(draft))
	lastSourceId = source.id
	serial += 1

	return {
		id = `{source.id}#{serial}`,
		prompt = draft.prompt,
		promptImage = draft.promptImage,
		choiceKind = source.choiceKind,
		choices = {
			A = if answer == "A" then draft.correct else draft.wrong,
			B = if answer == "B" then draft.correct else draft.wrong,
		},
		answer = answer,
		difficulty = source.difficulty,
	}
end

--- 클라이언트로 보낼 형태로 바꾼다. ★ answer 는 절대 넣지 않는다 ★
--- deadline 은 RoundStateChanged 의 endsAt 과 같은 값이어야 HUD 타이머가 어긋나지 않는다.
function QuestionService.payloadOf(question: Question, deadline: number): Payload
	return {
		id = question.id,
		prompt = question.prompt,
		choiceKind = question.choiceKind,
		choices = { A = question.choices.A, B = question.choices.B },
		deadline = deadline,
	}
end

--- 서버 콘솔 전용 한 줄 요약. 클라이언트로는 나가지 않는다.
function QuestionService.describe(question: Question): string
	local body = if question.promptImage then `{question.prompt} [사진]` else question.prompt
	return `{body} | A={question.choices.A} B={question.choices.B} → 정답 {question.answer} (난이도 {question.difficulty})`
end

return QuestionService

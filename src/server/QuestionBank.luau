--!strict
--[[
	QuestionBank — 문제의 '내용'. ★ 서버 전용 ★ (Phase 3)

	★ 왜 ReplicatedStorage 가 아니라 여기 있나
	  Shared 에 두면 클라이언트가 모듈을 통째로 읽을 수 있다. 문제 목록을 읽을 수 있으면
	  정답 보기 문자열도 함께 읽히고, 바닥에 뜬 두 선택지 중 어느 쪽이 correct 인지
	  대조하기만 하면 끝이다. 문제 DB 는 서버 밖으로 나가서는 안 된다 (README 규약 2).

	★ 왜 문제 목록이 아니라 '생성기' 목록인가
	  기획서 5장의 Type 1 은 사칙연산이다. 이걸 정적 목록으로 두면 몇 판만에 문제가 돌고,
	  플레이어는 문제를 읽는 대신 외운다 — 코어 루프가 통째로 죽는다. 그래서 각 항목이
	  make(rng) 로 매번 새 문제를 만든다. 이미지 문제도 마찬가지다 — 고정된 사진 쌍을
	  박지 않고, ImageAssets 의 세트에서 매번 두 장을 새로 뽑는다.

	★ 매체는 두 축이다 (promptKind / choiceKind)
	  "사진 보고 이름 고르기"와 "이름 보고 사진 고르기"는 서로 반대 방향의 문제이고,
	  하나의 kind 플래그로는 둘 다 표현할 수 없다. 자세한 표는 Types.luau 의 MediaKind.

	★ 정답 구역(A/B)은 여기서 정하지 않는다
	  make() 는 '정답 보기'와 '오답 보기'만 만든다. 둘 중 어느 것이 A 바닥에 놓이는지는
	  QuestionService 가 매 출제마다 무작위로 정한다. 여기에 존을 박으면 문제를 외운
	  사람이 문제를 읽지 않고 정해진 쪽으로 달린다.

	★ 숫자 범위가 Config 에 없는 이유
	  README 규약 1 은 '밸런싱 수치'를 Config 에 모으라는 것이다. 아래 범위는 밸런싱이
	  아니라 문제의 본문 그 자체다 — "1~9 사이 두 수의 덧셈"은 "짝수는?"이라는 문장과
	  같은 층위의 콘텐츠다. 난이도 커브·출제 확률처럼 진짜 손잡이인 값은 Config.Question 에 있다.
	  자세한 경계는 docs/question-system.md §3.
]]

local ImageAssets = require(script.Parent.ImageAssets)

-- Types.luau 의 MediaKind / QuestionDraft 와 같은 모양이다.
-- 컨테이너를 넘는 require 는 타입이 any 로 무너지므로 여기서 다시 적는다(map-builder.md §4).
type MediaKind = "text" | "image"

export type Draft = {
	prompt: string,
	promptImage: string?,
	correct: string,
	wrong: string,
	key: string?, -- 중복 회피 키. 비우면 prompt 를 쓴다.
}

--- 문제 한 종류. make 는 호출될 때마다 서로 다른 문제를 만들어야 한다.
---
--- ★ 매체가 두 축인 이유는 Types.luau 의 MediaKind 주석 참고.
---   promptKind = "image" 인 문제는 공중 보드가 있어야만 출제된다(QuestionService.poolFor).
export type Source = {
	id: string,
	promptKind: MediaKind, -- 본문에 사진이 붙는가
	choiceKind: MediaKind, -- 바닥 선택지가 사진인가
	difficulty: number, -- 1~5. Config.getMaxDifficulty(round) 이하만 후보가 된다.
	make: (rng: Random) -> Draft,
}

--- 후보를 고르는 조건. 위치 인자로 늘리면 호출부에서 true/false 가 뭘 뜻하는지 안 보인다.
export type Filter = {
	maxDifficulty: number,
	--- nil = 상관없음, true = 이미지를 쓰는 유형만, false = 텍스트 전용만
	usesImage: boolean?,
	--- false 면 본문이 사진인 유형을 제외한다 (보드가 없어 띄울 데가 없을 때)
	allowImagePrompt: boolean?,
}

type Range = { min: number, max: number }

-- ─────────────────────────────────────────────
-- 콘텐츠 파라미터 (밸런싱 아님 — 파일 헤더 참고)
-- ─────────────────────────────────────────────

local RANGE = {
	Digit = { min = 1, max = 9 } :: Range, -- 한 자리 수
	Factor = { min = 2, max = 9 } :: Range, -- 구구단 범위 (1 은 문제가 되지 않는다)
	TwoDigit = { min = 10, max = 49 } :: Range,
	Teen = { min = 5, max = 19 } :: Range,
	Large = { min = 30, max = 99 } :: Range,
	Compare = { min = 1, max = 99 } :: Range,
}

--- 오답을 정답에서 얼마나 떨어뜨릴지. 너무 가까우면 눈으로 못 고르고,
--- 너무 멀면 계산하지 않고도 어림짐작으로 맞힌다.
local SPREAD = { Near = 3, Far = 9 }

-- ─────────────────────────────────────────────
-- 헬퍼
-- ─────────────────────────────────────────────

local function draw(rng: Random, range: Range): number
	return rng:NextInteger(range.min, range.max)
end

--- 정답 근처의 오답. 음수는 만들지 않는다 — 하이퍼캐주얼에서 음수 보기는
--- 계산이 아니라 표기 때문에 헷갈리게 만든다.
local function nearMiss(rng: Random, answer: number, spread: number): number
	local offset = rng:NextInteger(1, spread)
	if rng:NextInteger(0, 1) == 0 then
		offset = -offset
	end
	local wrong = answer + offset
	if wrong < 0 then
		wrong = answer + math.abs(offset)
	end
	return wrong
end

local function numbers(prompt: string, answer: number, wrong: number): Draft
	return { prompt = prompt, correct = tostring(answer), wrong = tostring(wrong) }
end

--- 한국어 주제 조사(은/는)를 붙인다. "고양이은?" 같은 문구는 한 눈에 어색해서
--- 2초짜리 문제에서 읽는 속도를 떨어뜨린다. 마지막 음절에 받침이 있으면 "은".
local function topic(word: string): string
	local last: number? = nil
	for _, code in utf8.codes(word) do
		last = code
	end

	-- 한글 음절 영역(U+AC00~U+D7A3) 안에서만 판단한다. 영문·숫자로 끝나면 "는".
	local hasFinal = last ~= nil and last >= 0xAC00 and last <= 0xD7A3 and (last - 0xAC00) % 28 ~= 0
	return word .. (if hasFinal then "은" else "는")
end

-- ─────────────────────────────────────────────
-- 텍스트형 문제 (기획서 5장 Type 1)
--
-- 본문·선택지가 모두 글자인 흔한 경우라 두 축을 매번 적지 않고 textSource() 로 줄인다.
-- ─────────────────────────────────────────────

local function textSource(id: string, difficulty: number, make: (rng: Random) -> Draft): Source
	return { id = id, promptKind = "text", choiceKind = "text", difficulty = difficulty, make = make }
end

local TEXT_SOURCES: { Source } = {
	textSource("compare", 1, function(rng)
		local a = draw(rng, RANGE.Compare)
		local b = draw(rng, RANGE.Compare)
		while b == a do
			b = draw(rng, RANGE.Compare)
		end
		return numbers("더 큰 수는?", math.max(a, b), math.min(a, b))
	end),

	textSource("add-digit", 1, function(rng)
		local a, b = draw(rng, RANGE.Digit), draw(rng, RANGE.Digit)
		local answer = a + b
		return numbers(`{a} + {b} = ?`, answer, nearMiss(rng, answer, SPREAD.Near))
	end),

	textSource("parity", 2, function(rng)
		local wantEven = rng:NextInteger(0, 1) == 0

		-- 두 보기를 '이웃한 수'로 만든다. 따로 뽑으면 64 와 5 처럼 자릿수가 갈려서
		-- 홀짝이 아니라 크기로 찍을 수 있는 문제가 된다.
		local base = draw(rng, RANGE.Compare)
		local even = math.max(base - base % 2, 2) -- 0 은 헷갈리기만 하므로 피한다
		local odd = even + 1

		return numbers(
			if wantEven then "짝수는?" else "홀수는?",
			if wantEven then even else odd,
			if wantEven then odd else even
		)
	end),

	textSource("sub-teen", 2, function(rng)
		local a = draw(rng, RANGE.Teen)
		local b = rng:NextInteger(1, a - 1)
		local answer = a - b
		return numbers(`{a} - {b} = ?`, answer, nearMiss(rng, answer, SPREAD.Near))
	end),

	textSource("add-two-digit", 2, function(rng)
		local a, b = draw(rng, RANGE.TwoDigit), draw(rng, RANGE.TwoDigit)
		local answer = a + b
		return numbers(`{a} + {b} = ?`, answer, nearMiss(rng, answer, SPREAD.Far))
	end),

	textSource("multiply", 3, function(rng)
		local a, b = draw(rng, RANGE.Factor), draw(rng, RANGE.Factor)
		local answer = a * b
		return numbers(`{a} × {b} = ?`, answer, nearMiss(rng, answer, SPREAD.Far))
	end),

	textSource("sub-large", 3, function(rng)
		local a = draw(rng, RANGE.Large)
		local b = rng:NextInteger(RANGE.TwoDigit.min, math.min(RANGE.TwoDigit.max, a - 1))
		local answer = a - b
		return numbers(`{a} - {b} = ?`, answer, nearMiss(rng, answer, SPREAD.Far))
	end),

	textSource("divide", 4, function(rng)
		-- 나누어떨어지는 문제만 만든다. 곱셈에서 거꾸로 세우면 나머지가 생길 일이 없다.
		local divisor, answer = draw(rng, RANGE.Factor), draw(rng, RANGE.Factor)
		return numbers(`{divisor * answer} ÷ {divisor} = ?`, answer, nearMiss(rng, answer, SPREAD.Near))
	end),

	textSource("multiply-add", 4, function(rng)
		local a, b, c = draw(rng, RANGE.Factor), draw(rng, RANGE.Factor), draw(rng, RANGE.Digit)
		local answer = a * b + c
		return numbers(`{a} × {b} + {c} = ?`, answer, nearMiss(rng, answer, SPREAD.Far))
	end),

	textSource("precedence", 5, function(rng)
		local a, b, c = draw(rng, RANGE.Digit), draw(rng, RANGE.Factor), draw(rng, RANGE.Factor)
		-- 오답은 '연산 순서를 무시한 답'이다. 대충 왼쪽부터 계산한 사람만 정확히 틀린다.
		-- c ≥ 2, a ≥ 1 이므로 (a+b)×c 와 a+b×c 가 같아지는 경우는 없다.
		return numbers(`{a} + {b} × {c} = ?`, a + b * c, (a + b) * c)
	end),
}

-- ─────────────────────────────────────────────
-- 이미지형 문제 (기획서 5장 Type 2)
--
-- ★ 여기에 문제를 손으로 적지 않는다. ImageAssets 의 세트에서 자동으로 만든다.
--   세트 하나가 서로 반대 방향의 문제 두 종류를 낳는다.
--     · {id}-name  : 사진을 보여주고 이름 두 개 중에 고르게 한다  (본문=사진, 선택지=글자)
--     · {id}-photo : 이름을 보여주고 사진 두 장 중에 고르게 한다  (본문=글자, 선택지=사진)
--   에셋을 채우면 이 파일을 고칠 필요 없이 문제가 늘어난다.
--
-- ★ key 를 반드시 채운다
--   중복 회피는 draft.key(없으면 prompt)로 판정한다. 이미지 문제는 prompt 가 항상
--   "이 동물은?" 으로 같아서, key 를 비우면 첫 출제 직후부터 모든 재추첨이 중복으로
--   걸려 회피가 통째로 무력해진다(docs/question-system.md §4).
--
-- ★ 항목이 2개 미만인 세트는 등록되지 않는다
--   보기 두 개를 뽑을 수 없기 때문이다. 에셋이 하나도 없는 지금은 IMAGE_SOURCES 가
--   빈 목록이 되고, 추첨은 조용히 텍스트 문제로 넘어간다 — 정상이다.
-- ─────────────────────────────────────────────

local IMAGE_SOURCES: { Source } = {}

for _, set in ImageAssets.usableSets() do
	-- 사진 → 이름
	table.insert(IMAGE_SOURCES, {
		id = `{set.id}-name`,
		promptKind = "image",
		choiceKind = "text",
		difficulty = set.difficulty,
		make = function(rng)
			local answer, other = ImageAssets.pickTwo(rng, set)
			return {
				prompt = set.prompt,
				promptImage = answer.asset,
				correct = answer.name,
				wrong = other.name,
				key = `{set.id}-name:{answer.name}/{other.name}`,
			}
		end,
	})

	-- 이름 → 사진
	table.insert(IMAGE_SOURCES, {
		id = `{set.id}-photo`,
		promptKind = "text",
		choiceKind = "image",
		difficulty = set.difficulty,
		make = function(rng)
			local answer, other = ImageAssets.pickTwo(rng, set)
			return {
				prompt = `{topic(answer.name)}?`,
				correct = answer.asset,
				wrong = other.asset,
				key = `{set.id}-photo:{answer.name}/{other.name}`,
			}
		end,
	})
end

-- ─────────────────────────────────────────────
-- 공개 API
-- ─────────────────────────────────────────────

local QuestionBank = {}

--- 이 유형이 이미지를 쓰는가. 본문이든 선택지든 한쪽이라도 사진이면 이미지 문제다.
local function usesImage(source: Source): boolean
	return source.promptKind == "image" or source.choiceKind == "image"
end

--- 조건에 맞는 문제 후보.
--- 후보가 없으면 빈 목록을 반환한다 — 판단은 호출부(QuestionService)가 한다.
function QuestionBank.sources(filter: Filter): { Source }
	local result: { Source } = {}

	local function collect(pool: { Source })
		for _, source in pool do
			if source.difficulty > filter.maxDifficulty then
				continue
			end
			if filter.usesImage ~= nil and usesImage(source) ~= filter.usesImage then
				continue
			end
			-- 보드가 없으면 본문 사진을 띄울 데가 없다. 그냥 내면 지시문만 뜬 '풀 수 없는 문제'가 된다.
			if filter.allowImagePrompt == false and source.promptKind == "image" then
				continue
			end
			table.insert(result, source)
		end
	end

	collect(TEXT_SOURCES)
	collect(IMAGE_SOURCES)
	return result
end

--- 등록된 문제 종류 수. 부팅 로그와 테스트에서 쓴다. (텍스트 전용, 이미지 사용)
function QuestionBank.count(): (number, number)
	return #TEXT_SOURCES, #IMAGE_SOURCES
end

return QuestionBank

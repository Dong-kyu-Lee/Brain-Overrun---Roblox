--!strict
--[[
	ImageAssets — 이미지 문제가 쓰는 에셋과 그 '정답 이름'. ★ 서버 전용 ★ (Phase 3 개정)

	★ 왜 ReplicatedStorage 가 아니라 여기 있나
	  이 파일은 `rbxassetid://123 = 고양이` 라는 대응표다. 클라이언트가 이걸 읽으면
	  바닥에 뜬 사진의 에셋 ID 를 이름으로 역변환할 수 있고, 그러면 문제를 읽지 않고
	  정답을 찾아낸다. QuestionBank 를 서버에 둔 것과 정확히 같은 이유다(README 규약 2).
	  ★ Shared 로 옮기지 마라. 클라이언트에는 이름이 지워진 ID 배열만 나간다(assetIds).

	★ 세트 하나가 문제 두 종류를 만든다
	  QuestionBank 가 세트마다 두 방향의 Source 를 자동으로 등록한다.
	    · 사진 → 이름 : 🐱 보여주고 바닥에 "고양이" / "강아지"
	    · 이름 → 사진 : "고양이는?" 보여주고 바닥에 🐱 / 🐶
	  즉 여기에 항목만 채우면 문제는 저절로 생긴다. QuestionBank 는 건드릴 필요가 없다.

	★ 비어 있어도 정상이다
	  항목이 2개 미만인 세트는 보기 두 개를 뽑을 수 없으므로 아예 등록되지 않는다.
	  등록 가능한 세트가 하나도 없으면 이미지 문제가 0종이 되고, 추첨은 조용히 텍스트
	  문제로 넘어간다 — 에러가 아니라 설계된 폴백이다.

	★ 선택지용 사진의 규격 (바닥에 깔릴 때)
	  바닥 글자는 눈높이에서 시선각 약 8° 로 거의 눕혀 보인다(docs/question-system.md §5).
	  사진도 같은 각도로 눌리므로 아래를 지켜야 A/B 구분이 된다.
	    · 정사각형, 단색 배경, 굵은 실루엣 — 사진보다 픽토그램/아이콘에 가깝게
	    · 세부 질감·그림자 금지. 뭉개지면 두 보기가 같아 보인다
	  본문 사진(공중 보드)은 정면으로 보이므로 이 제약이 없다. 두 용도의 규격이 다르다.
]]

export type Entry = {
	--- 정답/오답 '보기'로 쓰는 이름. ★ 이 문자열이 클라이언트로 나가는 건 선택지로 쓰일 때뿐이다 ★
	name: string,
	--- rbxassetid://...
	asset: string,
}

export type Set = {
	id: string, -- Source id 의 접두어가 된다. 유일해야 한다.
	--- 사진 → 이름 방향에서 보드에 띄울 지시문. 사진만 던지면 무엇을 고르라는지 알 수 없다.
	prompt: string,
	difficulty: number, -- 1~5. Config.getMaxDifficulty(round) 이하일 때 후보가 된다.
	entries: { Entry },
}

-- ─────────────────────────────────────────────
-- 세트 정의
--
-- 에셋을 올린 뒤 entries 를 채우면 된다. 예:
--
--   { id = "animal", prompt = "이 동물은?", difficulty = 1, entries = {
--         { name = "고양이", asset = "rbxassetid://0000000000" },
--         { name = "강아지", asset = "rbxassetid://0000000000" },
--   } },
--
-- ★ 한 세트 안의 항목들은 서로 '헷갈리지 않아야' 한다. 고양이와 호랑이를 같은 세트에 두면
--   바닥에서 눌려 보일 때 구분이 안 된다. 헷갈리는 쌍은 세트를 나눠라.
-- ★ 항목이 많을수록 좋다. 2개면 매 라운드 같은 쌍만 나와 중복 회피가 곧바로 막힌다.
-- ─────────────────────────────────────────────

local SETS: { Set } = {
	{ id = "animal", prompt = "이 동물은?", difficulty = 1, entries = {
		{ name = "고양이", asset = "rbxassetid://130493442479400" },
		{ name = "강아지", asset = "rbxassetid://99617370404858" },
		{ name = "오리"  , asset = "rbxassetid://88602323928571" },
	} },
	{ id = "fruit", prompt = "이 과일은?", difficulty = 1, entries = {
		{ name = "사과", asset = "rbxassetid://86552897359496" },
		{ name = "바나나", asset = "rbxassetid://115072734905974" },
	} },
	{ id = "flag", prompt = "이 국가는?", difficulty = 2, entries = {
		{ name = "브라질", asset = "rbxassetid://115449110017529" },
		{ name = "인도", asset = "rbxassetid://74453415702613" },
	} },
}

local ImageAssets = {}

--- 문제로 쓸 수 있는 세트만 돌려준다. 항목이 2개 미만이면 보기 두 개를 만들 수 없다.
function ImageAssets.usableSets(): { Set }
	local result: { Set } = {}
	for _, set in SETS do
		if #set.entries >= 2 then
			table.insert(result, set)
		end
	end
	return result
end

--- 세트에서 서로 다른 두 항목. 첫 번째가 정답, 두 번째가 오답이 된다.
--- 뽑기를 두 번 하고 겹치면 다시 뽑는 대신, 두 번째를 남은 것 중에서 고른다(무한 재시도 없음).
function ImageAssets.pickTwo(rng: Random, set: Set): (Entry, Entry)
	local count = #set.entries
	assert(count >= 2, `[ImageAssets] 세트 '{set.id}' 에 항목이 {count}개뿐이다 — 2개 이상 필요하다`)

	local first = rng:NextInteger(1, count)
	local second = rng:NextInteger(1, count - 1)
	if second >= first then
		second += 1
	end

	return set.entries[first], set.entries[second]
end

--- 클라이언트 프리로드용 에셋 ID 목록. ★ 이름은 절대 넣지 않는다 ★
---
--- 제한시간이 2~5초인 게임에서 사진이 1초 늦게 뜨면 그 라운드는 못 푼다. 그래서 접속 직후
--- 한 번 내려받아 둔다. ID 만으로는 어느 게 무엇인지 알 수 없으므로 정답이 새지 않는다.
function ImageAssets.assetIds(): { string }
	local seen: { [string]: true } = {}
	local ids: { string } = {}

	for _, set in SETS do
		for _, entry in set.entries do
			if entry.asset ~= "" and not seen[entry.asset] then
				seen[entry.asset] = true
				table.insert(ids, entry.asset)
			end
		end
	end

	return ids
end

--- 부팅 로그용. (세트 수, 전체 항목 수)
function ImageAssets.count(): (number, number)
	local entries = 0
	for _, set in SETS do
		entries += #set.entries
	end
	return #SETS, entries
end

return ImageAssets

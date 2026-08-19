--!strict
--[[
	ImagePreload — 문제 이미지를 접속 직후 미리 내려받는다. (Phase 3 개정)

	★ 왜 필요한가
	  Roblox 는 ImageLabel 이 '처음 보일 때' 에셋을 내려받는다. 라운드 제한시간이 2~5초인
	  이 게임에서 첫 1초가 회색 사각형이면 그 라운드는 못 푼다 — 게임이 어려운 게 아니라
	  안 보이는 것이다. 그래서 로비에서 미리 받아 둔다.

	★ 서버가 주는 것은 '이름표 없는 ID 배열'뿐이다
	  ID 만으로는 어느 사진이 무엇인지 알 수 없다. ID↔이름 대응표(ImageAssets)는 서버에만
	  있고, 그래서 이 목록을 받아도 정답을 알아낼 수 없다 — 반대로 대응표가 넘어오면
	  바닥 사진을 이름으로 역변환해 문제를 읽지 않고 풀 수 있다(README 규약 2).

	★ 실패해도 조용히 넘어간다
	  프리로드는 최적화지 기능이 아니다. 서버가 늦게 뜨거나 목록이 비어 있어도(에셋 미등록)
	  게임은 그대로 돌아가야 한다. 사진이 조금 늦게 뜰 뿐이다.
]]

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local ImagePreload = {}

--- PreloadAsync 는 인스턴스 배열을 받는다. 문자열을 그대로 넘기는 건 버전에 따라 동작이
--- 갈리므로, 부모 없는 ImageLabel 을 잠깐 만들어 넘기고 바로 버린다.
local function holdersFor(ids: { string }): { Instance }
	local holders: { Instance } = {}
	for _, id in ids do
		local label = Instance.new("ImageLabel")
		label.Image = id
		table.insert(holders, label)
	end
	return holders
end

function ImagePreload.start()
	task.spawn(function()
		local ok, ids = pcall(function()
			return Remotes.func("GetImageAssets"):InvokeServer()
		end)

		if not ok or typeof(ids) ~= "table" or #ids == 0 then
			return
		end

		local holders = holdersFor(ids)
		-- PreloadAsync 는 개별 에셋이 실패해도 통째로 에러를 던질 수 있다(잘못된 ID 하나로
		-- 프리로드 전체가 죽는 것). 게임을 세울 이유가 없으므로 감싼다.
		pcall(function()
			ContentProvider:PreloadAsync(holders)
		end)

		for _, holder in holders do
			holder:Destroy()
		end

		if Config.Debug.Enabled then
			print(`[ImagePreload] 문제 이미지 {#ids}개 준비 완료`)
		end
	end)
end

return ImagePreload

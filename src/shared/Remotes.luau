--!strict
--[[
	Remotes — 네트워크 통신 채널 정의 및 생성.

	서버가 먼저 require 하여 인스턴스를 만들고, 클라이언트는 WaitForChild 로 받는다.

	★ 보안 원칙
	  - 정답(answer)은 어떤 경로로도 클라이언트에 전송하지 않는다. 선택지 텍스트만 보낸다.
	  - 대시/밀치기는 "요청"만 클라이언트가 보내고, 쿨타임·횟수·거리 판정은 전부 서버가 한다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "Remotes"

-- 서버 → 클라이언트 (단방향 알림) + 클라이언트 → 서버 (요청)
local EVENT_NAMES = {
	-- S→C
	"RoundStateChanged", -- (state: RoundState, round: number, payload: table?)
	"QuestionShown", -- (payload: QuestionPayload)
	"RoundResult", -- (correctZone: Zone, survivors: {number})

	-- (zone: Zone, cframe: CFrame, size: Vector3)  정답 구역 벽이 부서진 순간.
	-- ★ 정답 유출이 아니다 ★ 벽이 눈앞에서 사라지는 건 이미 월드에 보이는 사실이고,
	--   이 알림은 그 순간 '이후'에 나간다. 파괴 예정을 미리 알리는 채널은 만들지 말 것.
	-- ★ 위치를 함께 보내는 이유: 클라이언트가 복제된 벽 파트를 읽으면 복제 지연만큼
	--   폭발이 엉뚱한 곳에서 터진다.
	"WallBroken",
	"PlayerDataChanged", -- (data: PlayerData)
	"SessionStateChanged", -- (session: SessionState)
	"Notify", -- (message: string, kind: "info"|"warn"|"good")

	-- C→S
	"DashRequest", -- (direction: Vector3)
	"PushRequest", -- ()
}

-- 요청/응답이 필요한 경우
local FUNCTION_NAMES = {
	"GetPlayerData", -- () -> PlayerData
	"GetSessionState", -- () -> SessionState
	"PurchaseItem", -- (itemId: string) -> (ok: boolean, message: string)

	-- () -> { string }  프리로드용 이미지 에셋 ID 목록.
	-- ★ '이름표 없는' 평탄한 ID 배열만 나간다 ★ 어느 ID 가 어떤 동물인지는 서버만 안다.
	--   ID↔이름 대응표(ImageAssets)가 클라이언트로 새면 바닥 사진을 이름으로 역변환해
	--   문제를 읽지 않고 정답을 찾을 수 있다 — QuestionBank 를 서버에 둔 것과 같은 이유다.
	"GetImageAssets",
}

local Remotes = {}

local folder: Folder

if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME) :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end

	for _, name in EVENT_NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end

	for _, name in FUNCTION_NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME, 30) :: Folder
	assert(folder, "[Remotes] 서버가 Remotes 폴더를 생성하지 않았습니다.")
end

--- 이름으로 RemoteEvent 를 가져온다.
function Remotes.event(name: string): RemoteEvent
	local remote = folder:WaitForChild(name, 15)
	assert(remote and remote:IsA("RemoteEvent"), `[Remotes] RemoteEvent '{name}' 를 찾을 수 없습니다.`)
	return remote :: RemoteEvent
end

--- 이름으로 RemoteFunction 을 가져온다.
function Remotes.func(name: string): RemoteFunction
	local remote = folder:WaitForChild(name, 15)
	assert(remote and remote:IsA("RemoteFunction"), `[Remotes] RemoteFunction '{name}' 를 찾을 수 없습니다.`)
	return remote :: RemoteFunction
end

return Remotes

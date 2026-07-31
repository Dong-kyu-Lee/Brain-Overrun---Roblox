--!strict
--[[
	Bootstrap — 서버 진입점.

	초기화 순서가 중요하다.
	  1) Remotes  — 클라이언트가 WaitForChild 로 기다리므로 가장 먼저.
	  2) 맵 생성   — 아래 서비스들이 태그로 맵 오브젝트를 찾는다.
	  3) 서비스    — SessionService → Arena → RoundService (뒤가 앞을 require 한다).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local MapBuilder = require(script.Parent.MapBuilder)
local SessionService = require(script.Parent.SessionService)
local Arena = require(script.Parent.Arena)
local RoundService = require(script.Parent.RoundService)

-- Remotes 를 서버에서 먼저 require 해야 클라이언트가 기다리지 않는다.
local _ = Remotes

-- 맵은 place 파일이 아니라 코드로 만든다(README 규약 4).
-- 플레이어가 접속하기 전에 끝나야 하므로 부팅 시점에 동기적으로 생성한다.
MapBuilder.build()

SessionService.start()
Arena.start() -- KillPlane 태그를 찾으므로 build() 이후여야 한다
RoundService.start()

print("[BrainOverrun] 서버 부팅 완료")

if Config.Debug.Enabled then
	print(
		("[BrainOverrun] 디버그 모드 | 1R 제한시간 %ds, 1R 벽속도 %d studs/s"):format(
			Config.getCountdown(1),
			Config.getWallSpeed(1)
		)
	)
	if Config.Debug.RevealAnswer then
		warn("[BrainOverrun] Debug.RevealAnswer = true — 정답이 전 클라이언트에 노출됩니다. 출시 전 끌 것.")
	end
end

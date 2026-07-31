--!strict
--[[
	Bootstrap — 서버 진입점.

	Phase 1: 공유 모듈 로딩 + 맵 생성.
	Phase 2 이후 GameLoop(라운드 상태머신)를 여기에 연결한다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local MapBuilder = require(script.Parent.MapBuilder)

-- Remotes 를 서버에서 먼저 require 해야 클라이언트가 기다리지 않는다.
local _ = Remotes

-- 맵은 place 파일이 아니라 코드로 만든다(README 규약 4).
-- 플레이어가 접속하기 전에 끝나야 하므로 부팅 시점에 동기적으로 생성한다.
MapBuilder.build()

print("[BrainOverrun] 서버 부팅 완료")

if Config.Debug.Enabled then
	print(
		("[BrainOverrun] 디버그 모드 | 1R 제한시간 %ds, 1R 벽속도 %d studs/s"):format(
			Config.getCountdown(1),
			Config.getWallSpeed(1)
		)
	)
end

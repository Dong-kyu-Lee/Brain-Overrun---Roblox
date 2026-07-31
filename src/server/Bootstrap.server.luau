--!strict
--[[
	Bootstrap — 서버 진입점.

	Phase 0: 공유 모듈 로딩과 Rojo 연동만 확인한다.
	Phase 1 이후 MapBuilder → GameLoop 순으로 여기에 연결한다.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

-- Remotes 를 서버에서 먼저 require 해야 클라이언트가 기다리지 않는다.
local _ = Remotes

print("[BrainOverrun] 서버 부팅 완료")

if Config.Debug.Enabled then
	print(
		("[BrainOverrun] 디버그 모드 | 1R 제한시간 %ds, 1R 벽속도 %d studs/s"):format(
			Config.getCountdown(1),
			Config.getWallSpeed(1)
		)
	)
end

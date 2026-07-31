--!strict
--[[
	Tags — CollectionService 태그 이름 상수.

	맵 오브젝트를 이름/경로로 찾지 않고 태그로 찾는다.
	맵을 다시 만들거나 구조를 바꿔도 로직 코드가 깨지지 않게 하기 위함.
]]

local Tags = {
	-- 존
	ZoneA = "BO_ZoneA", -- A구역 바닥 (SurfaceGui 부착 대상)
	ZoneB = "BO_ZoneB", -- B구역 바닥
	SpectatorFloor = "BO_SpectatorFloor", -- 상공 투명 유리 관전장
	SpawnZone = "BO_SpawnZone", -- 라운드 시작 스폰 영역

	-- 기믹
	WallA = "BO_WallA", -- A레인 끝 파괴의 벽
	WallB = "BO_WallB", -- B레인 끝 파괴의 벽

	-- 판정
	KillPlane = "BO_KillPlane", -- 맵 밖 낙하 감지면

	-- 표시
	AnswerScreen = "BO_AnswerScreen", -- 선택지를 출력하는 바닥 SurfaceGui 호스트
	QuestionBoard = "BO_QuestionBoard", -- 문제 텍스트를 띄우는 공중 보드(선택)
}

return Tags

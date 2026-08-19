--!strict
--[[
	Tags — CollectionService 태그 이름 상수.

	맵 오브젝트를 이름/경로로 찾지 않고 태그로 찾는다.
	맵을 다시 만들거나 구조를 바꿔도 로직 코드가 깨지지 않게 하기 위함.
]]

local Tags = {
	-- 루트
	MapRoot = "BO_MapRoot", -- 씬에 미리 배치된 맵 전체를 담는 폴더

	-- 존
	ZoneA = "BO_ZoneA", -- A구역 바닥 (SurfaceGui 부착 대상)
	ZoneB = "BO_ZoneB", -- B구역 바닥
	SpectatorFloor = "BO_SpectatorFloor", -- 상공 투명 유리 관전장
	SpawnZone = "BO_SpawnZone", -- 라운드 시작 스폰 영역
	LobbySpawn = "BO_LobbySpawn", -- 관전장 위 로비 SpawnLocation (접속/리스폰 기본 위치)

	-- 기믹
	WallA = "BO_WallA", -- A레인 끝 파괴의 벽
	WallB = "BO_WallB", -- B레인 끝 파괴의 벽

	-- 판정
	KillPlane = "BO_KillPlane", -- 맵 밖 낙하 감지면
	SideBarrier = "BO_SideBarrier", -- 레인 좌우 추락 방지 벽 (디버그 시에만 보인다)

	-- 표시
	AnswerScreen = "BO_AnswerScreen", -- 선택지를 출력하는 바닥 SurfaceGui 호스트
	-- 문제 본문과 '본문 사진'을 띄우는 공중 보드. 없어도 서버는 뜨지만 이미지 본문 문제가
	-- 통째로 출제되지 않는다(QuestionService.poolFor). docs/question-system.md §6.
	QuestionBoard = "BO_QuestionBoard",
}

return Tags

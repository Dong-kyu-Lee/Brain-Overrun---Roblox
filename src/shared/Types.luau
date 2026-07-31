--!strict
--[[
	Types — 서버/클라이언트가 공유하는 타입 정의.
]]

--- 존 식별자
export type Zone = "A" | "B"

--- 문제 종류
export type QuestionKind = "text" | "image"

--- 문제 원본 (서버 전용 — answer 필드가 있으므로 절대 클라이언트로 보내지 않는다)
export type Question = {
	id: string,
	kind: QuestionKind,
	prompt: string, -- 예: "1 + 2 = ?"
	choices: { A: string, B: string }, -- 텍스트형이면 문자열, 이미지형이면 rbxassetid://
	answer: Zone,
	difficulty: number?, -- 1~5, 미지정 시 1
}

--- 클라이언트로 전송하는 문제 페이로드 (정답 제거됨)
export type QuestionPayload = {
	id: string,
	kind: QuestionKind,
	prompt: string,
	choices: { A: string, B: string },
	deadline: number, -- workspace:GetServerTimeNow() 기준 종료 시각
}

--- 라운드 상태 머신
export type RoundState =
	"Lobby" -- 플레이어 대기
	| "Countdown" -- 스폰 후 문제 노출, 이동 가능
	| "WallRush" -- 벽 돌진 중
	| "Judge" -- 생존/탈락 판정 및 보상
	| "Intermission" -- 다음 라운드 준비
	| "GameOver" -- 우승자 확정

--- 플레이어 영구 데이터 (DataStore 저장 단위)
export type PlayerData = {
	coins: number,
	ownsPushSkill: boolean,
	totalWins: number,
	totalRounds: number,
}

--- 플레이어 세션 상태 (게임 1판 동안만 유효, 저장하지 않음)
export type SessionState = {
	alive: boolean,
	spectating: boolean,
	pushUsesLeft: number,
	revivesLeft: number,
	lastDashAt: number,
	lastPushAt: number,
	roundsSurvived: number,
}

return {}

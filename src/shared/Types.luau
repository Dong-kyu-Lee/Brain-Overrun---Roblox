--!strict
--[[
	Types — 서버/클라이언트가 공유하는 타입 정의.
]]

--- 존 식별자
export type Zone = "A" | "B"

--- 표시 매체. ★ 문제 본문과 선택지는 서로 '독립된' 축이다 ★
---
--- 하나의 kind 로 문제 전체를 가르면 아래 네 칸 중 두 칸을 표현할 수 없다.
---
---              선택지=text            선택지=image
---   본문=text   "1+2=?" → 3 / 4       "고양이는?" → 🐱 / 🌳
---   본문=image  🐱 → 고양이 / 강아지   🐱 → 🐱 / 🌳
---
--- 그래서 promptKind / choiceKind 두 축으로 나눠 들고 다닌다.
export type MediaKind = "text" | "image"

--- 문제 DB 가 들고 있는 원본 (서버 전용 — QuestionBank).
--- 정답이 A/B 중 어느 바닥에 놓일지는 '출제 시점에' 무작위로 정해진다. 그래서 DB 에는
--- 존이 아니라 '정답 보기 / 오답 보기'만 있다 — DB 에 존을 박아두면 문제를 외운 사람이
--- 문제를 읽지 않고 정해진 쪽으로 달린다.
export type QuestionDraft = {
	--- 항상 있다. 이미지 본문 문제에서는 사진에 붙는 '지시문' 역할을 한다("이 동물은?").
	--- 사진만 던지면 무엇을 고르라는 건지 알 수 없어 2~5초 안에 풀 수 없는 문제가 된다.
	prompt: string,
	--- 있으면 본문에 사진이 함께 뜬다 (rbxassetid://). 공중 보드가 그린다.
	promptImage: string?,
	correct: string, -- 선택지가 텍스트면 문자열, 이미지면 rbxassetid://
	wrong: string,
	--- 중복 회피에 쓰는 키. 없으면 prompt 를 쓴다.
	--- ★ 이미지 문제는 prompt 가 항상 같으므로("이 동물은?") 반드시 채워야 한다 —
	---   비워 두면 첫 출제 직후부터 모든 재추첨이 중복으로 걸려 회피가 무력화된다.
	key: string?,
}

--- 출제가 끝난 문제 (서버 전용 — answer 필드가 있으므로 절대 클라이언트로 보내지 않는다)
export type Question = {
	id: string,
	prompt: string,
	promptImage: string?,
	choiceKind: MediaKind, -- 바닥 선택지를 글자로 그릴지 사진으로 그릴지
	choices: { A: string, B: string },
	answer: Zone,
	difficulty: number?, -- 1~5, 미지정 시 1
}

--- 클라이언트로 전송하는 문제 페이로드 (정답 제거됨)
--- ★ promptImage 가 없다 — 본문 사진은 공중 보드(월드)가 그린다. HUD 는 지시문만 띄운다.
export type QuestionPayload = {
	id: string,
	prompt: string,
	choiceKind: MediaKind,
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

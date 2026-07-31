# 두뇌풀가동 (Brain Overrun)

하이퍼캐주얼 생존 퀴즈 아케이드 · Roblox

제한 시간 안에 문제를 풀고 정답 구역으로 피신해 '파괴의 벽'을 피하는 배틀로얄.
전체 기획은 [CLAUDE.md](CLAUDE.md) 참고.

---

## 개발 환경 셋업

### 1. 툴체인 설치

이 저장소는 [Rokit](https://github.com/rojo-rbx/rokit)으로 툴 버전을 고정한다.
Rokit이 없다면 먼저 설치한 뒤:

```powershell
rokit install
```

`rokit.toml`에 명시된 Rojo 버전이 자동으로 설치된다.

### 2. Studio 플러그인 설치

```powershell
rojo plugin install
```

### 3. 동기화 시작

```powershell
rojo serve
```

Studio에서 **Plugins → Rojo → Connect** 를 누르면 연결된다.
이후 `src/` 아래 `.luau` 파일을 저장하면 Studio에 즉시 반영된다.

---

## 프로젝트 구조

```
src/
├── shared/     → ReplicatedStorage.Shared   (서버·클라이언트 공용)
│   ├── Config.luau     밸런싱 수치 단일 소스
│   ├── Tags.luau       CollectionService 태그 상수
│   ├── Types.luau      공유 타입 정의
│   └── Remotes.luau    네트워크 채널 정의
├── server/     → ServerScriptService.Server
└── client/     → StarterPlayer.StarterPlayerScripts.Client
```

## 코딩 규약

1. **모든 밸런싱 수치는 `Config.luau`에만 존재한다.** 다른 파일에 하드코딩된 상수가 보이면 버그다.
2. **서버 권위(Server Authority).** 정답 값은 클라이언트로 전송하지 않고, 쿨타임·사용 횟수·거리 판정은 전부 서버가 한다.
3. **맵 오브젝트는 이름이 아닌 태그로 찾는다.** (`Tags.luau`)
4. **맵은 빌더 스크립트로 생성한다.** `.rbxl`은 git에 추적하지 않으며 언제든 재생성 가능해야 한다.

## 구현 로드맵

| Phase | 내용 | 상태 |
|---|---|---|
| 0 | 프로젝트 골격 · 규약 · Config | ✅ |
| 1 | 맵 빌더 (레인/벽/관전장/킬플레인) | ⬜ |
| 2 | 라운드 상태머신 · 생존 판정 · 관전 전환 | ⬜ |
| 3 | 문제 시스템 · 바닥 SurfaceGui · HUD | ⬜ |
| 4 | 난이도 커브 · 벽 파괴 연출 | ⬜ |
| 5 | 대시 · 밀치기 | ⬜ |
| 6 | DataStore · 코인 경제 · 상점 | ⬜ |
| 7 | 부활권 (MarketplaceService) | ⬜ |
| 8 | 이미지형 문제 · 사운드 · QA | ⬜ |

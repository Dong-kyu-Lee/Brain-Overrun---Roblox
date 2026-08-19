--!strict
--[[
	WallEffects — 정답 벽이 부서지는 순간의 폭발. ★ 전부 클라이언트 로컬 ★ (Phase 4)

	★ 왜 서버가 아니라 클라이언트가 만드는가
	  서버가 폭발이나 파편을 실물로 뿌리면 그 힘이 캐릭터를 민다. 정답 구역에 서 있던
	  사람이 밀려 -Z 밖으로 떨어지면 오답도 아닌데 탈락한다 — 게임이 통째로 망가진다.
	  클라이언트가 만든 인스턴스는 서버로 복제되지 않고 판정에 닿지 않는다.

	★ Explosion 인스턴스를 쓰지 않는 이유
	  BlastPressure = 0 으로 둬도 굳이 쓸 이유가 없다. 로컬 캐릭터는 이 클라이언트가
	  직접 시뮬레이션하므로, 언젠가 누가 압력을 0 이 아닌 값으로 되돌리는 순간
	  '내 화면에서만 밀려나는' 서버와 어긋난 위치가 만들어진다. 애초에 힘이 없는
	  입자·빛·화면 흔들림만으로 조립한다.

	★ 예고(직전 깜빡임)를 넣지 않는다
	  벽 파괴는 WallRush 도중에 일어나고, 이 게임은 그때도 옆 레인으로 다이브해 살 수 있다
	  (round-loop.md §3). 즉 파괴 자체가 정답 공개이자 '마지막 기회' 신호다. 예고를 주면
	  그 기회가 통째로 앞당겨져 오답 구역에 있던 사람이 너무 쉽게 산다.

	★ 관전자도 본다
	  FireAllClients 로 오므로 탈락자 화면에서도 재생된다. 흔들림은 거리로 감쇠하므로
	  상공 관전장에서는 약하게만 흔들린다.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local FX = Config.Theme.WallBreak

--- 입자 한 겹의 설정. Config.Theme.WallBreak 의 Fire / Smoke / Spark 와 같은 모양이다.
type Burst = {
	Texture: string,
	Count: number,
	SpeedMin: number,
	SpeedMax: number,
	SizeStart: number,
	SizeEnd: number,
	LifeMin: number,
	LifeMax: number,
	ColorStart: Color3,
	ColorEnd: Color3,
	Spread: number,
	LightEmission: number,
}

local SHAKE_BINDING = "BO_WallBreakShake"
local HOST_NAME = "BO_WallBreakFX"

local WallEffects = {}

local rng = Random.new()
local shaking = false

-- ─────────────────────────────────────────────
-- 입자
-- ─────────────────────────────────────────────

--- Rate = 0 + Emit() 조합이다. 지속 분출이 아니라 '한 번 터지고 끝'이어야 하므로
--- Enabled 를 켜 두면 안 된다 — 켜 두면 Lifetime 동안 계속 연기가 새어 나온다.
local function newEmitter(parent: Attachment, spec: Burst): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = spec.Texture
	emitter.Color = ColorSequence.new(spec.ColorStart, spec.ColorEnd)
	emitter.Size = NumberSequence.new(spec.SizeStart, spec.SizeEnd)
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.6, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(spec.LifeMin, spec.LifeMax)
	emitter.Speed = NumberRange.new(spec.SpeedMin, spec.SpeedMax)
	emitter.SpreadAngle = Vector2.new(spec.Spread, spec.Spread)
	emitter.LightEmission = spec.LightEmission
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-120, 120)
	emitter.Drag = 2 -- 퍼지다가 멈춰야 '터졌다'로 읽힌다. 0 이면 끝없이 흘러간다.
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.Parent = parent
	return emitter
end

--- 폭발 지점 하나. 벽은 레인 폭(40 studs)만큼 넓어서 한 점에서만 터뜨리면
--- 눈앞을 가로막던 물건이 사라지는 느낌이 나지 않는다.
local function burstAt(host: BasePart, offset: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.Position = offset
	attachment.Parent = host

	for _, spec in { FX.Fire, FX.Smoke, FX.Spark } do
		newEmitter(attachment, spec :: Burst):Emit(spec.Count)
	end
end

-- ─────────────────────────────────────────────
-- 섬광
-- ─────────────────────────────────────────────

local function flash(host: BasePart)
	local light = Instance.new("PointLight")
	light.Color = FX.Flash.Color
	light.Brightness = FX.Flash.Brightness
	light.Range = FX.Flash.Range
	light.Shadows = false
	light.Parent = host

	TweenService:Create(light, TweenInfo.new(FX.Flash.Time, Enum.EasingStyle.Quad), {
		Brightness = 0,
	}):Play()
end

-- ─────────────────────────────────────────────
-- 화면 흔들림
--
-- ★ 과하면 그대로 멀미가 된다 ★ 짧게, 제곱으로 감쇠시키고, 거리로 한 번 더 줄인다.
-- 카메라 스크립트가 매 프레임 CFrame 을 새로 쓰므로 그 '뒤'(Camera 우선순위 + 1)에서
-- 오프셋을 얹어야 한다. 여기서 카메라를 대입이 아니라 덧셈으로 건드리는 이유도 같다 —
-- 회전이나 위치를 통째로 정하면 기본 카메라 조작과 싸운다.
-- ─────────────────────────────────────────────

local function shake(origin: Vector3)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local distance = (camera.CFrame.Position - origin).Magnitude
	local strength = FX.Shake.Intensity * math.clamp(1 - distance / FX.Shake.Falloff, 0, 1)
	if strength <= 0.01 then
		return
	end

	if shaking then
		RunService:UnbindFromRenderStep(SHAKE_BINDING)
	end
	shaking = true

	local elapsed = 0
	RunService:BindToRenderStep(SHAKE_BINDING, Enum.RenderPriority.Camera.Value + 1, function(deltaTime: number)
		elapsed += deltaTime
		local remaining = 1 - math.min(elapsed / FX.Shake.Time, 1)
		if remaining <= 0 then
			RunService:UnbindFromRenderStep(SHAKE_BINDING)
			shaking = false
			return
		end

		local current = Workspace.CurrentCamera
		if not current then
			return
		end
		local amount = strength * remaining * remaining
		current.CFrame = current.CFrame
			+ Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * amount
	end)
end

-- ─────────────────────────────────────────────
-- 재생
-- ─────────────────────────────────────────────

--- 폭발을 담아 둘 빈 파트. 보이지도, 부딪히지도, 레이캐스트에 잡히지도 않는다.
--- ★ 이 세 가지를 하나라도 빠뜨리면 '연출용' 파트가 게임에 개입하기 시작한다.
--- ★ 벽의 CFrame 을 회전째로 그대로 쓴다. 그래야 아래의 폭발 지점 오프셋을 '벽 기준'
---   로컬 좌표로 적을 수 있다 — 맵이 축에 정렬돼 있다고 가정하지 않는다.
local function newHost(cframe: CFrame): BasePart
	local host = Instance.new("Part")
	host.Name = HOST_NAME
	host.Size = Vector3.one
	host.CFrame = cframe
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Massless = true
	host.Transparency = 1
	host.Locked = true
	return host
end

local function playSound(host: BasePart)
	if FX.SoundId == "" then
		return -- 사운드는 Phase 8 담당. 자리만 있고 아직 비어 있다.
	end
	local sound = Instance.new("Sound")
	sound.SoundId = FX.SoundId
	sound.Volume = FX.SoundVolume
	sound.RollOffMaxDistance = FX.Shake.Falloff
	sound.Parent = host
	sound:Play()
end

--- 벽이 있던 자리에서 폭발을 터뜨린다. cframe/size 는 파괴 순간의 벽 그 자체다.
function WallEffects.play(cframe: CFrame, size: Vector3)
	local host = newHost(cframe)

	-- ★ 여기서는 '먼저 붙이고 나중에 채운다' ★
	--   서버 쪽 모듈들(MapBuilder·QuestionDisplay)은 리플리케이션 비용 때문에 내용을 다
	--   채운 뒤 마지막에 부모를 붙이지만, 입자는 반대다. Emit() 은 이미 월드에 들어가 있는
	--   이미터에서만 실제로 터진다 — 부모 없는 상태에서 부르면 아무 일도 일어나지 않는다.
	--   로컬 인스턴스라 복제 비용도 애초에 없다.
	host.Parent = Workspace
	Debris:AddItem(host, FX.Lifetime)

	-- 폭발 지점은 벽의 '앞면'(플레이어를 향한 -Z 면)에 붙인다. 벽 한가운데서 터뜨리면
	-- 두께 안쪽에서 나오는 셈이라 절반이 벽에 가려 보이지 않는다.
	local front = -size.Z / 2
	local points = math.max(FX.BurstPoints, 1)
	local span = size.X * FX.BurstSpread

	for index = 1, points do
		-- points 가 1 이면 정중앙, 2 이상이면 -span/2 ~ +span/2 에 고르게 편다.
		local t = if points == 1 then 0.5 else (index - 1) / (points - 1)
		burstAt(host, Vector3.new((t - 0.5) * span, 0, front))
	end

	flash(host)
	playSound(host)
	shake(cframe.Position)
end

function WallEffects.start()
	Remotes.event("WallBroken").OnClientEvent:Connect(function(zone: string, cframe: CFrame, size: Vector3)
		-- 서버가 보낸 값이지만 형만 확인하고 쓴다. 형이 어긋나면 조용히 넘어가는 편이
		-- 라운드 도중 클라이언트 스크립트가 죽는 것보다 낫다.
		if typeof(cframe) ~= "CFrame" or typeof(size) ~= "Vector3" then
			return
		end
		WallEffects.play(cframe, size)

		if Config.Debug.VerboseLogging then
			print(`[WallEffects] {zone} 구역 벽 파괴 폭발`)
		end
	end)
end

return WallEffects

-- ModuleScript: ReplicatedStorage/Shared/VFX/ForgeBridge
-- Plays VFX Forge templates as one layer of an effect. Effects call it through
-- ctx.Forge (VFXPlayer / VFXScrub), never directly.
--
-- A Forge template is a Model in Shared.VFX.ForgeAssets (an .rbxmx on disk) whose
-- pivot is the effect origin: on the ground, LookVector toward the viewer, like
-- ctx.CFrame. Its children are the Forge items (emitters, beams, mesh models...),
-- authored with the VFX Forge plugin and keeping their Forge attributes.
--
-- The ForgeVFX package (Shared.Packages, installed by Wally) is loaded lazily, the
-- first time a Forge layer plays, and only in a running client. Its license
-- (VFX-DL 1.1) allows it in game runtime only, not in plugins or edit-time tools,
-- so Forge layers are skipped in Edit mode (see VFXScrub).

local RunService = game:GetService("RunService")

local ForgeBridge = {}

local forge = nil

-- True when Forge layers can play here (a running client).
function ForgeBridge.Available()
	return RunService:IsRunning() and RunService:IsClient()
end

local function getForge()
	if forge then
		return forge
	end
	assert(ForgeBridge.Available(), "ForgeBridge: Forge layers play on the client at runtime only")
	local packages = script.Parent.Parent:FindFirstChild("Packages")
	local module = packages and packages:FindFirstChild("ForgeVFX")
	assert(module, "ForgeBridge: Shared.Packages.ForgeVFX is missing (run `wally install`)")
	forge = require(module)
	forge.init()
	return forge
end

local function scaleAttribute(instance, name, factor)
	local value = instance:GetAttribute(name)
	if typeof(value) == "number" or typeof(value) == "Vector3" then
		instance:SetAttribute(name, value * factor)
	elseif typeof(value) == "NumberRange" then
		instance:SetAttribute(name, NumberRange.new(value.Min * factor, value.Max * factor))
	end
end

local BEAM_SIZE_ATTRIBUTES = {
	"Width0_Start",
	"Width0_End",
	"Width1_Start",
	"Width1_End",
	"CurveSize0_Start",
	"CurveSize0_End",
	"CurveSize1_Start",
	"CurveSize1_End",
}
local LIGHTNING_SIZE_ATTRIBUTES = { "OffsetScale", "Width_Start", "Width_End" }
local SHOCKWAVE_SIZE_ATTRIBUTES = { "Radius", "Length", "MinSize", "MaxSize" }

-- Model:ScaleTo already scales parts, attachments, particle Size/Speed/Acceleration
-- and Beam widths/curves. Scale what it misses: SpecialMesh.Scale (Forge mesh
-- effects tween it from Start to End), light ranges and Forge's size attributes.
local function scaleTemplate(model, factor)
	model:ScaleTo(model:GetScale() * factor)
	for _, instance in model:GetDescendants() do
		if instance:IsA("SpecialMesh") then
			instance.Scale *= factor
		elseif instance:IsA("Light") then
			instance.Range *= factor
		elseif instance:IsA("Beam") then
			for _, name in BEAM_SIZE_ATTRIBUTES do
				scaleAttribute(instance, name, factor)
			end
		elseif instance:IsA("Attachment") and instance:HasTag("LightningBolt") then
			for _, name in LIGHTNING_SIZE_ATTRIBUTES do
				scaleAttribute(instance, name, factor)
			end
		elseif instance:IsA("BasePart") then
			for _, name in SHOCKWAVE_SIZE_ATTRIBUTES do
				scaleAttribute(instance, name, factor)
			end
		end
	end
end

-- Forge's retime scales delays, durations, speeds and lifetimes, but not looping
-- flipbook framerates (OneShot flipbooks follow the lifetime already).
local function retimeTemplate(api, model, timeScale)
	api.retime(timeScale, model)
	for _, instance in model:GetDescendants() do
		if instance:IsA("ParticleEmitter") and instance.FlipbookMode ~= Enum.ParticleFlipbookMode.OneShot then
			local framerate = instance.FlipbookFramerate
			instance.FlipbookFramerate = NumberRange.new(framerate.Min * timeScale, framerate.Max * timeScale)
		end
	end
end

-- Clones `template`, places its pivot at `cframe`, applies the options, parents
-- it to `parent` and emits its children. Non-blocking.
--   timeScale  playback speed (ctx.TimeScale)
--   options    optional { Scale = number, Color = Color3, ColorMode = "multiply" | "replace" }
-- Returns the clone and Forge's env (env.Finished:await() blocks until every
-- emitted item is done; env.Clear() stops them).
function ForgeBridge.Emit(template, cframe, parent, timeScale, options)
	local api = getForge()
	options = options or {}

	local clone = template:Clone()
	if options.Scale and options.Scale ~= 1 then
		scaleTemplate(clone, options.Scale)
	end
	clone:PivotTo(cframe)
	if options.Color then
		api.recolor(options.Color, options.ColorMode or "multiply", clone)
	end
	if timeScale ~= 1 then
		retimeTemplate(api, clone, timeScale)
	end
	clone.Parent = parent

	-- Emit the children, not the Model itself: Forge would treat a root Model as
	-- a spin model.
	local items = {}
	for _, child in clone:GetChildren() do
		if not child:IsA("LuaSourceContainer") then
			table.insert(items, child)
		end
	end
	return clone, api.emit(table.unpack(items))
end

return ForgeBridge

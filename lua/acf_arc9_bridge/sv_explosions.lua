-- ARC9 explosions -> ACF HE explosions.
--
-- ARC9's explosive entities (grenades, launcher rounds) derive from `arc9_nade_base` and explode in ENT:Detonate().
-- We wrap Detonate on each such entity instance. While the original Detonate runs, util.BlastDamage /
-- util.BlastDamageInfo calls are *captured* instead of executed (nothing else is touched, so ARC9's sounds, particles,
-- screen shake and removal all still happen). Each captured blast is then turned into an ACF explosion at the same place.
-- This is field-agnostic: we don't need to know what ARC9 calls its damage/radius variables.
--
-- Not covered: entities that deal damage some other way than util.BlastDamage(Info) (env_explosion, direct
-- TakeDamageInfo loops). `acf_arc9_dump_aim` shows what an entity is; use ExplosionOverrides for fixed values.

local Bridge  = ACFArc9Bridge
local Adapter = Bridge.Adapter

-------------------------------------------------------------------------------
-- Blast capture
-------------------------------------------------------------------------------

-- Keep the real functions across Lua refreshes so we never wrap a wrapper
Bridge.RealBlastDamage     = Bridge.RealBlastDamage or util.BlastDamage
Bridge.RealBlastDamageInfo = Bridge.RealBlastDamageInfo or util.BlastDamageInfo

local RealBlastDamage     = Bridge.RealBlastDamage
local RealBlastDamageInfo = Bridge.RealBlastDamageInfo
local Capture -- list while an ARC9 Detonate is running, nil otherwise

util.BlastDamage = function(Inflictor, Attacker, Pos, Radius, Damage, ...)
	if Capture then
		Capture[#Capture + 1] = {Inflictor = Inflictor, Attacker = Attacker, Pos = Pos, Radius = Radius, Damage = Damage}

		return
	end

	return RealBlastDamage(Inflictor, Attacker, Pos, Radius, Damage, ...)
end

if RealBlastDamageInfo then
	util.BlastDamageInfo = function(Info, Pos, Radius, ...)
		if Capture then
			Capture[#Capture + 1] = {
				Inflictor = Info:GetInflictor(),
				Attacker  = Info:GetAttacker(),
				Pos       = Pos,
				Radius    = Radius,
				Damage    = Info:GetDamage(),
			}

			return
		end

		return RealBlastDamageInfo(Info, Pos, Radius, ...)
	end
end

-------------------------------------------------------------------------------
-- Source blast -> ACF filler mass
-------------------------------------------------------------------------------
-- ACF's own scaling is Radius(in) = Filler(kg)^0.33 * 8 * 39.37, so by default we invert that with the blast radius
-- (Hammer units ~ inches). Mode 1 instead uses ~5 g of TNT per point of damage.

local FILLER_MIN, FILLER_MAX = 0.005, 50

local function GetFiller(Blast)
	local Filler

	if Bridge.CV.ExplMode:GetInt() == 1 then
		Filler = Blast.Damage * 0.005
	else
		Filler = (Blast.Radius / (8 * 39.37)) ^ (1 / 0.33)
	end

	return math.Clamp(Filler * Bridge.CV.ExplScale:GetFloat(), FILLER_MIN, FILLER_MAX)
end

local function ConvertBlast(Ent, Class, Blast)
	local Override = Bridge.ExplosionOverrides[Class]

	if Override and Override.Skip then
		-- Leave this class alone: run the real blast instead
		RealBlastDamage(Blast.Inflictor, Blast.Attacker, Blast.Pos, Blast.Radius, Blast.Damage)

		return
	end

	if not (isvector(Blast.Pos) and tonumber(Blast.Radius) and tonumber(Blast.Damage)) then return end
	if Blast.Radius <= 0 or Blast.Damage <= 0 then return end -- smoke/flash/etc: nothing to convert

	local Filler = Override and Override.FillerMass or GetFiller(Blast)
	local Frag   = Override and Override.FragMass or Filler * Bridge.CV.ExplFrag:GetFloat()

	local Attacker  = IsValid(Blast.Attacker) and Blast.Attacker or (IsValid(Ent) and Ent:GetOwner()) or game.GetWorld()
	local Inflictor = IsValid(Blast.Inflictor) and Blast.Inflictor or (IsValid(Ent) and Ent) or Attacker
	local Filter    = IsValid(Ent) and {Ent} or {}

	local Used, Err = Adapter.Explode(Blast.Pos, Filler, Frag, Attacker, Inflictor, Filter)

	if Used then
		Bridge.Debug("%s: blast (r=%.0f, dmg=%.0f) -> ACF %.3f kg filler, %.3f kg casing via %s", Class, Blast.Radius, Blast.Damage, Filler, Frag, Used)
	else
		-- Don't lose the explosion entirely
		Bridge.Debug("%s: ACF explosion failed (%s), running ARC9's blast instead", Class, tostring(Err))
		RealBlastDamage(Blast.Inflictor, Blast.Attacker, Blast.Pos, Blast.Radius, Blast.Damage)
	end
end

-------------------------------------------------------------------------------
-- Patching explosive entities
-------------------------------------------------------------------------------

local function IsARC9Explosive(Ent)
	if Ent:IsWeapon() or Ent:IsPlayer() or Ent:IsNPC() then return false end

	local Class = Ent:GetClass()

	if not (string.StartWith(Class, "arc9") or scripted_ents.IsBasedOn(Class, "arc9_nade_base")) then return false end

	return isfunction(Ent.Detonate)
end

local function Patch(Ent)
	if Ent.ACFBridgeExplosivePatched or not IsARC9Explosive(Ent) then return end

	local Original = Ent.Detonate
	local Class    = Ent:GetClass()

	Ent.ACFBridgeExplosivePatched = true

	Ent.Detonate = function(self, ...)
		if not (Bridge.CV.Explosions:GetBool() and Adapter.CanExplode()) or Capture then
			return Original(self, ...)
		end

		local List = {}

		Capture = List

		local Ok, A, B, C = pcall(Original, self, ...)

		Capture = nil

		if not Ok then ErrorNoHalt("[ACF-ARC9] " .. tostring(A) .. "\n") end

		if #List == 0 then
			Bridge.Debug("%s detonated but called no util.BlastDamage(Info); nothing to convert (see ExplosionOverrides)", Class)
		end

		for _, Blast in ipairs(List) do
			local Done, Err = pcall(ConvertBlast, self, Class, Blast)

			if not Done then ErrorNoHalt("[ACF-ARC9] " .. tostring(Err) .. "\n") end
		end

		if Ok then return A, B, C end
	end

	Bridge.Debug("patched explosive %s", Class)
end

hook.Add("OnEntityCreated", "ACFArc9BridgeExplosives", function(Ent)
	if not IsValid(Ent) then return end

	-- Wait a tick so the entity's table (and its Detonate method) is set up
	timer.Simple(0, function()
		if IsValid(Ent) then Patch(Ent) end
	end)
end)

hook.Add("InitPostEntity", "ACFArc9BridgeExplosives", function()
	for _, Ent in ipairs(ents.GetAll()) do Patch(Ent) end
end)

-------------------------------------------------------------------------------
-- Diagnostics: `acf_arc9_dump_aim` while looking at an ARC9 grenade/rocket entity
-------------------------------------------------------------------------------

concommand.Add("acf_arc9_dump_aim", function(Ply)
	local function Print(Text)
		if IsValid(Ply) then Ply:PrintMessage(HUD_PRINTCONSOLE, Text) else print(Text) end
	end

	if not IsValid(Ply) then return Print("[ACF-ARC9] Run this as a player, looking at the entity.") end

	local Ent = Ply:GetEyeTrace().Entity

	if not IsValid(Ent) then return Print("[ACF-ARC9] Look at an entity (e.g. a grenade stuck in a wall or a placed explosive).") end

	Print("[ACF-ARC9] class       : " .. Ent:GetClass())
	Print("[ACF-ARC9] has Detonate: " .. tostring(isfunction(Ent.Detonate)))
	Print("[ACF-ARC9] arc9 match  : " .. tostring(string.StartWith(Ent:GetClass(), "arc9") or scripted_ents.IsBasedOn(Ent:GetClass(), "arc9_nade_base")))
	Print("[ACF-ARC9] patched     : " .. tostring(Ent.ACFBridgeExplosivePatched == true))
	Print("[ACF-ARC9] ACF explode : " .. tostring(Adapter.CanExplode() and (isfunction(ACF.Damage and ACF.Damage.createExplosion) and "ACF.Damage.createExplosion" or "ACF.HE")))
	Print("[ACF-ARC9] Turn on acf_arc9_debug 1 and detonate it to see the converted blast.")
end)

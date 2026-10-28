local Bridge = ACFArc9Bridge

Bridge.Version = "0.1.0"

local Flags = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

Bridge.CV = {
	Enabled     = CreateConVar("acf_arc9_enabled", "1", Flags, "Replace ARC9 hitscan/physical bullets with ACF bullets.", 0, 1),
	Debug       = CreateConVar("acf_arc9_debug", "0", FCVAR_ARCHIVE, "Print what the bridge is doing to the console.", 0, 1),
	SpreadScale = CreateConVar("acf_arc9_spread_scale", "1", Flags, "Multiplier on the spread ARC9 hands to the bridge. 0 = perfectly accurate.", 0, 10),
	VelScale    = CreateConVar("acf_arc9_velocity_scale", "1", Flags, "Multiplier on every profile's muzzle velocity.", 0.05, 10),
	Explosions  = CreateConVar("acf_arc9_explosions", "1", Flags, "Replace ARC9 explosion damage (grenades, rockets, ...) with ACF HE explosions.", 0, 1),
	ExplMode    = CreateConVar("acf_arc9_explosion_mode", "0", Flags, "How ARC9's blast is turned into ACF filler mass. 0 = from blast radius (default), 1 = from blast damage.", 0, 1),
	ExplScale   = CreateConVar("acf_arc9_explosion_scale", "1", Flags, "Multiplier on the ACF filler mass computed for every converted explosion.", 0, 100),
	ExplFrag    = CreateConVar("acf_arc9_explosion_frag_ratio", "1", Flags, "Fragmenting casing mass as a multiple of the filler mass. Higher = fewer, heavier fragments.", 0.05, 50),
	ProjColl    = CreateConVar("acf_arc9_projectile_collision", "1", Flags, "Stop ARC9 launcher/thrown projectiles from passing through ACF armor.", 0, 1),
	ProjMode    = CreateConVar("acf_arc9_projectile_mode", "0", Flags, "0 = stop the projectile at the armor and let ARC9's own collision code react (bounce/detonate). 1 = call the projectile's PhysicsCollide directly.", 0, 1),
	ProjMinSpeed = CreateConVar("acf_arc9_projectile_minspeed", "150", Flags, "Ignore projectiles slower than this (Hammer units/s), e.g. rolling grenades.", 0, 10000),
	ProjFixGroup = CreateConVar("acf_arc9_projectile_fixgroup", "0", Flags, "Also change projectiles stuck in a debris collision group to COLLISION_GROUP_PROJECTILE so they can touch props at all.", 0, 1),
	ProjTargets = CreateConVar("acf_arc9_projectile_targets", "0", Flags, "What projectiles must not pass through. 0 = ACF-valid props and any parented prop (default), 1 = every solid prop (not world/players/NPCs).", 0, 1),
	ProjBounce  = CreateConVar("acf_arc9_projectile_bounce", "0.5", Flags, "Bounciness (0-1) for projectiles that survive hitting a parented prop (grenades). 0 = they drop dead at the surface.", 0, 1),
	PelletMode  = CreateConVar("acf_arc9_pellets_per_call", "1", Flags, "1 = fire the weapon's Num pellets per DoProjectileAttack call (ARC9 loops inside). 0 = fire exactly one ACF bullet per call (ARC9 loops outside).", 0, 1),
}

function Bridge.Debug(...)
	if not Bridge.CV.Debug:GetBool() then return end

	MsgC(Color(120, 200, 255), "[ACF-ARC9] ", color_white, string.format(...), "\n")
end

-------------------------------------------------------------------------------
-- Ballistic profiles
-------------------------------------------------------------------------------
-- Caliber  : mm
-- Mass     : kg (projectile)
-- MuzzleVel: m/s
-- Type     : "AP" (default) or "HE". HE additionally needs ProjLength (cm) and FillerMass (kg)
-- Tracer   : ACF tracer size, 0 = none
-- Ricochet / LimitVel / ShovePower: optional, fall back to the values ACF-3-SWEPs uses for kinetic rounds

-- Keyed by lower-cased ARC9 ammo name (SWEP.Ammo)
Bridge.AmmoProfiles = {
	pistol   = {Name = "9x19mm",    Caliber = 9,    Mass = 0.0080, MuzzleVel = 380, Tracer = 0},
	smg1     = {Name = "9x19mm SMG", Caliber = 9,   Mass = 0.0080, MuzzleVel = 400, Tracer = 0.5},
	ar2      = {Name = "5.56x45mm", Caliber = 5.56, Mass = 0.0040, MuzzleVel = 940, Tracer = 0.5},
	["357"]  = {Name = ".357 / 9.1mm", Caliber = 9.1, Mass = 0.0102, MuzzleVel = 440, Tracer = 0},
	buckshot = {Name = "00 buckshot pellet", Caliber = 8.4, Mass = 0.0035, MuzzleVel = 400, Tracer = 0},
	sniperpenetratedround = {Name = "7.62x51mm", Caliber = 7.62, Mass = 0.0097, MuzzleVel = 850, Tracer = 1},
	airboatgun = {Name = "12.7x99mm", Caliber = 12.7, Mass = 0.0420, MuzzleVel = 900, Tracer = 1},
	helicoptergun = {Name = "12.7x99mm", Caliber = 12.7, Mass = 0.0420, MuzzleVel = 900, Tracer = 1},

	-- Used by the damage-based fallback below
	_762 = {Name = "7.62x39/51mm", Caliber = 7.62, Mass = 0.0079, MuzzleVel = 720, Tracer = 0.5},
	_127 = {Name = "12.7x99mm", Caliber = 12.7, Mass = 0.0420, MuzzleVel = 900, Tracer = 1},
}

-- When a weapon's ammo name isn't in the table above, pick by ARC9 max damage
Bridge.DamageFallback = {
	{Max = 22,  Key = "pistol"},
	{Max = 32,  Key = "ar2"},
	{Max = 48,  Key = "_762"},
	{Max = 1e9, Key = "_127"},
}

-- Per-weapon overrides, keyed by weapon class. Partial tables are merged onto
-- whatever profile the weapon would have gotten otherwise.
-- Example:
--   Bridge.WeaponOverrides["arc9_mw19_ak47"] = {Name = "7.62x39mm", Caliber = 7.62, Mass = 0.0079, MuzzleVel = 715}
-- Use the `acf_arc9_dump` console command with the weapon in hand to see its class, ammo and resolved profile.
Bridge.WeaponOverrides = Bridge.WeaponOverrides or {}
Bridge.ExplosionOverrides = Bridge.ExplosionOverrides or {} -- see the explosion section below

-- Anything you drop into lua/acf_arc9_bridge/overrides/*.lua is loaded after this file and can call
-- ACFArc9Bridge.WeaponOverrides[...] = {...}
local OverrideFiles = file.Find("acf_arc9_bridge/overrides/*.lua", "LUA")

for _, Name in ipairs(OverrideFiles) do
	local Path = "acf_arc9_bridge/overrides/" .. Name

	if SERVER then AddCSLuaFile(Path) end

	include(Path)
end

-------------------------------------------------------------------------------
-- Explosion overrides
-------------------------------------------------------------------------------
-- Keyed by ARC9 explosive entity class. Fixed ACF values replace the radius/damage conversion:
--   ACFArc9Bridge.ExplosionOverrides["arc9_eft_f1"] = {FillerMass = 0.06, FragMass = 0.5}  -- kg
--   ACFArc9Bridge.ExplosionOverrides["arc9_some_smoke"] = {Skip = true}                    -- leave alone
Bridge.ExplosionOverrides = Bridge.ExplosionOverrides or {}

-------------------------------------------------------------------------------
-- Profile resolution
-------------------------------------------------------------------------------

-- ARC9 resolves stats through GetProcessedValue (attachments, conditions, ...). Fall back to the raw field.
function Bridge.GetStat(Weapon, Name)
	if isfunction(Weapon.GetProcessedValue) then
		local Ok, Value = pcall(Weapon.GetProcessedValue, Weapon, Name)

		if Ok and Value ~= nil then return Value end
	end

	return Weapon[Name]
end

local function Merge(Base, Extra)
	local Result = {}

	for K, V in pairs(Base or {}) do Result[K] = V end
	for K, V in pairs(Extra or {}) do Result[K] = V end

	return Result
end

local Resolved = {} -- class -> profile, so every instance of a class shares one table (and one ACF template)

function Bridge.GetProfile(Weapon)
	local Class = Weapon:GetClass()

	if Resolved[Class] then return Resolved[Class] end

	local Ammo = Bridge.GetStat(Weapon, "Ammo")

	if not isstring(Ammo) and istable(Weapon.Primary) then Ammo = Weapon.Primary.Ammo end

	local Base = isstring(Ammo) and Bridge.AmmoProfiles[string.lower(Ammo)]

	if not Base then
		local Damage = tonumber(Bridge.GetStat(Weapon, "DamageMax")) or 20

		for _, Step in ipairs(Bridge.DamageFallback) do
			if Damage <= Step.Max then
				Base = Bridge.AmmoProfiles[Step.Key]
				break
			end
		end
	end

	local Profile = Merge(Base, Bridge.WeaponOverrides[Class])

	Profile.Type = Profile.Type or "AP"
	Profile.Source = Bridge.WeaponOverrides[Class] and "override" or (Base and "ammo/damage") or "none"

	Resolved[Class] = Profile

	return Profile
end

function Bridge.ClearProfileCache()
	Resolved = {}
end

-- Everything this addon needs from ACF-3's internals lives in this file, so an ACF update only breaks here.
-- The calls below follow the ones ACF-Team's own ACF-3-SWEPs adapter (lua/acf_sweps/acf_adapter.lua) makes:
--   ACF.Classes.GetTypeByName("ACF.Ammunition.<Type>"):Create(Gun, BulletTable)
-- with Caliber in cm, ProjMass in kg, MuzzleVel in m/s, Flight in inches/s (m/s * 39.37).

local Bridge  = ACFArc9Bridge
local Adapter = {}

Bridge.Adapter = Adapter

local function GetAmmoType(Type)
	return ACF.Classes.GetTypeByName("ACF.Ammunition." .. Type)
end

function Adapter.IsAvailable()
	return ACF ~= nil and ACF.Classes ~= nil and isfunction(ACF.Classes.GetTypeByName)
end

local function BuildKinetic(Profile, Bullet)
	Bullet.ProjMass   = Profile.Mass
	Bullet.DragCoef   = Bullet.ProjArea * 0.0001 / Profile.Mass
	Bullet.Ricochet   = Profile.Ricochet or 60
	Bullet.LimitVel   = Profile.LimitVel or 800
	Bullet.ShovePower = Profile.ShovePower or 0.2
end

local function BuildHE(Profile, Bullet)
	local ProjLength = Profile.ProjLength or (Bullet.Caliber * 4)
	local Filler     = Profile.FillerMass or 0.001
	local FreeVol    = ACF.RoundShellCapacity(0, Bullet.ProjArea, Bullet.Caliber, ProjLength)

	Bullet.ProjLength = ProjLength
	Bullet.FillerMass = Filler
	Bullet.ProjMass   = math.max(FreeVol, 0) * ACF.SteelDensity + Filler
	Bullet.DragCoef   = Bullet.ProjArea * 0.0001 / Bullet.ProjMass
	Bullet.Ricochet   = Profile.Ricochet or 60
	Bullet.LimitVel   = Profile.LimitVel or 100
	Bullet.ShovePower = Profile.ShovePower or 0.1
end

local Builders = {
	AP  = BuildKinetic,
	HE  = BuildHE,
}

local Templates = {} -- Profile table -> built bullet template (profiles are cached per weapon class)

-- The bullet table ACF fires. Built once per profile; copy it before firing.
function Adapter.GetTemplate(Profile)
	local Cached = Templates[Profile]

	if Cached then return Cached end

	local Builder = Builders[Profile.Type]

	if not Builder then return nil, "unsupported ACF type '" .. tostring(Profile.Type) .. "'" end

	local Caliber = Profile.Caliber * 0.1 -- mm to cm
	local Bullet  = {
		Type     = Profile.Type,
		AmmoType = "ACF.Ammunition." .. Profile.Type,
		Caliber  = Caliber,
		Diameter = Caliber,
		ProjArea = math.pi * (Caliber * 0.5) ^ 2,
	}

	Builder(Profile, Bullet)

	Bullet.MuzzleVel = Profile.MuzzleVel * Bridge.CV.VelScale:GetFloat()
	Bullet.Tracer    = Profile.Tracer or 0

	Templates[Profile] = Bullet

	return Bullet
end

-- Velocity scale is a convar, so invalidate when it changes
cvars.AddChangeCallback("acf_arc9_velocity_scale", function() Templates = {} end, "ACFArc9Bridge")

-- ACF's bullet effect reads the round from the crate it came from; the weapon stands in for it
function Adapter.NetworkCrate(Weapon, Template)
	if Weapon.ACFBridgeNet == Template then return end

	Weapon:SetNW2Float("Caliber", Template.Caliber)
	Weapon:SetNW2Float("ProjMass", Template.ProjMass)
	Weapon:SetNW2Float("DragCoef", Template.DragCoef)
	Weapon:SetNW2String("AmmoType", Template.AmmoType)
	Weapon:SetNW2Float("Tracer", Template.Tracer or 0)

	if Template.Type == "HE" then Weapon:SetNW2Float("FillerMass", Template.FillerMass) end

	Weapon.ACFBridgeNet = Template
end

-- ACF and other addons can stop guns from firing
function Adapter.CanFire(Weapon)
	return ACF.GunsCanFire ~= false and hook.Run("ACF_FireShell", Weapon) ~= false
end

local function Copy(Table)
	local Result = {}

	for K, V in pairs(Table) do Result[K] = V end

	return Result
end

-- Fires one ACF bullet
function Adapter.FireProjectile(Weapon, Template, Pos, Dir, Filter)
	local Owner  = Weapon:GetOwner()
	local Bullet = Copy(Template)

	Bullet.Owner  = Owner
	Bullet.Gun    = Weapon
	Bullet.Pos    = Pos
	Bullet.Filter = Filter
	Bullet.Crate  = Weapon:EntIndex()
	Bullet.Flight = Dir * Bullet.MuzzleVel * 39.37 + Owner:GetVelocity()

	GetAmmoType(Bullet.Type):Create(Weapon, Bullet)
end

-------------------------------------------------------------------------------
-- Explosions
-------------------------------------------------------------------------------
-- Filler/Frag are kg. Two ACF generations are supported, tried in this order:
--   1. ACF.Damage.createExplosion(Pos, Filler, Frag, Filter, DamageInfo)   (newer ACF-3 damage objects, same
--      ACF.Damage.Objects.DamageInfo() the ACF-3-SWEPs adapter uses; signature NOT confirmed from source)
--   2. ACF.HE(Pos, Filler, Frag, Attacker, Filter, Gun)                    (older ACF-3, confirmed in its damage_sv.lua)
-- Returns the name of the function used, or nil + error.

function Adapter.CanExplode()
	local Damage = ACF and ACF.Damage

	return (istable(Damage) and isfunction(Damage.createExplosion)) or (ACF and isfunction(ACF.HE)) or false
end

function Adapter.Explode(Pos, Filler, Frag, Attacker, Inflictor, Filter)
	local Damage = ACF.Damage

	if istable(Damage) and isfunction(Damage.createExplosion) and istable(Damage.Objects) then
		local Ok, Err = pcall(function()
			local Info = Damage.Objects.DamageInfo()

			Info:SetAttacker(Attacker)
			Info:SetInflictor(Inflictor)
			Info:SetType(DMG_BLAST)
			Info:SetOrigin(Pos)

			Damage.createExplosion(Pos, Filler, Frag, Filter, Info)
		end)

		if Ok then return "ACF.Damage.createExplosion" end

		Bridge.Debug("ACF.Damage.createExplosion failed (%s), trying ACF.HE", tostring(Err))
	end

	if isfunction(ACF.HE) then
		local Ok, Err = pcall(ACF.HE, Pos, Filler, Frag, Attacker, Filter, Inflictor)

		if Ok then return "ACF.HE" end

		return nil, tostring(Err)
	end

	return nil, "no ACF explosion function found"
end

return Adapter

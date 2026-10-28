-- Everything this addon needs from ARC9's internals lives in this file.
--
-- ARC9's shot path (from its stack traces) is:
--   SWEP:DoPrimaryAttack -> SWEP:DoProjectileAttack -> ShootPhysBullet / FireBullets -> AfterShotFunction
-- We wrap DoProjectileAttack(pos, ang, spread) on each ARC9 weapon instance. Ammo use, recoil, animation,
-- sounds and muzzle effects all still run in ARC9; only the bullet itself is swapped for an ACF bullet.
--
-- Every assumption about ARC9 is guarded: if an argument doesn't look the way we expect, or anything
-- errors, the original ARC9 function runs instead so the weapon keeps working.

local Bridge = ACFArc9Bridge

local function IsARC9(Weapon)
	if not (IsValid(Weapon) and Weapon:IsWeapon()) then return false end

	return Weapon.ARC9 == true or weapons.IsBasedOn(Weapon:GetClass(), "arc9_base")
end

Bridge.IsARC9 = IsARC9

-- Projectile/launcher shots and underbarrel launchers stay ARC9's (ShootEnt / ShootEntUBGL in ARC9)
local function ShouldPassThrough(Weapon)
	-- ARC9 entity projectiles include rocket/grenade launchers. Keep their native ARC9
	-- behavior; this bridge is for ordinary bullet-firing firearms only.
	if Bridge.GetStat(Weapon, "ShootEnt") then return true end
	if Bridge.GetStat(Weapon, "ShootEntUBGL") and isfunction(Weapon.GetUBGL) then
		local Ok, Active = pcall(Weapon.GetUBGL, Weapon)
		if Ok and Active then return true end
	end

	if isfunction(Weapon.GetUBGL) then
		local Ok, Active = pcall(Weapon.GetUBGL, Weapon)

		if Ok and Active then return true end
	end

	return false
end

local function ApplySpread(Ang, Spread)
	local Dir = Ang:Forward()

	if isvector(Spread) then Spread = math.max(Spread.x, Spread.y) end
	if not isnumber(Spread) or Spread <= 0 then return Dir end

	Spread = Spread * Bridge.CV.SpreadScale:GetFloat()

	if Spread <= 0 then return Dir end

	-- Uniform point in a disc, same meaning as FireBullets' Spread
	local Radius = Spread * math.sqrt(math.random())
	local Theta  = math.random() * math.pi * 2

	return (Dir + Ang:Right() * (Radius * math.cos(Theta)) + Ang:Up() * (Radius * math.sin(Theta))):GetNormalized()
end

local function FireACF(Weapon, Pos, Ang, Spread)
	local Adapter = Bridge.Adapter
	local Owner   = Weapon:GetOwner()

	if not IsValid(Owner) then return false end
	if not Adapter.CanFire(Weapon) then return true end -- ACF says no; still counts as handled

	local Profile = Bridge.GetProfile(Weapon)
	local Template, Err = Adapter.GetTemplate(Profile)

	if not Template then
		Bridge.Debug("%s: %s", Weapon:GetClass(), Err)
		return false
	end

	Adapter.NetworkCrate(Weapon, Template)

	local Count  = Bridge.CV.PelletMode:GetBool() and math.max(math.floor(tonumber(Bridge.GetStat(Weapon, "Num")) or 1), 1) or 1
	local Filter = {Owner, Weapon}

	for _ = 1, Count do
		Adapter.FireProjectile(Weapon, Template, Pos, ApplySpread(Ang, Spread), Filter)
	end

	Bridge.Debug("%s fired %dx %s (%.1f mm, %.2f g, %d m/s) [profile: %s]", Weapon:GetClass(), Count, Profile.Type,
		Profile.Caliber, Profile.Mass * 1000, Template.MuzzleVel, Profile.Source)

	return true
end

local Warned = {}

local function Patch(Weapon)
	if Weapon.ACFBridgePatched or not IsARC9(Weapon) then return end

	local Original = Weapon.DoProjectileAttack

	if not isfunction(Original) then
		if not Warned[Weapon:GetClass()] then
			Warned[Weapon:GetClass()] = true
			Bridge.Debug("%s has no DoProjectileAttack, leaving it alone", Weapon:GetClass())
		end

		return
	end

	Weapon.ACFBridgePatched = true
	Weapon.ACFBridgeOriginal = Original

	Weapon.DoProjectileAttack = function(self, Pos, Ang, Spread, ...)
		-- Anything that doesn't look like what we expect goes straight back to ARC9
		if not Bridge.CV.Enabled:GetBool() then return Original(self, Pos, Ang, Spread, ...) end
		if not (ACF and ACF.Classes) then return Original(self, Pos, Ang, Spread, ...) end
		if not (isvector(Pos) and isangle(Ang)) then
			Bridge.Debug("%s: DoProjectileAttack args weren't (Vector, Angle, ...), using ARC9's bullet", self:GetClass())

			return Original(self, Pos, Ang, Spread, ...)
		end
		if ShouldPassThrough(self) then return Original(self, Pos, Ang, Spread, ...) end

		-- Clients don't make ACF bullets (the server replicates the effect); skip ARC9's local bullet too
		-- so the shot isn't doubled up visually.
		if CLIENT then return end

		local Ok, Handled = pcall(FireACF, self, Pos, Ang, Spread)

		if Ok and Handled then return end

		if not Ok then
			ErrorNoHalt("[ACF-ARC9] " .. tostring(Handled) .. "\n")
		end

		return Original(self, Pos, Ang, Spread, ...)
	end
end

-- Patch weapons as they appear. Instance-level patching works no matter how GMod resolved the SWEP's inheritance
-- or in which order addons loaded.
hook.Add("OnEntityCreated", "ACFArc9Bridge", function(Ent)
	if not (IsValid(Ent) and Ent:IsWeapon()) then return end

	-- Wait a tick so the SWEP table (and its class) is fully set up
	timer.Simple(0, function()
		if IsValid(Ent) then Patch(Ent) end
	end)
end)

hook.Add("InitPostEntity", "ACFArc9Bridge", function()
	for _, Ent in ipairs(ents.GetAll()) do
		if Ent:IsWeapon() then Patch(Ent) end
	end

	if SERVER and not Bridge.Adapter.IsAvailable() then
		ErrorNoHalt("[ACF-ARC9] ACF-3 doesn't look loaded (ACF.Classes missing); ARC9 weapons will use their own bullets.\n")
	end
end)

-------------------------------------------------------------------------------
-- Diagnostics: `acf_arc9_dump` with an ARC9 weapon in hand
-------------------------------------------------------------------------------

if SERVER then
	concommand.Add("acf_arc9_dump", function(Ply)
		local function Print(Text)
			if IsValid(Ply) then Ply:PrintMessage(HUD_PRINTCONSOLE, Text) else print(Text) end
		end

		local Weapon = IsValid(Ply) and Ply:GetActiveWeapon()

		if not IsValid(Weapon) then return Print("[ACF-ARC9] Hold an ARC9 weapon and run this again.") end
		if not IsARC9(Weapon) then return Print("[ACF-ARC9] " .. Weapon:GetClass() .. " isn't an ARC9 weapon.") end

		local Profile = Bridge.GetProfile(Weapon)

		Print("[ACF-ARC9] class        : " .. Weapon:GetClass())
		Print("[ACF-ARC9] ARC9 ammo    : " .. tostring(Bridge.GetStat(Weapon, "Ammo")))
		Print("[ACF-ARC9] ARC9 DamageMax: " .. tostring(Bridge.GetStat(Weapon, "DamageMax")))
		Print("[ACF-ARC9] ARC9 Num     : " .. tostring(Bridge.GetStat(Weapon, "Num")))
		Print("[ACF-ARC9] ShootEnt     : " .. tostring(Bridge.GetStat(Weapon, "ShootEnt")))
		Print("[ACF-ARC9] patched      : " .. tostring(Weapon.ACFBridgePatched == true))
		Print("[ACF-ARC9] profile      : " .. tostring(Profile.Name) .. " (" .. Profile.Source .. ")")
		Print(string.format("[ACF-ARC9] ACF round    : %s, %.2f mm, %.2f g, %d m/s", Profile.Type, Profile.Caliber or 0,
			(Profile.Mass or 0) * 1000, (Profile.MuzzleVel or 0) * Bridge.CV.VelScale:GetFloat()))
		Print("[ACF-ARC9] To change it: ACFArc9Bridge.WeaponOverrides[\"" .. Weapon:GetClass() .. "\"] = {...}")
	end)
end

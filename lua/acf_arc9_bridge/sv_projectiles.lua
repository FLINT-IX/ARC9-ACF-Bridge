-- ARC9 launcher rounds and thrown grenades -> collide with ACF armor instead of passing through it.
--
-- The usual cause is tunnelling: ACF armor is typically a thin plate, and a fast physics entity can cross it
-- between two physics steps without ever registering a collision. (The other possible cause, a debris-type
-- collision group, is handled by the optional acf_arc9_projectile_fixgroup.)
--
-- Every tick we sweep a small hull from each tracked projectile along its velocity for one tick. If the first thing
-- it would reach is an ACF entity, we act before the physics engine can skip over it:
--   mode 0: place the projectile right at the armor surface, so the engine's own collision fires on the next step and
--           ARC9's PhysicsCollide logic decides what happens (detonate, bounce, stick). If it hits the same armor
--           again within 0.2 s the physics didn't react, so we escalate to mode 1 for that hit.
--   mode 1: call the projectile's PhysicsCollide ourselves with a synthetic collision-data table.
-- Everything else (world, ordinary unparented props) is left to normal physics.
--
-- PARENTED PROPS: a prop parented to another entity has no simulated physics object of its own, so physics
-- projectiles never collide with it, no matter how slow they are. Traces do hit it (it's still solid to bullets),
-- so the sweep finds it, and since the engine can't resolve that collision we skip mode 0 for parented targets and
-- call PhysicsCollide ourselves. A projectile that survives (a grenade) is then bounced off the surface by hand.

local Bridge = ACFArc9Bridge

local Tracked = {} -- Ent -> state

local function IsARC9Projectile(Ent)
	if Ent:IsWeapon() or Ent:IsPlayer() or Ent:IsNPC() then return false end

	local Class = Ent:GetClass()

	if Bridge.ProjectileClasses and Bridge.ProjectileClasses[Class] then return true end

	return string.StartWith(Class, "arc9") or scripted_ents.IsBasedOn(Class, "arc9_nade_base")
end

-- Extra classes whose names don't start with "arc9": ACFArc9Bridge.ProjectileClasses["my_rocket"] = true
Bridge.ProjectileClasses = Bridge.ProjectileClasses or {}

local BAD_GROUPS = {
	[COLLISION_GROUP_DEBRIS]             = true,
	[COLLISION_GROUP_DEBRIS_TRIGGER]     = true,
	[COLLISION_GROUP_INTERACTIVE_DEBRIS] = true,
	[COLLISION_GROUP_WORLD]              = true,
}

local function Track(Ent)
	if Tracked[Ent] or not IsARC9Projectile(Ent) then return end

	Tracked[Ent] = {Born = CurTime()}

	if Bridge.CV.ProjFixGroup:GetBool() and BAD_GROUPS[Ent:GetCollisionGroup()] then
		Ent:SetCollisionGroup(COLLISION_GROUP_PROJECTILE)
		Bridge.Debug("%s: collision group changed to PROJECTILE", Ent:GetClass())
	end

	Bridge.Debug("tracking projectile %s", Ent:GetClass())
end

hook.Add("OnEntityCreated", "ACFArc9BridgeProjectiles", function(Ent)
	if not IsValid(Ent) then return end

	timer.Simple(0, function()
		if IsValid(Ent) then Track(Ent) end
	end)
end)

hook.Add("InitPostEntity", "ACFArc9BridgeProjectiles", function()
	for _, Ent in ipairs(ents.GetAll()) do Track(Ent) end
end)

local function Root(Ent)
	while IsValid(Ent:GetParent()) do Ent = Ent:GetParent() end

	return Ent
end

local function IsParented(Ent)
	return IsValid(Ent:GetParent())
end

-- Is this something the projectile must not pass through?
local function IsTarget(Ent)
	if not IsValid(Ent) or Ent:IsWorld() or Ent:IsPlayer() or Ent:IsNPC() or Ent:IsWeapon() then return false end

	if Bridge.CV.ProjTargets:GetInt() == 1 then return true end

	return IsParented(Ent) or (ACF and isfunction(ACF.Check) and ACF.Check(Ent) and true or false)
end

local TraceData = {start = true, endpos = true, mins = true, maxs = true, mask = MASK_SOLID, filter = true}
local Filter    = {}

local function SyntheticCollide(Ent, Phys, Tr, Vel, DT)
	local Hit      = Tr.Entity
	local HitPhys  = Hit:GetPhysicsObject()
	local TheirVel = Hit:GetVelocity()

	local Data = {
		HitPos           = Tr.HitPos,
		HitNormal        = Tr.HitNormal,
		HitEntity        = Hit,
		HitObject        = HitPhys,
		PhysObject       = Phys,
		OurOldVelocity   = Vel,
		TheirOldVelocity = TheirVel,
		Speed            = Vel:Length(),
		HitSpeed         = Vel - TheirVel,
		DeltaTime        = DT,
		OurSurfaceProps  = 0,
		TheirSurfaceProps = 0,
	}

	local Ok, Err = pcall(Ent.PhysicsCollide, Ent, Data, Phys)

	if not Ok then ErrorNoHalt("[ACF-ARC9] " .. tostring(Err) .. "\n") end
end

local function Think(Ent, State, Now, DT)
	if Now - State.Born < 0.15 then return end -- don't hit our own gun/vehicle on the way out

	local Phys = Ent:GetPhysicsObject()
	local Vel  = IsValid(Phys) and Phys:GetVelocity() or Ent:GetVelocity()
	local Speed = Vel:Length()

	if Speed < Bridge.CV.ProjMinSpeed:GetFloat() then return end

	local Pos  = Ent:GetPos()
	local Dir  = Vel / Speed
	local Size = math.Clamp(Ent:BoundingRadius() * 0.3, 1, 6)

	-- One tick of travel plus a little margin
	TraceData.start  = Pos
	TraceData.endpos = Pos + Vel * DT * 1.25 + Dir * Size
	TraceData.mins   = Vector(-Size, -Size, -Size)
	TraceData.maxs   = Vector(Size, Size, Size)

	Filter[1], Filter[2], Filter[3] = Ent, Ent:GetOwner(), nil

	local Owner = Ent:GetOwner()

	if IsValid(Owner) and Owner:IsPlayer() and Owner:InVehicle() then Filter[3] = Owner:GetVehicle() end

	TraceData.filter = Filter

	local Tr = util.TraceHull(TraceData)

	if not (Tr.Hit and IsTarget(Tr.Entity)) then return end

	local Target = Tr.Entity

	-- Parts of the shooter's own vehicle/contraption don't count
	if IsValid(Owner) then
		local Base = Root(Target)

		if Base == Owner or (Owner:IsPlayer() and Owner:InVehicle() and Base == Root(Owner:GetVehicle())) then return end
	end

	local Parented = IsParented(Target)
	local Again    = State.LastHit == Target and Now - State.LastHitTime < 0.2

	State.LastHit, State.LastHitTime = Target, Now

	-- Mode 0 only works when the engine can actually collide with the target; parented props can't be collided with
	if Bridge.CV.ProjMode:GetInt() == 0 and not Parented and not Again then
		local Snap = Tr.HitPos - Dir * 0.5

		Bridge.Debug("%s about to tunnel through %s at %.0f u/s: stopping at the surface", Ent:GetClass(), Target:GetClass(), Speed)

		if IsValid(Phys) then
			Phys:SetPos(Snap)
			Phys:SetVelocity(Vel)
			Phys:Wake()
		else
			Ent:SetPos(Snap)
		end

		return
	end

	Bridge.Debug("%s hit %s (%s) at %.0f u/s: calling PhysicsCollide%s", Ent:GetClass(), Target:GetClass(),
		Parented and "parented prop" or "ACF/prop", Speed, Again and " (physics didn't react)" or "")

	SyntheticCollide(Ent, Phys, Tr, Vel, DT)

	-- Still here (a grenade, say)? Bounce it off by hand, since physics won't
	if IsValid(Ent) and (Parented or Again) then
		local Normal = Tr.HitNormal
		local Bounce = Bridge.CV.ProjBounce:GetFloat()
		local NewVel = (Vel - Normal * Vel:Dot(Normal) * (1 + Bounce))

		local NewPos = Tr.HitPos + Normal * (Size + 1)

		if IsValid(Phys) then
			Phys:SetPos(NewPos)
			Phys:SetVelocity(NewVel)
			Phys:Wake()
		else
			Ent:SetPos(NewPos)
		end
	end
end

hook.Add("Tick", "ACFArc9BridgeProjectiles", function()
	if not Bridge.CV.ProjColl:GetBool() then return end

	local Now, DT = CurTime(), engine.TickInterval()

	for Ent, State in pairs(Tracked) do
		if not IsValid(Ent) then
			Tracked[Ent] = nil
		else
			local Ok, Err = pcall(Think, Ent, State, Now, DT)

			if not Ok then
				ErrorNoHalt("[ACF-ARC9] " .. tostring(Err) .. "\n")
				Tracked[Ent] = nil -- don't spam every tick
			end
		end
	end
end)

-- Extend `acf_arc9_dump_aim` with projectile info
concommand.Add("acf_arc9_dump_projectile", function(Ply)
	local function Print(Text)
		if IsValid(Ply) then Ply:PrintMessage(HUD_PRINTCONSOLE, Text) else print(Text) end
	end

	local Ent = IsValid(Ply) and Ply:GetEyeTrace().Entity

	if not IsValid(Ent) then return Print("[ACF-ARC9] Look at a projectile entity first.") end

	local Phys = Ent:GetPhysicsObject()

	Print("[ACF-ARC9] class           : " .. Ent:GetClass())
	Print("[ACF-ARC9] tracked         : " .. tostring(Tracked[Ent] ~= nil))
	Print("[ACF-ARC9] collision group : " .. tostring(Ent:GetCollisionGroup()) .. (BAD_GROUPS[Ent:GetCollisionGroup()] and "  (debris-type: won't touch props)" or ""))
	Print("[ACF-ARC9] has physics     : " .. tostring(IsValid(Phys)))
	Print("[ACF-ARC9] movetype        : " .. tostring(Ent:GetMoveType()))
	Print("[ACF-ARC9] has PhysicsCollide: " .. tostring(isfunction(Ent.PhysicsCollide)))
end)

-- `acf_arc9_dump_target` while looking at the prop a projectile is going through
concommand.Add("acf_arc9_dump_target", function(Ply)
	local function Print(Text)
		if IsValid(Ply) then Ply:PrintMessage(HUD_PRINTCONSOLE, Text) else print(Text) end
	end

	local Ent = IsValid(Ply) and Ply:GetEyeTrace().Entity

	if not IsValid(Ent) then return Print("[ACF-ARC9] Look at the prop first.") end

	local Phys = Ent:GetPhysicsObject()

	Print("[ACF-ARC9] class         : " .. Ent:GetClass())
	Print("[ACF-ARC9] parent        : " .. tostring(Ent:GetParent()) .. "  (root: " .. tostring(Root(Ent)) .. ")")
	Print("[ACF-ARC9] ACF.Check     : " .. tostring(ACF and isfunction(ACF.Check) and ACF.Check(Ent)))
	Print("[ACF-ARC9] solid / group : " .. tostring(Ent:GetSolid()) .. " / " .. tostring(Ent:GetCollisionGroup()))
	Print("[ACF-ARC9] physobj       : " .. tostring(IsValid(Phys)) .. (IsValid(Phys) and ("  collisions=" .. tostring(Phys:IsCollisionEnabled())) or ""))
	Print("[ACF-ARC9] counts as target: " .. tostring(IsTarget(Ent)))
end)

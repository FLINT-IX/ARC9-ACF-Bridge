-- ACF-3 <-> ARC9 normal firearm bridge loader.
-- This build intentionally does NOT patch ARC9 explosives, launchers, or projectile collision.

ACFArc9Bridge = ACFArc9Bridge or {}

if SERVER then
    AddCSLuaFile("acf_arc9_bridge/sh_config.lua")
    AddCSLuaFile("acf_arc9_bridge/sh_arc9_hook.lua")
end

include("acf_arc9_bridge/sh_config.lua")

-- Always start with debug logging disabled, even if an old archived convar saved it as 1.
if SERVER then
    RunConsoleCommand("acf_arc9_debug", "0")
end

if SERVER then
    include("acf_arc9_bridge/sv_acf_adapter.lua")
end

include("acf_arc9_bridge/sh_arc9_hook.lua")

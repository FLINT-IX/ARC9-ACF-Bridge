-- Drop-in per-weapon tuning. Every .lua file in this folder is loaded after the defaults.
-- Run `acf_arc9_dump` with the weapon in your hands to get its class name.
--
-- Fields (all optional, merged on top of the profile the weapon would get from its ARC9 ammo type):
--   Name, Caliber (mm), Mass (kg), MuzzleVel (m/s), Type ("AP" or "HE"), Tracer (ACF tracer size, 0 = none),
--   Ricochet, LimitVel, ShovePower, and for HE: ProjLength (cm), FillerMass (kg)
--
local Bridge = ACFArc9Bridge
Bridge.WeaponOverrides["arc9_cod2019_ar_ak47"] = {Name = "7.62x39mm", Caliber = 7.62, Mass = 0.0079, MuzzleVel = 715, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_ar_an94"] = {Name = "5.45×39mm", Caliber = 5.45, Mass = 0.0053, MuzzleVel = 880, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_ar_asval"] = {Name = "9×39mm", Caliber = 9, Mass = 0.0248, MuzzleVel = 300, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_ar_fal"] = {Name = "7.62×51mm", Caliber = 7.62, Mass = 0.0130, MuzzleVel = 930, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_ar_scar"] = {Name = "7.62×51mm", Caliber = 7.62, Mass = 0.0130, MuzzleVel = 930, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_ar_m13"] = {Name = ".300 AAC Blackout", Caliber = 7.62, Mass = 0.0078, MuzzleVel = 850, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_ar_oden"] = {Name = "12.7×55mm STs-130", Caliber = 12.7, Mass = 0.0911, MuzzleVel = 295, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_pi_357"] = {Name = ".357 Magnum", Caliber = 9.1, Mass = 0.0180, MuzzleVel = 600, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_pi_50gs"] = {Name = ".50 Action Express", Caliber = 12.7, Mass = 0.0300, MuzzleVel = 600, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_pi_m1911"] = {Name = ".45 ACP", Caliber = 11.5, Mass = 0.0230, MuzzleVel = 830, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_pi_357_akimbo"] = {Name = ".357 Magnum", Caliber = 9.1, Mass = 0.0180, MuzzleVel = 600, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_pi_50gs_akimbo"] = {Name = ".50 Action Express", Caliber = 12.7, Mass = 0.0300, MuzzleVel = 600, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_pi_m1911_akimbo"] = {Name = ".45 ACP", Caliber = 11.5, Mass = 0.0230, MuzzleVel = 830, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_lm_pkm"] = {Name = "7.62×54mmR", Caliber = 7.62, Mass = 0.0180, MuzzleVel = 830, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_lm_raal"] = {Name = ".338 Norma Magnum", Caliber = 8.60, Mass = 0.0300, MuzzleVel = 830, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_mm_sks"] = {Name = "7.62x39mm", Caliber = 7.62, Mass = 0.0079, MuzzleVel = 715, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_mm_spr208"] = {Name = ".300 Winchester Magnum", Caliber = 7.8, Mass = 0.0190, MuzzleVel = 950, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_sm_vector"] = {Name = ".45 ACP", Caliber = 11.5, Mass = 0.0230, MuzzleVel = 830, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_sm_mp7"] = {Name = "HK 4.6×30mm", Caliber = 4.65, Mass = 0.0030, MuzzleVel = 720, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_sm_p90"] = {Name = "FN 5.7×28mm", Caliber = 5.7, Mass = 0.0031, MuzzleVel = 715, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_sm_striker45"] = {Name = ".45 ACP", Caliber = 11.5, Mass = 0.0230, MuzzleVel = 830, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_sm_uzi"] = {Name = ".45 ACP", Caliber = 11.5, Mass = 0.0230, MuzzleVel = 830, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_sn_ax50"] = {Name = ".50 BMG", Caliber = 12.7, Mass = 0.0650, MuzzleVel = 928, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_sn_rytec"] = {Name = ".50 BMG", Caliber = 12.7, Mass = 0.0650, MuzzleVel = 928, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_sn_hdr"] = {Name = ".50 BMG", Caliber = 12.7, Mass = 0.0650, MuzzleVel = 928, Tracer = 0.5,}
Bridge.WeaponOverrides["arc9_cod2019_sn_svd"] = {Name = "7.62×54mmR", Caliber = 7.62, Mass = 0.0180, MuzzleVel = 830, Tracer = 0.5,}

-- Explosions: fixed ACF values for an ARC9 explosive entity class (kg), or leave it as ARC9's own blast.
-- Use `acf_arc9_dump_aim` while looking at the entity to get its class.
-- ACFArc9Bridge.ExplosionOverrides["arc9_eft_f1"]    = {FillerMass = 0.06, FragMass = 0.5}
-- ACFArc9Bridge.ExplosionOverrides["arc9_some_smoke"] = {Skip = true}

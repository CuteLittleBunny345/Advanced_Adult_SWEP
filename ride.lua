- His side of the NPC pack's Supreme Hunter (2026-11-04): only its drg_proto_supreme_hunter.lua plays these, through his seize (alex_mercer/ssgrip.lua): nothing without the pack.
-- The ride: //supreme_hunter's store grapple, node prototype (build/graph_supreme_hunter.txt 2574-2700); its side owns the scene, his Motion_Root on its Root_Grapple.
-- The tendrils of its devastator: hitreaction DevastatorTendril, bank prototype (build/graph_hitreaction_hunter.txt 5742-5801): impaled while they hit, then down.
-- The Mother's body: his half of her consume (build/graph_mother_core.txt S105), the pack's drg_proto_mother_corpse.lua.
if not ALEX_MERCER_FRAMES or not ALEX_MERCER_GRAPH then return end
local G = ALEX_MERCER_GRAPH
for name, n in pairs({supreme_hunter_grapped_start_gv = 97, supreme_hunter_grapped_cycle_gv = 61, supreme_hunter_grapped_punch_gv = 32, supreme_hunter_grapped_jump_off_gv = 81,
	supreme_hunter_grapped_throw_rcv = 44, alex_gethit_devastator_cycle = 31, alex_gethit_groundspike_to_idle = 76, alex_mother_consume_gv = 273, alex_blades_attack_d = 51}) do
	ALEX_MERCER_FRAMES[name] = ALEX_MERCER_FRAMES[name] or n
end
local function tr(t0, t1, anim, rate, f0, f1)
	return {start = t0, stop = t1, anim = anim, rate = rate, f0 = f0, f1 = f1, cyclic = false, part = "", blendin = 0, blendout = 0}
end
local function loop(anim, f1)
	return {start = 0, stop = -1, anim = anim, rate = 1, f0 = 0, f1 = f1, cyclic = true, part = "", blendin = 0.0667, blendout = 0}
end
G["mercer/ride/start"] = {tr(0, -1, "supreme_hunter_grapped_start_gv", 1, 0, 95)}
G["mercer/ride/cycle"] = {loop("supreme_hunter_grapped_cycle_gv", 60)}
G["mercer/ride/punch1"] = {tr(0, -1, "supreme_hunter_grapped_punch_gv", 1, 0, 10)}
G["mercer/ride/punch2"] = {tr(0, -1, "supreme_hunter_grapped_punch_gv", 1, 10, 30)}
-- (0-45, then held till he lands: its side goes on to the land)
G["mercer/ride/exit"] = {tr(0, 1.5, "supreme_hunter_grapped_jump_off_gv", 1, 0, 45), tr(1.5, 30, "supreme_hunter_grapped_jump_off_gv", 1, 45, 46)}
G["mercer/ride/land"] = {tr(0, -1, "supreme_hunter_grapped_jump_off_gv", 1, 45, -1)}
G["mercer/ride/thrown"] = {tr(0, -1, "supreme_hunter_grapped_throw_rcv", 1, 0, -1)}
G["mercer/mother/consume"] = {tr(0, -1, "alex_mother_consume_gv", 1, 0, -1)}
-- (2026-11-06) its death's finisher (e10m04 gives him the blades; the video's 315.8 - 316.1 s): alex_blades_attack_D's swing, the cut at frame 12 (0.4 s); the pack's
-- SupremeDecap carries him up through its neck and lets go
G["mercer/supreme/decap"] = {tr(0, 0.4, "alex_blades_attack_D", 1, 0, 12), tr(0.4, 0.8, "alex_blades_attack_D", 1, 12, 24), tr(0.8, -1, "alex_blades_attack_D", 1, 24, 50)}
-- 5755; detach 5781 (x0.2 2-8), hit_ground 5797-5801
G["mercer/hit/tendril"] = {loop("alex_gethit_devastator_cycle", 30)}
G["mercer/hit/tendril_off"] = {tr(0, 1, "alex_gethit_groundspike_to_idle", 0.2, 2, 8)}
G["mercer/hit/tendril_ground"] = {tr(0, 0.5667, "alex_gethit_groundspike_to_idle", 1, 8, 25), tr(0.5667, 1.067, "alex_gethit_groundspike_to_idle", 1, 25, 36),
	tr(1.067, 1.333, "alex_gethit_groundspike_to_idle", 1, 36, 44), tr(1.333, 1.6, "alex_gethit_groundspike_to_idle", 1, 44, 48), tr(1.6, -1, "alex_gethit_groundspike_to_idle", 1, 48, -1)}
-
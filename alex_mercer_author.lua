-[[
	Alex Mercer — Prototype (2009) port for Garry's Mod (DrGBase nextbot).
	Port, code and conversion tools by electromorphosiiis (Steam).
	Original upload: Steam Workshop item 3824067898, 2026-10-21.
	Source history: private GitHub repository of dvxrtg-crypto (alex-mercer-gmod-port).
	Prototype's models, animations, sounds and effects belong to Radical Entertainment / Activision.
]]
AddCSLuaFile()

ALEX_MERCER_AUTHOR = "electromorphosiiis"
ALEX_MERCER_WORKSHOP = "3824067898"

-- one line in the console when the addon loads (nothing on screen)
MsgC(Color(200, 40, 40), "[Alex Mercer] ", Color(220, 220, 220),
	"Prototype port by " .. ALEX_MERCER_AUTHOR .. " - Steam Workshop " .. ALEX_MERCER_WORKSHOP .. "\n")
-
--!strict
-- Icons: the one owner of the UI's uploaded image ids. GLYPHS are the HUD's icon family (soft,
-- rounded white glyphs that take a button's colour through ImageColor3); TEXTURES are the soft
-- shapes the motion uses (a radial glow, a vignette, a ring, a shooting-star streak, a nebula
-- cloud and a spark). tools/hud/icons.py draws them into assets/icons, whose README lists each
-- file with its id; tools/hud/polish_hud.luau puts the glyphs on the authored HUD.
local Icons = {}

Icons.GLYPHS = {
	Shop = "rbxassetid://127767520251085",
	Coin = "rbxassetid://133837907702735",
	Flask = "rbxassetid://86195398839667",
	Menu = "rbxassetid://88868341984519",
	Quests = "rbxassetid://85555061479373",
	Hammer = "rbxassetid://81099156450387",
	Book = "rbxassetid://108461104617235",
	Medal = "rbxassetid://101592650420845",
	Chart = "rbxassetid://116465044425811",
	Gear = "rbxassetid://129767158874012",
	Info = "rbxassetid://114281201578067",
	Check = "rbxassetid://114442165606293",
	Cross = "rbxassetid://96146042420376",
	Sparkle = "rbxassetid://134493256912200",
	Level = "rbxassetid://82265484384417",
	Search = "rbxassetid://140388053023208",
}

Icons.TEXTURES = {
	Glow = "rbxassetid://72829196661123",
	Vignette = "rbxassetid://78344255927008",
	Ring = "rbxassetid://134383753463972",
	Streak = "rbxassetid://110304708655123",
	Nebula = "rbxassetid://84022196244617",
	Spark = "rbxassetid://91088343461209",
}

return Icons

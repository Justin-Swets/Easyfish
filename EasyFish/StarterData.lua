-- EasyFish starter guide data. Sources: wow-professions.com (Forever and Classic fishing guides), method.gg Forever
-- fishing guide, warcraft.wiki.gg, wowhead. NPC positions: Questie's Classic NPC database; a route step's position is the
-- fishing NPC at that water. level is the character level the zone is safe at.

local ADDON, NS = ...

NS.STARTER = {
  basics = {
    { title = "Learn Fishing", text = "Visit a Fishing trainer in your starting zone or capital to learn Apprentice (skill 1-75).", npc = nil },
    { faction = "Alliance", title = "Trainers", text = "Lee Brown (Goldshire), Arnold Leland (Stormwind), Paxton Ganter (Dun Morogh), Androl Oakhand (Teldrassil).", npc = "Lee Brown" },
    { faction = "Horde", title = "Trainers", text = "Lau'Tiki (Durotar), Lumak (Orgrimmar), Uthan Stillwater (Mulgore), Clyde Kellen (Tirisfal).", npc = "Lau'Tiki" },
    { title = "Buy a pole and lures", text = "Fishing Supply or Trade Supply vendors sell the Fishing Pole and Shiny Bauble (+25 skill lure).", npc = nil },
    { title = "Equip and cast", text = "Equip the pole, drag Fishing from the Professions window to a bar, cast at water, click the bobber on a splash.", npc = nil },
    { title = "What raises skill", text = "Each catch can raise skill. Fish escape if your skill is below the water's need; lures and poles help.", npc = nil },
    { title = "Journeyman at 50", text = "At skill 50 and level 10, any trainer teaches Journeyman (cap 150). Nightcrawlers (+50) need skill 50.", npc = nil },
    { title = "Expert and Artisan", text = "Expert: level 20, skill 125, book from Old Man Heming. Artisan: level 35, skill 225, Nat Pagle quest.", npc = "Old Man Heming" },
  },

  poleVendors = {
    { name = "Tharynn Bouden", zone = "Elwynn Forest", x = 41.82, y = 67.16, faction = "Alliance", note = "Goldshire" },
    { name = "Catherine Leland", zone = "Stormwind City", x = 45.77, y = 58.58, faction = "Alliance", note = "Stormwind City" },
    { name = "Gretta Ganter", zone = "Dun Morogh", x = 31.53, y = 44.65, faction = "Alliance", note = "Dun Morogh" },
    { name = "Tansy Puddlefizz", zone = "Ironforge", x = 48.18, y = 6.51, faction = "Alliance", note = "Ironforge" },
    { name = "Khara Deepwater", zone = "Loch Modan", x = 40.28, y = 39.28, faction = "Alliance", note = "Thelsamar" },
    { name = "Nessa Shadowsong", zone = "Teldrassil", x = 56.26, y = 92.44, faction = "Alliance", note = "Teldrassil" },
    { name = "Zansoa", zone = "Durotar", x = 56.06, y = 73.39, faction = "Horde", note = "Sen'jin Village" },
    { name = "Shankys", zone = "Orgrimmar", x = 69.99, y = 29.77, faction = "Horde", note = "Orgrimmar" },
    { name = "Harn Longcast", zone = "Mulgore", x = 47.51, y = 55.06, faction = "Horde", note = "Mulgore" },
    { name = "Sewa Mistrunner", zone = "Thunder Bluff", x = 55.79, y = 47.02, faction = "Horde", note = "Thunder Bluff" },
    { name = "Martine Tramblay", zone = "Tirisfal Glades", x = 65.86, y = 59.64, faction = "Horde", note = "Tirisfal Glades" },
    { name = "Lizbeth Cromwell", zone = "Undercity", x = 81.04, y = 30.75, faction = "Horde", note = "Undercity" },
  },

  route = {
    Alliance = {
      { from = 1, to = 75, zone = "Elwynn Forest", x = 47.61, y = 62.32, spot = "Crystal Lake, east of Goldshire", level = 1,
        why = "Safe starter water; Shiny Bauble stops escapes even at skill 1.", todo = "Learn Fishing from Lee Brown; buy pole and baubles in Goldshire" },
      { from = 75, to = 125, zone = "Stormwind City", x = 45.64, y = 58.43, spot = "City canals and pools", level = 10,
        why = "Capital water suits skill 75+. Learn Journeyman from any trainer.", todo = "Journeyman at skill 50 and level 10 (Arnold Leland)" },
      { from = 125, to = 225, zone = "Stranglethorn Vale", x = 27.4, y = 77.0, spot = "Booty Bay coast", level = 30,
        why = "Heming sells the Expert book and Bright Baubles; coast fishing needs both.", todo = "Buy Expert book at level 20, skill 125; buy Bright Baubles" },
      { from = 225, to = 250, zone = "Dustwallow Marsh", x = 58.6, y = 60.0, spot = "Tidefury Cove, Nat Pagle", level = 35,
        why = "Nat Pagle gives the Artisan quest; fish the marsh while you collect quest fish.", todo = "Quest Nat Pagle, Angler Extreme (level 35, skill 225)" },
      { from = 250, to = 300, zone = "Tanaris", x = 66.64, y = 22.08, spot = "Coastal waters", level = 40,
        why = "Listed 225-300 water; use Bright Baubles for the last ranks.", todo = "Turn in the Artisan quest for Artisan Fishing" },
    },
    Horde = {
      { from = 1, to = 75, zone = "Durotar", x = 53.2, y = 81.6, spot = "Coast by Sen'jin Village", level = 1,
        why = "Safe starter water; other races use Mulgore or Tirisfal Glades.", todo = "Learn Fishing from Lau'Tiki; buy pole and baubles from Zansoa" },
      { from = 75, to = 125, zone = "Orgrimmar", x = 69.8, y = 29.21, spot = "City pools", level = 10,
        why = "Capital water suits skill 75+. Learn Journeyman from any trainer.", todo = "Journeyman at skill 50 and level 10 (Lumak)" },
      { from = 125, to = 225, zone = "Stranglethorn Vale", x = 27.4, y = 77.0, spot = "Booty Bay coast", level = 30,
        why = "Heming sells the Expert book and Bright Baubles; coast fishing needs both.", todo = "Buy Expert book at level 20, skill 125; buy Bright Baubles" },
      { from = 225, to = 250, zone = "Dustwallow Marsh", x = 58.6, y = 60.0, spot = "Tidefury Cove, Nat Pagle", level = 35,
        why = "Nat Pagle gives the Artisan quest; fish the marsh while you collect quest fish.", todo = "Quest Nat Pagle, Angler Extreme (level 35, skill 225)" },
      { from = 250, to = 300, zone = "Tanaris", x = 66.64, y = 22.08, spot = "Coastal waters", level = 40,
        why = "Listed 225-300 water; use Bright Baubles for the last ranks.", todo = "Turn in the Artisan quest for Artisan Fishing" },
    },
  },
}

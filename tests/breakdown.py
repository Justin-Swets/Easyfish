"""Splits the status window's per-update cost into the functions it calls.  python tests/breakdown.py"""
from perf import load_addon, SEED

lua = load_addon()
lua.execute(SEED)
lua.execute("seed(25, 80, 8)")
parts = [
    ("whole status update", "statusTick"),
    ("NS.ZoneReport", "NS.ZoneReport"),
    ("NS.ChooseLure", "NS.ChooseLure"),
    ("NS.GetFishingSkill", "NS.GetFishingSkill"),
    ("NS.TrainerLine", "NS.TrainerLine"),
    ("NS.PoolLine", "NS.PoolLine"),
    ("NS.ChestsHere", "NS.ChestsHere"),
    ("NS.MatsHereLine", "NS.MatsHereLine"),
    ("NS.PriceOf (1 item)", "function() NS.PriceOf('Raw Test Fish 3') end"),
    ("NS.FormatMoney", "function() NS.FormatMoney(123456) end"),
    ("NS.LureTimeLeft", "NS.LureTimeLeft"),
    ("NS.PoleEquipped", "NS.PoleEquipped"),
]
print(f"{'part':<26}{'ms':>8}{'KB':>8}   (large history, per call)")
for label, fn in parts:
    ms, kb = lua.eval(f"measure({fn}, 300)")
    print(f"{label:<26}{ms:8.3f}{kb:8.2f}")
# how many times one status update calls the repeated helpers
lua.execute('''
calls = {}
for _, name in ipairs({ "ZoneReport", "ChooseLure", "GetFishingSkill", "LureTimeLeft", "PriceOf", "GetItemInfo" }) do
    local orig = NS[name]
    NS[name] = function(...) calls[name] = (calls[name] or 0) + 1 return orig(...) end
end
statusTick()
''')
print("\ncalls per status update:", dict(lua.eval("calls").items()))

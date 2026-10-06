#!/usr/bin/env python3
"""Builds progress/index.html: each piece's latest render next to its reference, plus the critic log."""
import base64, io, json, os, glob, re, html
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PIECES = [
 ("characters","Characters","refs/ref1_home_office_day.png"),
 ("hud","HUD","refs/ref1_home_office_day.png"),
 ("home","House & lighting","refs/ref1_home_office_day.png"),
 ("backyard","Backyard BBQ","refs/ref4_backyard_bbq_sunset.png"),
 ("festival","Autumn festival","refs/ref2_autumn_festival.png"),
 ("market","Grocery market","refs/ref5_grocery_market.png"),
 ("gameplay","Game loop","refs/ref1_home_office_day.png"),
]
def uri(path, w=760):
    im = Image.open(path).convert("RGB"); im.thumbnail((w, w))
    b = io.BytesIO(); im.save(b, "JPEG", quality=72)
    return "data:image/jpeg;base64," + base64.b64encode(b.getvalue()).decode()
rounds = []
p = os.path.join(ROOT, "progress/rounds.jsonl")
if os.path.exists(p):
    for line in open(p):
        try: rounds.append(json.loads(line))
        except Exception: pass
stamp = os.environ.get("STAMP", "")
cards = []
for key, name, ref in PIECES:
    shots = sorted(glob.glob(os.path.join(ROOT, f"progress/shots/{key}_r*.png")), key=lambda s: int(re.search(r"_r(\d+)", s).group(1)))
    rs = [r for r in rounds if r.get("piece") == key]
    last = rs[-1] if rs else None
    if last and last.get("preset") == "home_night": ref = "refs/ref3_home_night_cutaway.png"
    status = "waiting" if not shots and not rs else ("won" if last and last.get("winner") == "OURS" else ("lost" if last else "building"))
    label = {"waiting": "Queued", "building": "Building"}.get(status) or (f"Round {last['round']} · " + ("ours won" if status == "won" else "reference won"))
    ours = f'<img src="{uri(shots[-1])}" alt="Our latest render of {html.escape(name)}">' if shots else '<div class="empty">No render yet</div>'
    hist = "".join(f'<li><span class="r">R{r["round"]}</span><span class="w {"ok" if r["winner"]=="OURS" else "no"}">{"Ours" if r["winner"]=="OURS" else "Ref"}</span><span class="g">{html.escape(r["gap"])}</span></li>' for r in reversed(rs))
    cards.append(f'''<section class="piece" id="{key}"><header><h2>{html.escape(name)}</h2><span class="chip {status}">{label}</span></header>
<div class="pair"><figure><figcaption>Ours</figcaption>{ours}</figure><figure><figcaption>Reference</figcaption><img src="{uri(os.path.join(ROOT, ref))}" alt="Reference"></figure></div>
<details {"open" if rs else ""}><summary>Critic verdicts ({len(rs)})</summary><ol class="log">{hist or '<li class="none">No verdicts yet</li>'}</ol></details></section>''')
won = sum(1 for k,_,_ in PIECES if any(r.get("piece")==k and r.get("winner")=="OURS" for r in rounds))
page = open(os.path.join(ROOT, "tools/progress_template.html")).read()
page = page.replace("{{CARDS}}", "\n".join(cards)).replace("{{STAMP}}", html.escape(stamp)).replace("{{WON}}", str(won)).replace("{{TOTAL}}", str(len(PIECES))).replace("{{ROUNDS}}", str(len(rounds)))
os.makedirs(os.path.join(ROOT, "progress"), exist_ok=True)
open(os.path.join(ROOT, "progress/index.html"), "w").write(page)
print("wrote progress/index.html", len(page)//1024, "KB")

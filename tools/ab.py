#!/usr/bin/env python3
"""Blind A/B pairing for the critic.

  ab.py make <ours.png> <ref.png> <outdir> [--crop x0,y0,x1,y1]
      Writes <outdir>/A.png and <outdir>/B.png (same size, labels stripped) in
      an order the critic cannot know. The key is stored outside the repo.
  ab.py reveal <outdir> <A|B>
      Prints which image the critic picked: "OURS" or "REFERENCE".
      Only run this AFTER writing the verdict down.
"""
import hashlib, json, os, sys
from PIL import Image

KEYDIR = os.path.expanduser("~/.vims_ab_keys")

def key_path(outdir):
    return os.path.join(KEYDIR, hashlib.sha1(os.path.abspath(outdir).encode()).hexdigest() + ".json")

def make(ours, ref, outdir, crop=None):
    os.makedirs(outdir, exist_ok=True); os.makedirs(KEYDIR, exist_ok=True)
    a = Image.open(ours).convert("RGB"); b = Image.open(ref).convert("RGB")
    a = a.resize(b.size, Image.LANCZOS)
    if crop:
        box = tuple(int(v) for v in crop.split(","))
        a = a.crop(box); b = b.crop(box)
    flip = hashlib.sha1(open(ours, "rb").read()).digest()[0] & 1
    first, second = (a, b) if flip else (b, a)
    first.save(os.path.join(outdir, "A.png")); second.save(os.path.join(outdir, "B.png"))
    json.dump({"A": "OURS" if flip else "REFERENCE", "B": "REFERENCE" if flip else "OURS"}, open(key_path(outdir), "w"))
    print(f"wrote {outdir}/A.png and {outdir}/B.png")

def reveal(outdir, pick):
    print(json.load(open(key_path(outdir)))[pick.strip().upper()])

if __name__ == "__main__":
    if sys.argv[1] == "make":
        crop = sys.argv[sys.argv.index("--crop") + 1] if "--crop" in sys.argv else None
        make(sys.argv[2], sys.argv[3], sys.argv[4], crop)
    elif sys.argv[1] == "reveal":
        reveal(sys.argv[2], sys.argv[3])

import json, sys
src, font, out = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(src) as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except Exception:
    sys.exit(2)
if data.get("terminal.integrated.fontFamily"):
    sys.exit(3)
data["terminal.integrated.fontFamily"] = font
with open(out, "w") as f:
    json.dump(data, f, indent=4, ensure_ascii=False)
    f.write("\n")

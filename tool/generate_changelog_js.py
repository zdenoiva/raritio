import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
changelog = root / "CHANGELOG.md"
target = root / "assets" / "web_assets" / "changelog.js"

entries = []
for raw_line in changelog.read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    heading = re.match(r"^## \[([^\]]+)\]\s*-\s*(.+)$", line)
    if heading:
        entries.append(
            {
                "version": heading.group(1).strip(),
                "date": heading.group(2).strip(),
                "changes": [],
            }
        )
        continue
    if not entries or not line or line.startswith("#"):
        continue
    if line.startswith("- "):
        line = line[2:].strip()
    elif line.startswith("##"):
        continue
    line = line.replace("**", "").replace("`", "")
    if line:
        entries[-1]["changes"].append(line)

content = (
    "// Generated from CHANGELOG.md by tool/generate_changelog_js.py.\n"
    "window.RARITIO_CHANGELOG = "
    + json.dumps(entries, ensure_ascii=False, indent=2)
    + ";\n"
)
target.write_text(content, encoding="utf-8")
print(f"Wrote {target} ({len(entries)} versions)")

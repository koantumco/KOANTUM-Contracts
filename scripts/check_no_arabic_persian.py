from pathlib import Path
import re
import sys

ROOT = Path(".")
EXCLUDED_DIRS = {
    ".git",
    "lib",
    "out",
    "cache",
    "broadcast",
}

SCRIPT_PATTERN = re.compile(
    r"[\u0600-\u06FF"
    r"\u0750-\u077F"
    r"\u08A0-\u08FF"
    r"\uFB50-\uFDFF"
    r"\uFE70-\uFEFF]"
)

hits = []

for path in ROOT.rglob("*"):
    rel = path.relative_to(ROOT)

    if any(part in EXCLUDED_DIRS for part in rel.parts):
        continue

    if SCRIPT_PATTERN.search(str(rel)):
        hits.append(("PATH", str(rel), ""))

    if not path.is_file():
        continue

    try:
        content = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, PermissionError):
        continue

    for line_no, line in enumerate(content.splitlines(), 1):
        if SCRIPT_PATTERN.search(line):
            hits.append(("CONTENT", str(rel), f"{line_no}: {line}"))

if hits:
    print("Arabic or Persian script detected:")
    for kind, path, detail in hits:
        print(f"{kind}: {path}")
        if detail:
            print(f"  {detail}")
    sys.exit(1)

print("PASS: No Arabic or Persian script found in project-owned files.")

"""Localize package prose while retaining a single installation rule set."""
import json
from pathlib import Path
import sys


def localize(language, destination):
    root = Path(__file__).resolve().parents[2]
    if language not in ("US", "GR"):
        raise ValueError("language must be US or GR")
    source = (root / "installer/INSTALL.INI").read_text(encoding="ascii")
    translation = {}
    if language == "GR":
        translation = json.loads((root / "installer/lang/GR.json").read_text())
    lines = []
    section = ""
    option = 0
    for line in source.splitlines():
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            lines.append(line)
            if section == "Setup":
                lines.append("Texts=" + ("German" if language == "GR" else "English"))
            if section == "Welcome" and translation:
                lines.extend(translation["Welcome"])
            continue
        if section == "Setup" and line.startswith("Texts="):
            continue
        if section == "Setup" and translation and "=" in line:
            key = line.split("=", 1)[0]
            if key in ("Title", "Done"):
                line = key + "=" + translation[key]
        elif section == "Welcome" and translation:
            continue
        elif section == "Options" and line.startswith("Option="):
            if translation:
                fields = line.split("|")
                fields[1] = translation["Options"][option]
                line = "|".join(fields)
            option += 1
        lines.append(line)
    if translation and option != len(translation["Options"]):
        raise ValueError("option translations no longer match INSTALL.INI")
    (destination / "INSTALL.INI").write_bytes(("\r\n".join(lines) + "\r\n").encode("ascii"))
    readme = root / "installer" / ("README.GR.TXT" if language == "GR" else "README.TXT")
    (destination / "README.TXT").write_bytes((readme.read_text(encoding="ascii").replace("\r\n", "\n").replace("\n", "\r\n")).encode("ascii"))


if __name__ == "__main__":
    localize(sys.argv[1], Path(sys.argv[2]))

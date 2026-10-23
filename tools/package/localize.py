"""Localize package prose while retaining a single installation rule set."""
import json
from pathlib import Path
import sys


# Generate package text into an existing destination; this does not build
# the installer or copy driver payload. INSTALL.INI remains the single rule
# source, with translation affecting visible prose and the selected text family.
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
    # Track sections explicitly: identical key names can have different meaning
    # in setup, welcome text and option rules. Preserve unhandled lines verbatim.
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
        # Option labels are positional in GR.json. Change only field 1, leaving
        # conditions, commands and payload paths from the original installation rules.
        elif section == "Options" and line.startswith("Option="):
            if translation:
                fields = line.split("|")
                fields[1] = translation["Options"][option]
                line = "|".join(fields)
            option += 1
        lines.append(line)
    # Reject drift in the number of translated options before writing output;
    # adding an installer option requires an accompanying translation entry.
    if translation and option != len(translation["Options"]):
        raise ValueError("option translations no longer match INSTALL.INI")
    # Output is ASCII with DOS CRLF. This writes two ordinary files sequentially,
    # not an atomic package transaction; a failed run must not be published as a
    # complete language set. Caller owns the destination directory and payload.
    (destination / "INSTALL.INI").write_bytes(("\r\n".join(lines) + "\r\n").encode("ascii"))
    readme = root / "installer" / ("README.GR.TXT" if language == "GR" else "README.TXT")
    (destination / "README.TXT").write_bytes((readme.read_text(encoding="ascii").replace("\r\n", "\n").replace("\n", "\r\n")).encode("ascii"))


if __name__ == "__main__":
    localize(sys.argv[1], Path(sys.argv[2]))

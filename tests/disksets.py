"""Verify actual FAT12 media bytes, package localization and shared rules."""
from pathlib import Path
import subprocess
import sys


def verify(language, package, image):
    root = Path(__file__).resolve().parents[1]
    expected_language = {"US": "English", "GR": "German"}[language]
    ini = (package / "INSTALL.INI").read_text(encoding="ascii")
    assert "Texts=" + expected_language in ini
    assert (package / "ASPIMGR.EXE").read_bytes() == (root / "build" / language / "dos/ASPIMGR.EXE").read_bytes()
    assert (package / "ASPIDDG.EXE").read_bytes() == (root / "build" / language / "dos/ASPIDDG.EXE").read_bytes()
    # Language changes must preserve all machine-facing sections and option IDs.
    def rules(text):
        result = []
        section = ""
        for line in text.splitlines():
            if line.startswith("["):
                section = line
            if not line.strip() or line.startswith(";"):
                continue
            if section == "[Welcome]":
                continue
            if section == "[Setup]" and line.split("=", 1)[0] in ("Texts", "Title", "Done"):
                continue
            if section == "[Options]" and line.startswith("Option="):
                fields = line.split("|")
                fields[1] = ""
                line = "|".join(fields)
            result.append(line)
        return result
    assert rules(ini) == rules((root / "installer/INSTALL.INI").read_text())
    assert image.stat().st_size == 1474560
    names = subprocess.check_output(["mdir", "-b", "-i", str(image), "::/"], text=True).splitlines()
    assert {Path(name).name.upper() for name in names} == {p.name for p in package.iterdir()}
    for source in package.iterdir():
        actual = subprocess.check_output(["mtype", "-i", str(image), "::/" + source.name])
        assert actual == source.read_bytes(), source.name
        assert len(source.stem) <= 8 and len(source.suffix) <= 4, source.name
    for name in ("INSTALL.INI", "README.TXT"):
        content = (package / name).read_bytes()
        assert b"\n" not in content.replace(b"\r\n", b""), name
    print(f"{language}: localized package, shared installation rules and FAT12 disk contents passed")


if __name__ == "__main__":
    verify(sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3]))

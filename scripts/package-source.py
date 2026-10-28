#!/usr/bin/env python3
"""Package public project files; exclude Git metadata, builds, and device data."""
from pathlib import Path
import plistlib
import zipfile

root = Path(__file__).resolve().parent.parent
with (root / "Resources/Info.plist").open("rb") as stream:
    version = plistlib.load(stream)["CFBundleShortVersionString"]
directories = ("Sources", "Tests", "Resources", "docs", "examples", "scripts", ".github")
files = [path for directory in directories for path in (root / directory).rglob("*") if path.is_file()]
files += [root / name for name in ("Package.swift", "README.md", "LICENSE", "CONTRIBUTING.md",
                                   "SECURITY.md", "CHANGELOG.md", ".gitignore", ".swift-format")]
output = root / "build" / f"AULA-Control-{version}-source.zip"
output.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(files):
        private_directories = {"__pycache__", ".aula-local", ".build", "build", ".git", ".swiftpm", "xcuserdata"}
        private_file = (path.name in {".DS_Store", "presets.json"}
                        or (path.name.startswith("keyboard-") and path.suffix == ".json")
                        or path.suffix in {".log", ".trace", ".pyc", ".xcuserstate"})
        if path.is_symlink() or private_file or private_directories.intersection(path.relative_to(root).parts):
            continue
        # Explicit metadata omits local account names and UID/GID data.
        entry = zipfile.ZipInfo(f"aula-control-{version}/{path.relative_to(root).as_posix()}")
        entry.external_attr = (0o100755 if path.stat().st_mode & 0o111 else 0o100644) << 16
        entry.compress_type = zipfile.ZIP_DEFLATED
        archive.writestr(entry, path.read_bytes())
print(f"Packaged {output.relative_to(root)}")

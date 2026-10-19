"""Rebuild manifest.json (what DevSync reads) from DesignDoc.lua and src/.

Each entry maps a file to the script it becomes in Studio:
  src/client/...        -> StarterPlayer.StarterPlayerScripts...
  src/server/Tools/...  -> ServerStorage.Tools...
  src/server/...        -> ServerScriptService...
  src/shared/...        -> ReplicatedStorage.Shared...
  DesignDoc.lua         -> ServerStorage.DesignDoc
  *.server.lua = Script, *.client.lua = LocalScript, *.lua = ModuleScript
sha is the SHA-1 of the file bytes; DevSync skips scripts whose SyncSha already matches.

Usage (from the project folder):  python tools/manifest.py
"""
import hashlib
import json
import os
from pathlib import Path

ROOTS = [
    ("src/client", "StarterPlayer.StarterPlayerScripts"),
    ("src/server/Tools", "ServerStorage.Tools"),
    ("src/server", "ServerScriptService"),
    ("src/shared", "ReplicatedStorage.Shared"),
]


def entry(rel, parent):
    path = Path(rel)
    stem = path.name
    for suffix, cls in ((".server.lua", "Script"), (".client.lua", "LocalScript"), (".lua", "ModuleScript")):
        if stem.endswith(suffix):
            return {
                "file": rel,
                "parent": parent,
                "name": stem[: -len(suffix)],
                "class": cls,
                "sha": hashlib.sha1(path.read_bytes()).hexdigest(),
            }
    return None


def main():
    os.chdir(Path(__file__).resolve().parent.parent)
    files = ["DesignDoc.lua"] + sorted(p.as_posix() for p in Path("src").rglob("*.lua"))
    manifest = []
    for rel in sorted(files):
        if rel == "DesignDoc.lua":
            manifest.append(entry(rel, "ServerStorage"))
            continue
        root, service = next(r for r in ROOTS if rel.startswith(r[0] + "/"))
        folders = Path(rel).parent.as_posix()[len(root):].strip("/")
        manifest.append(entry(rel, service + ("." + folders.replace("/", ".") if folders else "")))
    with open("manifest.json", "w") as f:
        json.dump(manifest, f, indent=1)
    print(f"manifest.json: {len(manifest)} scripts")


if __name__ == "__main__":
    main()

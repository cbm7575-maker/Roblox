"""Extract every script from a binary place file (NeonCoast.rbxl) into the project folder.

The reverse of DevSync: Studio -> files. Writes each script to the path manifest.json
uses for it (see ROOTS below), byte for byte, so its SHA-1 matches the SyncSha DevSync
stamped on it. Scripts outside the known roots are listed and skipped.

Usage:  pip install lz4 zstandard
        python tools/extract_rbxl.py NeonCoast.rbxl [project_folder]
"""
import os
import struct
import sys

import lz4.block
import zstandard

SCRIPT_CLASSES = ("Script", "LocalScript", "ModuleScript")

# Instance path prefix -> folder. Mirrors tools/manifest.py.
ROOTS = [
    ("ServerStorage.Tools.DevSync", None),  # bootstrap helper, kept as tools/DevSync.lua by hand
    ("StarterPlayer.StarterPlayerScripts", "src/client"),
    ("ServerScriptService", "src/server"),
    ("ServerStorage.Tools", "src/server/Tools"),
    ("ReplicatedStorage.Shared", "src/shared"),
    ("ServerStorage.DesignDoc", ""),
]
SUFFIX = {"Script": ".server.lua", "LocalScript": ".client.lua", "ModuleScript": ".lua"}


def _refs(buf, n):
    # Interleaved big-endian int32 array, zigzag encoded, delta accumulated.
    out, acc = [], 0
    for i in range(n):
        v = (buf[i] << 24) | (buf[n + i] << 16) | (buf[2 * n + i] << 8) | buf[3 * n + i]
        acc += (v >> 1) ^ -(v & 1)
        out.append(acc)
    return out


def _chunks(data):
    pos = 32
    while pos < len(data):
        name = data[pos:pos + 4]
        clen, ulen = struct.unpack_from("<II", data, pos + 4)
        pos += 16
        if clen == 0:
            body = data[pos:pos + ulen]
            pos += ulen
        else:
            raw = data[pos:pos + clen]
            pos += clen
            if raw[:4] == b"\x28\xb5\x2f\xfd":
                body = zstandard.ZstdDecompressor().decompress(raw, max_output_size=ulen)
            else:
                body = lz4.block.decompress(raw, uncompressed_size=ulen)
        if name == b"END\x00":
            return
        yield name, body


def read_place(path, wanted=("Name", "Source")):
    """Returns (class_of, props, parent): ref -> ClassName, ref -> {prop: bytes}, ref -> parent ref.
    Only string-typed properties named in `wanted` are read (Name must be one of them)."""
    data = open(path, "rb").read()
    if data[:8] != b"<roblox!":
        sys.exit(f"{path} is not a binary place file (.rbxlx XML files are not supported)")
    classes, class_of, props, parent = {}, {}, {}, {}
    for name, body in _chunks(data):
        if name == b"INST":
            cid, ln = struct.unpack_from("<Ii", body, 0)
            cname = body[8:8 + ln].decode()
            p = 8 + ln + 1
            count = struct.unpack_from("<I", body, p)[0]
            refs = _refs(body[p + 4:p + 4 + 4 * count], count)
            classes[cid] = refs
            for r in refs:
                class_of[r] = cname
        elif name == b"PROP":
            cid, ln = struct.unpack_from("<Ii", body, 0)
            pname = body[8:8 + ln].decode()
            p = 8 + ln
            if body[p] != 0x01 or pname not in wanted:
                continue
            p += 1
            for r in classes[cid]:
                ln = struct.unpack_from("<I", body, p)[0]
                props.setdefault(r, {})[pname] = body[p + 4:p + 4 + ln]
                p += 4 + ln
        elif name == b"PRNT":
            count = struct.unpack_from("<I", body, 1)[0]
            kids = _refs(body[5:5 + 4 * count], count)
            pars = _refs(body[5 + 4 * count:5 + 8 * count], count)
            parent.update(zip(kids, pars))
    return class_of, props, parent


def full_name(ref, props, parent):
    parts = []
    while ref is not None and ref != -1:
        parts.append(props.get(ref, {}).get("Name", b"?").decode("utf-8", "replace"))
        ref = parent.get(ref)
    return ".".join(reversed(parts))


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    place, out = sys.argv[1], (sys.argv[2] if len(sys.argv) > 2 else ".")
    class_of, props, parent = read_place(place)
    written, skipped = 0, []
    for ref, cls in class_of.items():
        if cls not in SCRIPT_CLASSES:
            continue
        name = full_name(ref, props, parent)
        root = next((r for r in ROOTS if name == r[0] or name.startswith(r[0] + ".")), None)
        if root is None or root[1] is None:
            skipped.append(name)
            continue
        rel = name[len(root[0]):].lstrip(".").split(".") if name != root[0] else [name.split(".")[-1]]
        dest = os.path.join(out, root[1], *rel[:-1], rel[-1] + SUFFIX[cls])
        os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
        with open(dest, "wb") as f:
            f.write(props[ref].get("Source", b""))
        written += 1
    print(f"Wrote {written} scripts to {os.path.abspath(out)}")
    for name in sorted(skipped):
        print("  skipped", name)


if __name__ == "__main__":
    main()

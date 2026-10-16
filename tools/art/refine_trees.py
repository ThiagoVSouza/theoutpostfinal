"""Rebuild the visual-pass trees from the original committed GLBs (Python 3 stdlib).

    python tools/art/refine_trees.py

The source revision is deliberately pinned: running this twice must not keep shrinking
the cards. Index buffers and triangle counts are preserved. The stone pine receives
a new branch-spray atlas and matching UVs; other embedded textures/UVs stay unchanged.
The runtime adds a two-triangle ground patch, included in the 200-triangle ceiling.
"""
import argparse
import json
import math
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[2]
SOURCE = "2f193f8"
SPECIES = {
    # foliage tint (linear glTF factor), bark tint, card scale, crown lift
    "oak": ((.44, .63, .60), (.76, .71, .62), .84, .34),
    "maple": ((.86, .94, .86), (.76, .71, .62), .88, .20),
    "birch": ((.76, .84, .76), (.70, .72, .69), .93, .05),
    "pine": ((.78, .90, .78), (.72, .77, .69), 1.03, .0),
    "stone-pine": ((.73, .82, .66), (.55, .67, .64), .90, .0),
    "spruce": ((.45, .55, .40), (.78, .81, .75), .86, .12),
    "cypress": ((.54, .64, .49), (.79, .82, .76), .95, .0),
    "white-willow": ((.75, .84, .70), (.77, .73, .65), .88, .0),
}


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def mul(a, s):
    return tuple(x * s for x in a)


def unit(v):
    length = math.sqrt(sum(x * x for x in v))
    return mul(v, 1.0 / max(length, 1e-9))


def mean(vectors):
    return tuple(sum(p[k] for p in vectors) / len(vectors) for k in range(3))


def clamp(x, low=0.0, high=1.0):
    return max(low, min(high, x))


class GLB:
    def __init__(self, data):
        magic, version, size = struct.unpack_from("<III", data)
        assert (magic, version, size) == (0x46546C67, 2, len(data))
        length, kind = struct.unpack_from("<II", data, 12)
        assert kind == 0x4E4F534A
        self.doc = json.loads(data[20:20 + length])
        length2, kind2 = struct.unpack_from("<II", data, 20 + length)
        assert kind2 == 0x004E4942
        self.binary = bytearray(data[28 + length:28 + length + length2])

    def values(self, index):
        a = self.doc["accessors"][index]
        view = self.doc["bufferViews"][a["bufferView"]]
        fmt = {5126: "f", 5123: "H", 5125: "I", 5121: "B"}[a["componentType"]]
        count = {"VEC2": 2, "VEC3": 3, "VEC4": 4, "SCALAR": 1}[a["type"]]
        stride = view.get("byteStride", struct.calcsize(fmt) * count)
        start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
        return [struct.unpack_from("<" + fmt * count, self.binary, start + i * stride)
                for i in range(a["count"])]

    def write_values(self, index, values):
        a = self.doc["accessors"][index]
        view = self.doc["bufferViews"][a["bufferView"]]
        assert a["componentType"] == 5126
        count = len(values[0])
        stride = view.get("byteStride", 4 * count)
        start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
        assert len(values) == a["count"]
        for i, v in enumerate(values):
            assert all(math.isfinite(x) for x in v)
            struct.pack_into("<" + "f" * count, self.binary, start + i * stride, *v)
        if "min" in a:
            a["min"] = [min(v[k] for v in values) for k in range(count)]
            a["max"] = [max(v[k] for v in values) for k in range(count)]

    def add_colors(self, colors):
        self.binary.extend(b"\0" * (-len(self.binary) % 4))
        offset = len(self.binary)
        for c in colors:
            self.binary.extend(struct.pack("<ffff", *c))
        view = len(self.doc["bufferViews"])
        self.doc["bufferViews"].append({"buffer": 0, "byteOffset": offset,
                                       "byteLength": len(colors) * 16, "target": 34962})
        index = len(self.doc["accessors"])
        self.doc["accessors"].append({"bufferView": view, "componentType": 5126,
                                      "count": len(colors), "type": "VEC4"})
        return index

    def replace_image(self, index, data, name):
        """Replace a packed image without retaining the unused original atlas bytes."""
        image = self.doc["images"][index]
        view = self.doc["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset", 0)
        end = start + (view["byteLength"] + 3) // 4 * 4
        padded = data + b"\0" * (-len(data) % 4)
        for other in self.doc["bufferViews"]:
            if other is view:
                continue
            offset = other.get("byteOffset", 0)
            assert offset >= end or offset + other["byteLength"] <= start
            if offset >= end:
                other["byteOffset"] = offset + len(padded) - (end - start)
        self.binary[start:end] = padded
        view["byteLength"] = len(data)
        image["name"] = name

    def save(self, path):
        self.doc["buffers"][0]["byteLength"] = len(self.binary)
        document = json.dumps(self.doc, separators=(",", ":")).encode()
        document += b" " * (-len(document) % 4)
        self.binary.extend(b"\0" * (-len(self.binary) % 4))
        total = 12 + 8 + len(document) + 8 + len(self.binary)
        path.write_bytes(struct.pack("<III", 0x46546C67, 2, total)
                         + struct.pack("<II", len(document), 0x4E4F534A) + document
                         + struct.pack("<II", len(self.binary), 0x004E4942) + self.binary)


def foliage(name, positions, normals, scale, lift):
    """Keep each three-card bough together, giving it a smaller uneven envelope.

    The pine uses unindexed triangle pairs; its six vertices form one card. All
    others use four-vertex quads and three differently facing cards per bough.
    """
    block = 6 if name == "pine" else 12
    assert len(positions) % block == 0
    low = min(p[1] for p in positions)
    high = max(p[1] for p in positions)
    radius = max(math.hypot(p[0], p[2]) for p in positions)
    centre_y = (high + low) * .5
    result, result_n, colors = [], [], []
    for group, start in enumerate(range(0, len(positions), block)):
        points = positions[start:start + block]
        c = mean(points)
        theta = math.atan2(c[2], c[0])
        variation = math.sin(group * 2.39996 + .8)
        size = scale * (1.0 + .09 * variation)
        if name == "stone-pine":
            # Airy sprays need a connected core; keep the outer fringe much lighter.
            interior = clamp(1.0 - math.hypot(c[0], c[2]) / 3.2)
            size *= 1.06 + .24 * interior
        lobing = 1.0 + .085 * math.sin(3 * theta + .6) + .045 * math.cos(5 * theta)
        target = (c[0] * lobing, c[1] + lift + .17 * variation, c[2] * lobing)
        if name == "stone-pine":
            target = (target[0] * 1.07, 6.65 + (c[1] - 6.65) * .86, target[2] * 1.07)
        elif name == "spruce":
            # Gather the boughs into staggered tiers; preserve an irregular skirt.
            tier = round((c[1] - .6) / 1.22) * 1.22 + .6
            target = (target[0], .65 * c[1] + .35 * tier + lift, target[2])
        elif name == "cypress":
            target = (c[0] + .17 * (c[1] / high) ** 2, c[1], c[2])
        elif name == "white-willow":
            target = (target[0] * 1.02, target[1] - .26 * math.hypot(c[0], c[2]) / radius,
                      target[2] * 1.02)
        elif name == "pine":
            target = c
        for local_index, p in enumerate(points):
            rel = sub(p, c)
            sy = size * (.80 if name == "spruce" else .94 if name == "stone-pine" else 1.0)
            p2 = add(target, (rel[0] * size, rel[1] * sy, rel[2] * size))
            if name == "white-willow":
                p2 = (p2[0], p2[1] - .14 * math.hypot(rel[0], rel[2]), p2[2])
            result.append(p2)
            local = unit(add(sub(p2, target), (0, .18, 0)))
            envelope = unit((p2[0] / radius, (p2[1] - centre_y) / max(high - low, 1) * 1.6,
                             p2[2] / radius))
            # The stone pine should read as one broad umbrella, not individually inflated pads.
            local_weight = .25 if name == "stone-pine" else .65
            n = unit(add(add(mul(local, local_weight), mul(envelope, 1 - local_weight)), (0, .22, 0)))
            # Keep a soft underside without the uniformly upward-facing original normals.
            n = unit((n[0], max(n[1], -.18), n[2]))
            result_n.append(n)
            height = clamp((p2[1] - low) / (high - low))
            outer = clamp(math.hypot(p2[0], p2[2]) / radius)
            shade = clamp((.78 + .15 * height + .07 * outer) * (1 + .045 * variation), .70, 1)
            colors.append((shade, shade, shade * (.98 + .02 * height), 1.0))
    return result, result_n, colors


def stone_pine_uvs(count):
    """Give the three plates in each bough complementary sprays from the 2x2 atlas."""
    assert count % 4 == 0
    result = []
    for card in range(count // 4):
        group, plate = divmod(card, 3)
        cell = (group * 3 + plate) % 4
        x, y = cell % 2, cell // 2
        corners = [(0, 1), (1, 1), (1, 0), (0, 0)]
        # Flip whole sprays to break repetition while preserving the transparent cell margin.
        for u, v in corners:
            if group % 2:
                u = 1 - u
            # This primary plate's local V points inward; its painted stem belongs there.
            if plate == 0:
                v = 1 - v
            result.append(((x + u) * .5, (y + v) * .5))
    return result


def rebuild(name, source):
    relative = f"assets/trees/{name}.glb"
    raw = subprocess.run(["git", "show", f"{source}:{relative}"], cwd=ROOT,
                         check=True, capture_output=True).stdout
    glb = GLB(raw)
    if name == "stone-pine":
        atlas = ROOT / "assets/trees/textures/stone-pine-boughs.png"
        glb.replace_image(1, atlas.read_bytes(), "stone-pine-branch-sprays")
    tint, bark, scale, lift = SPECIES[name]
    triangles = 0
    for mesh in glb.doc["meshes"]:
        for primitive in mesh["primitives"]:
            assert primitive.get("mode", 4) == 4
            attrs = primitive["attributes"]
            positions = glb.values(attrs["POSITION"])
            normals = glb.values(attrs["NORMAL"])
            triangles += len(glb.values(primitive["indices"])) // 3
            material = glb.doc["materials"][primitive["material"]]
            if material.get("alphaMode") == "MASK":
                positions, normals, colors = foliage(name, positions, normals, scale, lift)
                if name == "stone-pine":
                    glb.write_values(attrs["TEXCOORD_0"], stone_pine_uvs(len(positions)))
                attrs["COLOR_0"] = glb.add_colors(colors)
                material.setdefault("extras", {})["outpostFoliageNormalMode"] = "volume"
                material["extras"]["outpostVisualPass"] = 1
                material["pbrMetallicRoughness"]["baseColorFactor"] = [*tint, 1.0]
            else:
                # Keep the authored trunk geometry; the ground texture supplies the transition.
                material["pbrMetallicRoughness"]["baseColorFactor"] = [*bark, 1.0]
            glb.write_values(attrs["POSITION"], positions)
            glb.write_values(attrs["NORMAL"], normals)
    assert triangles + 2 <= 200, (name, triangles)
    glb.doc.setdefault("extras", {})["outpostVisualPass"] = {
        "source": source, "meshTriangles": triangles, "withGroundPatch": triangles + 2,
        "generator": "tools/art/refine_trees.py"}
    glb.save(ROOT / relative)
    return {"species": name, "meshTriangles": triangles, "withGroundPatch": triangles + 2}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-ref", default=SOURCE)
    parser.add_argument("--species", nargs="+", choices=list(SPECIES), default=list(SPECIES))
    args = parser.parse_args()
    report = [rebuild(name, args.source_ref) for name in args.species]
    print(json.dumps(report, indent=2))

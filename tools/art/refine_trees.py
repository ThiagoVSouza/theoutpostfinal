"""Rebuild the visual-pass trees from the original committed GLBs (Python 3 stdlib).

    python tools/art/refine_trees.py

The source revision is deliberately pinned: running this twice must not keep shrinking
the cards. Embedded textures, UVs and index buffers are preserved byte-for-byte. Only
positions, foliage volume normals, vertex occlusion and material tints are changed.
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


def undergrowth(name, positions, normals, colors):
    """Move two obscured canopy cards to low vegetation beside the root flare.

    This spends existing geometry on grounding instead of adding triangles or a
    fourth material. Only one card is taken from a bough, keeping its other views.
    """
    vertices = 6 if name == "pine" else 4
    cards = len(positions) // vertices
    centres = [mean(positions[i * vertices:(i + 1) * vertices]) for i in range(cards)]
    # Prefer cards near the trunk, where other boughs cover them. Avoid the leader.
    candidates = sorted(range(cards), key=lambda i:
                        centres[i][0] ** 2 + centres[i][2] ** 2 + .13 * centres[i][1] ** 2)
    chosen = []
    for i in candidates:
        if name == "pine" or all(i // 3 != j // 3 for j in chosen):
            chosen.append(i)
        if len(chosen) == 2:
            break
    corners = [(0, 0), (1, 0), (1, 1), (0, 1)]
    order = [0, 1, 2, 0, 2, 3] if vertices == 6 else [0, 1, 2, 3]
    for patch, card in enumerate(chosen):
        cx, cz, yaw = ((.52, .38, -.6), (-.46, .17, 1.25))[patch]
        width = 1.4 if patch == 0 else 1.15
        height = .32 if patch == 0 else .25
        depth = .85 if patch == 0 else .72
        if name in ("birch", "cypress"):
            width *= .8
            height *= .9
            cx *= .8
            cz *= .8
        right = (math.cos(yaw), 0, math.sin(yaw))
        outward = (-math.sin(yaw), 0, math.cos(yaw))
        for vertex, corner in enumerate(order):
            u, v = corners[corner]
            p = add((cx, .015 + height * v, cz),
                    add(mul(right, (u - .5) * width), mul(outward, (v - .25) * depth)))
            index = card * vertices + vertex
            positions[index] = p
            normals[index] = unit((p[0] - cx, .45, p[2] - cz))
            shade = .64 + .22 * v
            colors[index] = (shade * .88, shade, shade * .80, 1.0)


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
        lobing = 1.0 + .085 * math.sin(3 * theta + .6) + .045 * math.cos(5 * theta)
        target = (c[0] * lobing, c[1] + lift + .17 * variation, c[2] * lobing)
        if name == "stone-pine":
            target = (target[0] * 1.07, 6.65 + (c[1] - 6.65) * .72, target[2] * 1.07)
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
            sy = size * (.80 if name == "spruce" else .84 if name == "stone-pine" else 1.0)
            p2 = add(target, (rel[0] * size, rel[1] * sy, rel[2] * size))
            if name == "white-willow":
                p2 = (p2[0], p2[1] - .14 * math.hypot(rel[0], rel[2]), p2[2])
            result.append(p2)
            local = unit(add(sub(p2, target), (0, .18, 0)))
            envelope = unit((p2[0] / radius, (p2[1] - centre_y) / max(high - low, 1) * 1.6,
                             p2[2] / radius))
            n = unit(add(add(mul(local, .65), mul(envelope, .35)), (0, .22, 0)))
            # Keep a soft underside without the uniformly upward-facing original normals.
            n = unit((n[0], max(n[1], -.18), n[2]))
            result_n.append(n)
            height = clamp((p2[1] - low) / (high - low))
            outer = clamp(math.hypot(p2[0], p2[2]) / radius)
            shade = clamp((.78 + .15 * height + .07 * outer) * (1 + .045 * variation), .70, 1)
            colors.append((shade, shade, shade * (.98 + .02 * height), 1.0))
    undergrowth(name, result, result_n, colors)
    return result, result_n, colors


def wood(name, positions, normals):
    """Extend the existing lowest ring into uneven buttresses without adding faces."""
    result, result_n = [], []
    for p, normal in zip(positions, normals):
        x, y, z = p
        influence = clamp((.8 - y) / .8) ** 2
        angle = math.atan2(z, x)
        flare = 1 + influence * (.38 + .16 * math.sin(angle * 3 + .7))
        # The bottom ring stays just below the ground; the sloped face remains visible.
        if y < 0:
            y = -.035 + (y + .12) * .1
        p2 = (x * flare, y, z * flare)
        result.append(p2)
        result_n.append(unit((normal[0], normal[1] + influence * .22, normal[2])))
    return result, result_n


def rebuild(name, source):
    relative = f"assets/trees/{name}.glb"
    raw = subprocess.run(["git", "show", f"{source}:{relative}"], cwd=ROOT,
                         check=True, capture_output=True).stdout
    glb = GLB(raw)
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
                attrs["COLOR_0"] = glb.add_colors(colors)
                material.setdefault("extras", {})["outpostFoliageNormalMode"] = "volume"
                material["extras"]["outpostVisualPass"] = 1
                material["pbrMetallicRoughness"]["baseColorFactor"] = [*tint, 1.0]
            else:
                positions, normals = wood(name, positions, normals)
                # Dark, warm bark at ground contact joins the flare to the litter patch.
                # glTF vertex colour also works in the ordinary imported wood material.
                contact = [clamp((.85 - p[1]) / .85) for p in positions]
                attrs["COLOR_0"] = glb.add_colors([
                    (1 - .24 * w, 1 - .29 * w, 1 - .36 * w, 1.0) for w in contact])
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
    args = parser.parse_args()
    report = [rebuild(name, args.source_ref) for name in SPECIES]
    print(json.dumps(report, indent=2))

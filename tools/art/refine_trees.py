"""Rebuild the visual-pass trees from the original committed GLBs (Python 3 stdlib).

    python tools/art/refine_trees.py

The source revision is deliberately pinned: running this twice must not keep shrinking
the cards. Index buffers and triangle counts are preserved. Oak, maple, birch, stone
pine and white willow use branch-spray atlases; pine restores its v1 needle texture.
Other embedded textures and all remaining UVs stay unchanged.
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
    "oak": ((.56, .70, .70), (.76, .71, .62), .84, .34),
    "maple": ((.86, .94, .86), (.76, .71, .62), .88, .20),
    "birch": ((.76, .84, .76), (.70, .72, .69), .93, .05),
    "pine": ((.78, .90, .78), (.72, .77, .69), 1.06, .0),
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


def willow_drooping_cards(points):
    """Turn the two side sprays down around their own horizontal card centers."""
    result = list(points[:4])  # The primary spray already points down with its V flip.
    for start in (4, 8):
        card = points[start:start + 4]
        centre_y = mean(card)[1]
        result.extend((x, 2.0 * centre_y - y, z) for x, y, z in card)
    return result


def birch_rising_cards(points):
    """Keep the birch's delicate sprays rising away from its narrow crown."""
    centre = mean(points)
    radial = unit((centre[0], 0.0, centre[2]))
    result = []
    for start in (0, 4, 8):
        card = points[start:start + 4]
        v = sub(mean(card[2:]), mean(card[:2]))
        outward_sign = 1.0 if sum(a * b for a, b in zip(v, radial)) >= 0 else -1.0
        if v[1] * outward_sign < 0:
            centre_y = mean(card)[1]
            card = [(x, 2.0 * centre_y - y, z) for x, y, z in card]
        result.extend(card)
    return result


def oak_inner_overlap(points):
    """Reach inward from each bough's fixed outer edge to connect the middle crown."""
    centre = mean(points)
    radius = math.hypot(centre[0], centre[2])
    radial = unit((centre[0], 0.0, centre[2]))
    weight = clamp((3.4 - radius) / 1.1) * clamp((6.15 - centre[1]) / .9)
    projections = [sum(a * b for a, b in zip(sub(p, centre), radial)) for p in points]
    outer = max(projections)
    return [add(p, mul(radial, .40 * weight * (d - outer)))
            for p, d in zip(points, projections)]


def pine_bough_groups(positions):
    """Join the pine's paired folded strips before transforming whole boughs."""
    assert len(positions) % 6 == 0
    parent = list(range(len(positions) // 6))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    owner = {}
    for i, p in enumerate(positions):
        block = i // 6
        other = owner.setdefault(p, block)
        parent[find(block)] = find(other)
    groups = {}
    for i in range(len(positions)):
        groups.setdefault(find(i // 6), []).append(i)
    return list(groups.values())


def pine_foliage(positions, normals, uvs, scale):
    """Fill the lower crown while pinning every branch root and shared fold join."""
    groups = pine_bough_groups(positions)
    assert len(groups) == 58 and sum(len(g) == 12 for g in groups) == 26
    roots = [mean([positions[i] for i in g if uvs[i][0] == 0.0]) for g in groups]
    low_root, high_root = min(r[1] for r in roots), max(r[1] for r in roots)
    low, high = min(p[1] for p in positions), max(p[1] for p in positions)
    radius = max(math.hypot(p[0], p[2]) for p in positions)
    result, result_n = list(positions), list(normals)
    colors = [(1.0, 1.0, 1.0, 1.0)] * len(positions)
    for number, (group, root) in enumerate(zip(groups, roots)):
        anchors = {}
        for i in group:
            assert uvs[i][0] in (0.0, 1.0)
            if uvs[i][0] == 0.0:
                v = uvs[i][1]
                assert v not in anchors or anchors[v] == positions[i]
                anchors[v] = positions[i]
        height = (root[1] - low_root) / (high_root - low_root)
        weight = clamp((.88 - height) / .65)
        for i in group:
            if uvs[i][0] == 0.0 or weight == 0.0:
                continue
            anchor = anchors[uvs[i][1]]
            # Grow the outside of the bough; its root edge and the apex stay fixed.
            result[i] = add(add(root, mul(sub(anchor, root), 1.0 + .15 * weight)),
                            mul(sub(positions[i], anchor), 1.0 + (scale - 1.0) * weight))
        centre = mean([result[i] for i in group])
        variation = math.sin(number * 2.39996 + .8)
        for i in group:
            p = result[i]
            base = normals[i] if normals[i][1] >= 0.0 else mul(normals[i], -1.0)
            envelope = unit((p[0] / radius, (p[1] - (high + low) * .5) / (high - low) * 1.6,
                             p[2] / radius))
            local = unit(add(sub(p, centre), (0.0, .18, 0.0)))
            n = unit(add(add(mul(base, .60), mul(envelope, .25)), mul(local, .15)))
            result_n[i] = unit((n[0], max(n[1], .30), n[2]))
            height = clamp((p[1] - low) / (high - low))
            outer = clamp(math.hypot(p[0], p[2]) / radius)
            shade = clamp((.78 + .15 * height + .07 * outer) * (1 + .045 * variation), .70, 1)
            colors[i] = (shade, shade, shade * (.98 + .02 * height), 1.0)
    return result, result_n, colors


def foliage(name, positions, normals, scale, lift):
    """Keep each three-card broadleaf/conifer bough together in an uneven envelope."""
    block = 12
    assert len(positions) % block == 0
    low = min(p[1] for p in positions)
    high = max(p[1] for p in positions)
    radius = max(math.hypot(p[0], p[2]) for p in positions)
    centre_y = (high + low) * .5
    result, result_n, colors = [], [], []
    for group, start in enumerate(range(0, len(positions), block)):
        points = positions[start:start + block]
        if name == "white-willow":
            points = willow_drooping_cards(points)
        elif name == "birch":
            points = birch_rising_cards(points)
        c = mean(points)
        theta = math.atan2(c[2], c[0])
        variation = math.sin(group * 2.39996 + .8)
        size = scale * (1.0 + .09 * variation)
        if name == "stone-pine":
            # Airy sprays need a connected core; keep the outer fringe much lighter.
            interior = clamp(1.0 - math.hypot(c[0], c[2]) / 3.2)
            size *= 1.06 + .24 * interior
        elif name in ("maple", "white-willow", "birch"):
            # Keep the deciduous crown full, with extra overlap inside its rounded envelope.
            envelope_distance = math.sqrt((math.hypot(c[0], c[2]) / radius) ** 2
                                          + ((c[1] - centre_y) * 2 / (high - low)) ** 2)
            # Birch needs only a small interior fill, preserving its airy outer branches.
            growth, fill = (1.0, .08) if name == "birch" else (1.08, .16)
            size *= growth + fill * clamp(1.0 - envelope_distance)
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
        sy = size * (.80 if name == "spruce" else .94 if name == "stone-pine" else 1.0)
        transformed = [add(target, (rel[0] * size, rel[1] * sy, rel[2] * size))
                       for rel in (sub(p, c) for p in points)]
        if name == "oak":
            transformed = oak_inner_overlap(transformed)
            target = mean(transformed)
        for p2 in transformed:
            result.append(p2)
            local = unit(add(sub(p2, target), (0, .18, 0)))
            envelope = unit((p2[0] / radius, (p2[1] - centre_y) / max(high - low, 1) * 1.6,
                             p2[2] / radius))
            # Branch sprays share the crown's lighting, with some local bough volume retained.
            local_weight = (.25 if name == "stone-pine" else .40 if name in ("oak", "maple", "birch")
                            else .35 if name == "white-willow" else .65)
            n = unit(add(add(mul(local, local_weight), mul(envelope, 1 - local_weight)), (0, .22, 0)))
            # Keep a soft underside without the uniformly upward-facing original normals.
            n = unit((n[0], max(n[1], -.18), n[2]))
            result_n.append(n)
            height = clamp((p2[1] - low) / (high - low))
            outer = clamp(math.hypot(p2[0], p2[2]) / radius)
            shade = clamp((.78 + .15 * height + .07 * outer) * (1 + .045 * variation), .70, 1)
            colors.append((shade, shade, shade * (.98 + .02 * height), 1.0))
    return result, result_n, colors


def branch_spray_uvs(count, name):
    """Give the three plates in each bough complementary sprays from the 2x2 atlas."""
    assert count % 4 == 0
    result = []
    for card in range(count // 4):
        group, plate = divmod(card, 3)
        cell = (group * 3 + plate) % 4
        x, y = cell % 2, cell // 2
        # Oak and birch source plates face the opposite way to the other atlas species.
        flip_v = plate != 0 if name in ("oak", "birch") else plate == 0
        corners = [(0, 1), (1, 1), (1, 0), (0, 0)]
        # Flip whole sprays to break repetition while preserving the transparent cell margin.
        for u, v in corners:
            if group % 2:
                u = 1 - u
            # Put the painted stem toward the crown and the spray tips outward.
            if flip_v:
                v = 1 - v
            if name == "birch":
                # The birch atlas has extra padding; use more of each leafy bough.
                u, v = .04 + .92 * u, .04 + .92 * v
            result.append(((x + u) * .5, (y + v) * .5))
    return result


def rebuild(name, source):
    relative = f"assets/trees/{name}.glb"
    raw = subprocess.run(["git", "show", f"{source}:{relative}"], cwd=ROOT,
                         check=True, capture_output=True).stdout
    glb = GLB(raw)
    if name in ("oak", "stone-pine", "maple", "white-willow", "birch"):
        atlas = ROOT / f"assets/trees/textures/{name}-boughs.png"
        glb.replace_image(1, atlas.read_bytes(), f"{name}-branch-sprays")
    elif name == "pine":
        # Pine stores its foliage first, unlike the other species; keep image 1 (bark).
        atlas = ROOT / "assets/trees/textures/pine-bough-v1.png"
        glb.replace_image(0, atlas.read_bytes(), "pine-needle-bough-v1")
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
                if name == "pine":
                    positions, normals, colors = pine_foliage(
                        positions, normals, glb.values(attrs["TEXCOORD_0"]), scale)
                else:
                    positions, normals, colors = foliage(name, positions, normals, scale, lift)
                if name in ("oak", "stone-pine", "maple", "white-willow", "birch"):
                    glb.write_values(attrs["TEXCOORD_0"], branch_spray_uvs(len(positions), name))
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

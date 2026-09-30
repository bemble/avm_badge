#!/usr/bin/env python3
"""Rasterise the brand logos into raw rgba8888 for the Name page's live screen.

Stdlib only: a small SVG path filler covering what the sources use (paths
with M/L/H/V/C/S/Q/Z, absolute or relative, flat fills, matrix, translate
and scale transforms). Each logo is fitted into a square, centred, rendered
at 8x8 samples per pixel and averaged down. Alpha stays real and straight,
so the logo sits on any skin's background.

Usage:
  python3 tools/brands.py                      # assets/brands/<name>@40x40.rgba
  python3 tools/brands.py --size 32 --preview /tmp/brands
"""

import argparse
import math
import os
import re
import struct
import xml.etree.ElementTree as ET
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets", "src", "logo")
OUT = os.path.join(ROOT, "assets", "brands")
LOGOS = ["home_assistant", "nabu_casa"]
SAMPLES = 8
CURVE_STEPS = 24

IDENTITY = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)


def multiply(m, n):
    a, b, c, d, e, f = m
    a2, b2, c2, d2, e2, f2 = n
    return (
        a * a2 + c * b2,
        b * a2 + d * b2,
        a * c2 + c * d2,
        b * c2 + d * d2,
        a * e2 + c * f2 + e,
        b * e2 + d * f2 + f,
    )


def parse_transform(text):
    matrix = IDENTITY
    for name, args in re.findall(r"(\w+)\s*\(([^)]*)\)", text or ""):
        v = [float(x) for x in re.split(r"[\s,]+", args.strip()) if x]
        if name == "matrix":
            step = tuple(v)
        elif name == "translate":
            step = (1.0, 0.0, 0.0, 1.0, v[0], v[1] if len(v) > 1 else 0.0)
        elif name == "scale":
            step = (v[0], 0.0, 0.0, v[1] if len(v) > 1 else v[0], 0.0, 0.0)
        else:
            raise SystemExit(f"unsupported transform {name}")
        matrix = multiply(matrix, step)
    return matrix


def apply(m, point):
    a, b, c, d, e, f = m
    x, y = point
    return (a * x + c * y + e, b * x + d * y + f)


def style_of(node):
    style = dict(
        pair.split(":", 1) for pair in (node.get("style") or "").split(";") if ":" in pair
    )
    return {k.strip(): v.strip() for k, v in style.items()}


def fill_of(node, inherited):
    fill = style_of(node).get("fill", node.get("fill", inherited))
    return fill


def colour(fill):
    fill = fill.lstrip("#")
    if len(fill) == 3:
        fill = "".join(ch * 2 for ch in fill)
    return tuple(int(fill[i : i + 2], 16) for i in (0, 2, 4))


def tokens(d):
    for command, args in re.findall(r"([MmLlHhVvCcSsQqZz])([^MmLlHhVvCcSsQqZz]*)", d):
        numbers = [float(x) for x in re.findall(r"-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?", args)]
        yield command, numbers


def bezier(p0, p1, p2, p3):
    out = []
    for i in range(1, CURVE_STEPS + 1):
        t = i / CURVE_STEPS
        u = 1 - t
        out.append(
            (
                u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
                u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1],
            )
        )
    return out


def polygons(d):
    """Flattens a path into closed polygons, in user units."""
    shapes, current = [], []
    x = y = 0.0
    start = (0.0, 0.0)
    last_control = None

    for command, n in tokens(d):
        rel = command.islower()
        op = command.upper()

        if op == "Z":
            if current:
                shapes.append(current)
            current = []
            x, y = start
            last_control = None
            continue

        step = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4}[op]
        for i in range(0, len(n), step):
            a = n[i : i + step]
            ox, oy = (x, y) if rel else (0.0, 0.0)

            if op == "M" and i == 0:
                if current:
                    shapes.append(current)
                x, y = ox + a[0], oy + a[1]
                start = (x, y)
                current = [(x, y)]
                last_control = None
            elif op in ("M", "L"):
                x, y = ox + a[0], oy + a[1]
                current.append((x, y))
                last_control = None
            elif op == "H":
                x = (x if rel else 0.0) + a[0]
                current.append((x, y))
                last_control = None
            elif op == "V":
                y = (y if rel else 0.0) + a[0]
                current.append((x, y))
                last_control = None
            elif op == "C":
                c1 = (ox + a[0], oy + a[1])
                c2 = (ox + a[2], oy + a[3])
                end = (ox + a[4], oy + a[5])
                current.extend(bezier((x, y), c1, c2, end))
                x, y = end
                last_control = c2
            elif op == "S":
                c1 = (2 * x - last_control[0], 2 * y - last_control[1]) if last_control else (x, y)
                c2 = (ox + a[0], oy + a[1])
                end = (ox + a[2], oy + a[3])
                current.extend(bezier((x, y), c1, c2, end))
                x, y = end
                last_control = c2
            elif op == "Q":
                q = (ox + a[0], oy + a[1])
                end = (ox + a[2], oy + a[3])
                c1 = (x + 2 / 3 * (q[0] - x), y + 2 / 3 * (q[1] - y))
                c2 = (end[0] + 2 / 3 * (q[0] - end[0]), end[1] + 2 / 3 * (q[1] - end[1]))
                current.extend(bezier((x, y), c1, c2, end))
                x, y = end
                last_control = None

    if current:
        shapes.append(current)
    return shapes


def shapes_of(path):
    """Every filled path in the file, as (rgb, [polygon]) in document order."""
    root = ET.parse(path).getroot()
    out = []

    def walk(node, matrix, fill):
        tag = node.tag.split("}")[-1]
        matrix = multiply(matrix, parse_transform(node.get("transform")))
        fill = fill_of(node, fill)
        if tag == "path" and fill and fill != "none":
            polys = [[apply(matrix, p) for p in poly] for poly in polygons(node.get("d"))]
            out.append((colour(fill), polys))
        for child in node:
            walk(child, matrix, fill)

    walk(root, IDENTITY, "#000000")
    return out


def fill_samples(polys, size):
    """Nonzero-winding coverage of one path on a size x size sample grid."""
    edges = []
    for poly in polys:
        for i in range(len(poly)):
            (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % len(poly)]
            if y0 != y1:
                edges.append((x0, y0, x1, y1, 1 if y1 > y0 else -1))

    rows = []
    for sy in range(size):
        cy = sy + 0.5
        crossings = []
        for x0, y0, x1, y1, w in edges:
            if min(y0, y1) <= cy < max(y0, y1):
                crossings.append((x0 + (cy - y0) * (x1 - x0) / (y1 - y0), w))
        crossings.sort()
        spans, winding = [], 0
        for i, (cx, w) in enumerate(crossings):
            before = winding
            winding += w
            if before == 0 and winding != 0:
                left = cx
            elif before != 0 and winding == 0:
                spans.append((left, cx))
        rows.append(spans)
    return rows


def render(path, size):
    shapes = shapes_of(path)
    points = [p for _rgb, polys in shapes for poly in polys for p in poly]
    left, right = min(p[0] for p in points), max(p[0] for p in points)
    top, bottom = min(p[1] for p in points), max(p[1] for p in points)

    grid = size * SAMPLES
    scale = grid / max(right - left, bottom - top)
    dx = (grid - (right - left) * scale) / 2 - left * scale
    dy = (grid - (bottom - top) * scale) / 2 - top * scale

    # The sample canvas: one rgb index per sample, or None where nothing is painted.
    canvas = [[None] * grid for _ in range(grid)]
    for rgb, polys in shapes:
        placed = [[(x * scale + dx, y * scale + dy) for x, y in poly] for poly in polys]
        for sy, spans in enumerate(fill_samples(placed, grid)):
            row = canvas[sy]
            for a, b in spans:
                for sx in range(max(0, math.ceil(a - 0.5)), min(grid, math.ceil(b - 0.5))):
                    row[sx] = rgb

    out = bytearray(size * size * 4)
    per = SAMPLES * SAMPLES
    for py in range(size):
        for px in range(size):
            r = g = b = count = 0
            for sy in range(py * SAMPLES, (py + 1) * SAMPLES):
                row = canvas[sy]
                for sx in range(px * SAMPLES, (px + 1) * SAMPLES):
                    rgb = row[sx]
                    if rgb is not None:
                        r, g, b, count = r + rgb[0], g + rgb[1], b + rgb[2], count + 1
            o = (py * size + px) * 4
            if count:
                out[o : o + 4] = bytes((r // count, g // count, b // count, count * 255 // per))
    return bytes(out)


def png(path, size, data):
    raw = b"".join(b"\x00" + data[y * size * 4 : (y + 1) * size * 4] for y in range(size))

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))

    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header))
        handle.write(chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--size", type=int, default=40, help="logo width and height in pixels")
    parser.add_argument("--out", default=OUT)
    parser.add_argument("--preview", help="also write PNGs into this directory")
    args = parser.parse_args()

    os.makedirs(args.out, exist_ok=True)
    for name in LOGOS:
        for stale in os.listdir(args.out):
            if stale.startswith(name + "@") and stale.endswith(".rgba"):
                os.remove(os.path.join(args.out, stale))

        data = render(os.path.join(SRC, name + ".svg"), args.size)
        file = f"{name}@{args.size}x{args.size}.rgba"
        with open(os.path.join(args.out, file), "wb") as handle:
            handle.write(data)
        print(f"{file} {len(data)} bytes")

        if args.preview:
            os.makedirs(args.preview, exist_ok=True)
            png(os.path.join(args.preview, name + ".png"), args.size, data)


if __name__ == "__main__":
    main()

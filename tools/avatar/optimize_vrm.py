"""Resize embedded PNG textures and verify VRM extension preservation."""

import argparse
import json
from pathlib import Path
import struct
import subprocess
import tempfile

GLB_HEADER = struct.Struct("<4sII")
CHUNK_HEADER = struct.Struct("<I4s")
PNG_HEADER = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"
MAX_SIDE = 512
MAX_MODEL_BYTES = 6_000_000


def read_glb(path):
    data = path.read_bytes()
    if len(data) < GLB_HEADER.size:
        raise ValueError("Truncated GLB header")
    if GLB_HEADER.unpack_from(data) != (b"glTF", 2, len(data)):
        raise ValueError("Invalid GLB v2 header")

    offset = GLB_HEADER.size
    chunks = []
    for expected in (b"JSON", b"BIN\0"):
        if offset + CHUNK_HEADER.size > len(data):
            raise ValueError("Truncated GLB chunk header")
        length, kind = CHUNK_HEADER.unpack_from(data, offset)
        offset += CHUNK_HEADER.size
        end = offset + length
        if kind != expected or length % 4 or end > len(data):
            raise ValueError(f"Invalid {expected!r} chunk")
        chunks.append(data[offset:end])
        offset = end
    if offset != len(data):
        raise ValueError("Unexpected data after the BIN chunk")

    model = json.loads(chunks[0])
    if model["asset"]["version"] != "2.0":
        raise ValueError("Expected a glTF 2.0 document")
    buffers = model["buffers"]
    if len(buffers) != 1 or "uri" in buffers[0]:
        raise ValueError("Expected one embedded BIN buffer")
    binary = chunks[1]
    length = buffers[0]["byteLength"]
    if length <= 0 or not 0 <= len(binary) - length <= 3:
        raise ValueError("BIN chunk does not match the declared buffer length")
    for view in model["bufferViews"]:
        start = view.get("byteOffset", 0)
        if view["buffer"] != 0 or start < 0 or not 0 < view["byteLength"] <= length - start:
            raise ValueError("Invalid bufferView")
    return model, binary


def image_views(model):
    views = model["bufferViews"]
    for image in model["images"]:
        if image.get("mimeType") != "image/png" or "uri" in image:
            raise ValueError("Expected an embedded PNG texture")
        index = image["bufferView"]
        if not 0 <= index < len(views):
            raise ValueError("Invalid image bufferView index")
        yield index


def view_bytes(view, binary):
    start = view.get("byteOffset", 0)
    return binary[start:start + view["byteLength"]]


def png_size(data):
    if not data.startswith(PNG_HEADER) or len(data) < 33:
        raise ValueError("Invalid PNG header")
    width, height = struct.unpack_from(">II", data, len(PNG_HEADER))
    if not width or not height:
        raise ValueError("Invalid PNG dimensions")
    return width, height


def pad(data, value):
    return data + value * (-len(data) % 4)


def write_glb(path, model, binary):
    metadata = pad(json.dumps(model, separators=(",", ":")).encode(), b" ")
    binary = pad(binary, b"\0")
    length = GLB_HEADER.size + 2 * CHUNK_HEADER.size + len(metadata) + len(binary)
    with path.open("wb") as output:
        output.write(GLB_HEADER.pack(b"glTF", 2, length))
        output.write(CHUNK_HEADER.pack(len(metadata), b"JSON"))
        output.write(metadata)
        output.write(CHUNK_HEADER.pack(len(binary), b"BIN\0"))
        output.write(binary)


def optimize(source, destination):
    model, binary = read_glb(source)
    views = model["bufferViews"]
    images = set(image_views(model))
    replacements = {}
    with tempfile.TemporaryDirectory(prefix="avatar-textures-") as directory:
        for index in sorted(images):
            data = view_bytes(views[index], binary)
            if max(png_size(data)) <= MAX_SIDE:
                continue
            texture = Path(directory) / f"{index}.png"
            texture.write_bytes(data)
            subprocess.run(["sips", "-Z", str(MAX_SIDE), str(texture)], check=True,
                           stdout=subprocess.DEVNULL)
            resized = texture.read_bytes()
            if max(png_size(resized)) > MAX_SIDE:
                raise ValueError(f"sips did not resize texture {index} to {MAX_SIDE} px")
            replacements[index] = resized

    rebuilt = bytearray()
    offsets = {}
    for index, view in enumerate(views):
        data = replacements.get(index)
        if data is None:
            data = view_bytes(view, binary)
        # Share identical geometry bytes while retaining all bufferView indices.
        key = (data, view.get("target"), view.get("byteStride"))
        offset = offsets.get(key) if index not in images else None
        if offset is None:
            rebuilt.extend(b"\0" * (-len(rebuilt) % 4))
            offset = len(rebuilt)
            rebuilt.extend(data)
            if index not in images:
                offsets[key] = offset
        view["byteOffset"] = offset
        view["byteLength"] = len(data)
    model["buffers"][0]["byteLength"] = len(rebuilt)
    write_glb(destination, model, rebuilt)


def vrmc_extensions(document):
    """Map every VRMC payload to its JSON location."""
    def walk(value, path):
        if isinstance(value, dict):
            for key, item in value.items():
                location = (*path, key)
                if key.startswith("VRMC_"):
                    yield location, item
                else:
                    yield from walk(item, location)
        elif isinstance(value, list):
            for index, item in enumerate(value):
                yield from walk(item, (*path, index))

    return dict(walk(document, ()))


def check(destination, source):
    model, binary = read_glb(destination)
    views = model["bufferViews"]
    if any(view.get("byteOffset", 0) % 4 for view in views):
        raise ValueError("Optimized bufferViews must be four-byte aligned")
    dimensions = [png_size(view_bytes(views[index], binary)) for index in image_views(model)]
    if not dimensions or any(max(size) > MAX_SIDE for size in dimensions):
        raise ValueError(f"Expected embedded textures no larger than {MAX_SIDE} px per side")
    extensions = model["extensions"]
    if "VRMC_vrm" not in extensions or "VRMC_springBone" not in extensions or not any(
        "VRMC_materials_mtoon" in material.get("extensions", {})
        for material in model["materials"]
    ):
        raise ValueError("Required VRMC extensions are missing")
    if source:
        original, original_binary = read_glb(source)
        if vrmc_extensions(model) != vrmc_extensions(original):
            raise ValueError("VRMC extension data changed")
        for key in ("images", "textures"):
            if model[key] != original[key]:
                raise ValueError(f"{key} metadata or indices changed")
        original_views = original["bufferViews"]
        if len(views) != len(original_views):
            raise ValueError("bufferView count changed")
        images = set(image_views(model))
        for index, (view, original_view) in enumerate(zip(views, original_views)):
            if index not in images and view_bytes(view, binary) != view_bytes(original_view, original_binary):
                raise ValueError(f"Non-image bufferView {index} changed")
    size = destination.stat().st_size
    if size > MAX_MODEL_BYTES:
        raise ValueError(f"Optimized model exceeds {MAX_MODEL_BYTES} bytes")
    print(f"{destination}: {size} bytes, {len(dimensions)} PNG textures, "
          f"largest side {max(map(max, dimensions))} px"
          + (", VRMC extensions and image/texture indices match source" if source else ""))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    optimize_args = commands.add_parser("optimize")
    optimize_args.add_argument("source", type=Path)
    optimize_args.add_argument("destination", type=Path)
    check_args = commands.add_parser("check")
    check_args.add_argument("destination", type=Path)
    check_args.add_argument("--source", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "optimize":
            optimize(args.source, args.destination)
        else:
            check(args.destination, args.source)
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"error: {error}\n")


if __name__ == "__main__":
    main()

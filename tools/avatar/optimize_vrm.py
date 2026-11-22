"""Resize embedded PNGs, compress morph targets and verify VRM preservation."""

import argparse
from itertools import repeat, zip_longest
import json
from pathlib import Path
import struct
import subprocess
import tempfile

GLB_HEADER = struct.Struct("<4sII")
CHUNK_HEADER = struct.Struct("<I4s")
PNG_HEADER = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"
MAX_SIDE = 1024
THUMBNAIL_SIDE = 256
COMPONENTS = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}


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


def thumbnail_view(model):
    extensions = model["extensions"]
    if "VRMC_vrm" in extensions:
        image = extensions["VRMC_vrm"]["meta"].get("thumbnailImage")
    else:
        texture = extensions["VRM"]["meta"].get("texture", -1)
        image = model["textures"][texture]["source"] if texture >= 0 else None
    return model["images"][image]["bufferView"] if image is not None else None


def resize_images(model, binary, max_side, thumbnail_side, thumbnail_out):
    views = model["bufferViews"]
    thumbnail = thumbnail_view(model)
    if thumbnail_out is not None and thumbnail is None:
        raise ValueError("The model has no thumbnail")
    replacements = {}
    with tempfile.TemporaryDirectory(prefix="avatar-textures-") as directory:
        for index in sorted(set(image_views(model))):
            data = view_bytes(views[index], binary)
            limit = min(thumbnail_side, max_side) if index == thumbnail else max_side
            if max(png_size(data)) > limit:
                texture = Path(directory) / f"{index}.png"
                texture.write_bytes(data)
                subprocess.run(["sips", "-Z", str(limit), str(texture)], check=True,
                               stdout=subprocess.DEVNULL)
                data = texture.read_bytes()
                if max(png_size(data)) > limit:
                    raise ValueError(f"sips did not resize texture {index} to {limit} px")
                replacements[index] = data
            if index == thumbnail and thumbnail_out is not None:
                thumbnail_out.write_bytes(data)
    return replacements


def accessor_layout(accessor):
    component = COMPONENTS[accessor["componentType"]]
    kind = accessor["type"]
    if kind.startswith("MAT"):
        columns = rows = int(kind[-1])
        column_size = struct.calcsize("<" + component * rows)
        padding = -column_size % 4
        column = component * rows
        layout = struct.Struct("<" + (column + "x" * padding) * (columns - 1) + column)
        return layout, (column_size + padding) * columns
    size = 1 if kind == "SCALAR" else int(kind[-1])
    layout = struct.Struct("<" + component * size)
    return layout, layout.size


def read_elements(views, binary, location, count, layout, element_size):
    index = location["bufferView"]
    if not 0 <= index < len(views):
        raise ValueError("Invalid accessor bufferView index")
    view = views[index]
    offset = location.get("byteOffset", 0)
    stride = view.get("byteStride", element_size)
    if count < 1 or offset < 0 or stride < element_size or (
        offset + (count - 1) * stride + layout.size > view["byteLength"]
    ):
        raise ValueError("Accessor data exceeds its bufferView")
    start = view.get("byteOffset", 0) + offset
    for index in range(count):
        yield layout.unpack_from(binary, start + index * stride)


def accessor_values(accessor, views, binary):
    count = accessor["count"]
    if count < 1:
        raise ValueError("Invalid accessor count")
    layout, element_size = accessor_layout(accessor)
    if "bufferView" in accessor:
        base = read_elements(views, binary, accessor, count, layout, element_size)
    else:
        base = repeat(layout.unpack(bytes(layout.size)), count)
    sparse = accessor.get("sparse")
    if sparse is None:
        yield from base
        return

    indices = sparse["indices"]
    component_type = indices["componentType"]
    if component_type not in (5121, 5123, 5125):
        raise ValueError("Invalid sparse index component type")
    index_layout = struct.Struct("<" + COMPONENTS[component_type])
    values = read_elements(views, binary, sparse["values"], sparse["count"], layout, element_size)
    overrides = {}
    previous = -1
    for (index,), value in zip(
        read_elements(views, binary, indices, sparse["count"], index_layout, index_layout.size),
        values,
    ):
        if not previous < index < count:
            raise ValueError("Sparse accessor indices must be increasing and in range")
        overrides[index] = value
        previous = index
    for index, value in enumerate(base):
        yield overrides.get(index, value)


def referenced_views(value):
    if isinstance(value, dict):
        for key, item in value.items():
            if key == "bufferView" and isinstance(item, int):
                yield item
            else:
                yield from referenced_views(item)
    elif isinstance(value, list):
        for item in value:
            yield from referenced_views(item)


def sparsify_morphs(model, binary, replacements):
    views = model["bufferViews"]
    targets = {
        index for mesh in model["meshes"] for primitive in mesh["primitives"]
        for target in primitive.get("targets", []) for index in target.values()
    }
    replaced = set()

    def append_view(data):
        index = len(views)
        views.append({"buffer": 0, "byteLength": len(data)})
        replacements[index] = data
        return index

    for index in sorted(targets):
        accessor = model["accessors"][index]
        if "bufferView" not in accessor or "sparse" in accessor:
            continue
        layout, element_size = accessor_layout(accessor)
        source_values = list(accessor_values(accessor, views, binary))
        nonzero = [(i, value) for i, value in enumerate(source_values) if any(value)]
        component_type = 5123 if not nonzero or nonzero[-1][0] <= 65535 else 5125
        index_layout = struct.Struct("<" + COMPONENTS[component_type])
        sparse_size = len(nonzero) * (index_layout.size + element_size)
        if sparse_size >= accessor["count"] * element_size:
            continue

        # A missing base view initializes the accessor to zeros.
        candidate = {key: value for key, value in accessor.items()
                     if key not in ("bufferView", "byteOffset")}
        if nonzero:
            indices = b"".join(index_layout.pack(i) for i, _ in nonzero)
            values = b"".join(layout.pack(*value).ljust(element_size, b"\0") for _, value in nonzero)
            candidate["sparse"] = {
                "count": len(nonzero),
                "indices": {"bufferView": 0, "componentType": component_type},
                "values": {"bufferView": 1},
            }
            candidate_views = [
                {"byteLength": len(indices)},
                {"byteOffset": len(indices), "byteLength": len(values)},
            ]
        else:
            candidate_views = []
            indices = values = b""
        if list(accessor_values(candidate, candidate_views, indices + values)) != source_values:
            print(f"Morph accessor {index} retained dense storage after round-trip mismatch")
            continue
        if nonzero:
            candidate["sparse"]["indices"]["bufferView"] = append_view(indices)
            candidate["sparse"]["values"]["bufferView"] = append_view(values)
        replaced.add(accessor["bufferView"])
        model["accessors"][index] = candidate

    # Keep existing view indices and reclaim only storage with no remaining references.
    for index in replaced - set(referenced_views(model)):
        views[index] = {"buffer": 0, "byteLength": 1}
        replacements[index] = b"\0"


def optimize(source, destination, max_side, thumbnail_side, thumbnail_out):
    model, binary = read_glb(source)
    views = model["bufferViews"]
    images = set(image_views(model))
    replacements = resize_images(model, binary, max_side, thumbnail_side, thumbnail_out)
    sparsify_morphs(model, binary, replacements)
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


def vrm_extensions(model):
    extensions = model["extensions"]
    if "VRM" in extensions:
        vrm = extensions["VRM"]
        if not {"materialProperties", "secondaryAnimation"} <= vrm.keys():
            raise ValueError("Required VRM 0.x extension data is missing")
        return {"VRM": vrm}
    if not {"VRMC_vrm", "VRMC_springBone"} <= extensions.keys() or not any(
        "VRMC_materials_mtoon" in material.get("extensions", {})
        for material in model["materials"]
    ):
        raise ValueError("Required VRMC extensions are missing")
    return vrmc_extensions(model)


def check(destination, source, max_side, max_bytes):
    model, binary = read_glb(destination)
    views = model["bufferViews"]
    if any(view.get("byteOffset", 0) % 4 for view in views):
        raise ValueError("Optimized bufferViews must be four-byte aligned")
    dimensions = [png_size(view_bytes(views[index], binary)) for index in image_views(model)]
    if not dimensions or any(max(size) > max_side for size in dimensions):
        raise ValueError(f"Expected embedded textures no larger than {max_side} px per side")
    original, original_binary = read_glb(source)
    if vrm_extensions(model) != vrm_extensions(original):
        raise ValueError("VRM extension data changed")
    for key in ("images", "textures"):
        if model[key] != original[key]:
            raise ValueError(f"{key} metadata or indices changed")
    storage_keys = {"bufferView", "byteOffset", "sparse"}
    for index, (accessor, original_accessor) in enumerate(zip_longest(
        model["accessors"], original["accessors"],
    )):
        if accessor is None or original_accessor is None:
            raise ValueError("Accessor count changed")
        if ({k: v for k, v in accessor.items() if k not in storage_keys}
                != {k: v for k, v in original_accessor.items() if k not in storage_keys}):
            raise ValueError(f"Accessor {index} metadata changed")
        values = accessor_values(accessor, views, binary)
        original_values = accessor_values(original_accessor, original["bufferViews"], original_binary)
        if any(value != expected for value, expected in zip_longest(values, original_values)):
            raise ValueError(f"Accessor {index} values changed")
    size = destination.stat().st_size
    if max_bytes is not None and size > max_bytes:
        raise ValueError(f"Optimized model is {size} bytes, exceeds {max_bytes} bytes")
    print(f"{destination}: {size} bytes, {len(dimensions)} PNG textures, "
          f"largest side {max(map(max, dimensions))} px, "
          f"VRM extensions, image/texture indices and {len(model['accessors'])} accessors match source")


def positive_int(value):
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError("expected a positive integer")
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    optimize_args = commands.add_parser("optimize")
    optimize_args.add_argument("source", type=Path)
    optimize_args.add_argument("destination", type=Path)
    optimize_args.add_argument("--max-side", type=positive_int, default=MAX_SIDE)
    optimize_args.add_argument("--thumbnail-side", type=positive_int, default=THUMBNAIL_SIDE)
    optimize_args.add_argument("--thumbnail-out", type=Path)
    check_args = commands.add_parser("check")
    check_args.add_argument("destination", type=Path)
    check_args.add_argument("--source", type=Path, required=True)
    check_args.add_argument("--max-side", type=positive_int, default=MAX_SIDE)
    check_args.add_argument("--max-bytes", type=positive_int)
    args = parser.parse_args()
    try:
        if args.command == "optimize":
            optimize(args.source, args.destination, args.max_side, args.thumbnail_side, args.thumbnail_out)
        else:
            check(args.destination, args.source, args.max_side, args.max_bytes)
    except (OSError, ValueError, KeyError, TypeError, IndexError, struct.error, subprocess.CalledProcessError) as error:
        parser.exit(1, f"error: {error}\n")


if __name__ == "__main__":
    main()

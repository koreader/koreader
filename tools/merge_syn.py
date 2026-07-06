#!/usr/bin/env python3
"""Fold a StarDict .syn file into the .idx.

sdcv linearly re-scans the whole .syn on every process launch (no offset
cache), which makes lookups against large inflection dictionaries very slow
on e-readers. Folding every synonym into the .idx as a real entry removes
the .syn entirely; sdcv then uses its lazy, .oft-cached index access.

Usage: merge_syn.py <src_dict_dir> <out_dir>

The source directory must contain one dictionary (.ifo/.idx[/.syn] and
.dict or .dict.dz). The output directory receives the merged dictionary;
the source is never modified.
"""
import struct
import shutil
import sys
from pathlib import Path

LOWER = bytes(c + 32 if 65 <= c <= 90 else c for c in range(256))


def sd_key(word: bytes):
    """stardict_strcmp sort key: ascii-casefolded bytes, then raw bytes."""
    return (word.translate(LOWER), word)


def read_ifo(path: Path):
    pairs = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            pairs.append((k, v))
    return pairs


def read_idx(path: Path):
    data = path.read_bytes()
    entries, i = [], 0
    while i < len(data):
        z = data.index(0, i)
        off, size = struct.unpack(">II", data[z + 1:z + 9])
        entries.append((data[i:z], off, size))
        i = z + 9
    return entries


def read_syn(path: Path):
    data = path.read_bytes()
    entries, i = [], 0
    while i < len(data):
        z = data.index(0, i)
        (n,) = struct.unpack(">I", data[z + 1:z + 5])
        entries.append((data[i:z], n))
        i = z + 5
    return entries


def main(src_dir: str, out_dir: str):
    src, dst = Path(src_dir), Path(out_dir)
    try:
        ifo_path = next(src.glob("*.ifo"))
    except StopIteration:
        sys.exit(f"no .ifo file found in {src}")
    base = ifo_path.stem
    ifo = read_ifo(ifo_path)
    ifo_map = dict(ifo)
    if ifo_map.get("idxoffsetbits") == "64":
        sys.exit("64-bit idx offsets are not supported")

    idx = read_idx(src / f"{base}.idx")
    n_syn = 0
    entries = list(idx)
    syn_path = src / f"{base}.syn"
    if syn_path.exists():
        for word, n in read_syn(syn_path):
            if n < len(idx):
                _, off, size = idx[n]
                entries.append((word, off, size))
                n_syn += 1
    entries.sort(key=lambda e: sd_key(e[0]))

    merged, seen = [], set()
    for e in entries:
        if e not in seen:
            seen.add(e)
            merged.append(e)

    buf = bytearray()
    for word, off, size in merged:
        buf += word + b"\0" + struct.pack(">II", off, size)

    dst.mkdir(parents=True, exist_ok=True)
    (dst / f"{base}.idx").write_bytes(buf)

    out_lines = ["StarDict's dict ifo file"]
    for k, v in ifo:
        if k == "synwordcount":
            continue
        if k == "wordcount":
            v = str(len(merged))
        elif k == "idxfilesize":
            v = str(len(buf))
        out_lines.append(f"{k}={v}")
    (dst / f"{base}.ifo").write_text("\n".join(out_lines) + "\n", encoding="utf-8")

    for suffix in (".dict.dz", ".dict"):
        p = src / f"{base}{suffix}"
        if p.exists():
            shutil.copy2(p, dst / p.name)

    print(f"{base}: {len(idx)} idx entries + {n_syn} syn entries "
          f"-> {len(merged)} merged (idx {len(buf)} bytes)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])

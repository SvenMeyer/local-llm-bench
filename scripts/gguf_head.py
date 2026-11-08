#!/usr/bin/env python3
"""Read a remote GGUF's header + tensor table via HTTP range requests.

Downloads only the leading bytes, growing the window until the tensor table parses.
Prints the quant-type histogram so a 66-76 GB download can be validated for ~0 cost.
"""
import struct
import subprocess
import sys

GGML_TYPES = {}  # filled from our local ggml.h so names are authoritative


def load_type_names(hdr="/home/sum/Downloads/AI-Runtime/llama.cpp/ggml/include/ggml.h"):
    import re
    for line in open(hdr):
        m = re.search(r"GGML_TYPE_([A-Z0-9_]+)\s*=\s*(\d+)", line)
        if m:
            GGML_TYPES[int(m.group(2))] = m.group(1)


class Need(Exception):
    pass


class Buf:
    def __init__(self, b):
        self.b, self.o = b, 0

    def take(self, n):
        if self.o + n > len(self.b):
            raise Need()
        v = self.b[self.o:self.o + n]
        self.o += n
        return v

    def u32(self):
        return struct.unpack("<I", self.take(4))[0]

    def u64(self):
        return struct.unpack("<Q", self.take(8))[0]

    def i32(self):
        return struct.unpack("<i", self.take(4))[0]

    def string(self):
        return self.take(self.u64()).decode("utf-8", "replace")


# GGUF metadata value types
SCALAR = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8}


def skip_value(b, vt):
    if vt in SCALAR:
        b.take(SCALAR[vt])
    elif vt == 8:  # STRING
        b.string()
    elif vt == 9:  # ARRAY
        et, n = b.u32(), b.u64()
        if et in SCALAR:
            b.take(SCALAR[et] * n)
        elif et == 8:
            for _ in range(n):
                b.string()
        elif et == 9:
            for _ in range(n):
                skip_value(b, 9)
        else:
            raise ValueError(f"array elem type {et}")
    else:
        raise ValueError(f"value type {vt}")


def parse(data):
    b = Buf(data)
    if b.take(4) != b"GGUF":
        raise ValueError("not a GGUF file")
    ver = b.u32()
    n_tensors = b.u64()
    n_kv = b.u64()
    meta = {}
    for _ in range(n_kv):
        k = b.string()
        vt = b.u32()
        if vt == 8:
            meta[k] = b.string()
        elif vt in SCALAR and vt not in (7,):
            raw = b.take(SCALAR[vt])
            fmt = {4: "<I", 5: "<i", 6: "<f", 10: "<Q", 11: "<q", 12: "<d",
                   0: "<B", 1: "<b", 2: "<H", 3: "<h"}.get(vt)
            meta[k] = struct.unpack(fmt, raw)[0] if fmt else None
        else:
            b.o -= 4
            b.u32()
            skip_value(b, vt)
    tensors = []
    for _ in range(n_tensors):
        name = b.string()
        nd = b.u32()
        dims = [b.u64() for _ in range(nd)]
        t = b.u32()
        b.u64()  # offset
        tensors.append((name, dims, GGML_TYPES.get(t, f"TYPE_{t}")))
    return ver, n_kv, meta, tensors, b.o


def fetch(url, nbytes):
    return subprocess.run(
        ["curl", "-sS", "-L", "--max-time", "180", "-r", f"0-{nbytes - 1}", url],
        capture_output=True, check=True).stdout


def main(url, label):
    load_type_names()
    for mb in (8, 24, 64, 160):
        data = fetch(url, mb * 1024 * 1024)
        try:
            ver, n_kv, meta, tensors, used = parse(data)
        except Need:
            continue
        import collections
        hist = collections.Counter(t for _, _, t in tensors)
        print(f"\n===== {label} =====")
        print(f"  GGUF v{ver}  kv={n_kv}  tensors={len(tensors)}  "
              f"header={used/1e6:.2f} MB  (fetched {mb} MB)")
        for k in ("general.architecture", "general.size_label", "general.file_type",
                  "qwen4exp.expert_count", "qwen4exp.block_count"):
            if k in meta:
                print(f"  {k} = {meta[k]}")
        print("  types: " + ", ".join(f"{t}={n}" for t, n in
                                      sorted(hist.items(), key=lambda kv: -kv[1])))
        unknown = [t for t in hist if t.startswith("TYPE_")]
        print(f"  UNKNOWN TYPES: {unknown}" if unknown
              else "  all types resolve against our ggml.h")
        exps = collections.Counter(t for n, _, t in tensors if "_exps" in n)
        print(f"  routed-expert tensors: {dict(exps)}")
        return
    print(f"{label}: header did not fit in 160 MB", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])

"""Progress estimate for `leanchecker --fresh` (step 7), which prints no progress.

The replay walks every declaration (in hash order, dependencies first), and the kernel
traverses each declaration's term, which lives in a memory-mapped .olean file. So the
fraction of .olean pages the process has *ever* touched approximates the fraction of
work done. Resident pages get evicted when RAM fills up, so this samples which pages are
present (/proc/PID/pagemap, readable by the process owner) every interval and keeps the
union.

Usage: python3 -I replay_progress.py <pid> <out.csv> [interval-seconds]
Appends: utc,elapsed_s,touched_pages,total_pages,touched_pct,resident_pct
Exits when the process exits. Approximate: the last few percent of pages may never be
touched (data the kernel does not need), so the replay can finish below 100%.
"""
import os
import struct
import sys
import time

pid, out = int(sys.argv[1]), sys.argv[2]
interval = int(sys.argv[3]) if len(sys.argv) > 3 else 60
PS = os.sysconf("SC_PAGE_SIZE")
seen = {}            # (start, end) -> bytearray of 0/1 per page
t0 = time.time()

if not os.path.exists(out):
    with open(out, "w") as f:
        f.write("utc,elapsed_s,touched_pages,total_pages,touched_pct,resident_pct\n")


def olean_maps():
    with open(f"/proc/{pid}/maps") as f:
        for line in f:
            if line.rstrip().endswith(".olean"):
                a, b = (int(x, 16) for x in line.split()[0].split("-"))
                yield a, b


while os.path.exists(f"/proc/{pid}"):
    try:
        total = touched = resident = 0
        with open(f"/proc/{pid}/pagemap", "rb") as pm:
            for a, b in olean_maps():
                n = (b - a) // PS
                pm.seek((a // PS) * 8)
                data = pm.read(n * 8)
                if len(data) != n * 8:
                    continue
                present = bytes(v >> 63 for v in struct.unpack(f"{n}Q", data))
                bits = seen.get((a, b))
                if bits is None:
                    bits = seen[(a, b)] = bytearray(n)
                # OR the present bits into the union
                merged = bytes(x | y for x, y in zip(bits, present))
                bits[:] = merged
                total += n
                touched += merged.count(1)
                resident += present.count(1)
        if total:
            with open(out, "a") as f:
                f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())},{int(time.time() - t0)},"
                        f"{touched},{total},{100 * touched / total:.2f},{100 * resident / total:.2f}\n")
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        break
    time.sleep(interval)

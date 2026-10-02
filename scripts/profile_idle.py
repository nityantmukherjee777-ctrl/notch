#!/usr/bin/python3
"""Read-only CPU measurement for Notch and its directly owned usage helper."""
import json
import subprocess
import sys
import time

pid = int(sys.argv[1])
duration = float(sys.argv[2]) if len(sys.argv) > 2 else 60

def snapshot():
    rows = subprocess.check_output(["ps", "-axo", "pid=,ppid=,time=,rss="], text=True)
    result = {}
    for row in rows.splitlines():
        fields = row.split()
        if len(fields) != 4:
            continue
        process, parent = int(fields[0]), int(fields[1])
        if process != pid and parent != pid:
            continue
        seconds = 0.0
        for part in fields[2].split(":"):
            seconds = seconds * 60 + float(part)
        result[process] = {"cpu_seconds": seconds, "rss_mb": round(int(fields[3]) / 1024, 1)}
    return result

initial = snapshot()
started = time.monotonic()
time.sleep(duration)
final = snapshot()
elapsed = time.monotonic() - started
measurements = []
for process, reading in final.items():
    if process in initial:
        measurements.append({"pid": process, "average_cpu_percent": round((reading["cpu_seconds"] - initial[process]["cpu_seconds"]) / elapsed * 100, 3), "rss_mb": reading["rss_mb"]})
print(json.dumps({"elapsed_seconds": round(elapsed, 2), "processes": measurements}, indent=2))

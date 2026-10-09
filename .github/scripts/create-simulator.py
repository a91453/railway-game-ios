#!/usr/bin/env python3
"""Create a new Simulator for ios-build.yml and write its UDID to GITHUB_ENV.

    create-simulator.py <iPhone|iPad> <ENV_VARIABLE>

The new device has the type and runtime of the first available preinstalled
one of that family. A preinstalled device's first boot migrates its data (4.5
to 7.6 minutes on the runners); a new device has none to migrate. If the new
device cannot be created, the preinstalled one is used.
"""
import json
import os
import subprocess
import sys

family, variable = sys.argv[1:]
listed = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "--json"],
                        capture_output=True, text=True, check=True)
devices = json.loads(listed.stdout)["devices"]
found = [(runtime, device) for runtime, group in devices.items()
         if ".iOS-" in runtime for device in group
         if device["isAvailable"] and device["name"].startswith(family)]
if not found:
    raise SystemExit(f"No available {family} Simulator")
runtime, device = found[0]
udid = device["udid"]
print(f"First available: {device['name']} ({udid}, {runtime})")

kind = device.get("deviceTypeIdentifier")
created = None
if kind:
    created = subprocess.run(
        ["xcrun", "simctl", "create", f"RailwayGame CI {device['name']}", kind, runtime],
        capture_output=True, text=True)
if created is not None and created.returncode == 0 and created.stdout.strip():
    udid = created.stdout.strip()
    print(f"Created a new {device['name']} ({udid})")
else:
    reason = " ".join(created.stderr.split()) if created is not None else "the list gives no device type"
    print(f"::warning::Could not create a new {family} Simulator ({reason}); using the preinstalled one.")

with open(os.environ["GITHUB_ENV"], "a") as env:
    env.write(f"{variable}={udid}\n")

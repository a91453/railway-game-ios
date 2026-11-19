#!/usr/bin/env python3
"""Choose the Simulator a job builds for and tests on (decision 857).

    select-simulator.py iPhone SIMULATOR_UDID
    select-simulator.py iPad IPAD_SIMULATOR_UDID

Reads `xcrun simctl list devices available --json` and the selected Xcode's
Simulator SDK version, and appends NAME=udid to $GITHUB_ENV.

A runner image holds several iOS runtimes, and "the first device simctl
lists" is then whichever runtime comes first. The device is taken from the
runtime of the SDK the app is built with; an iPhone is a Pro that is not a
Max when there is one, and never a folding iPhone, whose screen is another
shape; an iPad is the 13-inch Pro when there is one. Those are the sizes the
tests were written on (iPhone 17 Pro and iPad Pro 13-inch on macos-26): on
an iPad mini three of the tutorial's tests failed (#2453, run 44265510040). With --devices and --sdk the
choice is made from a file, for the self-test (--selftest).
"""
import json
import os
import subprocess
import sys


def choose(devices, sdk, kind):
    """The device for `kind` ("iPhone" or "iPad"), and its runtime."""
    found = [(runtime, device) for runtime, group in devices.items()
             if ".iOS-" in runtime for device in group
             if device.get("isAvailable") and device["name"].startswith(kind)]
    if not found:
        raise SystemExit(f"No available {kind} Simulator")
    wanted = ".iOS-" + sdk.replace(".", "-")
    same = [pair for pair in found if pair[0].endswith(wanted)]
    if not same:
        print(f"No {kind} Simulator of iOS {sdk}; taking one of another runtime.")
    pool = same or found
    if kind == "iPhone":
        plain = [pair for pair in pool if "Duo" not in pair[1]["name"] and "Fold" not in pair[1]["name"]]
        pros = [pair for pair in plain if pair[1]["name"].endswith(" Pro")]
        pool = pros or plain or pool
    else:
        # The iPad the tests were written on: the 13-inch Pro, then any Pro.
        for start in ("iPad Pro 13", "iPad Pro"):
            large = [pair for pair in pool if pair[1]["name"].startswith(start)]
            if large:
                pool = large
                break
    return pool[0]


def selftest():
    def device(name, available=True):
        return {"name": name, "udid": name.upper(), "isAvailable": available}
    prefix = "com.apple.CoreSimulator.SimRuntime."
    devices = {
        prefix + "iOS-27-0": [device("iPhone 17"), device("iPhone 18 Pro"), device("iPad (A16)")],
        prefix + "iOS-27-1": [device("iPhone Duo")],
        prefix + "iOS-27-2": [device("iPhone Duo"), device("iPhone 17"), device("iPhone 18 Pro Max"),
                              device("iPhone 18 Pro"), device("iPad mini (A20 Pro)"), device("iPad (A16)"),
                              device("iPad Pro 11-inch (M5)"), device("iPad Pro 13-inch (M5)")],
        prefix + "tvOS-27-2": [device("iPhone in name only")],
    }
    def name(sdk, kind, source=devices):
        runtime, chosen = choose(source, sdk, kind)
        return runtime.removeprefix(prefix), chosen["name"]
    assert name("27.2", "iPhone") == ("iOS-27-2", "iPhone 18 Pro")
    assert name("27.2", "iPad") == ("iOS-27-2", "iPad Pro 13-inch (M5)")
    assert name("27.0", "iPad") == ("iOS-27-0", "iPad (A16)")
    no_13 = {prefix + "iOS-27-2": [device("iPad mini (A20 Pro)"), device("iPad Pro 11-inch (M5)")]}
    assert name("27.2", "iPad", no_13) == ("iOS-27-2", "iPad Pro 11-inch (M5)")
    assert name("27.0", "iPhone") == ("iOS-27-0", "iPhone 18 Pro")
    # Only a folding iPhone in the SDK's runtime: it is still that runtime's.
    assert name("27.1", "iPhone") == ("iOS-27-1", "iPhone Duo")
    # No runtime of the SDK: another runtime's device, not a failure.
    assert name("26.5", "iPhone") == ("iOS-27-0", "iPhone 18 Pro")
    # No Pro: the first that does not fold.
    no_pro = {prefix + "iOS-27-2": [device("iPhone Duo"), device("iPhone 17"), device("iPhone Air")]}
    assert name("27.2", "iPhone", no_pro) == ("iOS-27-2", "iPhone 17")
    # An unavailable device is never chosen.
    gone = {prefix + "iOS-27-2": [device("iPhone 18 Pro", available=False), device("iPhone 17")]}
    assert name("27.2", "iPhone", gone) == ("iOS-27-2", "iPhone 17")
    try:
        choose({prefix + "iOS-27-2": [device("iPhone 17")]}, "27.2", "iPad")
    except SystemExit:
        pass
    else:
        raise AssertionError("no iPad should fail")
    print("select-simulator.py self-test passed.")


def main(arguments):
    if arguments == ["--selftest"]:
        selftest()
        return
    if len(arguments) not in (2, 6) or arguments[0] not in ("iPhone", "iPad"):
        raise SystemExit(__doc__)
    kind, variable = arguments[:2]
    if len(arguments) == 6:
        options = dict(zip(arguments[2::2], arguments[3::2]))
        with open(options["--devices"]) as file:
            listing = json.load(file)
        sdk = options["--sdk"]
    else:
        listing = json.loads(subprocess.run(
            ["xcrun", "simctl", "list", "devices", "available", "--json"],
            check=True, capture_output=True, text=True).stdout)
        sdk = subprocess.run(
            ["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"],
            check=True, capture_output=True, text=True).stdout.strip()
    runtime, device = choose(listing["devices"], sdk, kind)
    print(f"Selected {device['name']} ({device['udid']}), {runtime.rsplit('.', 1)[-1]}; the SDK is iOS {sdk}")
    with open(os.environ["GITHUB_ENV"], "a") as env:
        env.write(f"{variable}={device['udid']}\n")


if __name__ == "__main__":
    main(sys.argv[1:])

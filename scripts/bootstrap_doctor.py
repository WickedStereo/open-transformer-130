#!/usr/bin/env python3
"""Validate the Sprint 00 bootstrap environment."""

from __future__ import annotations

import importlib.util
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass


@dataclass
class Check:
    section: str
    name: str
    ok: bool
    required: bool
    detail: str


def binary_check(section: str, command: str, *, required: bool, detail: str) -> Check:
    path = shutil.which(command)
    if path:
        return Check(section, command, True, required, path)
    return Check(section, command, False, required, detail)


def module_check(section: str, module: str, *, required: bool, detail: str) -> Check:
    spec = importlib.util.find_spec(module)
    if spec is not None:
        location = spec.origin or "module available"
        return Check(section, module, True, required, location)
    return Check(section, module, False, required, detail)


def env_check(name: str) -> Check:
    value = os.environ.get(name)
    if not value:
        return Check(
            "Environment",
            name,
            False,
            False,
            "unset; required later for OpenLane smoke runs",
        )
    if os.path.exists(value):
        return Check("Environment", name, True, False, value)
    return Check(
        "Environment",
        name,
        False,
        False,
        f"{value} (set but path does not exist)",
    )


def docker_access_check() -> Check:
    docker = shutil.which("docker")
    if not docker:
        return Check(
            "Environment",
            "docker access",
            False,
            False,
            "docker binary not found; needed for make gds",
        )

    result = subprocess.run(
        [docker, "info"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if result.returncode == 0:
        return Check("Environment", "docker access", True, False, "docker info succeeded")

    return Check(
        "Environment",
        "docker access",
        False,
        False,
        "docker present but not accessible from this shell",
    )


def collect_checks() -> list[Check]:
    checks = [
        binary_check(
            "Core bootstrap tools",
            "python3",
            required=True,
            detail="required for make test and helper scripts",
        ),
        binary_check(
            "Core bootstrap tools",
            "make",
            required=True,
            detail="required for repository entrypoints",
        ),
        binary_check(
            "Core bootstrap tools",
            "verilator",
            required=True,
            detail="required for make lint, make sim, and cocotb verilator runs",
        ),
        binary_check(
            "Core bootstrap tools",
            "c++",
            required=True,
            detail="required for Verilator C++ builds",
        ),
        module_check(
            "Core Python packages",
            "pytest",
            required=True,
            detail="required for make test",
        ),
        module_check(
            "Core Python packages",
            "cocotb",
            required=True,
            detail="required for make test",
        ),
        module_check(
            "Core Python packages",
            "numpy",
            required=True,
            detail="required for the reference model",
        ),
        binary_check(
            "Current optional flows",
            "yosys",
            required=False,
            detail="needed for make fpga",
        ),
        binary_check(
            "Current optional flows",
            "nextpnr-ice40",
            required=False,
            detail="needed for make fpga",
        ),
        binary_check(
            "Current optional flows",
            "icepack",
            required=False,
            detail="needed for make fpga",
        ),
        module_check(
            "Current optional flows",
            "openlane",
            required=False,
            detail="needed for make gds",
        ),
        module_check(
            "Current optional flows",
            "pyuvm",
            required=False,
            detail="useful for future verification expansion",
        ),
        module_check(
            "Current optional flows",
            "onnx",
            required=False,
            detail="useful for future compiler/runtime work",
        ),
        module_check(
            "Current optional flows",
            "matplotlib",
            required=False,
            detail="useful for architecture studies and reports",
        ),
        module_check(
            "Current optional flows",
            "torch",
            required=False,
            detail="useful for reference workloads and experimentation",
        ),
        env_check("PDK_ROOT"),
        docker_access_check(),
        binary_check(
            "Planned future tooling",
            "sby",
            required=False,
            detail="planned for Sprint 06 formal verification",
        ),
        binary_check(
            "Planned future tooling",
            "openroad",
            required=False,
            detail="planned for backend and power analysis stages",
        ),
        binary_check(
            "Planned future tooling",
            "sta",
            required=False,
            detail="planned for timing verification stages",
        ),
        binary_check(
            "Planned future tooling",
            "openram",
            required=False,
            detail="planned for SRAM macro generation",
        ),
    ]
    return checks


def render(checks: list[Check]) -> int:
    current_section = None
    required_failures = 0

    for check in checks:
        if check.section != current_section:
            if current_section is not None:
                print()
            print(f"== {check.section} ==")
            current_section = check.section

        if check.ok:
            status = "PASS"
        elif check.required:
            status = "FAIL"
            required_failures += 1
        else:
            status = "WARN"

        print(f"[{status}] {check.name}: {check.detail}")

    print()
    if required_failures:
        print(
            f"Bootstrap doctor failed: {required_failures} required check(s) missing."
        )
        return 1

    print("Bootstrap doctor passed: required Sprint 00 checks are satisfied.")
    print("Warnings are non-blocking and capture optional or later-sprint gaps.")
    return 0


def main() -> int:
    checks = collect_checks()
    return render(checks)


if __name__ == "__main__":
    sys.exit(main())

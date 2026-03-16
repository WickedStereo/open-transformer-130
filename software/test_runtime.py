"""Unit tests for the thin host-side runtime."""

from __future__ import annotations

from dataclasses import dataclass, field

from sim.rtl_scoreboard import descriptor as reference_descriptor
from software.runtime import (
    AttnCoreRuntime,
    CTRL_ENABLE,
    DEFAULT_QUEUE_BASE,
    Descriptor,
    HostMemoryImage,
    Opcode,
    RegisterOffset,
    RuntimeProgram,
    SLOT_BYTES,
    STATUS_BUSY,
)


@dataclass
class FakeTransport:
    registers: dict[int, int] = field(default_factory=dict)
    host_memory: dict[int, int] = field(default_factory=dict)
    writes: list[tuple[int, int]] = field(default_factory=list)
    status_script: list[int] = field(default_factory=list)
    tail_script: list[int] = field(default_factory=list)

    def write32(self, offset: int, value: int) -> None:
        self.writes.append((offset, value & 0xFFFF_FFFF))
        self.registers[offset] = value & 0xFFFF_FFFF

    def read32(self, offset: int) -> int:
        if offset == int(RegisterOffset.STATUS) and self.status_script:
            value = self.status_script.pop(0)
            self.registers[offset] = value
            return value
        if offset == int(RegisterOffset.CMD_TAIL) and self.tail_script:
            value = self.tail_script.pop(0)
            self.registers[offset] = value
            return value
        return self.registers.get(offset, 0)

    def write_host_memory(self, addr: int, data: bytes) -> None:
        for index, value in enumerate(data):
            self.host_memory[addr + index] = value

    def read_host_memory(self, addr: int, length: int) -> bytes:
        return bytes(self.host_memory.get(addr + index, 0) for index in range(length))


def test_descriptor_pack_matches_reference_helper():
    descriptor = Descriptor(
        Opcode.MATMUL,
        flags=0x47,
        dst=3,
        src=2,
        m=4,
        n=5,
        k=6,
        tag=7,
    )
    assert int(descriptor) == reference_descriptor(
        0x03,
        flags=0x47,
        dst=3,
        src=2,
        m=4,
        n=5,
        k=6,
        tag=7,
    )


def test_host_memory_image_writes_slots_and_descriptors():
    image = HostMemoryImage()
    image.write_slot(0, 5, bytes(range(16)))
    image.write_descriptors(
        DEFAULT_QUEUE_BASE,
        [Descriptor(Opcode.NOP), Descriptor(Opcode.LOAD_TILE, dst=5, m=4, n=4)],
    )

    assert image.read_bytes(5 * SLOT_BYTES, 4) == bytes([0, 1, 2, 3])
    first_descriptor = int.from_bytes(image.read_bytes(DEFAULT_QUEUE_BASE, 8), byteorder="little")
    second_descriptor = int.from_bytes(
        image.read_bytes(DEFAULT_QUEUE_BASE + 8, 8),
        byteorder="little",
    )
    assert first_descriptor == int(Descriptor(Opcode.NOP))
    assert second_descriptor == int(Descriptor(Opcode.LOAD_TILE, dst=5, m=4, n=4))


def test_runtime_run_stages_program_and_collects_outputs():
    transport = FakeTransport(
        status_script=[STATUS_BUSY, STATUS_BUSY, 0],
        tail_script=[0, 1, 1],
    )
    runtime = AttnCoreRuntime(transport)
    program = RuntimeProgram(
        descriptors=[Descriptor(Opcode.NOP)],
        input_tiles={0: b"\x01\x02\x03\x04"},
        result_slots={"attention_out": (7, 4)},
    )

    expected_output = bytes([15, 25, 24, 34])
    transport.write_host_memory(7 * SLOT_BYTES, expected_output)

    result = runtime.run(program, max_polls=8)

    assert result.outputs["attention_out"] == expected_output
    assert transport.read_host_memory(0, 4) == b"\x01\x02\x03\x04"
    assert transport.writes[:6] == [
        (int(RegisterOffset.CMD_QUEUE_BASE), DEFAULT_QUEUE_BASE),
        (int(RegisterOffset.CMD_QUEUE_SIZE), 4),
        (int(RegisterOffset.DMA_HOST_ADDR), 0),
        (int(RegisterOffset.TILE_DEFAULT_M), 64),
        (int(RegisterOffset.TILE_DEFAULT_N), 64),
        (int(RegisterOffset.TILE_DEFAULT_K), 64),
    ]
    assert transport.registers[int(RegisterOffset.CTRL)] == CTRL_ENABLE
    assert transport.registers[int(RegisterOffset.CMD_HEAD)] == 1

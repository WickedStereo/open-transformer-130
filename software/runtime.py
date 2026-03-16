"""Thin host-side runtime for the integrated ``attn_core`` profile."""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import IntEnum
from typing import Protocol, Sequence

SLOT_BYTES = 4096
DEFAULT_QUEUE_BASE = 0x0002_0000
DEFAULT_QUEUE_SIZE_LOG2 = 4


class Opcode(IntEnum):
    NOP = 0x00
    LOAD_TILE = 0x01
    STORE_TILE = 0x02
    MATMUL = 0x03
    ACCUMULATE = 0x04
    SOFTMAX = 0x05
    CONFIG = 0x06
    BARRIER = 0x07


class RegisterOffset(IntEnum):
    CTRL = 0x00
    STATUS = 0x04
    CMD_QUEUE_BASE = 0x08
    CMD_QUEUE_SIZE = 0x0C
    CMD_HEAD = 0x10
    CMD_TAIL = 0x14
    FAULT_INFO = 0x18
    TILE_DEFAULT_M = 0x1C
    TILE_DEFAULT_N = 0x20
    TILE_DEFAULT_K = 0x24
    PERF_BUSY_CYCLES = 0x28
    PERF_STALL_CYCLES = 0x2C
    PERF_DMA_BYTES = 0x30
    PERF_TILE_COUNT = 0x34
    DMA_HOST_ADDR = 0x38
    SCRATCH_BASE = 0x3C


CTRL_ENABLE = 1 << 0
CTRL_SOFT_RESET = 1 << 1
CTRL_FAULT_CLEAR = 1 << 2

STATUS_BUSY = 1 << 0
STATUS_FAULT = 1 << 1
STATUS_DMA_ACTIVE = 1 << 2
STATUS_COMPUTE_ACTIVE = 1 << 3


class RuntimeFaultError(RuntimeError):
    """Raised when the accelerator reports a decoder/runtime fault."""


def _check_range(name: str, value: int, width: int) -> int:
    max_value = (1 << width) - 1
    if value < 0 or value > max_value:
        raise ValueError(f"{name} must fit in {width} bits, got {value}")
    return value


def _coerce_payload(payload: bytes | bytearray | Sequence[int]) -> bytes:
    if isinstance(payload, bytes):
        return payload
    if isinstance(payload, bytearray):
        return bytes(payload)
    return bytes(int(value) & 0xFF for value in payload)


@dataclass(frozen=True)
class Descriptor:
    opcode: int | Opcode
    flags: int = 0
    dst: int = 0
    src: int = 0
    m: int = 0
    n: int = 0
    k: int = 0
    tag: int = 0

    def pack(self) -> int:
        return (
            (_check_range("opcode", int(self.opcode), 8) << 56)
            | (_check_range("flags", self.flags, 8) << 48)
            | (_check_range("dst", self.dst, 8) << 40)
            | (_check_range("src", self.src, 8) << 32)
            | (_check_range("m", self.m, 8) << 24)
            | (_check_range("n", self.n, 8) << 16)
            | (_check_range("k", self.k, 8) << 8)
            | (_check_range("tag", self.tag, 4) << 4)
        )

    @classmethod
    def from_word(cls, word: int) -> "Descriptor":
        return cls(
            opcode=(word >> 56) & 0xFF,
            flags=(word >> 48) & 0xFF,
            dst=(word >> 40) & 0xFF,
            src=(word >> 32) & 0xFF,
            m=(word >> 24) & 0xFF,
            n=(word >> 16) & 0xFF,
            k=(word >> 8) & 0xFF,
            tag=(word >> 4) & 0xF,
        )

    def __int__(self) -> int:
        return self.pack()


@dataclass
class HostMemoryImage:
    """Byte-addressable host-memory image for queue descriptors and DMA tiles."""

    memory: dict[int, int] = field(default_factory=dict)

    def write_bytes(self, base_addr: int, payload: bytes | bytearray | Sequence[int]) -> None:
        payload_bytes = _coerce_payload(payload)
        for index, value in enumerate(payload_bytes):
            self.memory[base_addr + index] = value

    def read_bytes(self, base_addr: int, length: int) -> bytes:
        return bytes(self.memory.get(base_addr + index, 0) for index in range(length))

    def write_slot(
        self,
        dma_host_addr: int,
        slot_id: int,
        payload: bytes | bytearray | Sequence[int],
    ) -> None:
        payload_bytes = _coerce_payload(payload)
        if len(payload_bytes) > SLOT_BYTES:
            raise ValueError(
                f"slot payload exceeds {SLOT_BYTES} bytes: slot={slot_id}, size={len(payload_bytes)}"
            )
        self.write_bytes(dma_host_addr + slot_id * SLOT_BYTES, payload_bytes)

    def write_descriptors(self, queue_base: int, descriptors: Sequence[Descriptor | int]) -> None:
        for index, descriptor in enumerate(descriptors):
            word = descriptor.pack() if isinstance(descriptor, Descriptor) else int(descriptor)
            self.write_bytes(queue_base + index * 8, word.to_bytes(8, byteorder="little"))

    def to_byte_dict(self) -> dict[int, int]:
        return dict(self.memory)


@dataclass
class RuntimeProgram:
    """Runtime staging object for a single queued workload."""

    descriptors: list[Descriptor]
    input_tiles: dict[int, bytes] = field(default_factory=dict)
    result_slots: dict[str, tuple[int, int]] = field(default_factory=dict)
    queue_base: int = DEFAULT_QUEUE_BASE
    queue_size_log2: int = DEFAULT_QUEUE_SIZE_LOG2
    dma_host_addr: int = 0
    default_dims: tuple[int, int, int] = (64, 64, 64)

    def descriptor_words(self) -> list[int]:
        return [descriptor.pack() for descriptor in self.descriptors]

    def build_memory_image(self) -> HostMemoryImage:
        image = HostMemoryImage()
        image.write_descriptors(self.queue_base, self.descriptors)
        for slot_id, payload in self.input_tiles.items():
            image.write_slot(self.dma_host_addr, slot_id, payload)
        return image


@dataclass(frozen=True)
class StatusSnapshot:
    raw: int
    queue_depth: int
    busy: bool
    fault: bool
    dma_active: bool
    compute_active: bool

    @classmethod
    def from_raw(cls, raw: int) -> "StatusSnapshot":
        return cls(
            raw=raw,
            queue_depth=(raw >> 4) & 0xF,
            busy=bool(raw & STATUS_BUSY),
            fault=bool(raw & STATUS_FAULT),
            dma_active=bool(raw & STATUS_DMA_ACTIVE),
            compute_active=bool(raw & STATUS_COMPUTE_ACTIVE),
        )


@dataclass(frozen=True)
class PerformanceSnapshot:
    busy_cycles: int
    stall_cycles: int
    dma_bytes: int
    tile_count: int


@dataclass(frozen=True)
class RuntimeResult:
    status: StatusSnapshot
    perf: PerformanceSnapshot
    outputs: dict[str, bytes]


class AcceleratorTransport(Protocol):
    def write32(self, offset: int, value: int) -> None:
        """Write a 32-bit MMIO register."""

    def read32(self, offset: int) -> int:
        """Read a 32-bit MMIO register."""

    def write_host_memory(self, addr: int, data: bytes) -> None:
        """Write a byte range into the host-visible DMA / queue memory."""

    def read_host_memory(self, addr: int, length: int) -> bytes:
        """Read a byte range from the host-visible DMA memory."""


class AttnCoreRuntime:
    """Thin runtime for queue programming, execution, and result collection."""

    def __init__(self, transport: AcceleratorTransport):
        self.transport = transport

    def write_register(self, offset: int | RegisterOffset, value: int) -> None:
        self.transport.write32(int(offset), value & 0xFFFF_FFFF)

    def read_register(self, offset: int | RegisterOffset) -> int:
        return self.transport.read32(int(offset)) & 0xFFFF_FFFF

    def write_descriptor_ring(self, queue_base: int, descriptors: Sequence[Descriptor | int]) -> None:
        for index, descriptor in enumerate(descriptors):
            word = descriptor.pack() if isinstance(descriptor, Descriptor) else int(descriptor)
            self.transport.write_host_memory(
                queue_base + index * 8,
                word.to_bytes(8, byteorder="little"),
            )

    def write_tile(
        self,
        slot_id: int,
        payload: bytes | bytearray | Sequence[int],
        *,
        dma_host_addr: int,
    ) -> None:
        payload_bytes = _coerce_payload(payload)
        if len(payload_bytes) > SLOT_BYTES:
            raise ValueError(
                f"tile payload exceeds {SLOT_BYTES} bytes: slot={slot_id}, size={len(payload_bytes)}"
            )
        self.transport.write_host_memory(dma_host_addr + slot_id * SLOT_BYTES, payload_bytes)

    def read_tile(self, slot_id: int, length: int, *, dma_host_addr: int) -> bytes:
        return self.transport.read_host_memory(dma_host_addr + slot_id * SLOT_BYTES, length)

    def configure(
        self,
        *,
        queue_base: int,
        queue_size_log2: int,
        dma_host_addr: int,
        default_dims: tuple[int, int, int] = (64, 64, 64),
    ) -> None:
        if queue_size_log2 <= 0 or queue_size_log2 > 8:
            raise ValueError(f"queue_size_log2 must be in [1, 8], got {queue_size_log2}")
        default_m, default_n, default_k = default_dims
        self.write_register(RegisterOffset.CMD_QUEUE_BASE, queue_base)
        self.write_register(RegisterOffset.CMD_QUEUE_SIZE, queue_size_log2)
        self.write_register(RegisterOffset.DMA_HOST_ADDR, dma_host_addr)
        self.write_register(RegisterOffset.TILE_DEFAULT_M, default_m)
        self.write_register(RegisterOffset.TILE_DEFAULT_N, default_n)
        self.write_register(RegisterOffset.TILE_DEFAULT_K, default_k)

    def enable(self) -> None:
        self.write_register(RegisterOffset.CTRL, CTRL_ENABLE)

    def soft_reset(self) -> None:
        self.write_register(RegisterOffset.CTRL, CTRL_SOFT_RESET)

    def clear_fault(self, *, keep_enabled: bool = True) -> None:
        ctrl_value = CTRL_FAULT_CLEAR
        if keep_enabled:
            ctrl_value |= CTRL_ENABLE
        self.write_register(RegisterOffset.CTRL, ctrl_value)

    def read_status(self) -> StatusSnapshot:
        return StatusSnapshot.from_raw(self.read_register(RegisterOffset.STATUS))

    def read_perf_counters(self) -> PerformanceSnapshot:
        return PerformanceSnapshot(
            busy_cycles=self.read_register(RegisterOffset.PERF_BUSY_CYCLES),
            stall_cycles=self.read_register(RegisterOffset.PERF_STALL_CYCLES),
            dma_bytes=self.read_register(RegisterOffset.PERF_DMA_BYTES),
            tile_count=self.read_register(RegisterOffset.PERF_TILE_COUNT),
        )

    def stage_program(self, program: RuntimeProgram) -> None:
        self.write_descriptor_ring(program.queue_base, program.descriptors)
        for slot_id, payload in program.input_tiles.items():
            self.write_tile(slot_id, payload, dma_host_addr=program.dma_host_addr)
        self.configure(
            queue_base=program.queue_base,
            queue_size_log2=program.queue_size_log2,
            dma_host_addr=program.dma_host_addr,
            default_dims=program.default_dims,
        )

    def submit(self, descriptor_count: int) -> None:
        self.enable()
        self.write_register(RegisterOffset.CMD_HEAD, descriptor_count)

    def wait_for_idle(self, *, expected_tail: int | None = None, max_polls: int = 4096) -> StatusSnapshot:
        last_status = self.read_status()
        for _ in range(max_polls):
            status = self.read_status()
            tail = self.read_register(RegisterOffset.CMD_TAIL) & 0xFF
            last_status = status
            if status.fault:
                fault_info = self.read_register(RegisterOffset.FAULT_INFO)
                raise RuntimeFaultError(
                    f"accelerator faulted: status=0x{status.raw:08x}, fault_info=0x{fault_info:08x}"
                )
            if expected_tail is not None:
                if tail >= expected_tail and not status.busy:
                    return status
            elif not status.busy and status.queue_depth == 0:
                return status
        raise TimeoutError(
            f"timed out waiting for accelerator idle after {max_polls} polls; "
            f"last status=0x{last_status.raw:08x}"
        )

    def run(self, program: RuntimeProgram, *, max_polls: int = 4096) -> RuntimeResult:
        self.stage_program(program)
        self.submit(len(program.descriptors))
        status = self.wait_for_idle(expected_tail=len(program.descriptors), max_polls=max_polls)
        perf = self.read_perf_counters()
        outputs = {
            name: self.read_tile(slot_id, length, dma_host_addr=program.dma_host_addr)
            for name, (slot_id, length) in program.result_slots.items()
        }
        return RuntimeResult(status=status, perf=perf, outputs=outputs)


__all__ = [
    "AcceleratorTransport",
    "AttnCoreRuntime",
    "CTRL_ENABLE",
    "CTRL_FAULT_CLEAR",
    "CTRL_SOFT_RESET",
    "DEFAULT_QUEUE_BASE",
    "DEFAULT_QUEUE_SIZE_LOG2",
    "Descriptor",
    "HostMemoryImage",
    "Opcode",
    "PerformanceSnapshot",
    "RegisterOffset",
    "RuntimeFaultError",
    "RuntimeProgram",
    "RuntimeResult",
    "SLOT_BYTES",
    "StatusSnapshot",
]

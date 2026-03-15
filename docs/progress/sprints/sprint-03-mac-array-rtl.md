# Sprint 03 - MAC Array RTL

Status: done

## Objective

Implement and validate the core compute datapath as reusable lane and array RTL blocks with unit-level verification and early implementation feedback.

## Deliverables

- `rtl/mac_lane.sv`
- `rtl/mac_array.sv`
- unit tests and scoreboards for multiply-accumulate behavior
- initial synthesis or lint-quality implementation snapshot

## Dependencies

- Sprint 02 compute-datapath spec
- numeric policy from Sprint 01

## Parallelization Note

RTL, numeric-reference, verification, and synthesis profiling can run together once interface definitions are frozen.

## Parallel Workstreams

### RTL implementation lane

- code `mac_lane` with valid/ready or equivalent local handshake semantics
- compose `mac_array` around the lane primitive and chosen accumulation scheme
- keep interfaces aligned with the microarchitecture spec to avoid later scheduler churn

### Numeric-reference lane

- encode the chosen rounding and saturation rules in the reference model
- generate deterministic expected results for edge cases
- record any mismatch between ideal math and hardware-friendly behavior

### Verification lane

- add directed tests for reset, zero operands, signed extremes, and accumulation boundaries
- add constrained scenarios for stalls and backpressure if present
- publish a short report on functional coverage and known gaps

### Implementation-feedback lane

- run lint and early synthesis estimates on the compute block
- capture area and timing pressure points
- feed any high-risk implementation findings back into the microarchitecture docs

## Exit Criteria

- the MAC blocks are lint-clean and pass their unit-level test plan
- numeric behavior matches the defined reference policy
- initial area or timing feedback exists for the compute datapath

## Evidence To Capture

- RTL files in `rtl/`
- unit-test results
- compute-block implementation report

## Open Risks And Decisions

- array organization may be too wide for later timing closure
- numeric edge cases may expose a need for wider accumulation than initially assumed

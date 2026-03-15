# Sprint 12 - Tapeout Preparation

Status: planned

## Objective

Freeze the design package, verify signoff evidence, and assemble all collateral required for a disciplined tapeout submission.

## Deliverables

- tapeout checklist and frozen manifests
- final regression archive and signoff evidence set
- packaged submission collateral and release notes
- bring-up preparation notes for first silicon

## Dependencies

- physical-design closure from Sprint 11
- stable Caravel integration collateral and firmware hooks

## Parallelization Note

Closure review, regression reruns, collateral packaging, and bring-up preparation can all progress in parallel near the end of the program.

## Parallel Workstreams

### Closure-review lane

- confirm timing, DRC, LVS, and any waiver decisions are fully documented
- review open risks and convert them into explicit acceptance decisions or blockers
- freeze the exact design revision for submission

### Regression lane

- rerun the final simulation, formal, and integration checks required for signoff confidence
- archive versions, commands, and outcomes
- capture any last-minute deltas from the prior milestone

### Packaging lane

- assemble the GDS, netlists, configuration files, manifests, and release metadata
- verify that all required collateral is reproducible from the tagged revision
- document ownership and storage locations for the final package

### Bring-up-prep lane

- prepare initial firmware, diagnostics, and benchmark scripts for silicon arrival
- define a first-lab checklist and debug priorities
- record known limitations that the lab team should expect

## Exit Criteria

- all submission artifacts are assembled and traceable to a frozen revision
- signoff evidence is complete enough for a deliberate go/no-go decision
- post-silicon bring-up preparation exists before fabrication wait time begins

## Evidence To Capture

- tapeout checklist
- final signoff report bundle
- release manifest and bring-up notes

## Open Risks And Decisions

- missing provenance on final artifacts can undermine submission confidence
- late-breaking backend or firmware issues can consume the remaining schedule buffer

# Vector and Softmax

## Scope

Specify the helper datapath used for reductions, normalization, nonlinear approximation, and any vector-style elementwise operations needed for attention.

## Design questions

- fully dedicated softmax hardware versus staged vector micro-ops
- approximation choice for exponentiation and normalization
- temporary storage requirements and scratchpad interaction
- acceptable numeric error bounds relative to the golden model

## Expected responsibilities

- row-wise reductions such as max and sum
- exponent or approximation pipeline
- scaling and normalization output formatting
- elementwise helper operations needed by the command set

## Evidence required

- numeric error reports against the golden model
- latency and utilization estimates for softmax-heavy workloads
- directed tests for edge cases such as saturation, large negative values, and reset behavior

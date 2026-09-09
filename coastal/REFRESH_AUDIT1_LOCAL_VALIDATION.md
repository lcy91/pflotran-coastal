# Local refresh audit 1 validation

The original local PFLOTRAN installation was not edited. A copied experimental
build was recompiled with two source changes: actual requested/applied refresh
logging and standard Fortran command argument intrinsics.

Local audit binary SHA256:
`83d456da57db5b295cd039225731c98109055bbda984a1895676f0ed9cb25ed4`.

| Case | Requested / actually applied | Exit | 24 hourly records |
| --- | --- | --- | --- |
| Historical 35047 | 0 / 0 | 88 | No |
| Historical 35047 | 8 / 8 | 0 | Yes |
| S15 35047 | 0 / 0 | 88 | No |
| S15 35047 | 8 / 8 | 0 | Yes |

Inputs remained byte-identical; each 0/8 pair used the same checkpoint SHA.
Both serial and two-rank calcite regression tests passed (2/2). Named input
files with no default pflotran.in demonstrate working input-prefix handling.
Actual applied counts are read from executable-emitted messages, not wrapper
constants. The old diagnostic refresh algorithm itself was not changed.

Earlier local launcher-only failures (sandbox socket restriction and unsupported
macOS CPU binding) are preserved in runs/ and runs_mpi/. Successful runs are
in runs_verified/. macOS uses --bind-to none; the Linux/NERSC gate uses core.

These are local 24-hour diagnostics, not a NERSC pass, accepted historical
states, full mass-conservation certification, or completed 50-year branches.
The NERSC audit binary must be built and tested separately before longer runs.

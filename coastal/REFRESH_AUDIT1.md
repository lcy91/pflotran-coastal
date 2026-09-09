# Verify restart refresh before longer CONUS runs — Chuyang Liu

Do not rebuild PETSc or overwrite the working diagnostic executable.
The new audit candidate is a separate PFLOTRAN checkout/binary. It retains the
same refresh operation and scientific inputs, adds runtime reporting, and
repairs v5.0's dependence on obsolete PETSc command-argument macros using
standard Fortran intrinsics. Two source commits separate these changes.

The old 58110470 gate established two 24-hour runs with finite hourly ledgers.
Its JSON field refresh_passes=8 was a request record, not a readback. The new
gate parses actual PFLOTRAN log records emitted before and after the loop.

## 1. Build a separate audit executable on the NERSC login node

```bash
module load cpu
module load gcc/12.2.0
module load openmpi/5.0.7
module load cmake/3.30.2
export BUILD_ROOT=/global/homes/c/cliu6/Software/pflotran-v5.0-auxrefresh1-openmpi1
export PETSC_DIR="$BUILD_ROOT/src/petsc"
export PETSC_ARCH=arch-openmpi-gnu-cpu-opt
export PFLOTRAN_DIR="$BUILD_ROOT/src/pflotran-refresh-audit1"
export PFLOTRAN_EXE_NEW="$BUILD_ROOT/bin/pflotran-coastal-refresh-audit1"
```

Confirm neither new checkout nor executable exists. Stop if either exists;
preserve it and inspect before retrying. Then clone the audit tag:

```bash
git clone --depth 1 --single-branch --branch coastal-v5.0-refresh-audit1 \
  https://github.com/lcy91/pflotran-coastal.git "$PFLOTRAN_DIR"
cd "$PFLOTRAN_DIR/src/pflotran"
set -o pipefail
make -j4 PETSC_DIR="$PETSC_DIR" PETSC_ARCH="$PETSC_ARCH" pflotran \
  2>&1 | tee "$BUILD_ROOT/audit/refresh-audit1-build.log"
printf 'build_exit=%s\n' "$?"
```

Stop on nonzero exit. On success:

```bash
cp -n pflotran "$PFLOTRAN_EXE_NEW"
cmp pflotran "$PFLOTRAN_EXE_NEW"
sha256sum "$PFLOTRAN_EXE_NEW" > "$BUILD_ROOT/audit/refresh-audit1-executable.sha256"
git -C "$PFLOTRAN_DIR" rev-parse HEAD > "$BUILD_ROOT/audit/refresh-audit1-source.txt"
```

The previous `bin/pflotran-coastal-diag1`, original Software/pflotran and all
existing results stay unchanged. Fortran standard command_argument_count
and get_command_argument replace only the obsolete macro-selected wrappers;
no model boundary/mesh/forcing or numerical solver setting is changed.

## 2. Verify the argument-reader repair with the login calcite checks

Set `COASTAL_MPIEXEC=$(command -v mpiexec)` and export it, then repeat the
Open MPI guide's step 11 in a NEW scratch directory with PFLOTRAN_DIR and
PFLOTRAN_EXE_NEW set to the audit candidate above. Require both serial and
two-rank tests to pass. Do not reuse failed test directories. This checks
-input_prefix and -successful_exit_code handling; it does not by itself
verify the restart refresh loop.

## 3. Upload and submit the controlled CONUS option test

Upload `conus_refresh_audit1_debug.tar.gz` and its `.sha256` to Norfolk scratch.
Verify the checksum, then extract into a new directory. Do not overwrite an
existing extraction. This is a different bundle from conus_openmpi_diag1_debug.

```bash
cd /pscratch/sd/c/cliu6/NERSC_notebooks/Norfolk
sha256sum -c conus_refresh_audit1_debug.tar.gz.sha256
test ! -e conus_refresh_audit1_debug && tar -xzf conus_refresh_audit1_debug.tar.gz
cd conus_refresh_audit1_debug
sbatch --export=ALL submit-refresh-audit.sh
```

One debug node, 30-minute cap, four sequential one-rank runs: the same site
35047 historical and S15 checkpoints, each with refresh 0 and 8. Each run is
24 hours. Both checkpoint copies in each pair must have identical SHA-256.
The script exports every installation path inside the job and loads the
recorded Open MPI/GCC modules. It records binary hash, source commit and
module list. No production controller or result tree is modified.

## 4. Required evidence

The actual candidate output must include:

```
SWI_REFRESH_AUDIT requested=8 supplied=T restart=T salinity_density=T
SWI_REFRESH_AUDIT applied=8
```

The control must report requested=0 and applied=0. The `applied` counter is
incremented only after each InitializeRun call returns. Each test deliberately
uses `audit_case.in`, with no `pflotran.in`, to expose the old argument bug.

`REFRESH_AUDIT_RESULT.json` passes only when all four option/prefix checks
succeed, all inputs remain unchanged, each pair shares the same checkpoint,
and both refresh-8 cases exit zero with finite, strictly increasing hourly
ledger data at every hour 1–24. A zero-pass control may fail numerically and
is preserved with its exit status; it is not automatically counted as a defect
in the audit candidate. If zero also succeeds, no benefit is inferred simply
from both endpoints passing. The four cases establish option application,
not a complete assessment of density/mass conservation or long-run stability.

Read stdout/stderr and JSON after completion. Slurm COMPLETED is insufficient.
Do not infer an option value from a wrapper's requested setting again.

## 5. Then proceed to longer CONUS validation

After the argument tests and audit gate pass on NERSC, evaluate representative
five-year histories with another restart, followed by fixed uninterrupted
50-year future branches from an accepted historical checkpoint. Those longer
runs belong in appropriate production/interactive allocations, not chained
debug jobs. Do not launch a national production wave or change its executable
until the longer restart, mass-ledger and launcher checks pass.

The audit source and tests are prepared locally. NERSC execution remains a
manual user action. Refer to the accompanying local validation report for
local results, which do not certify the NERSC binary.

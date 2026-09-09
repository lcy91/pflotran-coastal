> Superseded by the user-requested [Open MPI installation guide](NERSC_OPENMPI_INSTALL.md). Do not follow this Cray-MPICH recipe for the replacement.

# PFLOTRAN coastal: home installation, login-node compilation and quick test

Maintainer: Chuyang Liu.

**Already configured successfully? Start at step 6, not deletion or cloning.**
The required sequence is: check/remove oversubscribe (6), make PETSc (7),
export PETSc paths (8), run PETSc make check (9), make PFLOTRAN (10),
prepare the quick test (11), and run it (12). Configuration alone does not build the PETSc library or PFLOTRAN.

## Status and scope

The supplied terminal output shows build job 58107545 ran for eight minutes,
then `scancel -u cliu6` was issued. That command cancels all the user's jobs;
do not repeat it to manage one build. The expected new executable was absent.
Neither PETSc nor PFLOTRAN compilation can be certified from that transcript.
The user has explicitly authorized deletion of this interrupted installation
and reinstallation at the same path. This guide does not edit the original
`Software/petsc` or `Software/pflotran` installations.

Sources, libraries, build objects and build logs are in home. Model test files
and outputs are on scratch. New source is pinned to the published `home1` tag.
The hydrostatic SALINITY error override and opt-in restart refresh are included.
No scientific production acceptance is implied by an installation test.

NERSC permits limited-thread compilation on login nodes (example: `make -j 8`).
This guide uses four workers. PETSc runtime configuration probes may require a
short compute allocation. A direct login-node singleton test is bounded to
120 seconds and may fail because of Cray MPI initialization, independently of
solver correctness. It is not a certified NERSC singleton launch pattern.
Do not switch MPI libraries to work around that failure.

## 1. Historical cleanup — already completed; skip for the current build

The user has already completed this deletion and successfully configured the
replacement. Do not repeat it for the current build. The historical command
below removes all partial sources, dependencies and
logs within the named experimental directory. First inspect `squeue` and
confirm no active build uses this directory; do not cancel unrelated jobs.

```bash
squeue -u cliu6
```

Once no job is using it, leave the directory before deleting it:

```bash
cd /global/homes/c/cliu6/Software
rm -rf -- /global/homes/c/cliu6/Software/pflotran-v5.0-auxrefresh1-cpe2603
```

Do not substitute `Software`, `Software/petsc`, or `Software/pflotran` in this
command. Continue below to create the same experimental directory afresh.

## 2. Load the CPU compiler environment in a fresh Bash login shell

Run each section in order, and stop on any failure. Enable pipeline failure
reporting so `tee` cannot hide configure/make errors:

```bash
set -o pipefail
showquota
module load cpe/26.03
module load PrgEnv-gnu
module load cpu
module load cmake
module list
command -v cc CC ftn python3 cmake timeout
```

Confirm `module list` shows the intended CPU/GNU/Cray-MPICH environment.
The simplified setup omits the restore script and optional environment
settings at the user's request. If module loading or linking fails, preserve
the actual error for diagnosis rather than silently changing the MPI stack.
No shell startup files or original installation links are changed.

## 3. Create and clone the new installation

```bash
export BUILD_ROOT=/global/homes/c/cliu6/Software/pflotran-v5.0-auxrefresh1-cpe2603
mkdir "$BUILD_ROOT" && mkdir -p "$BUILD_ROOT/src" "$BUILD_ROOT/audit" "$BUILD_ROOT/bin"
```

If `mkdir` reports that the directory exists, stop and inspect it; do not
continue this fresh-build procedure there.

```bash
git clone --depth 1 --single-branch --branch coastal-v5.0-auxrefresh-diag1-home1 \
  https://github.com/lcy91/pflotran-coastal.git "$BUILD_ROOT/src/pflotran"
git clone --depth 1 --branch v3.21.5 \
  https://gitlab.com/petsc/petsc.git "$BUILD_ROOT/src/petsc"
export PFLOTRAN_DIR="$BUILD_ROOT/src/pflotran"
export PETSC_DIR="$BUILD_ROOT/src/petsc"
export PETSC_ARCH=arch-cpe2603-gnu-cpu-opt
export PFLOTRAN_EXE_NEW="$BUILD_ROOT/bin/pflotran-coastal-diag1"

test "$(git -C "$PFLOTRAN_DIR" rev-parse HEAD)" = 46f6841acb1a7aebf108918baca4e973a88a93ae
test "$(git -C "$PETSC_DIR" rev-parse HEAD)" = 9cffe78795669c5fbaf7ca6d864d230635faa5ef
module -t list 2> "$BUILD_ROOT/audit/modules.txt"
cc --version > "$BUILD_ROOT/audit/compiler.txt" 2>&1
ftn --version >> "$BUILD_ROOT/audit/compiler.txt" 2>&1
```

A detached HEAD is expected when using a pinned release tag.

## 4. Verify the local PFLOTRAN edits

```bash
sed -n '303,311p' "$PFLOTRAN_DIR/src/pflotran/pm_auxiliary.F90"
grep -n swi_restart_refresh_passes "$PFLOTRAN_DIR/src/pflotran/simulation_subsurface.F90"
```

These three error lines are already commented with Fortran `!`:

```fortran
!             this%option%io_buffer = 'Hydrostatic flow conditions are &
!               &currently not supported by the SALINITY process model.'
!             call PrintErrMsg(this%option)
```

The restart-refresh edit is enabled only by `-swi_restart_refresh_passes 8`.
No further source edits are needed for this guide.

## 5. Configure PETSc with runnable MPI probes (corrected)

The previous `--with-batch=1` recipe was incorrect for these dependencies.
PETSc 3.21.5 explicitly marks downloaded HDF5 as unsupported in batch-aware
configuration (and some Hypre configurations also prohibit it). The observed
`--download-hdf5 cannot be used on this batch systems` error is an option
conflict, not a compiler error. Do not delete or clone the sources again.

The user subsequently completed this `--with-batch=0` configuration on
login06, with `configure_exit=0`. No debug allocation is required by these
installation instructions. If configuration has completed, skip to step 6.
For a fresh installation, run the following on the login node:

```bash
set -o pipefail
cd "$PETSC_DIR"
python3 ./configure PETSC_ARCH="$PETSC_ARCH" \
  --with-cc=cc --with-cxx=CC --with-fc=ftn \
  '--with-mpiexec=srun --mpi=cray_shasta --cpu-bind=cores' \
  --with-batch=0 --with-debugging=0 --with-make-np=4 \
  --COPTFLAGS=-O3 --CXXOPTFLAGS=-O3 --FOPTFLAGS=-O3 \
  --download-hdf5=yes --download-hdf5-fortran-bindings=yes \
  --download-fblaslapack=yes --download-metis=yes \
  --download-parmetis=yes --download-hypre=yes \
  2>&1 | tee "$BUILD_ROOT/audit/configure-retry.log"
printf 'configure_pipeline_exit=%s\n' "$?"
```

Require exit zero and a configuration-complete message before continuing.
Successful configuration does not establish PETSc/PFLOTRAN compilation or
MPI runtime acceptance.

## 6. Explicitly remove and verify no `--oversubscribe`

This is a required check of the actual generated file, not just the
configure summary. Run after configuration and again after any reconfiguration. This edits only
the NEW installation's generated file and preserves its original contents.
The chosen `srun` launcher should already omit this Open-MPI option; in that
case this step reports zero removals and leaves the file unchanged.

```bash
python3 - <<'PY'
import os, re, shutil
from pathlib import Path
root = Path(os.environ['BUILD_ROOT']).resolve()
p = Path(os.environ['PETSC_DIR']) / os.environ['PETSC_ARCH'] / 'lib/petsc/conf/petscvariables'
assert root in p.resolve().parents, 'Refuse to edit outside the new build'
s = p.read_text()
clean, count = re.subn(r'(?<!\S)--oversubscribe(?=\s|$)', '', s)
assert '--oversubscribe' not in clean, 'Unexpected option spelling; inspect manually'
if count:
    backup = p.with_name('petscvariables.before-oversubscribe-removal')
    assert not backup.exists(), 'Backup exists; inspect before changing again'
    shutil.copy2(str(p), str(backup))
    p.write_text(clean)
print('Removed --oversubscribe occurrences:', count)
print('Verified absent:', p)
PY
grep -nE '^(MPIEXEC|MPIEXEC_FLAGS)[[:space:]]*=' \
  "$PETSC_DIR/$PETSC_ARCH/lib/petsc/conf/petscvariables"
```

Keep `MPIEXEC` as `srun ...`; do not substitute the old Open-MPI launcher.

## 7. Build PETSc: make all

Run one command at a time and stop on any nonzero exit:

```bash
set -o pipefail
cd "$PETSC_DIR"
make PETSC_DIR="$PETSC_DIR" PETSC_ARCH="$PETSC_ARCH" -j4 all \
  2>&1 | tee "$BUILD_ROOT/audit/petsc-build.log"
printf 'petsc_build_exit=%s\n' "$?"
```

Stop if the PETSc build exit is nonzero.

## 8. Export PETSc paths after make

After a successful build, explicitly
export the PETSc paths for the subsequent PFLOTRAN build:

```bash
export PETSC_DIR=/global/homes/c/cliu6/Software/pflotran-v5.0-auxrefresh1-cpe2603/src/petsc
export PETSC_ARCH=arch-cpe2603-gnu-cpu-opt
```

## 9. Check PETSc: make check

Run PETSc's own installation check before compiling PFLOTRAN:

```bash
cd "$PETSC_DIR"
set -o pipefail
make PETSC_DIR="$PETSC_DIR" PETSC_ARCH="$PETSC_ARCH" check \
  2>&1 | tee "$BUILD_ROOT/audit/petsc-check.log"
printf 'petsc_check_exit=%s\n' "$?"
```

Require exit zero and passing test output. This is separate from PFLOTRAN's
calcite regression test below. Compilation alone does not replace this check.

**Launcher distinction:** the configured MPIEXEC is `/usr/bin/srun
--mpi=cray_shasta --cpu-bind=cores`. Thus, although `make check` is entered
from the login terminal, its MPI tests use Slurm; they are not guaranteed to
execute directly on the login node. Without an allocation, srun may request
resources or report missing job options. If that happens, retain the error;
do not replace MPIEXEC with a dummy command or declare the tests passed.
The separate allocation procedure in step 13 can run the same check if needed.

The exports in step 8 repeat earlier settings for clarity. Make command-line assignments
do not export variables into the parent shell; prior exports persist within
the same shell. Recheck the generated file before building PFLOTRAN:

```bash
python3 - <<'PY'
import os
from pathlib import Path
p = Path(os.environ['PETSC_DIR']) / os.environ['PETSC_ARCH'] / 'lib/petsc/conf/petscvariables'
assert '--oversubscribe' not in p.read_text(), 'Repeat the removal in step 6'
print('Verified no --oversubscribe:', p)
PY
```

## 10. Build PFLOTRAN: make pflotran

Only after the check succeeds:

```bash
cd "$PFLOTRAN_DIR/src/pflotran"
make PETSC_DIR="$PETSC_DIR" PETSC_ARCH="$PETSC_ARCH" -j4 pflotran \
  2>&1 | tee "$BUILD_ROOT/audit/pflotran-build.log"
printf 'pflotran_build_exit=%s\n' "$?"
```

Stop on a nonzero build exit. On success:

```bash
test -x pflotran
if test -e "$PFLOTRAN_EXE_NEW"; then
  cmp pflotran "$PFLOTRAN_EXE_NEW"
else
  cp pflotran "$PFLOTRAN_EXE_NEW"
fi
cmp pflotran "$PFLOTRAN_EXE_NEW"
sha256sum "$PFLOTRAN_EXE_NEW" | tee "$BUILD_ROOT/audit/executable.sha256"
ldd "$PFLOTRAN_EXE_NEW" | tee "$BUILD_ROOT/audit/ldd.txt"
showquota
du -sh "$BUILD_ROOT"
```

Stop if either `cmp` reports different files; preserve the existing binary
and choose a new executable name before proceeding. Do not test a stale copy.
Stop if `ldd` reports missing libraries or unexpected Open-MPI linkage.
Compilation is only confirmed after both make commands exit successfully and
the executable exists. Do not run the old all-in-one build script in parallel.

## 11. Prepare the quick test

This is the upstream 20-cell calcite installation test, not a coastal
historical acceptance or restart-continuity test. Preserve its inputs and gold
reference. Use a unique temporary directory and the original relative layout.
Stop if mktemp or its directory check fails:

```bash
TEST_ROOT=$(mktemp -d /pscratch/sd/c/cliu6/NERSC_notebooks/Norfolk/pflotran-login-smoke.XXXXXX)
export TEST_ROOT
test -n "$TEST_ROOT" && test -d "$TEST_ROOT"
export TEST_CASE="$TEST_ROOT/regression_tests/ascem/1d/1d-calcite"
mkdir -p "$TEST_CASE" "$TEST_ROOT/database"
cp "$PFLOTRAN_DIR"/regression_tests/ascem/1d/1d-calcite/* "$TEST_CASE/"
cp "$PFLOTRAN_DIR/database/hanford.dat" "$TEST_ROOT/database/"
printf '%s\n' "$TEST_ROOT" | tee "$BUILD_ROOT/audit/latest-smoke-path.txt"
```

## 12. Run the quick test on the login node

Run only one test instance for at most two minutes. This simplified setup
does not force library thread counts; stop the test if it consumes excessive
login-node resources:

```bash
cd "$TEST_ROOT"
timeout --signal=TERM --kill-after=5s 120s \
  python3 "$PFLOTRAN_DIR/regression_tests/regression_tests.py" \
  -e "$PFLOTRAN_EXE_NEW" --suite standard \
  --config-files "$TEST_CASE/1d-calcite.cfg" \
  > "$TEST_ROOT/login-test.log" 2>&1
TEST_RC=$?
printf 'login_test_exit=%s\n' "$TEST_RC"
cat "$TEST_ROOT/login-test.log"
```

Require runner exit zero and a reported passing test. Exit 124 indicates a
time limit. A PMI/libfabric/MPI startup error is not proof of solver failure.
Do not unset rank variables or swap MPI libraries speculatively. This direct
singleton attempt is unvalidated on this stack; stop after a failure.

For a failed singleton attempt, preserve its directory and repeat step 11 to
create a NEW test directory. Then use the supported one-rank compute launch:

```bash
cat > "$TEST_ROOT/launch-one.sh" <<'SH'
#!/bin/bash
exec srun --account=m2398 --constraint=cpu --qos=debug \
  --nodes=1 --ntasks=1 --cpus-per-task=1 --time=00:05:00 \
  --mpi=cray_shasta --cpu-bind=cores "$PFLOTRAN_EXE_NEW" "$@"
SH
chmod +x "$TEST_ROOT/launch-one.sh"
cd "$TEST_ROOT"
python3 "$PFLOTRAN_DIR/regression_tests/regression_tests.py" \
  -e "$TEST_ROOT/launch-one.sh" --suite standard \
  --config-files "$TEST_CASE/1d-calcite.cfg" \
  2>&1 | tee "$TEST_ROOT/debug-test.log"
```

The regression runner may impose its own timeout while waiting in the queue;
inspect a timeout rather than declaring a solver failure. Do not chain debug
jobs. Multi-rank PETSc checks and coastal tests remain required separately.

## 13. Allocation fallback for PETSc make check (only if needed)

If step 9 already passed, do not repeat it. If it could not launch MPI tests
without an allocation, this runs that same check with allocated resources.
From the login terminal:

```bash
salloc --account=m2398 --constraint=cpu --qos=debug \
  --nodes=1 --ntasks=4 --time=00:10:00
```

After allocation is granted, in its shell with the same exported paths/modules:

```bash
cd "$PETSC_DIR"
make PETSC_DIR="$PETSC_DIR" PETSC_ARCH="$PETSC_ARCH" check \
  2>&1 | tee "$BUILD_ROOT/audit/petsc-check.log"
exit
```

The PETSc-generated `MPIEXEC=srun ...` launches the test executables on the
allocated node. Do not treat `make check` as a completed coastal-science gate.

## 14. Complete PFLOTRAN installation check: serial AND two-rank tests

The original instructions ended with:

```bash
export PFLOTRAN_DIR="$BUILD_ROOT/src/pflotran"
cd "$PFLOTRAN_DIR/regression_tests"
make check
```

This is a reference to the original command, not an extra command to run
alongside the procedure below. In PFLOTRAN v5.0 it selects `standard` and
`standard_parallel` from the calcite configuration. The quick test in step
12 covers only the serial test; it does not replace this complete check.

Two implementation details matter in this exact version:

- The regression makefile prefixes its Python command with `-`, so make can
  ignore a failed test command. Require the regression runner's actual result.
- The runner treats `--mpiexec` as one executable path and appends `-np N`.
  Passing the full `srun --mpi=...` command as that path is incorrect. The
  supplied `coastal/mpi-test-launch.sh` translates `-np N` to Slurm arguments.

For the complete check, repeat step 11 to create a NEW scratch test directory,
then use a short allocation for the two-rank MPI test. This validates MPI
runtime behavior; it is not an installation/build allocation.

```bash
salloc --account=m2398 --constraint=cpu --qos=debug \
  --nodes=1 --ntasks=2 --time=00:10:00
```

Once granted, run the same two suites selected by `make check`, directly via
the runner so its exit code is visible. The serial wrapper uses `srun -n 1`;
the MPI wrapper uses the requested two ranks. Both wrappers are in the pinned
tag, and the serial wrapper uses `$BUILD_ROOT/bin/pflotran-coastal-diag1`.

```bash
cd "$TEST_ROOT"
set -o pipefail
python3 "$PFLOTRAN_DIR/regression_tests/regression_tests.py" \
  -e "$PFLOTRAN_DIR/coastal/serial-test-launch.sh" \
  --suite standard --config-files "$TEST_CASE/1d-calcite.cfg" \
  2>&1 | tee "$TEST_ROOT/pflotran-check-serial.log"
printf 'pflotran_serial_check_exit=%s\n' "$?"
```

Require zero and a pass before continuing:

```bash
python3 "$PFLOTRAN_DIR/regression_tests/regression_tests.py" \
  -e "$PFLOTRAN_EXE_NEW" \
  --mpiexec "$PFLOTRAN_DIR/coastal/mpi-test-launch.sh" \
  --suite standard_parallel --config-files "$TEST_CASE/1d-calcite.cfg" \
  2>&1 | tee "$TEST_ROOT/pflotran-check-parallel.log"
printf 'pflotran_parallel_check_exit=%s\n' "$?"
```

Require zero, a pass, and no skipped parallel test. Release this allocation:

```bash
exit
```

If only the login quick test has passed, record the parallel installation
check as pending. Do not describe it as completed. These calcite tests use
the default restart-refresh setting and do not exercise the coastal patch.
Separate coastal historical/future restart tests with
`-swi_restart_refresh_passes 8` are still required before production use.

## Comparison with the original installation recipe

| Original action | Current equivalent |
| --- | --- |
| GCC/OpenMPI/CMake modules | CPE 26.03 + PrgEnv-gnu + cpu + cmake, as requested |
| PETSc v3.21.5 checkout | Same version, exact commit checked |
| mpicc/mpicxx/mpif90 | cc/CC/ftn Cray compiler wrappers for the new MPI stack |
| Optimization -O3 | COPTFLAGS/CXXOPTFLAGS/FOPTFLAGS=-O3 |
| HDF5 with Fortran, BLAS/LAPACK, METIS, ParMETIS, Hypre | All retained; configure output confirms dependencies |
| Download CMake | Intentionally omitted; loaded CMake 3.30.2 supplies it |
| Delete --oversubscribe | Explicit backup/removal/verification of new petscvariables, step 6 |
| PETSc make all | Step 7 |
| Export PETSC_DIR/PETSC_ARCH after make | Step 8 |
| PETSc make check | Step 9 (allocation fallback only if needed) |
| PFLOTRAN v5.0 checkout | Pinned downstream based on exact upstream v5.0 |
| Comment hydrostatic SALINITY error | Included and inspected in step 4 |
| Local restart-density diagnostic | Included, opt-in; not enabled by the basic calcite test |
| PFLOTRAN make pflotran | Step 10 |
| Export PFLOTRAN_DIR | Step 3 and explicitly shown again in step 14 |
| PFLOTRAN regression_tests/make check | Both suites restored in step 14, with reliable error reporting |
| Original installations | Preserved; all new build paths are isolated |

## Future sessions

```bash
export BUILD_ROOT=/global/homes/c/cliu6/Software/pflotran-v5.0-auxrefresh1-cpe2603
export PFLOTRAN_DIR="$BUILD_ROOT/src/pflotran"
export PETSC_DIR="$BUILD_ROOT/src/petsc"
export PETSC_ARCH=arch-cpe2603-gnu-cpu-opt
export PFLOTRAN_EXE_NEW="$BUILD_ROOT/bin/pflotran-coastal-diag1"
```

Reload the same modules before using this executable. The existing Open-MPI
GNU Parallel controller is not validated for this Cray-MPICH binary. Perform
coastal restart and full 50-year tests before production replacement.

## References and validation status

- https://docs.nersc.gov/policies/resource-usage/
- https://docs.nersc.gov/development/programming-models/mpi/cray-mpich/
- https://petsc.org/release/install/install/
- PETSc 3.21.5 `config/BuildSystem/config/packages/HDF5.py` and
  `config/BuildSystem/config/framework.py`: inspected for the batch-download
  restriction. Configuration uses `--with-batch=0`; successful login-node
  configuration was reported by the user.

User evidence confirms login-node configuration succeeded. Compilation and
runtime acceptance still require their own successful logs.

# PFLOTRAN coastal: home installation, login-node compilation and quick test

Maintainer: Chuyang Liu.

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

## 1. Delete only the interrupted installation, then reuse its path

User-authorized deletion: this removes all partial sources, dependencies and
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

Preserve the failed configure log before retrying, if present:

```bash
cd "$PETSC_DIR"
if test -f configure.log; then
  cp configure.log "$BUILD_ROOT/audit/configure-batch-rejected-$(date +%Y%m%dT%H%M%S).log"
fi
salloc --account=m2398 --constraint=cpu --qos=debug \
  --nodes=1 --ntasks=4 --time=00:30:00
```

Wait for the allocation to be granted. Run the following in its shell.
Configuration builds downloaded dependencies too, so it may take more than a
few minutes. Completion within 30 minutes is not guaranteed. No regular-QOS
job is required. This configuration stage needs an allocation so its `srun`
MPI probes can execute; after it succeeds, the main PETSc and PFLOTRAN make
commands in step 7 can run on the login node.

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

Require exit zero and a configuration-complete message. Stop on errors or
allocation timeout and inspect the log; do not chain debug jobs or proceed
to make with an incomplete configuration. Do not run conftest/reconfigure
commands from the previous batch-aware recipe.

After successful configuration, leave the allocation shell:

```bash
exit
```

Back in the login shell, check the generated file, then continue with step 6:

```bash
test -f "$PETSC_DIR/$PETSC_ARCH/lib/petsc/conf/petscvariables"
```

The corrected recipe still requires NERSC validation. Keep dependency build
failures and MPI startup failures distinct when inspecting logs.

## 6. Explicitly remove and verify no `--oversubscribe`

Run after configuration and again after any reconfiguration. This edits only
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

## 7. Compile PETSc, then PFLOTRAN on the login node

Run one command at a time and stop on any nonzero exit:

```bash
cd "$PETSC_DIR"
make PETSC_DIR="$PETSC_DIR" PETSC_ARCH="$PETSC_ARCH" -j4 all \
  2>&1 | tee "$BUILD_ROOT/audit/petsc-build.log"

cd "$PFLOTRAN_DIR/src/pflotran"
make PETSC_DIR="$PETSC_DIR" PETSC_ARCH="$PETSC_ARCH" -j4 pflotran \
  2>&1 | tee "$BUILD_ROOT/audit/pflotran-build.log"

test -x pflotran
cp -n pflotran "$PFLOTRAN_EXE_NEW"
sha256sum "$PFLOTRAN_EXE_NEW" | tee "$BUILD_ROOT/audit/executable.sha256"
ldd "$PFLOTRAN_EXE_NEW" | tee "$BUILD_ROOT/audit/ldd.txt"
showquota
du -sh "$BUILD_ROOT"
```

Stop if `ldd` reports missing libraries or unexpected Open-MPI linkage.
Compilation is only confirmed after both make commands exit successfully and
the executable exists. Do not run the old all-in-one build script in parallel.

## 8. Stage a tiny regression case on scratch

This is the upstream 20-cell calcite installation test, not a coastal
historical acceptance or restart-continuity test. Preserve its inputs and gold
reference. Use a unique temporary directory and the original relative layout:

```bash
export TEST_ROOT=$(mktemp -d /pscratch/sd/c/cliu6/NERSC_notebooks/Norfolk/pflotran-login-smoke.XXXXXX)
export TEST_CASE="$TEST_ROOT/regression_tests/ascem/1d/1d-calcite"
mkdir -p "$TEST_CASE" "$TEST_ROOT/database"
cp "$PFLOTRAN_DIR"/regression_tests/ascem/1d/1d-calcite/* "$TEST_CASE/"
cp "$PFLOTRAN_DIR/database/hanford.dat" "$TEST_ROOT/database/"
printf '%s\n' "$TEST_ROOT" | tee "$BUILD_ROOT/audit/latest-smoke-path.txt"
```

## 9. One bounded direct login-node test

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

For a failed singleton attempt, preserve its directory and repeat step 8 to
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

## 10. PETSc installation check on a short compute allocation

From the login terminal, request an allocation for the MPI checks:

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
  restriction. Configuration now uses `--with-batch=0` in an allocation.

This is a prepared procedure, not evidence of a completed NERSC installation.

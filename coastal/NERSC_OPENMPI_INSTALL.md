# PFLOTRAN coastal — Open MPI home build

Maintainer: Chuyang Liu. This supersedes the Cray-MPICH installation guide.
The user authorized deleting only the experimental CPE build and rebuilding
with Open MPI. No remote deletion or compilation has been performed by the
assistant. Original `Software/petsc` and `Software/pflotran` remain intact.

Run sections in order in a login shell; stop on any failure. Compilation uses
four workers. Small installation tests are separate from production models.

## 1. Delete the superseded experimental build

Check that no active process/job uses the directory, then leave it and delete
exactly the authorized path. This deletes its build logs as well.

```bash
squeue -u cliu6
```

After checking:

```bash
cd /global/homes/c/cliu6/Software
rm -rf -- /global/homes/c/cliu6/Software/pflotran-v5.0-auxrefresh1-cpe2603
```

## 2. Select Open MPI, matching the original compiler approach

```bash
module reset
module load cpu
module load gcc/12.2.0
module load openmpi
module load cmake
module list
command -v mpicc mpicxx mpif90 mpiexec
mpicc --showme:version
mpif90 --showme:command
mpiexec --version
```

Stop if any requested module is unavailable or the wrappers are not Open MPI.
The old installation used Open MPI 5.0.3; the unversioned module may select a
different release today. Record the actual version; require Open MPI 5.x or
newer for the currently supported Perlmutter Slingshot path. Do not silently
load Cray MPICH afterward or use `cc`, `CC`, `ftn` for this recipe. No CPE
26.03 version is forced. The configure command retains `--download-cmake=yes` to match the user
recipe, although the loaded CMake may already be sufficient.

## 3. Create a distinctly named installation and clone sources

```bash
set -o pipefail
export BUILD_ROOT=/global/homes/c/cliu6/Software/pflotran-v5.0-auxrefresh1-openmpi1
mkdir "$BUILD_ROOT"
mkdir -p "$BUILD_ROOT/src" "$BUILD_ROOT/bin" "$BUILD_ROOT/audit"
```

If the directory exists, stop and inspect it; do not delete or overwrite it.

```bash
git clone --depth 1 --single-branch --branch coastal-v5.0-auxrefresh-diag1-home1 \
  https://github.com/lcy91/pflotran-coastal.git "$BUILD_ROOT/src/pflotran"
git clone --depth 1 --branch v3.21.5 \
  https://gitlab.com/petsc/petsc.git "$BUILD_ROOT/src/petsc"
export PETSC_DIR="$BUILD_ROOT/src/petsc"
export PETSC_ARCH=arch-openmpi-gnu-cpu-opt
export PFLOTRAN_DIR="$BUILD_ROOT/src/pflotran"
export PFLOTRAN_EXE_NEW="$BUILD_ROOT/bin/pflotran-coastal-diag1"
export COASTAL_MPIEXEC=$(command -v mpiexec)
test -x "$COASTAL_MPIEXEC"
module -t list 2> "$BUILD_ROOT/audit/modules.txt"
mpiexec --version > "$BUILD_ROOT/audit/mpi-version.txt"
mpicc --showme > "$BUILD_ROOT/audit/mpicc.txt"
mpif90 --showme > "$BUILD_ROOT/audit/mpif90.txt"
test "$(git -C "$PETSC_DIR" rev-parse HEAD)" = 9cffe78795669c5fbaf7ca6d864d230635faa5ef
test "$(git -C "$PFLOTRAN_DIR" rev-parse HEAD)" = 46f6841acb1a7aebf108918baca4e973a88a93ae
```

The tag name contains `home1` but its Fortran source is independent of MPI.
Do not execute its `coastal/*cpe2603*` scripts or Cray launcher wrappers.

## 4. Verify both source edits

```bash
sed -n '303,311p' "$PFLOTRAN_DIR/src/pflotran/pm_auxiliary.F90"
grep -n swi_restart_refresh_passes "$PFLOTRAN_DIR/src/pflotran/simulation_subsurface.F90"
```

The three hydrostatic SALINITY error lines must begin with `!`. The diagnostic
refresh remains opt-in via `-swi_restart_refresh_passes 8`; default is zero.

## 5. Configure fresh PETSc/dependencies with Open MPI on the login node

```bash
cd "$PETSC_DIR"
./configure \
  --CFLAGS='-O3' --CXXFLAGS='-O3' --FFLAGS='-O3' \
  --with-cc=mpicc --with-cxx=mpicxx --with-fc=mpif90 \
  --with-debugging=no \
  --download-hdf5=yes --download-hdf5-fortran-bindings=yes \
  --download-fblaslapack=yes --download-metis=yes \
  --download-parmetis=yes --download-hypre=yes --download-cmake=yes \
  2>&1 | tee "$BUILD_ROOT/audit/configure-openmpi.log"
printf 'configure_exit=%s\n' "$?"
```

Require exit zero and configuration complete. Dependencies are rebuilt from
source against Open MPI; do not reuse the deleted Cray-MPICH libraries.

## 6. Explicitly remove --oversubscribe and verify the real launcher

PETSc may add this flag when detecting Open MPI. This step backs up the
actual generated file if a change is needed, removes the flag, and verifies
that MPIEXEC points to the Open MPI launcher selected above, not srun.

```bash
python3 - <<'PY'
import os, re, shutil
from pathlib import Path
root = Path(os.environ['BUILD_ROOT']).resolve()
p = Path(os.environ['PETSC_DIR']) / os.environ['PETSC_ARCH'] / 'lib/petsc/conf/petscvariables'
assert root in p.resolve().parents
s = p.read_text()
clean, count = re.subn(r'(?<!\S)--oversubscribe(?=\s|$)', '', s)
assert '--oversubscribe' not in clean, 'Unexpected spelling: inspect file'
if count:
    backup = p.with_name('petscvariables.before-oversubscribe-removal')
    assert not backup.exists(), 'Backup exists: inspect before editing again'
    shutil.copy2(str(p), str(backup))
    p.write_text(clean)
m = re.search(r'^MPIEXEC\s*=\s*(.+)$', clean, re.M)
assert m, 'MPIEXEC missing'
assert m.group(1).strip() == os.environ['COASTAL_MPIEXEC'], m.group(1)
print('Removed occurrences:', count)
print('Verified MPIEXEC:', m.group(1).strip())
PY
```

Stop if verification fails. Repeat after any reconfiguration.

## 7. Build PETSc

```bash
cd "$PETSC_DIR"
make -j4 PETSC_DIR="$PETSC_DIR" PETSC_ARCH="$PETSC_ARCH" all \
  2>&1 | tee "$BUILD_ROOT/audit/petsc-build.log"
printf 'petsc_build_exit=%s\n' "$?"
```

Require exit zero before continuing.

## 8. Export PETSc paths AFTER make

```bash
export PETSC_DIR=/global/homes/c/cliu6/Software/pflotran-v5.0-auxrefresh1-openmpi1/src/petsc
export PETSC_ARCH=arch-openmpi-gnu-cpu-opt
```

## 9. Run PETSc make check

```bash
cd "$PETSC_DIR"
make PETSC_DIR="$PETSC_DIR" PETSC_ARCH="$PETSC_ARCH" check \
  2>&1 | tee "$BUILD_ROOT/audit/petsc-check.log"
printf 'petsc_check_exit=%s\n' "$?"
```

Require zero and no example failures. MPIEXEC now uses Open MPI directly,
without srun. If MPI startup or slot allocation fails, stop and retain the
error; do not restore oversubscribe or replace the launcher with a dummy.
This new environment has not yet been runtime-tested at NERSC.

## 10. Build PFLOTRAN

```bash
export PFLOTRAN_DIR="$BUILD_ROOT/src/pflotran"
cd "$PFLOTRAN_DIR/src/pflotran"
make -j4 PETSC_DIR="$PETSC_DIR" PETSC_ARCH="$PETSC_ARCH" pflotran \
  2>&1 | tee "$BUILD_ROOT/audit/pflotran-build.log"
printf 'pflotran_build_exit=%s\n' "$?"
```

Require zero. Then copy and verify the new binary:

```bash
if test -e "$PFLOTRAN_EXE_NEW"; then
  cmp pflotran "$PFLOTRAN_EXE_NEW"
else
  cp pflotran "$PFLOTRAN_EXE_NEW"
fi
cmp pflotran "$PFLOTRAN_EXE_NEW"
sha256sum "$PFLOTRAN_EXE_NEW" | tee "$BUILD_ROOT/audit/executable.sha256"
ldd "$PFLOTRAN_EXE_NEW" | tee "$BUILD_ROOT/audit/ldd.txt"
showquota
```

Stop on a mismatched binary, missing libraries or unexpected Cray-MPICH
linkage. Do not test a stale binary or copy over one silently.

## 11. PFLOTRAN quick installation check: serial and two ranks

The original `cd "$PFLOTRAN_DIR/regression_tests"; make check` selects both
calcite suites. Run the same suites directly below to preserve error status:
the v5.0 makefile can ignore the regression runner's nonzero exit. Keep test
outputs on scratch, with the original relative database layout:

```bash
TEST_ROOT=$(mktemp -d /pscratch/sd/c/cliu6/NERSC_notebooks/Norfolk/pflotran-openmpi-smoke.XXXXXX)
export TEST_ROOT
test -n "$TEST_ROOT" && test -d "$TEST_ROOT"
```

Stop if directory creation failed. Then:

```bash
TEST_CASE="$TEST_ROOT/regression_tests/ascem/1d/1d-calcite"
mkdir -p "$TEST_CASE" "$TEST_ROOT/database"
cp "$PFLOTRAN_DIR"/regression_tests/ascem/1d/1d-calcite/* "$TEST_CASE/"
cp "$PFLOTRAN_DIR/database/hanford.dat" "$TEST_ROOT/database/"
cd "$TEST_ROOT"
timeout --signal=TERM --kill-after=5s 240s \
  python3 "$PFLOTRAN_DIR/regression_tests/regression_tests.py" \
  -e "$PFLOTRAN_EXE_NEW" --mpiexec "$COASTAL_MPIEXEC" \
  --suite standard standard_parallel --config-files "$TEST_CASE/1d-calcite.cfg" \
  > "$TEST_ROOT/pflotran-check.log" 2>&1
printf 'pflotran_check_exit=%s\n' "$?"
cat "$TEST_ROOT/pflotran-check.log"
```

Require exit zero, both tests passed and no skipped parallel test. These are
small installation tests; stop if they hang or consume excessive login-node
resources. They do not validate the coastal restart patch or production runs.
Use the diagnostic option explicitly in separate coastal restart tests.

## Later shells and provenance

Reload the exact GCC/Open MPI/CMake versions recorded in `audit/modules.txt`,
then export BUILD_ROOT, PETSC_DIR, PETSC_ARCH, PFLOTRAN_DIR and
PFLOTRAN_EXE_NEW as above. Do not change global startup files or original
installation paths. Do not carry old Cray launcher scripts into this build.

Source-only changes remain on the public repository under Chuyang Liu's
identity. No new NERSC compilation or test pass is claimed by this document.

References:
- https://docs.nersc.gov/development/programming-models/mpi/openmpi/
- https://docs.nersc.gov/policies/resource-usage/
- https://petsc.org/release/install/install/

## Current reported installation evidence and additional CONUS debug test

User transcript confirms PETSc build exit 0; PETSc C/C++ one/two-rank,
HYPRE, HDF5 and Fortran checks succeeded; PFLOTRAN build exit 0; copied
binary matches the built binary. Its SHA-256 is
`ac45879212d37bca11a838019e8f14c2484bde1db8b33363f144c94ba5bd9188`.
ldd resolves the new PETSc and Open MPI 5.0.7 dependencies without missing
entries. Compiler warnings are retained; this is not proof of scientific
correctness. The login PFLOTRAN test command returned but its log/pass status
was not included. Inspect, without rerunning:

```bash
cat /pscratch/sd/c/cliu6/NERSC_notebooks/Norfolk/pflotran-openmpi-smoke.jMKYrF/pflotran-check.log
```

Additional manual-upload bundle: `deploy/conus_openmpi_diag1_debug.tar.gz`
and its adjacent SHA-256 file. After uploading to Norfolk scratch:

```bash
cd /pscratch/sd/c/cliu6/NERSC_notebooks/Norfolk
sha256sum -c conus_openmpi_diag1_debug.tar.gz.sha256
test ! -e conus_openmpi_diag1_debug && tar -xzf conus_openmpi_diag1_debug.tar.gz
cd conus_openmpi_diag1_debug
sbatch --export=ALL submit-conus-openmpi-debug.sh
```

Stop if the extraction destination already exists; do not extract over results.
The job script explicitly exports BUILD_ROOT, PETSC_DIR, PETSC_ARCH,
PFLOTRAN_DIR, PFLOTRAN_EXE_NEW and COASTAL_MPIEXEC after loading pinned modules.
It pins the reported binary checksum and runs two sequential one-rank CONUS
24-hour restart tests (historical and S15) with `-swi_restart_refresh_passes 8`.
All inputs/results are isolated in scratch. Checkpoints are diagnostic states,
not accepted histories. Require both per-case DIAGNOSTIC_PASS.json files and
TWO_CASE_GATE_PASSED.json. The ledger checker verifies finite entries, strictly
increasing times, every hour 1–24 and the 24-hour endpoint. Inputs are checksum
verified before/after each run. Inspect stderr and accounting as well:

```bash
# Replace JOBID with the submitted debug job number.
sacct -j JOBID --format=JobID,State,Elapsed,AllocCPUS,TotalCPU,ExitCode
seff JOBID
tail -n 50 conus_openmpi_JOBID.out
tail -n 50 conus_openmpi_JOBID.err
```

This gate is not a fresh spinup, historical acceptance, a 50-year future run,
or sustained 128-core validation. No new NERSC debug run has yet been submitted
by the assistant. Do not use smoke-cpe2603.slurm for this Open MPI installation.

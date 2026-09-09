# Separate Perlmutter CPU installation — Chuyang Liu

For the newer user-requested login-node compilation procedure, see
[NERSC_LOGIN_INSTALL.md](NERSC_LOGIN_INSTALL.md). It preserves the interrupted
build and includes explicit oversubscribe removal and a bounded login test.

This recipe creates a new experimental installation. It does not modify
`/global/homes/c/cliu6/Software/petsc`,
`/global/homes/c/cliu6/Software/pflotran`, the older Open-MPI build, shell
startup files, production job scripts, or existing results.

CPE 26.03 is listed in NERSC's August 2026 environment update. Use its Cray
compiler wrappers and Cray MPICH, not a mixture with Open MPI. CMake is a
build tool; loading it does not select an MPI library. PFLOTRAN itself uses
make; PETSc downloads/builds its needed libraries.

## 1. Start a fresh NERSC login shell and inspect modules

```bash
showquota
module reset
module load cpe/26.03
module load PrgEnv-gnu
module load cpu
module load cmake
module list
command -v cc CC ftn cmake python3
cc --version
ftn --version
srun --mpi=list
```

Confirm `cray-mpich` is loaded, Open MPI is absent, and `cray_shasta` is
available. If `module reset` reports that a previous CPE needs its restore
script, follow the exact restore path printed by Lmod, then start this step
again. Do not copy the old 24.07 restore path blindly. If a requested module
is unavailable, stop and record `module spider cpe/26.03`; do not silently
substitute a different compiler stack.

## 2. Create an isolated home Software directory and clone pinned sources

```bash
export BUILD_ROOT=/global/homes/c/cliu6/Software/pflotran-v5.0-auxrefresh1-cpe2603
if test -e "$BUILD_ROOT"; then
  echo 'Directory already exists: choose a new BUILD_ROOT; do not overwrite it.'
else
  mkdir -p "$BUILD_ROOT/src"
fi
```

Proceed only with a newly created directory:

```bash
git clone --branch coastal-v5.0-auxrefresh-diag1-home1 --depth 1 --single-branch \
  https://github.com/lcy91/pflotran-coastal.git "$BUILD_ROOT/src/pflotran"
git clone --branch v3.21.5 --depth 1 \
  https://gitlab.com/petsc/petsc.git "$BUILD_ROOT/src/petsc"
git -C "$BUILD_ROOT/src/pflotran" rev-parse HEAD
git -C "$BUILD_ROOT/src/petsc" rev-parse HEAD
```

The PETSc commit must be `9cffe78795669c5fbaf7ca6d864d230635faa5ef`.
Record the PFLOTRAN release-tag commit. A tag identifies the source; the build
also records exact compiler/module versions and executable checksum. Keep
these records because CPE module dependencies can change over time.

The latest user-reported home quota is 24.47 GiB / 40 GiB and 684.83K /
1.00M inodes: approximately 15.53 GiB and 315K inodes remain. These are
available headroom, not a measured build-space requirement. Use `showquota`
before and after building; shallow clones reduce unnecessary Git history.
Sources, compiled dependencies, executable and build audit stay under this
new home directory. Keep this directory in place because shared libraries
may contain absolute paths. The existing `Software/petsc` and
`Software/pflotran` directories are never build targets.

Model smoke tests and production outputs remain on scratch. Small installation
regression outputs are generated within the new source tree by the build job.
This home-software/scratch-model-data split follows NERSC's filesystem guidance.

## 3. Submit the isolated build and basic tests

```bash
cd "$BUILD_ROOT/src/pflotran"
sbatch --qos=debug --time=00:30:00 \
  --export=ALL,BUILD_ROOT="$BUILD_ROOT" coastal/build-cpe2603.slurm
```

The command-line overrides above select debug QOS and a 30-minute cap,
replacing the script's regular/2-hour defaults without editing the pinned tag.
It uses one CPU node and eight build workers. This is a complete PETSc,
dependency and PFLOTRAN build plus installation checks, not just a one-core
model smoke test; completion within 30 minutes has not been measured.
Do not chain debug jobs. If the build times out, retain the build logs and
inspect the failed stage before deciding how to continue.

NERSC permits limited-thread compilation on login nodes (for example,
`make -j 8`). However, this particular all-in-one script requires an allocation:
PETSc configuration probes and regression checks use `srun`, and it reads
`SLURM_JOB_ID`. Do not run it directly with `bash` on a login node.
It configures PETSc with:

```bash
export PETSC_DIR="$BUILD_ROOT/src/petsc"
export PETSC_ARCH=arch-cpe2603-gnu-cpu-opt
# Executed inside the supplied batch job:
python3 ./configure PETSC_ARCH="$PETSC_ARCH" \
  --with-cc=cc --with-cxx=CC --with-fc=ftn \
  '--with-mpiexec=srun --mpi=cray_shasta --cpu-bind=cores' \
  --with-batch=0 --with-debugging=0 --with-make-np=8 \
  --COPTFLAGS=-O3 --CXXOPTFLAGS=-O3 --FOPTFLAGS=-O3 \
  --download-hdf5=yes --download-hdf5-fortran-bindings=yes \
  --download-fblaslapack=yes --download-metis=yes --download-parmetis=yes \
  --download-hypre=yes
```

Configuration requires outbound dependency downloads from the allocated
node; a download failure is not a solver failure. Preserve logs and resolve
that failure before retrying in a fresh build root. `--with-batch=0` is used
because this configure runs inside an allocation with a working `srun`; do
not copy it into a login-node MPI configuration run.

There is no `--download-openmpi` or `--download-mpich`. HDF5 and dependencies
are rebuilt against the new stack. No old PETSc libraries are reused.
No `--download-cmake` is requested because the module supplies CMake.
No manual removal of `--oversubscribe` is needed: the launcher is selected
at configuration time. Do not edit generated `petscvariables`.

The job runs PETSc `make check` and the PFLOTRAN check configuration via the
Python regression runner, with separate serial and MPI launch wrappers.
The original PFLOTRAN makefile prefixes regression commands with `-`, which
can mask a nonzero test status; the recipe calls the runner directly instead.
These are basic installation checks, not the complete regression suite.

## 4. Read build results before running models

```bash
squeue -u cliu6
# Replace JOBID with the actual build job ID:
sacct -j JOBID --format=JobID,State,Elapsed,ExitCode
```

Inspect `build_JOBID.out`, `build_JOBID.err`, and
`$BUILD_ROOT/audit/build_JOBID/`. The latter includes full build log, module
versions, compiler versions, source commits, PETSc configuration and
`ldd.txt`. Confirm there are no missing libraries or Open-MPI dependencies.
Do not interpret a successful compilation as a coastal runtime pass.

New executable:

```bash
export PFLOTRAN_EXE_NEW="$BUILD_ROOT/bin/pflotran-coastal-diag1"
sha256sum "$PFLOTRAN_EXE_NEW"
showquota
du -sh "$BUILD_ROOT"
```

No global PATH change is needed. Your old executable stays at its old path.
After a failed build, preserve its directory/logs and choose a new suffix;
the script deliberately refuses to overwrite a configured architecture.

## 5. Run the two separate coastal smoke cases

Upload the separately provided `pflotran_coastal_diag1_smoke_cases.tar.gz`
and `.sha256` file to the Norfolk scratch directory. This bundle is not in
GitHub: it contains small model inputs and checkpoint copies, not source.
It is a diagnostic bundle, not accepted scientific histories.

```bash
cd /pscratch/sd/c/cliu6/NERSC_notebooks/Norfolk
sha256sum -c pflotran_coastal_diag1_smoke_cases.tar.gz.sha256
# Extract once into a new directory; stop if it already exists.
test ! -e pflotran_coastal_diag1_smoke_cases && \
  tar -xzf pflotran_coastal_diag1_smoke_cases.tar.gz
export CASE_DIR="$PWD/pflotran_coastal_diag1_smoke_cases/historical_35047"
cd "$CASE_DIR"
sbatch --export=ALL,BUILD_ROOT="$BUILD_ROOT",CASE_DIR="$CASE_DIR" \
  "$BUILD_ROOT/src/pflotran/coastal/smoke-cpe2603.slurm"
```

After reviewing the historical result, submit the distinct future test:

```bash
export CASE_DIR=/pscratch/sd/c/cliu6/NERSC_notebooks/Norfolk/pflotran_coastal_diag1_smoke_cases/future_S15_35047
cd "$CASE_DIR"
sbatch --export=ALL,BUILD_ROOT="$BUILD_ROOT",CASE_DIR="$CASE_DIR" \
  "$BUILD_ROOT/src/pflotran/coastal/smoke-cpe2603.slurm"
```

Each requests one debug node for at most 30 minutes, runs one 24-hour
simulation, and verifies the ledger endpoint. They are bounded diagnostics,
not production or chained debug allocations. The launcher is:

```bash
srun --mpi=cray_shasta -n 1 -c 2 --cpu-bind=cores \
  "$PFLOTRAN_EXE_NEW" -input_prefix pflotran -swi_restart_refresh_passes 8
```

Run from the selected case directory. The option is essential: default zero
leaves the experimental refresh disabled. Keep the PMI/Slurm environment
provided by `srun`; do not reuse the old Open-MPI singleton variable-unsetting
logic. Do not reuse old `HWLOC_COMPONENTS=-x86` settings without independent
evidence that this different MPI stack needs them.

## 6. Gates before production

Review stdout/stderr, `sacct` and `seff`; verify both diagnostic endpoints,
hourly ledgers, restart continuity and numerical results. Then validate
representative repeated histories and full uninterrupted 50-year branches.
Finally validate a distinct 128-physical-core ensemble launcher for this MPI
stack. The current GNU Parallel/direct-singleton Open-MPI controller is not
certified for Cray MPICH and must not simply receive this executable path.

The hydrostatic guard override suppresses a v5.0 restriction, and the refresh
is a diagnostic repeated-initialization prototype. Neither is claimed to be
upstream-approved or generally safe for all PFLOTRAN modes. Preserve default
zero and explicitly select the diagnostic option in tests. Do not overwrite
the old release or its result trees.

## Resume these instructions in a later login shell

```bash
export BUILD_ROOT=/global/homes/c/cliu6/Software/pflotran-v5.0-auxrefresh1-cpe2603
export PETSC_DIR="$BUILD_ROOT/src/petsc"
export PETSC_ARCH=arch-cpe2603-gnu-cpu-opt
export PFLOTRAN_EXE_NEW="$BUILD_ROOT/bin/pflotran-coastal-diag1"
source "$BUILD_ROOT/src/pflotran/coastal/nersc-env.sh"
```

Use the executable explicitly from a scratch case directory. No shell startup
file or existing executable symlink needs changing.

## Confirm the local edits and MPI launcher

The source includes the three commented hydrostatic SALINITY error lines in
`src/pflotran/pm_auxiliary.F90` and the opt-in restart-refresh edit in
`src/pflotran/simulation_subsurface.F90`. Inspect with:

```bash
sed -n '303,311p' "$BUILD_ROOT/src/pflotran/src/pflotran/pm_auxiliary.F90"
grep -n swi_restart_refresh_passes "$BUILD_ROOT/src/pflotran/src/pflotran/simulation_subsurface.F90"
```

The new PETSc configure explicitly selects `srun`; it does not patch or reuse
old `petscvariables`. After configuration, verify the generated launcher:

```bash
grep -nE '^(MPIEXEC|MPIEXEC_FLAGS)[[:space:]]*=' \
  "$BUILD_ROOT/src/petsc/arch-cpe2603-gnu-cpu-opt/lib/petsc/conf/petscvariables"
```

No `--oversubscribe` is supplied by this recipe. Inspect the actual generated
file after building; do not claim its contents have been verified before that.

## Version control

Installation revision: `coastal-v5.0-auxrefresh-diag1-home1`. This changes
installation placement and documentation only; PFLOTRAN Fortran source is
identical to `coastal-v5.0-auxrefresh-diag1`. The previous tag is preserved.

New work is committed as Chuyang Liu. Upstream authors and LICENSE/COPYRIGHT
remain intact. This is a GitHub-hosted downstream of Bitbucket PFLOTRAN,
not a native GitHub fork relationship. Use separate descriptive branches and
new tags for changes; do not rewrite released tags. Never commit executable
build outputs, PETSc downloads, credentials, or model result trees.

## Official references

- [NERSC login-node and debug usage policy](https://docs.nersc.gov/policies/resource-usage/)

- [NERSC filesystem guidance](https://docs.nersc.gov/filesystems/)

- [NERSC environment timeline](https://docs.nersc.gov/systems/perlmutter/timeline/)
- [NERSC compiler wrappers](https://docs.nersc.gov/development/build-tools/autoconf-make/)
- [NERSC CMake](https://docs.nersc.gov/development/build-tools/cmake/)
- [NERSC Slurm jobs](https://docs.nersc.gov/jobs/)
- [NERSC Cray MPI launcher selection](https://docs.nersc.gov/development/programming-models/mpi/nvshmem/)
- [PETSc configure guidance](https://petsc.org/release/install/install/)
- [PFLOTRAN PETSc version history](https://www.pflotran.org/documentation/user_guide/how_to/installation/previous_petsc_releases.html)

NERSC execution of this recipe is still to be performed. Local script syntax
and source equivalence were checked; no claim of a completed NERSC build.

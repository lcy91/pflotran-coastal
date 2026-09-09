#!/bin/bash
#SBATCH --job-name=cliu-pflotran-build
#SBATCH --account=m2398
#SBATCH --constraint=cpu
#SBATCH --qos=regular
#SBATCH --nodes=1
#SBATCH --ntasks=8
#SBATCH --cpus-per-task=1
#SBATCH --time=02:00:00
#SBATCH --output=build_%j.out
#SBATCH --error=build_%j.err
set -euo pipefail
: "${BUILD_ROOT:?Export the new isolated BUILD_ROOT before sbatch}"
# Restrict builds to a distinct installation beside the original software.
case "$(basename "$BUILD_ROOT")" in
  pflotran-v5.0-auxrefresh1-cpe2603*) ;;
  *) echo 'Use a new pflotran-v5.0-auxrefresh1-cpe2603 directory under Software.' >&2; exit 2;;
esac
software_parent=$(cd /global/homes/c/cliu6/Software && pwd -P)
build_parent=$(cd "$(dirname "$BUILD_ROOT")" && pwd -P)
test "$build_parent" = "$software_parent" && test ! -L "$BUILD_ROOT" || {
  echo 'BUILD_ROOT must be a separate, non-symlink directory directly under home Software.' >&2; exit 2;
}
export PFLOTRAN_DIR="$BUILD_ROOT/src/pflotran"
export PETSC_DIR="$BUILD_ROOT/src/petsc"
export PETSC_ARCH=arch-cpe2603-gnu-cpu-opt
source "$PFLOTRAN_DIR/coastal/nersc-env.sh"
LOG="$BUILD_ROOT/audit/build_${SLURM_JOB_ID}"
mkdir -p "$LOG" "$BUILD_ROOT/bin"
exec > >(tee "$LOG/build.log") 2>&1
module -t list 2> "$LOG/modules.txt"
cc --version > "$LOG/cc-version.txt" 2>&1
ftn --version > "$LOG/ftn-version.txt" 2>&1
cmake --version > "$LOG/cmake-version.txt"
git -C "$PFLOTRAN_DIR" rev-parse HEAD > "$LOG/pflotran-commit.txt"
test -z "$(git -C "$PFLOTRAN_DIR" status --porcelain --untracked-files=no)"
test "$(git -C "$PETSC_DIR" rev-parse HEAD)" = 9cffe78795669c5fbaf7ca6d864d230635faa5ef
git -C "$PETSC_DIR" rev-parse HEAD > "$LOG/petsc-commit.txt"
test ! -e "$PETSC_DIR/$PETSC_ARCH" || { echo 'Build architecture already exists; choose a fresh BUILD_ROOT.'; exit 2; }
test ! -e "$BUILD_ROOT/bin/pflotran-coastal-diag1"
cd "$PETSC_DIR"
python3 ./configure PETSC_ARCH="$PETSC_ARCH" \
  --with-cc=cc --with-cxx=CC --with-fc=ftn \
  '--with-mpiexec=srun --mpi=cray_shasta --cpu-bind=cores' \
  --with-batch=0 --with-debugging=0 --with-make-np=8 \
  --COPTFLAGS=-O3 --CXXOPTFLAGS=-O3 --FOPTFLAGS=-O3 \
  --download-hdf5=yes --download-hdf5-fortran-bindings=yes \
  --download-fblaslapack=yes --download-metis=yes --download-parmetis=yes \
  --download-hypre=yes
make -j8 all
make check
cp configure.log "$LOG/petsc-configure.log"
cp "$PETSC_DIR/$PETSC_ARCH/lib/petsc/conf/petscvariables" "$LOG/petscvariables.txt"
cd "$PFLOTRAN_DIR/src/pflotran"
make -j8 pflotran
cp pflotran "$BUILD_ROOT/bin/pflotran-coastal-diag1"
sha256sum "$BUILD_ROOT/bin/pflotran-coastal-diag1" > "$LOG/executable.sha256"
ldd "$BUILD_ROOT/bin/pflotran-coastal-diag1" > "$LOG/ldd.txt"
if grep -q 'not found' "$LOG/ldd.txt"; then echo 'Missing runtime library'; exit 2; fi
cd "$PFLOTRAN_DIR/regression_tests"
python3 regression_tests.py -e "$PFLOTRAN_DIR/coastal/serial-test-launch.sh" \
  --suite standard --config-files ascem/1d/1d-calcite/1d-calcite.cfg
python3 regression_tests.py -e "$BUILD_ROOT/bin/pflotran-coastal-diag1" \
  --mpiexec "$PFLOTRAN_DIR/coastal/mpi-test-launch.sh" \
  --suite standard_parallel --config-files ascem/1d/1d-calcite/1d-calcite.cfg
printf '%s\n' 'BUILD_FINISHED: coastal runtime and scientific gates are still required.' 

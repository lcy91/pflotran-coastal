#!/bin/bash
#SBATCH --job-name=cliu-refresh-audit1
#SBATCH --account=m2398
#SBATCH --constraint=cpu
#SBATCH --qos=debug
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --time=00:30:00
#SBATCH --output=refresh_audit_%j.out
#SBATCH --error=refresh_audit_%j.err
set -euo pipefail
module reset
module load cpu
module load gcc/12.2.0
module load openmpi/5.0.7
module load cmake/3.30.2
export BUILD_ROOT=/global/homes/c/cliu6/Software/pflotran-v5.0-auxrefresh1-openmpi1
export PETSC_DIR="$BUILD_ROOT/src/petsc"
export PETSC_ARCH=arch-openmpi-gnu-cpu-opt
export PFLOTRAN_DIR="$BUILD_ROOT/src/pflotran-refresh-audit1"
export PFLOTRAN_EXE_NEW="$BUILD_ROOT/bin/pflotran-coastal-refresh-audit1"
export COASTAL_MPIEXEC=$(command -v mpiexec)
export AUDIT_BUNDLE="$SLURM_SUBMIT_DIR"
case "$AUDIT_BUNDLE" in /pscratch/sd/c/cliu6/*) ;; *) echo 'Submit from scratch audit bundle';exit 2;; esac
export AUDIT_RUN=$(mktemp -d "$AUDIT_BUNDLE/run_${SLURM_JOB_ID}.XXXXXX")
test -d "$AUDIT_RUN"
module -t list 2> "$AUDIT_RUN/modules.txt"
printf 'BUILD_ROOT=%s\nPETSC_DIR=%s\nPETSC_ARCH=%s\nPFLOTRAN_DIR=%s\nPFLOTRAN_EXE_NEW=%s\nMPIEXEC=%s\n' "$BUILD_ROOT" "$PETSC_DIR" "$PETSC_ARCH" "$PFLOTRAN_DIR" "$PFLOTRAN_EXE_NEW" "$COASTAL_MPIEXEC" > "$AUDIT_RUN/environment.txt"
sha256sum "$PFLOTRAN_EXE_NEW" > "$AUDIT_RUN/executable.sha256"
git -C "$PFLOTRAN_DIR" rev-parse HEAD > "$AUDIT_RUN/source-commit.txt"
# The local build record must match the binary being tested.
sha256sum -c "$BUILD_ROOT/audit/refresh-audit1-executable.sha256"
python3 "$AUDIT_BUNDLE/run-refresh-audit.py"
printf 'REFRESH_AUDIT_PASSED run=%s\n' "$AUDIT_RUN"

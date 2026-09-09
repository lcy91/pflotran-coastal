#!/bin/bash
#SBATCH --job-name=cliu-pflotran-smoke
#SBATCH --account=m2398
#SBATCH --constraint=cpu
#SBATCH --qos=debug
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --time=00:30:00
#SBATCH --output=smoke_%j.out
#SBATCH --error=smoke_%j.err
set -euo pipefail
: "${BUILD_ROOT:?}" "${CASE_DIR:?Supply a separate staged diagnostic case directory}"
source "$BUILD_ROOT/src/pflotran/coastal/nersc-env.sh"
export PETSC_DIR="$BUILD_ROOT/src/petsc"
export PETSC_ARCH=arch-cpe2603-gnu-cpu-opt
EXE="$BUILD_ROOT/bin/pflotran-coastal-diag1"
case "$CASE_DIR" in /pscratch/sd/c/cliu6/*) ;; *) echo 'CASE_DIR must be on scratch'; exit 2;; esac
cd "$CASE_DIR"
test -f pflotran.in
test ! -e pflotran.out && test ! -e pflotran.h5
module list
sha256sum "$EXE"
srun --mpi=cray_shasta -n 1 -c 2 --cpu-bind=cores "$EXE" \
  -input_prefix pflotran -swi_restart_refresh_passes 8
# A successful launcher alone does not prove the model reached its endpoint.
python3 - <<'PY'
import re, math
from pathlib import Path
deck=Path('pflotran.in').read_text()
m=re.search(r'FINAL_TIME\s+([0-9.eE+-]+)\s+h\b',deck)
assert m, 'Diagnostic must specify FINAL_TIME in hours'
expected=float(m.group(1)); last=None
for line in Path('pflotran-mas.dat').open():
    try: row=[float(v) for v in line.split()]
    except ValueError: continue
    assert all(math.isfinite(v) for v in row)
    last=row[0]
assert last is not None and abs(last-expected)<1e-6, (last, expected)
print('DIAGNOSTIC_ENDPOINT_PASSED',last)
PY

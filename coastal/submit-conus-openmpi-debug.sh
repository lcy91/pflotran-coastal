#!/bin/bash
#SBATCH --job-name=cliu-conus-ompi-diag1
#SBATCH --account=m2398
#SBATCH --constraint=cpu
#SBATCH --qos=debug
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --time=00:30:00
#SBATCH --output=conus_openmpi_%j.out
#SBATCH --error=conus_openmpi_%j.err
set -euo pipefail
module reset
module load cpu
module load gcc/12.2.0
module load openmpi/5.0.7
module load cmake/3.30.2
# Explicit exports: never inherit old PETSc paths or select an old binary.
export BUILD_ROOT=/global/homes/c/cliu6/Software/pflotran-v5.0-auxrefresh1-openmpi1
export PETSC_DIR="$BUILD_ROOT/src/petsc"
export PETSC_ARCH=arch-openmpi-gnu-cpu-opt
export PFLOTRAN_DIR="$BUILD_ROOT/src/pflotran"
export PFLOTRAN_EXE_NEW="$BUILD_ROOT/bin/pflotran-coastal-diag1"
export COASTAL_MPIEXEC=$(command -v mpiexec)
: "${SLURM_SUBMIT_DIR:?}" "${SLURM_JOB_ID:?}"
case "$SLURM_SUBMIT_DIR" in /pscratch/sd/c/cliu6/*) ;; *) echo 'Submit from the unpacked scratch bundle.' >&2; exit 2;; esac
bundle="$SLURM_SUBMIT_DIR"
inputs="$bundle/pflotran_coastal_diag1_smoke_cases"
test -d "$inputs/historical_35047" && test -d "$inputs/future_S15_35047"
# Fail instead of accidentally validating a different executable.
expected=ac45879212d37bca11a838019e8f14c2484bde1db8b33363f144c94ba5bd9188
actual=$(sha256sum "$PFLOTRAN_EXE_NEW" | awk '{print $1}')
test "$actual" = "$expected" || { echo 'Executable hash differs from the reported build.'; exit 2; }
"$COASTAL_MPIEXEC" --version | head -n 1
run=$(mktemp -d "$bundle/run_${SLURM_JOB_ID}.XXXXXX")
export DIAGNOSTIC_RUN="$run"
trap 'rc=$?; if [ "$rc" -ne 0 ]; then printf "exit=%s case=%s\n" "$rc" "${case_name:-preflight}" > "$run/FAILED.txt"; fi' EXIT
printf 'diagnostic_run=%s\n' "$run"
module -t list 2> "$run/modules.txt"
printf 'BUILD_ROOT=%s\nPETSC_DIR=%s\nPETSC_ARCH=%s\nPFLOTRAN_DIR=%s\nPFLOTRAN_EXE_NEW=%s\nMPIEXEC=%s\n' "$BUILD_ROOT" "$PETSC_DIR" "$PETSC_ARCH" "$PFLOTRAN_DIR" "$PFLOTRAN_EXE_NEW" "$COASTAL_MPIEXEC" > "$run/environment.txt"
sha256sum "$PFLOTRAN_EXE_NEW" > "$run/executable.sha256"
ldd "$PFLOTRAN_EXE_NEW" > "$run/ldd.txt"
if grep -q 'not found' "$run/ldd.txt"; then echo 'Missing library'; exit 2; fi
for case_name in historical_35047 future_S15_35047; do
  cp -R "$inputs/$case_name" "$run/$case_name"
  cd "$run/$case_name"
  sha256sum pflotran.in mesh_pflotran.h5 tide_forcing.dat recharge_monthly_equal_depth.dat restart/pflotran-restart.h5 > inputs.sha256
  printf 'starting_case=%s\n' "$case_name"
  "$COASTAL_MPIEXEC" -n 1 --bind-to core --report-bindings \
    "$PFLOTRAN_EXE_NEW" -input_prefix pflotran -swi_restart_refresh_passes 8 \
    > model.stdout 2> model.stderr
  sha256sum -c inputs.sha256 > inputs-verified.txt
  python3 - <<'PY'
import math, json, re
from pathlib import Path
text=Path('pflotran.in').read_text()
assert re.search(r'FINAL_TIME\s+24\s+h\b',text)
times=[]
for line in Path('pflotran-mas.dat').open():
    fields=line.split()
    if not fields: continue
    try: float(fields[0])
    except ValueError: continue
    row=[float(x) for x in fields]
    assert all(math.isfinite(x) for x in row), 'Nonfinite ledger entry'
    times.append(row[0])
assert times and abs(times[-1]-24)<1e-6, ('Final time',times[-1:] )
assert all(b>a for a,b in zip(times,times[1:])), 'Nonincreasing ledger times'
assert all(any(abs(t-h)<1e-6 for t in times) for h in range(1,25)), 'Missing hourly ledger'
result={'status':'PASS','case':Path.cwd().name,'end_hours':times[-1],
        'hourly_ledger_records':len(times),'refresh_passes':8,
        'scope':'24-hour diagnostic restart only; not historical acceptance or 50-year validation'}
Path('DIAGNOSTIC_PASS.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
PY
done
python3 - <<'PY'
import os,json
from pathlib import Path
p=Path(os.environ['DIAGNOSTIC_RUN'])
cases=[json.loads((p/n/'DIAGNOSTIC_PASS.json').read_text()) for n in ['historical_35047','future_S15_35047']]
assert all(c['status']=='PASS' for c in cases)
(p/'TWO_CASE_GATE_PASSED.json').write_text(json.dumps({'status':'PASS','cases':cases},indent=2)+'\n')
PY
printf 'TWO_CASE_GATE_PASSED run=%s\n' "$run"

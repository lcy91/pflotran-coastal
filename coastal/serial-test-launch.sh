#!/bin/bash
set -euo pipefail
: "${BUILD_ROOT:?}"
exec srun --mpi=cray_shasta --nodes=1 --ntasks=1 --cpus-per-task=1 --cpu-bind=cores \
  "$BUILD_ROOT/bin/pflotran-coastal-diag1" "$@"

#!/bin/bash
set -euo pipefail
case "${1:-}" in -np|-n) ranks="$2"; shift 2;; *) echo 'Expected -np N or -n N'; exit 2;; esac
exec srun --mpi=cray_shasta --nodes=1 --ntasks="$ranks" --cpus-per-task=1 --cpu-bind=cores "$@"

# Source this file in a fresh NERSC shell or batch job.
module reset
module load cpe/26.03
module load PrgEnv-gnu
module load cpu
module load cmake
case ":${LOADEDMODULES:-}:" in
  *openmpi*) echo 'Open MPI remains loaded; stop and use a clean shell.' >&2; return 1 ;;
esac
export MPICH_GPU_SUPPORT_ENABLED=0
export OMP_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export CRAYPE_LINK_TYPE=dynamic

# PFLOTRAN coastal restart experiments

Maintainer: **Chuyang Liu**.

This repository preserves upstream PFLOTRAN v5.0 and its authors/license.
It carries two separately committed coastal-workflow changes:

1. The existing hydrostatic/auxiliary-salinity restriction override. This
   suppresses an upstream error; it is not proof of general hydrostatic
   compatibility.
2. An **opt-in experimental restart initialization refresh**:
   `-swi_restart_refresh_passes 8`. Default zero retains the baseline path.
   Repeating initialization is a diagnostic prototype, not a certified
   general production repair.

Upstream: https://bitbucket.org/pflotran/pflotran.git

Pinned baseline: `a2104cedea1528a00aa2718572d43a4461019c60` (v5.0).
PETSc baseline: v3.21.5, `9cffe78795669c5fbaf7ca6d864d230635faa5ef`.

Local validation: two known failing checkpoints passed five additional years
and another restart with the refresh enabled. All seven future scenarios at
one site and H/S15 at a second site passed one-year diagnostics. The
original executable failed the corresponding startup controls. No full
50-year national validation or Perlmutter validation is claimed.

See [the separate NERSC installation guide](coastal/NERSC_INSTALL.md).
The original local and NERSC installations are not modified by this recipe.

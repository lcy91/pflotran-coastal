#!/usr/bin/env python3
"""Chuyang Liu: controlled 0/8 restart-option gate; Python 3.6 compatible."""
import hashlib, json, math, os, re, shutil, subprocess, time, sys
from pathlib import Path

def digest(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    bundle=Path(os.environ['AUDIT_BUNDLE']).resolve()
    exe=Path(os.environ['PFLOTRAN_EXE_NEW']).resolve()
    run=Path(os.environ['AUDIT_RUN']).resolve()
    launcher=os.environ['COASTAL_MPIEXEC']
    inputs=bundle/'pflotran_coastal_diag1_smoke_cases'
    results=[]
    for site in ['historical_35047','future_S15_35047']:
        for requested in [0,8]:
            name=site+'_refresh'+str(requested)
            d=run/name
            shutil.copytree(str(inputs/site),str(d))
            # No pflotran.in: this deliberately requires working -input_prefix.
            (d/'pflotran.in').rename(d/'audit_case.in')
            originals={str(p.relative_to(d)):digest(p) for p in d.rglob('*') if p.is_file()}
            binding='none' if sys.platform=='darwin' else 'core'
            cmd=[launcher,'-n','1','--bind-to',binding,str(exe),
                 '-input_prefix','audit_case','-successful_exit_code','0',
                 '-swi_restart_refresh_passes',str(requested)]
            start=time.monotonic()
            with (d/'model.stdout').open('w') as out,(d/'model.stderr').open('w') as err:
                try: rc=subprocess.run(cmd,cwd=str(d),stdout=out,stderr=err,timeout=240).returncode
                except subprocess.TimeoutExpired: rc=124
            text=(d/'model.stdout').read_text(errors='replace')+'\n'+(d/'model.stderr').read_text(errors='replace')
            # Include PFLOTRAN's output when screen output does not carry PrintMsg.
            if (d/'audit_case.out').exists(): text+='\n'+(d/'audit_case.out').read_text(errors='replace')
            opts=re.findall(r'SWI_REFRESH_AUDIT requested=(\d+) supplied=([TF]) restart=([TF]) salinity_density=([TF])',text)
            counts=re.findall(r'SWI_REFRESH_AUDIT applied=(\d+)',text)
            option_ok=bool(opts and counts) and all(x==(str(requested),'T','T','T') for x in opts) and all(int(x)==requested for x in counts)
            unchanged=all(digest(d/n)==v for n,v in originals.items())
            times=[];finite=True
            ledger=d/'audit_case-mas.dat'
            if ledger.exists():
                for line in ledger.open():
                    vals=line.split()
                    if not vals: continue
                    try: float(vals[0])
                    except ValueError: continue
                    try: row=[float(v) for v in vals]
                    except ValueError: finite=False;continue
                    finite=finite and all(math.isfinite(v) for v in row)
                    times.append(row[0])
            endpoint=bool(times) and abs(times[-1]-24)<1e-6
            hourly=all(any(abs(t-h)<1e-6 for t in times) for h in range(1,25))
            ledger_ok=finite and endpoint and hourly and all(b>a for a,b in zip(times,times[1:]))
            rec=dict(case=name,requested=requested,reported_option_records=opts,
                     reported_applied_counts=[int(x) for x in counts],option_verified=option_ok,
                     exit_code=rc,seconds=time.monotonic()-start,inputs_unchanged=unchanged,
                     restart_sha256=originals['restart/pflotran-restart.h5'],
                     ledger_valid=ledger_ok,ledger_rows=len(times),
                     executable_sha256=digest(exe),input_prefix_verified=(d/'audit_case.out').exists())
            (d/'result.json').write_text(json.dumps(rec,indent=2)+'\n');results.append(rec)
            print(json.dumps(rec),flush=True)
    # Zero-pass controls may fail numerically, but must prove option/prefix handling.
    gate=all(r['option_verified'] and r['inputs_unchanged'] and r['input_prefix_verified'] for r in results)
    gate=gate and all(r['exit_code']==0 and r['ledger_valid'] for r in results if r['requested']==8)
    for site in ['historical_35047','future_S15_35047']:
        pair=[r for r in results if r['case'].startswith(site)]
        gate=gate and len(set(r['restart_sha256'] for r in pair))==1
    summary={'status':'PASS' if gate else 'FAIL','cases':results,
             'scope':'Requested/applied refresh and 24-hour restart gate; no 50-year or national acceptance'}
    (run/'REFRESH_AUDIT_RESULT.json').write_text(json.dumps(summary,indent=2)+'\n')
    if not gate: raise SystemExit(2)
if __name__=='__main__': main()

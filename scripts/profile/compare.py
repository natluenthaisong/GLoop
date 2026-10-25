#!/usr/bin/env python3
"""Alternate already-built variants to reduce time/order bias. No input paths in JSON."""
import argparse, json, subprocess
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--variant',nargs=2,action='append',required=True,metavar=('LABEL','EXECUTABLE'))
p.add_argument('--media',nargs=2,action='append',required=True,metavar=('LABEL','PATH'))
p.add_argument('--runs',type=int,default=5)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args(); rows=[]
for label,path in a.media:
    for mode in ['prepare','bpm','fingerprint']:
        for run in range(1 if mode=='fingerprint' else a.runs):
            variants=a.variant[run%len(a.variant):]+a.variant[:run%len(a.variant)]
            for variant,exe in variants:
                output=subprocess.run([exe,mode,path],capture_output=True,text=True,check=True).stdout
                row=dict(label=label,mode=mode,variant=variant,run=run,**json.loads(output))
                rows.append(row); print(json.dumps(row),flush=True)
a.output.write_text(json.dumps(rows,indent=2)+'\n')

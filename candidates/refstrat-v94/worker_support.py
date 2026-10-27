"""Persistent protocol. Nothing here chooses a game action."""
import contextlib
import gc
import json
import os
import random
import re
import sys
import time

_audit = None

def audit_fresh(run):
    """Passive constructor check before any --set or Lua stack is loaded."""
    global _audit
    lua=run.lua
    # Lua 5.1 math.random uses a process-level C generator. A fresh interpreter
    # starts with seed 1; reset that baseline before modules/patches load. The
    # original main.lua then seeds it from CUSTOM_SEED at the normal time.
    lua.execute('math.randomseed(1)')
    pristine=lua.execute('''
      local names, modules = {}, {}
      for k in pairs(_G) do names[#names+1]=tostring(k) end
      for k in pairs(package.loaded) do modules[#modules+1]=tostring(k) end
      table.sort(names); table.sort(modules)
      assert(REFSTRAT_STRATEGIES == nil and __V91_SENTINEL == nil)
      assert(package.loaded["ai.strategies"] == nil)
      return table.concat(names, "|"), table.concat(modules, "|")
    ''')
    _audit=dict(lua_globals=pristine[0],lua_modules=pristine[1],frame=run.frames,
                splits=len(run.splits),power_cycles=len(run.power_cycles),
                fresh_ram_bytes=0x8000)
    assert run.frames==1 and not run.splits and not run.power_cycles

def release_attempt(run):
    """Break Python -> Lua -> bound-method -> Python cycles deterministically."""
    try:
        for name in ('actions','strategy_events','logs'):
            handle=getattr(run,name,None)
            if handle is not None and not handle.closed: handle.close()
        gb=getattr(run,'gb',None)
        if gb is not None: gb.stop(save=False)
    finally:
        # Includes lua, _invalidate_reads (Lua upvalue cache), memory, PyBoy,
        # all bound callbacks and the per-game Dev class closure's only instance.
        run.__dict__.clear()
        gc.collect()

def validate(job):
    if not isinstance(job,dict): raise ValueError('request must be an object')
    if type(job.get('seed')) is not int: raise ValueError('integer seed required')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+',job.get('tag','')): raise ValueError('safe tag required')
    if not isinstance(job.get('job_id'),str): raise ValueError('job_id required')
    if not isinstance(job.get('sets',[]),list) or not all(isinstance(s,str) and '=' in s for s in job.get('sets',[])):
        raise ValueError('sets must be ordered NAME=VALUE strings')
    if job.get('pace') is not None and not isinstance(job['pace'],str): raise ValueError('pace must be path or null')
    if type(job.get('max_frames',480000)) is not int or job.get('max_frames',480000)<1:
        raise ValueError('max_frames must be positive integer')

def serve(main):
    import warnings
    warnings.filterwarnings('ignore')
    # Warm imports once; no Attempt, PyBoy, Lua runtime or adapter is pooled.
    with contextlib.redirect_stdout(sys.stderr):
        import refstrat_adapter
        import numpy as np
    print(json.dumps(dict(protocol='v91',ready=True,pid=os.getpid())),flush=True)
    index=0
    for line in sys.stdin:
        if not line.strip(): continue
        index+=1
        start=time.perf_counter()
        job={}
        try:
            job=json.loads(line); validate(job)
            for key in ('REFSTRAT_PACE','HUNT_CONFIG','REFSTRAT_TURN_HOOK','REFSTRAT_SRAM_DUMP'):
                os.environ.pop(key,None)
            if job.get('pace'): os.environ['REFSTRAT_PACE']=job['pace']
            if job.get('config'): os.environ['HUNT_CONFIG']=json.dumps(job['config'])
            # The bot does not use these two generators; reseed from OS entropy
            # as a fresh process does, so dependency state cannot carry over.
            random.seed(None); np.random.seed(None)
            args=[str(job['seed']),'--tag',job['tag'],'--quiet','--max-frames',str(job.get('max_frames',480000))]
            retention = job.get('retention', {})
            if retention:
                if retention.get('enabled'): args += ['--temp-runs']
                if retention.get('named'): args += ['--keep-input']
                for key, flag in [('summary_jsonl','--summary-jsonl'), ('keep_pace','--keep-pace'),
                                  ('late_split','--keep-split'), ('artifact_root','--artifact-root')]:
                    if key in retention: args += [flag, str(retention[key])]
            args += [x for kv in job.get('sets',[]) for x in ('--set',kv)]
            with contextlib.redirect_stdout(sys.stderr):
                result=main(args,_worker=True)
            result['worker']=dict(job_id=job['job_id'],index=index,pid=os.getpid(),
                                  wall=time.perf_counter()-start,fresh=_audit)
            print(json.dumps(result),flush=True)
        except BaseException as ex:
            result=dict(seed=job.get('seed') if isinstance(job,dict) else None,
                        outcome='technical_error',kind='worker_exception',error=f'{type(ex).__name__}: {ex}',
                        worker=dict(job_id=job.get('job_id') if isinstance(job,dict) else None,index=index,pid=os.getpid()))
            print(json.dumps(result),flush=True)
            # Exception may leave a partially initialized dependency. Never run
            # another game in this interpreter. Parent records failure/restarts.
            raise SystemExit(1)
if __name__=='__main__': raise SystemExit('Use devrun.py --worker')

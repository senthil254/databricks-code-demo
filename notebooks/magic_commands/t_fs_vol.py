# Databricks notebook source
import json
res={}
try:
    res["ls_root"] = f"PASS ({len(dbutils.fs.ls('/'))} entries)"
except Exception as e:
    res["ls_root"] = f"FAIL {type(e).__name__}: {str(e)[:120]}"
V="/Volumes/demo_training/magic_cmds/demo_vol"
try:
    dbutils.fs.mkdirs(f"{V}/sub")
    dbutils.fs.put(f"{V}/sub/a.txt","hello",True)
    dbutils.fs.cp(f"{V}/sub/a.txt",f"{V}/sub/b.txt")
    n=len(dbutils.fs.ls(f"{V}/sub"))
    dbutils.fs.rm(f"{V}/sub",True)
    res["volume_ops"]=f"PASS (mkdirs/put/cp/ls={n}/rm)"
except Exception as e:
    res["volume_ops"]=f"FAIL {type(e).__name__}: {str(e)[:150]}"
dbutils.notebook.exit(json.dumps(res))

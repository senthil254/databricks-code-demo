# Databricks notebook source
r = dbutils.fs.ls("/")
dbutils.fs.mkdirs("/tmp/magic_cmds_test")
dbutils.fs.put("/tmp/magic_cmds_test/a.txt","hello",True)
dbutils.fs.cp("/tmp/magic_cmds_test/a.txt","/tmp/magic_cmds_test/b.txt")
n = len(dbutils.fs.ls("/tmp/magic_cmds_test"))
dbutils.fs.rm("/tmp/magic_cmds_test", True)
dbutils.notebook.exit(f"fs_dbutils PASS (root entries={len(r)}, tmp files={n})")

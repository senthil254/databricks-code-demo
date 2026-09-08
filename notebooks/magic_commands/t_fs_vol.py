# Databricks notebook source
# MAGIC %md
# MAGIC # 6. `dbutils.fs` — working with files, the modern way
# MAGIC
# MAGIC Not all data is tidy tables. You also deal with CSVs, PDFs, images and model
# MAGIC files. `dbutils.fs` is how a notebook reads and writes those.
# MAGIC
# MAGIC ### Why this notebook uses Volumes, and why `%fs` is absent
# MAGIC You will see `%fs` in older tutorials. **It does not work here**, for two
# MAGIC reasons worth understanding — both are common real-world stumbling blocks:
# MAGIC
# MAGIC 1. **`%fs` is blocked on serverless compute.** Under the hood it is implemented
# MAGIC    in Scala, and serverless does not permit Scala. `dbutils.fs` is the Python
# MAGIC    equivalent and works fine. **Use `dbutils.fs`.**
# MAGIC 2. **The old "DBFS" storage area is disabled** in this workspace, on purpose.
# MAGIC    DBFS had no real access control — anyone could read anyone's files.
# MAGIC
# MAGIC The replacement is a **Unity Catalog Volume**: a folder that lives inside your
# MAGIC catalog and obeys the same permissions as your tables. **Business benefit:**
# MAGIC one consistent set of access rules covering both tables and files, and a full
# MAGIC audit trail of who opened what.

# COMMAND ----------

import json
res = {}

# COMMAND ----------

# MAGIC %md
# MAGIC ### Listing a location
# MAGIC `ls` on the root is a quick connectivity check — it proves the storage layer is
# MAGIC reachable before we attempt to write anything.

# COMMAND ----------

try:
    res["ls_root"] = f"PASS ({len(dbutils.fs.ls('/'))} entries)"
except Exception as e:
    # Capture the failure rather than crashing, so the summary still prints.
    res["ls_root"] = f"FAIL {type(e).__name__}: {str(e)[:120]}"

# COMMAND ----------

# MAGIC %md
# MAGIC ### The full file lifecycle on a governed Volume
# MAGIC Create a folder, write a file, copy it, list the folder, then clean up. That is
# MAGIC the complete set of operations most data pipelines ever need.
# MAGIC
# MAGIC Note the path shape: `/Volumes/<catalog>/<schema>/<volume>/...`. It reads like a
# MAGIC normal folder path, but every access is permission-checked and logged.

# COMMAND ----------

V = "/Volumes/demo_training/magic_cmds/demo_vol"

try:
    # mkdirs creates the folder (and any missing parents). Safe to re-run.
    dbutils.fs.mkdirs(f"{V}/sub")

    # put writes text to a file. The final True means "overwrite if it exists",
    # which keeps this notebook safely repeatable.
    dbutils.fs.put(f"{V}/sub/a.txt", "hello", True)

    # cp copies a file — the everyday backup/staging operation.
    dbutils.fs.cp(f"{V}/sub/a.txt", f"{V}/sub/b.txt")

    # ls confirms both files are really there. Expect 2.
    n = len(dbutils.fs.ls(f"{V}/sub"))

    # Clean up after ourselves so the demo can be run repeatedly from a clean slate.
    # True means recursive (delete the folder and everything in it).
    dbutils.fs.rm(f"{V}/sub", True)

    res["volume_ops"] = f"PASS (mkdirs/put/cp/ls={n}/rm)"
except Exception as e:
    res["volume_ops"] = f"FAIL {type(e).__name__}: {str(e)[:150]}"

# COMMAND ----------

dbutils.notebook.exit(json.dumps(res))

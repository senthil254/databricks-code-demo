# Databricks notebook source
dbutils.widgets.text("tier", "gold", "Customer tier")
t = dbutils.widgets.get("tier")
print("widget tier =", t)

# COMMAND ----------

n = spark.sql(f"SELECT count(*) c FROM demo_training.magic_cmds.customers WHERE tier='{t}'").collect()[0]["c"]

# COMMAND ----------

scopes = "unavailable"
try:
    scopes = str(len(dbutils.secrets.listScopes()))
except Exception as e:
    scopes = f"ERR: {type(e).__name__}"

# COMMAND ----------

child = dbutils.notebook.run("./child", 60)

# COMMAND ----------

import json
dbutils.notebook.exit(json.dumps({"widgets":f"PASS (tier={t}, {n} rows)","secrets_scopes":scopes,"notebook_run":"PASS"}))

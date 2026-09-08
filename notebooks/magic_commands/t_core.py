# Databricks notebook source
# MAGIC %md
# MAGIC # Core magic test

# COMMAND ----------

results = {}

# COMMAND ----------

# MAGIC %python
# MAGIC df = spark.table("demo_training.magic_cmds.customers")
# MAGIC print("python rows:", df.count())

# COMMAND ----------

# MAGIC %sql
# MAGIC CREATE OR REPLACE TEMP VIEW gold_customers AS
# MAGIC SELECT * FROM demo_training.magic_cmds.customers WHERE tier = 'gold'

# COMMAND ----------

n = spark.table("gold_customers").count()
print("cross-language temp view rows:", n)

# COMMAND ----------

import json
dbutils.notebook.exit(json.dumps({"md":"PASS","python":"PASS","sql":"PASS","cross_language_view":f"PASS ({n} gold rows)"}))

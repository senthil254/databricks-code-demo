# Databricks notebook source
# MAGIC %fs ls /

# COMMAND ----------

# MAGIC %fs mkdirs /tmp/magic_cmds_test

# COMMAND ----------

dbutils.fs.put("/tmp/magic_cmds_test/a.txt", "hello", True)

# COMMAND ----------

# MAGIC %fs cp /tmp/magic_cmds_test/a.txt /tmp/magic_cmds_test/b.txt

# COMMAND ----------

# MAGIC %fs rm -r /tmp/magic_cmds_test

# COMMAND ----------

dbutils.notebook.exit("fs PASS (ls, mkdirs, cp, rm)")

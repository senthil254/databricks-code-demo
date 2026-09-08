# Databricks notebook source
# MAGIC %scala
# MAGIC val n = spark.table("demo_training.magic_cmds.orders").count()
# MAGIC println(s"scala rows: $n")

# COMMAND ----------

dbutils.notebook.exit("scala PASS")

# Databricks notebook source
# MAGIC %pip install tabulate==0.9.0

# COMMAND ----------

import tabulate
v = tabulate.__version__

# COMMAND ----------

dbutils.notebook.exit(f"pip PASS (tabulate {v})")

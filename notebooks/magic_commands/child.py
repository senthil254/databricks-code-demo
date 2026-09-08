# Databricks notebook source
# MAGIC %md
# MAGIC # Helper notebook: `child`
# MAGIC
# MAGIC **This notebook is not run on its own** — it exists to be called by other
# MAGIC notebooks (`t_run`, `t_dbutils`).
# MAGIC
# MAGIC **Why have a "child" notebook at all?**
# MAGIC In real projects you don't want to copy-paste the same setup code into
# MAGIC twenty notebooks. You put it in one place and pull it in — exactly like
# MAGIC importing a shared library. This file plays the role of that shared library
# MAGIC so we can demonstrate two different ways of calling it.

# COMMAND ----------

# A plain variable. The point of the demo is that the CALLING notebook will be
# able to see this value — proving the two notebooks genuinely shared state.
CHILD_VALUE = "child_ran_ok"

# Printing gives us visible proof in the logs that this file actually executed,
# rather than being silently skipped.
print("child notebook executed")

# Databricks notebook source
# MAGIC %md
# MAGIC # 4. `%sh` — run a shell command
# MAGIC
# MAGIC **What it does:** runs an ordinary Linux command on the machine your notebook
# MAGIC is running on, exactly as if you had opened a terminal there.
# MAGIC
# MAGIC **Why it is useful:** it is an escape hatch. When something behaves unexpectedly,
# MAGIC `%sh` lets you inspect the actual machine — what user am I? where am I? is that
# MAGIC file really there? Most troubleshooting starts with questions like these.
# MAGIC
# MAGIC **Important limitation to understand:** the command runs only on the *driver*
# MAGIC (the single coordinating machine), **not** across the cluster. So `%sh` is for
# MAGIC inspecting and small local tasks — never for processing your data. Data work
# MAGIC belongs in Spark, which spreads the job across every machine.

# COMMAND ----------

# MAGIC %sh
# MAGIC # A basic sanity check that shell execution is permitted at all.
# MAGIC echo "shell works"
# MAGIC
# MAGIC # Which OS user is the notebook running as? Useful when a file-permission
# MAGIC # error appears and you need to know who was denied.
# MAGIC whoami
# MAGIC
# MAGIC # Which directory are we in? Explains why a relative file path did or didn't
# MAGIC # resolve — a very common source of confusion.
# MAGIC pwd

# COMMAND ----------

dbutils.notebook.exit("sh PASS")

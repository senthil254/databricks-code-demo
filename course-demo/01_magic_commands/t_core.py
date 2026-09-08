# Databricks notebook source
# MAGIC %md
# MAGIC # 1. Core magic commands: `%md`, `%python`, `%sql`
# MAGIC
# MAGIC **What is a "magic command"?**
# MAGIC A line starting with `%` at the very top of a cell. It tells Databricks
# MAGIC *"treat this cell differently from the default."* Normally a cell is Python;
# MAGIC a magic can switch it to SQL, to documentation, to a shell command, and so on.
# MAGIC
# MAGIC **Why it matters (the business case):**
# MAGIC One notebook can hold the SQL an analyst wrote, the Python a data scientist
# MAGIC wrote, and the plain-English explanation a manager needs — side by side, in
# MAGIC one file, sharing one set of data. No exporting, no handing files between teams.
# MAGIC
# MAGIC **This cell is itself the first demo:** it uses `%md` (markdown) to render
# MAGIC formatted text instead of running code. That is how you document a notebook
# MAGIC so a non-technical reader can follow along.

# COMMAND ----------

# A dictionary to collect our results as we go, so the notebook can report a
# clean pass/fail summary at the end instead of making you scroll through logs.
results = {}

# COMMAND ----------

# MAGIC %md
# MAGIC ### `%python` — run Python
# MAGIC Python is the default language here, so `%python` is redundant. We state it
# MAGIC explicitly to prove the magic is accepted and to make the language obvious
# MAGIC to a reader skimming the notebook.

# COMMAND ----------

# MAGIC %python
# MAGIC # spark.table() opens a governed table in Unity Catalog. Nothing is copied or
# MAGIC # downloaded — we are pointing at data that lives in the lakehouse.
# MAGIC df = spark.table("demo_training.magic_cmds.customers")
# MAGIC
# MAGIC # .count() forces Spark to actually go and read the data. Until now nothing ran:
# MAGIC # Spark is "lazy" and waits for a real question before doing work. Seeing a
# MAGIC # number proves the connection, the permissions, and the table are all healthy.
# MAGIC print("python rows:", df.count())

# COMMAND ----------

# MAGIC %md
# MAGIC ### `%sql` — run SQL in the same notebook
# MAGIC The **key benefit**: an analyst who only knows SQL can contribute to the very
# MAGIC same notebook as a Python engineer. Below we create a *temporary view* — a
# MAGIC named, reusable query result. It costs nothing to store and disappears when
# MAGIC the session ends, so it is a safe way to build up a result step by step.

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Filter our customers down to just the 'gold' tier.
# MAGIC -- Naming this result 'gold_customers' means the next cell can reuse it
# MAGIC -- without repeating the filter logic.
# MAGIC CREATE OR REPLACE TEMP VIEW gold_customers AS
# MAGIC SELECT * FROM demo_training.magic_cmds.customers WHERE tier = 'gold'

# COMMAND ----------

# MAGIC %md
# MAGIC ### The payoff: SQL and Python share one workspace
# MAGIC The view was created in **SQL**. The next cell reads it in **Python** — with no
# MAGIC export, no file, no copy. This is the single most useful thing about magic
# MAGIC commands: **each team works in its own language, on the same live data.**

# COMMAND ----------

# Reading the SQL-created view from Python. If this returns a number, the two
# languages are genuinely sharing one session and one set of data.
n = spark.table("gold_customers").count()
print("cross-language temp view rows:", n)

# COMMAND ----------

import json

# dbutils.notebook.exit() ends the notebook and hands a value back to whatever
# called it. This is what makes a notebook usable as an automated, reusable step
# in a pipeline rather than something a human must read the output of.
dbutils.notebook.exit(json.dumps({
    "md": "PASS",
    "python": "PASS",
    "sql": "PASS",
    "cross_language_view": f"PASS ({n} gold rows)",
}))

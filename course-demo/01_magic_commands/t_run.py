# Databricks notebook source
# MAGIC %md
# MAGIC # 2. `%run` — reuse another notebook
# MAGIC
# MAGIC **What it does:** drops the entire contents of another notebook into *this* one
# MAGIC and runs it, as if you had pasted the code in yourself.
# MAGIC
# MAGIC **Why you would want that:** stop copy-pasting. Put your shared setup —
# MAGIC connection details, helper functions, standard filters — in one notebook and
# MAGIC `%run` it everywhere. Fix a bug once and every notebook gets the fix.
# MAGIC
# MAGIC **The important detail:** `%run` shares variables. Anything the child defines
# MAGIC is available here afterwards. (Compare this with `dbutils.notebook.run` in
# MAGIC notebook 5, which does *not* share variables — a genuinely different tool.)
# MAGIC
# MAGIC **Non-technical analogy:** `%run` is like pulling a colleague's checklist into
# MAGIC your own document so you can keep working with it. `dbutils.notebook.run` is
# MAGIC like emailing them a task and waiting for a one-line answer back.

# COMMAND ----------

# MAGIC %run ./child

# COMMAND ----------

# MAGIC %md
# MAGIC ### Proof it worked
# MAGIC `CHILD_VALUE` was never defined in this notebook — it was defined in `child`.
# MAGIC The fact that we can read it here is the evidence that `%run` merged the two
# MAGIC notebooks into a single shared session.

# COMMAND ----------

# If %run had failed, CHILD_VALUE would not exist and this line would raise a
# NameError. So this cell doubles as the test.
dbutils.notebook.exit(f"run PASS ({CHILD_VALUE})")

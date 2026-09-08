# Databricks notebook source
# MAGIC %md
# MAGIC # 5. `dbutils` — the Databricks toolbox
# MAGIC
# MAGIC `dbutils` is not a magic command; it is a built-in Python object that every
# MAGIC Databricks notebook gets for free. It is where the platform's practical tools
# MAGIC live. We cover the three that turn a notebook from a personal scratchpad into
# MAGIC something you can safely put into production:
# MAGIC
# MAGIC | Tool | What it gives you |
# MAGIC |---|---|
# MAGIC | `dbutils.widgets` | Input boxes, so the notebook takes parameters |
# MAGIC | `dbutils.secrets` | Passwords without writing passwords in code |
# MAGIC | `dbutils.notebook.run` | Call another notebook and get an answer back |

# COMMAND ----------

# MAGIC %md
# MAGIC ### Widgets — make one notebook serve many cases
# MAGIC A widget is an input box at the top of the notebook. Instead of editing code to
# MAGIC change 'gold' to 'silver', a **non-technical user can just pick a value from a
# MAGIC box** and re-run. One notebook then covers every tier, region or date range.
# MAGIC
# MAGIC The same widget is also how an automated schedule passes parameters in — so the
# MAGIC identical notebook serves both a human clicking, and a job running at 3am.

# COMMAND ----------

# Create a text input. Arguments: internal name, default value, visible label.
dbutils.widgets.text("tier", "gold", "Customer tier")

# Read whatever is currently in the box. Because a default was supplied, this works
# even on the very first run, when nobody has typed anything.
t = dbutils.widgets.get("tier")
print("widget tier =", t)

# COMMAND ----------

# MAGIC %md
# MAGIC ### Using the widget value in a query
# MAGIC The query below changes its behaviour based on the box above — no code edit.

# COMMAND ----------

# Note: for a real production job, prefer a parameterised query over string
# formatting. We keep it simple here to keep the demo readable.
n = spark.sql(
    f"SELECT count(*) c FROM demo_training.magic_cmds.customers WHERE tier='{t}'"
).collect()[0]["c"]

# COMMAND ----------

# MAGIC %md
# MAGIC ### Secrets — the rule is "never type a password into a notebook"
# MAGIC Notebooks get committed to Git, shared, and screenshotted in demos like this
# MAGIC one. A password written in a cell is a password leaked.
# MAGIC
# MAGIC `dbutils.secrets` keeps credentials in a locked vault. The notebook asks for a
# MAGIC secret by *name*, uses it, and Databricks automatically blanks the value out of
# MAGIC any printed output. **The person running the notebook never sees the password.**
# MAGIC
# MAGIC We only *list* the vaults here — we never read a value. Expect `0`, because this
# MAGIC training workspace has no vaults configured yet.

# COMMAND ----------

# Wrapped in try/except so a permissions error becomes a readable message instead
# of stopping the whole demo.
try:
    scopes = str(len(dbutils.secrets.listScopes()))
except Exception as e:
    scopes = f"ERR: {type(e).__name__}"

# COMMAND ----------

# MAGIC %md
# MAGIC ### `dbutils.notebook.run` — chain notebooks into a workflow
# MAGIC This runs another notebook in its **own separate session** and returns just its
# MAGIC final answer. Contrast with `%run` (notebook 2), which merges the two notebooks
# MAGIC and shares all variables.
# MAGIC
# MAGIC **When to use which:** `%run` for shared helper code you want in your session.
# MAGIC `dbutils.notebook.run` for building a *pipeline* — step 1, then step 2, then
# MAGIC step 3 — where each step stays cleanly isolated from the others.

# COMMAND ----------

# The '60' is a timeout in seconds. Without a timeout, a hung notebook could block
# a production pipeline indefinitely.
child = dbutils.notebook.run("./child", 60)

# COMMAND ----------

import json
dbutils.notebook.exit(json.dumps({
    "widgets": f"PASS (tier={t}, {n} rows)",
    "secrets_scopes": scopes,
    "notebook_run": "PASS",
}))

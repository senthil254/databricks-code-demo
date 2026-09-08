# Databricks notebook source
# MAGIC %md
# MAGIC # 3. `%pip` — install a library for this notebook only
# MAGIC
# MAGIC **What it does:** installs an open-source Python package on the fly.
# MAGIC
# MAGIC **Why this is a big deal:** the install is *scoped to this notebook session*.
# MAGIC You are not changing the shared cluster, so you cannot break a colleague's job
# MAGIC by installing something they didn't ask for. Before this existed, adding a
# MAGIC library meant filing a ticket and restarting shared infrastructure.
# MAGIC
# MAGIC **Why we pin the version (`==0.9.0`):** without a pinned version you get
# MAGIC whatever is newest that day, so the same notebook can work on Monday and fail
# MAGIC on Tuesday. Pinning makes runs **reproducible** — the same result every time.
# MAGIC That is a requirement in any regulated or audited environment.
# MAGIC
# MAGIC **Heads-up:** `%pip` restarts the Python process, so any variables defined
# MAGIC before this cell are wiped. Always put `%pip` at the *top* of a notebook.

# COMMAND ----------

# MAGIC %pip install tabulate==0.9.0

# COMMAND ----------

# MAGIC %md
# MAGIC ### Proof the install worked
# MAGIC Importing the package is the real test — if the install had silently failed,
# MAGIC this import would raise `ModuleNotFoundError`.

# COMMAND ----------

# 'tabulate' is a small library that formats data as readable tables. The library
# itself doesn't matter; it is a stand-in for whatever your project needs.
import tabulate

# Reading the version back confirms we got the EXACT version we pinned, not a
# different one that happened to already be installed.
v = tabulate.__version__

# COMMAND ----------

dbutils.notebook.exit(f"pip PASS (tabulate {v})")

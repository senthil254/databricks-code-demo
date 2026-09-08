# Databricks notebook source
# MAGIC %md
# MAGIC # Databricks Magic Commands — Demo Walkthrough
# MAGIC
# MAGIC **Start here.** This notebook runs all six lessons in order and reports a
# MAGIC single pass/fail scoreboard at the end.
# MAGIC
# MAGIC ### What is this demo about?
# MAGIC A Databricks notebook is a document that mixes explanation, code and results.
# MAGIC **Magic commands** are the switches that let one notebook do many different
# MAGIC jobs — run SQL in one cell, Python in the next, install software in a third.
# MAGIC
# MAGIC **Why an organisation cares:** analysts (SQL), engineers (Python) and managers
# MAGIC (plain English) collaborate in *one* document on *one* copy of the data.
# MAGIC No exporting spreadsheets, no emailing files, no "which version is current?".
# MAGIC
# MAGIC ### The six lessons
# MAGIC | # | Notebook | Teaches | Why it matters |
# MAGIC |---|---|---|---|
# MAGIC | 1 | `t_core` | `%md`, `%python`, `%sql` | Mix documentation, Python and SQL in one file |
# MAGIC | 2 | `t_run` | `%run` | Reuse shared code instead of copy-pasting it |
# MAGIC | 3 | `t_pip` | `%pip` | Add a library safely, without affecting colleagues |
# MAGIC | 4 | `t_sh` | `%sh` | Inspect the machine when troubleshooting |
# MAGIC | 5 | `t_dbutils` | `dbutils` | Parameters, secure passwords, chained notebooks |
# MAGIC | 6 | `t_fs_vol` | `dbutils.fs` | Handle files under proper access control |
# MAGIC
# MAGIC ### Before you run
# MAGIC - Data must exist: run `sql/00_setup_demo_training.sql` (creates
# MAGIC   `demo_training.magic_cmds` with 100 customers / 300 orders / 500 events).
# MAGIC - First run takes ~30–50s per lesson while serverless compute starts up.
# MAGIC
# MAGIC > Commands that do **not** work on this workspace (`%scala`, `%r`, `%fs`,
# MAGIC > `%conda`) are deliberately excluded — see `notebooks/not_supported/`.

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 1 — Check the data is there
# MAGIC Always confirm your inputs before running anything. Discovering a missing table
# MAGIC now is far better than a confusing failure three lessons in.

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Count all three demo tables in one query so we see the full picture at once.
# MAGIC   SELECT 'customers' AS table_name, count(*) AS row_count FROM demo_training.magic_cmds.customers
# MAGIC UNION ALL SELECT 'orders',    count(*) FROM demo_training.magic_cmds.orders
# MAGIC UNION ALL SELECT 'events',    count(*) FROM demo_training.magic_cmds.events
# MAGIC ORDER BY table_name

# COMMAND ----------

# MAGIC %md
# MAGIC Expected: **customers 100, events 500, orders 300**. Anything else (especially
# MAGIC a "table not found" error) means the setup SQL has not been run yet.

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 2 — Run the six lessons in order
# MAGIC
# MAGIC We use `dbutils.notebook.run`, which executes each lesson in its **own isolated
# MAGIC session** and hands back its final result. Isolation is the point: one lesson
# MAGIC failing cannot corrupt or mask the others, so the scoreboard is trustworthy.
# MAGIC
# MAGIC (This is itself lesson 5 in action — the demo runs on the very feature it teaches.)

# COMMAND ----------

import json, time

# Each entry: (notebook file, plain-English description of what it proves).
# The order is deliberate — concepts build on each other.
LESSONS = [
    ("t_core",    "1. %md, %python, %sql + sharing data between languages"),
    ("t_run",     "2. %run - pull in a shared helper notebook"),
    ("t_pip",     "3. %pip - install a pinned library for this session"),
    ("t_sh",      "4. %sh  - run a shell command on the driver"),
    ("t_dbutils", "5. dbutils - widgets, secrets, notebook chaining"),
    ("t_fs_vol",  "6. dbutils.fs - file operations on a governed UC Volume"),
]

# Generous per-lesson timeout: serverless cold start alone can take ~50s.
TIMEOUT_SECONDS = 600

# COMMAND ----------

results = []

for nb, description in LESSONS:
    print(f"\n{'='*70}\nRunning {nb}  —  {description}\n{'='*70}")
    started = time.time()
    try:
        # Returns whatever the lesson passed to dbutils.notebook.exit().
        raw = dbutils.notebook.run(f"./{nb}", TIMEOUT_SECONDS)
        status = "PASS"
        # Lessons return either a JSON object or a plain string. Handle both so a
        # formatting difference is never mistaken for a failure.
        try:
            detail = json.dumps(json.loads(raw))
        except (json.JSONDecodeError, TypeError):
            detail = str(raw)
    except Exception as e:
        # Catch the failure so the remaining lessons still run and we get a
        # complete picture instead of stopping at the first problem.
        status = "FAIL"
        detail = f"{type(e).__name__}: {str(e)[:300]}"

    elapsed = round(time.time() - started, 1)
    print(f"-> {status} in {elapsed}s :: {detail}")
    results.append({
        "lesson": description,
        "notebook": nb,
        "status": status,
        "seconds": elapsed,
        "detail": detail,
    })

# COMMAND ----------

# MAGIC %md
# MAGIC ## Step 3 — Scoreboard
# MAGIC One table showing every lesson, whether it passed, and how long it took.

# COMMAND ----------

# Turning the results into a Spark DataFrame lets display() render a proper sortable
# table — much easier to read on a projector than raw printed text.
summary_df = spark.createDataFrame(results).select(
    "lesson", "status", "seconds", "detail"
)
display(summary_df)

# COMMAND ----------

passed = sum(r["status"] == "PASS" for r in results)
total = len(results)

print(f"\n{'='*70}")
print(f"  RESULT: {passed}/{total} lessons passed")
print(f"{'='*70}")

for r in results:
    print(f"  [{r['status']}] {r['lesson']}  ({r['seconds']}s)")

# Fail loudly if anything broke. In an automated schedule this is what turns a
# silent problem into an alert somebody actually sees.
if passed != total:
    failed = [r["notebook"] for r in results if r["status"] == "FAIL"]
    raise Exception(f"{total - passed} lesson(s) failed: {', '.join(failed)}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Recap — what you just saw
# MAGIC
# MAGIC - **One notebook, many languages.** SQL and Python side by side on the same live
# MAGIC   data, so every team works in the language it already knows.
# MAGIC - **Reuse over copy-paste.** `%run` for shared helpers, `dbutils.notebook.run`
# MAGIC   for chaining isolated pipeline steps.
# MAGIC - **Safe by default.** `%pip` cannot break a colleague's work; `dbutils.secrets`
# MAGIC   keeps passwords out of code; UC Volumes apply the same permissions to files as
# MAGIC   to tables.
# MAGIC - **Built for automation.** Widgets take parameters and `dbutils.notebook.exit`
# MAGIC   returns results, so the same notebook a person runs by hand can run unattended
# MAGIC   on a schedule.
# MAGIC
# MAGIC **Honest limitations** (see `notebooks/not_supported/`): `%scala` and `%r` need
# MAGIC classic compute, which this serverless workspace does not have; `%fs` is blocked
# MAGIC because it is Scala-based — use `dbutils.fs`; `%conda` is retired — use `%pip`.

# COMMAND ----------

dbutils.notebook.exit(json.dumps({"passed": passed, "total": total}))

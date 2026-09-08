# Databricks notebook source
# MAGIC %md
# MAGIC # Databricks Magic Commands — All Six Lessons in One Notebook
# MAGIC
# MAGIC This notebook contains the code from all six lesson notebooks, inline and in
# MAGIC order, so you can **run it top to bottom and watch each command execute**.
# MAGIC
# MAGIC - Use **this** notebook to walk through the material cell by cell.
# MAGIC - Use `00_demo_walkthrough` to run the six as separate notebooks and get a scoreboard.
# MAGIC - The individual `t_*` notebooks remain unchanged if you want them standalone.
# MAGIC
# MAGIC ### What is a "magic command"?
# MAGIC A line starting with `%` at the very top of a cell. It tells Databricks
# MAGIC *"treat this cell differently from the default."* Normally a cell is Python; a
# MAGIC magic can switch it to SQL, to documentation, to a shell command, and so on.
# MAGIC
# MAGIC **Why an organisation cares:** analysts (SQL), engineers (Python) and managers
# MAGIC (plain English) collaborate in *one* document on *one* copy of the data. No
# MAGIC exporting spreadsheets, no emailing files, no "which version is current?".
# MAGIC
# MAGIC ### Running order
# MAGIC | # | Topic | Why it matters |
# MAGIC |---|---|---|
# MAGIC | 0 | `%pip` | Add a library safely, without affecting colleagues |
# MAGIC | 1 | `%md`, `%python`, `%sql` | Mix documentation, Python and SQL in one file |
# MAGIC | 2 | `%run` | Reuse shared code instead of copy-pasting it |
# MAGIC | 3 | `%sh` | Inspect the machine when troubleshooting |
# MAGIC | 4 | `dbutils` | Parameters, secure passwords, chained notebooks |
# MAGIC | 5 | `dbutils.fs` | Handle files under proper access control |
# MAGIC
# MAGIC **Prerequisite:** run `sql/00_setup_demo_training.sql` first — it creates
# MAGIC `demo_training.magic_cmds` with 100 customers / 300 orders / 500 events.
# MAGIC
# MAGIC > Commands that do **not** work on this serverless workspace (`%scala`, `%r`,
# MAGIC > `%fs`, `%conda`) are excluded on purpose. See `not_supported/` for each one
# MAGIC > and the reason it fails.

# COMMAND ----------

# MAGIC %md
# MAGIC ## Lesson 0 — `%pip`: install a library for this notebook only
# MAGIC
# MAGIC **Why is this first, and not third?**
# MAGIC `%pip` **restarts the Python process**, which erases every variable defined
# MAGIC before it. If we ran it in the middle, all our earlier work would silently
# MAGIC vanish. So the rule is: **`%pip` always goes at the top of a notebook.** This is
# MAGIC one of the most common causes of "my variable disappeared" confusion.
# MAGIC
# MAGIC **What it does:** installs an open-source Python package on the fly, *scoped to
# MAGIC this notebook session only*. You are not changing the shared cluster, so you
# MAGIC cannot break a colleague's job. Before this existed, adding a library meant
# MAGIC filing a ticket and restarting shared infrastructure.
# MAGIC
# MAGIC **Why pin the version (`==0.9.0`):** without pinning you get whatever is newest
# MAGIC that day, so the same notebook can work Monday and fail Tuesday. Pinning makes
# MAGIC runs **reproducible** — a requirement in any audited environment.

# COMMAND ----------

# MAGIC %pip install tabulate==0.9.0

# COMMAND ----------

# MAGIC %md
# MAGIC ### Proof the install worked
# MAGIC Importing is the real test — a silently failed install shows up here as
# MAGIC `ModuleNotFoundError`.

# COMMAND ----------

# 'tabulate' formats data as readable text tables. The library itself doesn't
# matter; it stands in for whatever your project actually needs.
import tabulate

# Reading the version back confirms we got the EXACT version we pinned, not some
# other version that happened to be installed already.
pip_result = f"PASS (tabulate {tabulate.__version__})"
print(pip_result)

# COMMAND ----------

# Collect results as we go so we can print one clean scoreboard at the end,
# instead of making you scroll back through the whole notebook.
# NOTE: defined AFTER the %pip cell, because %pip would have wiped it.
results = {"0. %pip": pip_result}

# COMMAND ----------

# MAGIC %md
# MAGIC ## Lesson 1 — `%md`, `%python`, `%sql`
# MAGIC
# MAGIC **This cell is itself the first demo:** it uses `%md` (markdown) to render
# MAGIC formatted text instead of running code. That is how you document a notebook so
# MAGIC a non-technical reader can follow along — the explanation lives right next to
# MAGIC the code it describes, so the two never drift apart.

# COMMAND ----------

# MAGIC %md
# MAGIC ### `%python` — run Python
# MAGIC Python is the default here, so `%python` is redundant. We state it explicitly to
# MAGIC prove the magic is accepted and to make the language obvious to a reader skimming.

# COMMAND ----------

# MAGIC %python
# MAGIC # spark.table() opens a governed table in Unity Catalog. Nothing is copied or
# MAGIC # downloaded — we are pointing at data that lives in the lakehouse.
# MAGIC df = spark.table("demo_training.magic_cmds.customers")
# MAGIC
# MAGIC # .count() forces Spark to actually read the data. Until now nothing ran: Spark
# MAGIC # is "lazy" and waits for a real question before doing work. Seeing a number
# MAGIC # proves the connection, the permissions and the table are all healthy.
# MAGIC print("python rows:", df.count())

# COMMAND ----------

# MAGIC %md
# MAGIC ### `%sql` — run SQL in the same notebook
# MAGIC **The key benefit:** an analyst who only knows SQL can contribute to the very
# MAGIC same notebook as a Python engineer.
# MAGIC
# MAGIC Below we create a *temporary view* — a named, reusable query result. It costs
# MAGIC nothing to store and disappears when the session ends, so it is a safe way to
# MAGIC build up a result step by step.

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Filter our customers down to just the 'gold' tier.
# MAGIC -- Naming this result 'gold_customers' lets the next cell reuse it without
# MAGIC -- repeating the filter logic.
# MAGIC CREATE OR REPLACE TEMP VIEW gold_customers AS
# MAGIC SELECT * FROM demo_training.magic_cmds.customers WHERE tier = 'gold'

# COMMAND ----------

# MAGIC %md
# MAGIC ### The payoff: SQL and Python share one workspace
# MAGIC The view was created in **SQL**. The next cell reads it in **Python** — no export,
# MAGIC no file, no copy. This is the single most useful thing about magic commands:
# MAGIC **each team works in its own language, on the same live data.**

# COMMAND ----------

# Reading the SQL-created view from Python. A number here proves the two languages
# genuinely share one session and one set of data.
gold_count = spark.table("gold_customers").count()
print("cross-language temp view rows:", gold_count)

results["1. %md / %python / %sql"] = f"PASS ({gold_count} gold customers, SQL view read from Python)"

# COMMAND ----------

# MAGIC %md
# MAGIC ## Lesson 2 — `%run`: reuse another notebook
# MAGIC
# MAGIC **What it does:** drops the entire contents of another notebook into *this* one
# MAGIC and runs it, as if you had pasted the code in yourself.
# MAGIC
# MAGIC **Why you would want that:** stop copy-pasting. Put shared setup — connection
# MAGIC details, helper functions, standard filters — in one notebook and `%run` it
# MAGIC everywhere. Fix a bug once and every notebook gets the fix.
# MAGIC
# MAGIC **The important detail:** `%run` **shares variables**. Anything the child defines
# MAGIC is available here afterwards. Compare with `dbutils.notebook.run` in Lesson 4,
# MAGIC which does *not* share variables — a genuinely different tool.
# MAGIC
# MAGIC **Non-technical analogy:** `%run` is like pulling a colleague's checklist into
# MAGIC your own document so you can keep working with it. `dbutils.notebook.run` is like
# MAGIC emailing them a task and waiting for a one-line answer back.

# COMMAND ----------

# MAGIC %run ./child

# COMMAND ----------

# MAGIC %md
# MAGIC ### Proof it worked
# MAGIC `CHILD_VALUE` was never defined in this notebook — it was defined in `child`.
# MAGIC Reading it here is the evidence that `%run` merged the two into one session.
# MAGIC (If `%run` had failed, this cell would raise `NameError`, so it doubles as the test.)

# COMMAND ----------

print("value from child notebook:", CHILD_VALUE)
results["2. %run"] = f"PASS ({CHILD_VALUE})"

# COMMAND ----------

# MAGIC %md
# MAGIC ## Lesson 3 — `%sh`: run a shell command
# MAGIC
# MAGIC **What it does:** runs an ordinary Linux command on the machine your notebook is
# MAGIC running on, exactly as if you had opened a terminal there.
# MAGIC
# MAGIC **Why it is useful:** it is an escape hatch. When something behaves unexpectedly,
# MAGIC `%sh` lets you inspect the actual machine — what user am I? where am I? is that
# MAGIC file really there? Most troubleshooting starts with questions like these.
# MAGIC
# MAGIC **Important limitation:** the command runs only on the *driver* (the single
# MAGIC coordinating machine), **not** across the cluster. So `%sh` is for inspecting and
# MAGIC small local tasks — never for processing your data. Data work belongs in Spark,
# MAGIC which spreads the job across every machine.

# COMMAND ----------

# MAGIC %sh
# MAGIC # A basic sanity check that shell execution is permitted at all.
# MAGIC echo "shell works"
# MAGIC
# MAGIC # Which OS user is the notebook running as? Useful when a file-permission error
# MAGIC # appears and you need to know who was denied.
# MAGIC whoami
# MAGIC
# MAGIC # Which directory are we in? Explains why a relative file path did or didn't
# MAGIC # resolve — a very common source of confusion.
# MAGIC pwd

# COMMAND ----------

results["3. %sh"] = "PASS (echo / whoami / pwd ran on the driver)"

# COMMAND ----------

# MAGIC %md
# MAGIC ## Lesson 4 — `dbutils`: the Databricks toolbox
# MAGIC
# MAGIC `dbutils` is not a magic command; it is a built-in Python object every Databricks
# MAGIC notebook gets for free. It is where the platform's practical tools live. These
# MAGIC three turn a notebook from a personal scratchpad into something you can safely
# MAGIC put into production:
# MAGIC
# MAGIC | Tool | What it gives you |
# MAGIC |---|---|
# MAGIC | `dbutils.widgets` | Input boxes, so the notebook takes parameters |
# MAGIC | `dbutils.secrets` | Passwords without writing passwords in code |
# MAGIC | `dbutils.notebook.run` | Call another notebook and get an answer back |

# COMMAND ----------

# MAGIC %md
# MAGIC ### Widgets — make one notebook serve many cases
# MAGIC A widget is an input box that appears at the top of the notebook. Instead of
# MAGIC editing code to change 'gold' to 'silver', a **non-technical user just picks a
# MAGIC value from a box** and re-runs. One notebook then covers every tier, region or
# MAGIC date range.
# MAGIC
# MAGIC The same widget is also how an automated schedule passes parameters in — so the
# MAGIC identical notebook serves both a human clicking, and a job running at 3am.
# MAGIC
# MAGIC **Watch the top of the screen** when this cell runs: the input box appears there.

# COMMAND ----------

# Create a text input. Arguments: internal name, default value, visible label.
dbutils.widgets.text("tier", "gold", "Customer tier")

# Read whatever is currently in the box. Because a default was supplied, this works
# on the very first run, when nobody has typed anything yet.
tier = dbutils.widgets.get("tier")
print("widget tier =", tier)

# COMMAND ----------

# MAGIC %md
# MAGIC ### Using the widget value in a query
# MAGIC The query below changes behaviour based on the box above — with no code edit.
# MAGIC **Try it live:** change the box to `silver` or `bronze` and re-run this cell.

# COMMAND ----------

# Note: for a real production job, prefer a parameterised query over string
# formatting. We keep it simple here to keep the demo readable.
tier_count = spark.sql(
    f"SELECT count(*) c FROM demo_training.magic_cmds.customers WHERE tier='{tier}'"
).collect()[0]["c"]

print(f"customers in tier '{tier}': {tier_count}")

# COMMAND ----------

# MAGIC %md
# MAGIC ### Secrets — the rule is "never type a password into a notebook"
# MAGIC Notebooks get committed to Git, shared, and screenshotted in demos like this one.
# MAGIC A password written in a cell is a password leaked.
# MAGIC
# MAGIC `dbutils.secrets` keeps credentials in a locked vault. The notebook asks for a
# MAGIC secret by *name*, uses it, and Databricks automatically blanks the value out of
# MAGIC any printed output. **The person running the notebook never sees the password.**
# MAGIC
# MAGIC We only *list* the vaults here — we never read a value. Expect `0`, because this
# MAGIC training workspace has no vaults configured yet.

# COMMAND ----------

# Wrapped in try/except so a permissions error becomes a readable message rather
# than stopping the whole demo.
try:
    scopes = str(len(dbutils.secrets.listScopes()))
except Exception as e:
    scopes = f"ERR: {type(e).__name__}"

print("secret scopes visible:", scopes)

# COMMAND ----------

# MAGIC %md
# MAGIC ### `dbutils.notebook.run` — chain notebooks into a workflow
# MAGIC This runs another notebook in its **own isolated session** and returns just its
# MAGIC final answer. Contrast with `%run` (Lesson 2), which merges the two notebooks and
# MAGIC shares all variables.
# MAGIC
# MAGIC **When to use which:** `%run` for shared helper code you want in your session.
# MAGIC `dbutils.notebook.run` for building a *pipeline* — step 1, then step 2, then step
# MAGIC 3 — where each step stays cleanly isolated from the others.

# COMMAND ----------

# The '60' is a timeout in seconds. Without one, a hung notebook could block a
# production pipeline indefinitely.
child_answer = dbutils.notebook.run("./child", 60)
print("child notebook returned:", child_answer)

results["4. dbutils"] = (
    f"PASS (widget tier={tier} -> {tier_count} rows; {scopes} secret scopes; notebook.run OK)"
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## Lesson 5 — `dbutils.fs`: working with files, the modern way
# MAGIC
# MAGIC Not all data is tidy tables. You also deal with CSVs, PDFs, images and model
# MAGIC files. `dbutils.fs` is how a notebook reads and writes those.
# MAGIC
# MAGIC ### Why you won't see `%fs` here
# MAGIC You will see `%fs` in older tutorials. **It does not work on this workspace**, for
# MAGIC two reasons worth understanding — both are common real-world stumbling blocks:
# MAGIC
# MAGIC 1. **`%fs` is blocked on serverless compute.** Under the hood it is implemented in
# MAGIC    Scala, and serverless does not permit Scala. `dbutils.fs` is the Python
# MAGIC    equivalent and works fine. **Use `dbutils.fs`.**
# MAGIC 2. **The old "DBFS" storage area is disabled** here, on purpose. DBFS had no real
# MAGIC    access control — anyone could read anyone's files.
# MAGIC
# MAGIC The replacement is a **Unity Catalog Volume**: a folder that lives inside your
# MAGIC catalog and obeys the same permissions as your tables. **Business benefit:** one
# MAGIC consistent set of access rules covering both tables and files, plus a full audit
# MAGIC trail of who opened what.

# COMMAND ----------

# MAGIC %md
# MAGIC ### Listing a location
# MAGIC `ls` on the root is a quick connectivity check — it proves the storage layer is
# MAGIC reachable before we attempt to write anything.

# COMMAND ----------

try:
    ls_root = f"PASS ({len(dbutils.fs.ls('/'))} entries)"
except Exception as e:
    # Capture the failure rather than crashing, so the scoreboard still prints.
    ls_root = f"FAIL {type(e).__name__}: {str(e)[:120]}"

print("ls / ->", ls_root)

# COMMAND ----------

# MAGIC %md
# MAGIC ### The full file lifecycle on a governed Volume
# MAGIC Create a folder, write a file, copy it, list the folder, then clean up. That is
# MAGIC the complete set of operations most data pipelines ever need.
# MAGIC
# MAGIC Note the path shape: `/Volumes/<catalog>/<schema>/<volume>/...`. It reads like a
# MAGIC normal folder path, but every access is permission-checked and logged.

# COMMAND ----------

V = "/Volumes/demo_training/magic_cmds/demo_vol"

try:
    # mkdirs creates the folder (and any missing parents). Safe to re-run.
    dbutils.fs.mkdirs(f"{V}/sub")

    # put writes text to a file. The final True means "overwrite if it exists",
    # which keeps this notebook safely repeatable.
    dbutils.fs.put(f"{V}/sub/a.txt", "hello", True)

    # cp copies a file — the everyday backup/staging operation.
    dbutils.fs.cp(f"{V}/sub/a.txt", f"{V}/sub/b.txt")

    # ls confirms both files are really there. Expect 2.
    file_count = len(dbutils.fs.ls(f"{V}/sub"))

    # Clean up after ourselves so the demo can be re-run from a clean slate.
    # True means recursive (delete the folder and everything in it).
    dbutils.fs.rm(f"{V}/sub", True)

    volume_ops = f"PASS (mkdirs/put/cp/ls={file_count}/rm)"
except Exception as e:
    volume_ops = f"FAIL {type(e).__name__}: {str(e)[:150]}"

print("volume operations ->", volume_ops)

results["5. dbutils.fs"] = f"{ls_root} | {volume_ops}"

# COMMAND ----------

# MAGIC %md
# MAGIC ## Scoreboard
# MAGIC Everything we just ran, in one table.

# COMMAND ----------

# Building a Spark DataFrame lets display() render a proper sortable table — much
# easier to read on a projector than raw printed text.
summary_df = spark.createDataFrame(
    [(k, v) for k, v in results.items()], ["lesson", "result"]
)
display(summary_df)

# COMMAND ----------

passed = sum(1 for v in results.values() if v.startswith("PASS"))
total = len(results)

print("=" * 70)
print(f"  RESULT: {passed}/{total} lessons passed")
print("=" * 70)
for k, v in results.items():
    print(f"  {k:28} {v}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Recap — what you just saw
# MAGIC
# MAGIC - **One notebook, many languages.** SQL and Python side by side on the same live
# MAGIC   data, so every team works in the language it already knows.
# MAGIC - **Reuse over copy-paste.** `%run` for shared helpers, `dbutils.notebook.run` for
# MAGIC   chaining isolated pipeline steps.
# MAGIC - **Safe by default.** `%pip` cannot break a colleague's work; `dbutils.secrets`
# MAGIC   keeps passwords out of code; UC Volumes apply the same permissions to files as
# MAGIC   to tables.
# MAGIC - **Built for automation.** Widgets take parameters and `dbutils.notebook.exit`
# MAGIC   returns results, so the same notebook a person runs by hand can run unattended
# MAGIC   on a schedule.
# MAGIC
# MAGIC **Honest limitations** (see `not_supported/`): `%scala` and `%r` need classic
# MAGIC compute, which this serverless workspace does not have; `%fs` is blocked because
# MAGIC it is Scala-based — use `dbutils.fs`; `%conda` is retired — use `%pip`.

# COMMAND ----------

import json
dbutils.notebook.exit(json.dumps({"passed": passed, "total": total}))

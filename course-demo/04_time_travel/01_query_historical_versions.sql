-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Topic 4 — Time Travel: Querying Historical Versions
-- MAGIC
-- MAGIC **Pure SQL. No Python.**
-- MAGIC
-- MAGIC Topic 3 introduced time travel in passing. This notebook is the deep dive: how
-- MAGIC history is actually recorded, every way to query it, how to see precisely what
-- MAGIC changed between two points, and where the limits are.
-- MAGIC
-- MAGIC ## The idea in one sentence
-- MAGIC **A Delta table remembers every version of itself, so you can query the past as
-- MAGIC easily as the present.**
-- MAGIC
-- MAGIC ## Why this is not just a nice trick
-- MAGIC
-- MAGIC | Situation | Without time travel | With time travel |
-- MAGIC |---|---|---|
-- MAGIC | A job corrupted the table at 2am | Restore from backup — hours, if a backup exists | Read yesterday's version, or roll back — seconds |
-- MAGIC | "Why is this number different from last month's report?" | Guesswork | Query the table as it was, and compare |
-- MAGIC | An auditor asks what the data looked like on 1 March | Hope someone kept a snapshot | Query it directly |
-- MAGIC | A model gave a strange prediction last quarter | Training data is gone | Reproduce the exact training set |
-- MAGIC | "Who changed this row, and when?" | No idea | It is in the history |
-- MAGIC
-- MAGIC The last two matter most in regulated work. **Reproducibility** — being able to
-- MAGIC show precisely what data produced a result — stops being a manual discipline and
-- MAGIC becomes a property of the storage layer.
-- MAGIC
-- MAGIC ## How it works, briefly
-- MAGIC Delta never edits a file in place. Every change writes **new** files and appends an
-- MAGIC entry to a transaction log. The old files are still there, so "version 3" is just
-- MAGIC "the set of files the log says existed at version 3". Reading the past therefore
-- MAGIC costs nothing extra — you are reading files that were never deleted.
-- MAGIC
-- MAGIC This notebook uses its own catalog, **`demo_timetravel`**, and drops it first so
-- MAGIC you watch the history accumulate from zero.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 0 — Clean slate

-- COMMAND ----------

DROP CATALOG IF EXISTS demo_timetravel CASCADE;

-- COMMAND ----------

CREATE CATALOG IF NOT EXISTS demo_timetravel
  COMMENT 'Training catalog for the time travel lesson. Safe to drop and recreate.';

CREATE SCHEMA IF NOT EXISTS demo_timetravel.inventory
  COMMENT 'Stock levels used to demonstrate Delta time travel.';

USE CATALOG demo_timetravel;
USE SCHEMA inventory;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 1 — Create a table, with Change Data Feed switched on
-- MAGIC
-- MAGIC `delta.enableChangeDataFeed = true` tells Delta to record not just *that* rows
-- MAGIC changed but **exactly how** — the before and after of each row. We use it in Step 8.
-- MAGIC
-- MAGIC **Enable it at creation time.** It only captures changes made *after* it is
-- MAGIC switched on, so turning it on later leaves a blind spot you cannot backfill. This
-- MAGIC is a decision worth making deliberately for any table that matters.

-- COMMAND ----------

CREATE TABLE stock_levels (
  sku        STRING  COMMENT 'Product code',
  warehouse  STRING  COMMENT 'Warehouse holding the stock',
  quantity   INT     COMMENT 'Units currently in stock',
  updated_on DATE    COMMENT 'Date this stock level was recorded'
)
COMMENT 'Warehouse stock levels. Change Data Feed enabled.'
TBLPROPERTIES (delta.enableChangeDataFeed = true);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 2 — Build up a history
-- MAGIC
-- MAGIC To demonstrate time travel we need a past. The next few cells each make **one
-- MAGIC distinct change**, so the history is easy to read: an initial load, a correction,
-- MAGIC a restock, a discontinued line, and a new product.
-- MAGIC
-- MAGIC Watch the version number climb with each one.

-- COMMAND ----------

-- Version 1: the initial load
INSERT INTO stock_levels VALUES
  ('SKU-100', 'Chennai',   500, DATE'2025-01-05'),
  ('SKU-200', 'Chennai',   120, DATE'2025-01-05'),
  ('SKU-300', 'Bangalore', 300, DATE'2025-01-05'),
  ('SKU-400', 'Bangalore',  45, DATE'2025-01-05');

-- COMMAND ----------

-- Version 2: a stock count found SKU-200 was wrong
UPDATE stock_levels
SET quantity = 95, updated_on = DATE'2025-01-20'
WHERE sku = 'SKU-200';

-- COMMAND ----------

-- Version 3: a delivery restocked SKU-400
UPDATE stock_levels
SET quantity = 250, updated_on = DATE'2025-02-01'
WHERE sku = 'SKU-400';

-- COMMAND ----------

-- Version 4: SKU-300 was discontinued and removed
DELETE FROM stock_levels WHERE sku = 'SKU-300';

-- COMMAND ----------

-- Version 5: a new product arrives
INSERT INTO stock_levels VALUES
  ('SKU-500', 'Mumbai', 80, DATE'2025-02-10');

-- COMMAND ----------

-- The table as it stands today.
SELECT * FROM stock_levels ORDER BY sku;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 3 — Reading the history
-- MAGIC
-- MAGIC `DESCRIBE HISTORY` is the index of every version. The columns that matter:
-- MAGIC
-- MAGIC | Column | What it tells you |
-- MAGIC |---|---|
-- MAGIC | `version` | The version number you pass to `VERSION AS OF` |
-- MAGIC | `timestamp` | When it happened — used by `TIMESTAMP AS OF` |
-- MAGIC | `userName` | **Who** made the change |
-- MAGIC | `operation` | What kind of change (`WRITE`, `UPDATE`, `DELETE`, `MERGE`…) |
-- MAGIC | `operationParameters` | The detail — e.g. the predicate of a `DELETE` |
-- MAGIC | `operationMetrics` | How many rows were added, changed or removed |
-- MAGIC
-- MAGIC Together these answer *who changed what, when, and how much* — with no auditing
-- MAGIC framework, no triggers and no extra tables. It is simply on.

-- COMMAND ----------

DESCRIBE HISTORY stock_levels;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### A readable audit log
-- MAGIC The raw output is wide. Because history is just a queryable table, we can select
-- MAGIC the useful parts — the sort of view you would hand to an auditor.
-- MAGIC
-- MAGIC Note `numOutputRows` in the metrics: it tells you the *size* of each change, so an
-- MAGIC unexpectedly large one stands out immediately.

-- COMMAND ----------

SELECT
  version,
  timestamp,
  userName                              AS changed_by,
  operation,
  operationMetrics['numOutputRows']     AS rows_written,
  operationMetrics['numDeletedRows']    AS rows_deleted,
  operationMetrics['numUpdatedRows']    AS rows_updated
FROM (DESCRIBE HISTORY stock_levels)
ORDER BY version;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 4 — `VERSION AS OF`: query a specific version
-- MAGIC
-- MAGIC The most direct form. Version 1 is the original load — before the correction,
-- MAGIC before the restock, before the deletion.
-- MAGIC
-- MAGIC SKU-300 is present again, and SKU-200 shows its original (wrong) count of 120.

-- COMMAND ----------

SELECT * FROM stock_levels VERSION AS OF 1 ORDER BY sku;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### The `@v` shorthand
-- MAGIC `table@v1` means the same as `table VERSION AS OF 1`. It is convenient because it
-- MAGIC works anywhere a table name works — including inside joins and subqueries, which
-- MAGIC is what makes Step 6 possible.

-- COMMAND ----------

SELECT * FROM stock_levels@v3 ORDER BY sku;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 5 — `TIMESTAMP AS OF`: query a point in time
-- MAGIC
-- MAGIC Usually more natural than version numbers: nobody asks *"what did version 3 look
-- MAGIC like?"* — they ask *"what did it look like last Tuesday?"*
-- MAGIC
-- MAGIC Delta returns the state as of the **latest version at or before** that moment.
-- MAGIC
-- MAGIC Because this notebook builds its history in seconds, we read the timestamp from
-- MAGIC the history itself rather than hardcoding a date. In real use you would simply
-- MAGIC write `TIMESTAMP AS OF '2025-03-01'`.

-- COMMAND ----------

-- The exact moment version 2 was committed.
SELECT version, timestamp AS committed_at
FROM (DESCRIBE HISTORY stock_levels)
WHERE version = 2;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### The syntax, and why we are not running it here
-- MAGIC On a real table you would simply write:
-- MAGIC
-- MAGIC ```sql
-- MAGIC SELECT * FROM stock_levels TIMESTAMP AS OF '2025-03-01';
-- MAGIC SELECT * FROM stock_levels TIMESTAMP AS OF '2025-03-01 14:30:00';
-- MAGIC ```
-- MAGIC
-- MAGIC **This notebook cannot run that, and the reason is worth understanding.** Delta
-- MAGIC rejects a timestamp that falls outside the table's actual lifetime, in both
-- MAGIC directions:
-- MAGIC
-- MAGIC | You ask for | Error |
-- MAGIC |---|---|
-- MAGIC | A time **before the first commit** | `DELTA_TIMESTAMP_BEFORE_FIRST_COMMIT` |
-- MAGIC | A time **after the latest commit** | `DELTA_TIMESTAMP_GREATER_THAN_COMMIT` |
-- MAGIC
-- MAGIC Our table was created seconds ago, so *every* fixed date fails one test or the
-- MAGIC other — `'2025-03-01'` is before it existed, and `current_timestamp()` is after
-- MAGIC its last commit. There is no safe literal to hardcode.
-- MAGIC
-- MAGIC You also cannot work around it with a variable or a subquery: the time travel
-- MAGIC clause requires a **constant** expression and rejects anything that refers to
-- MAGIC columns or session variables.
-- MAGIC
-- MAGIC > **The practical rule this leads to — and it is the real lesson of this step:**
-- MAGIC > **use timestamps to explore, and version numbers to reproduce.** A timestamp is
-- MAGIC > friendly for a human question ("last Tuesday") but resolves to whatever version
-- MAGIC > happened to be current then, and fails outright outside the table's lifetime. A
-- MAGIC > version number means exactly one state, forever. Anything that must be
-- MAGIC > repeatable — a regulatory report, a model's training set — should pin a
-- MAGIC > **version**, never a timestamp.
-- MAGIC
-- MAGIC Time travel is also bounded by the retention window, which we look at in Step 9.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 6 — Comparing two versions
-- MAGIC
-- MAGIC This is where time travel becomes genuinely powerful. Because any version behaves
-- MAGIC like an ordinary table, **you can join the past to the present in one query.**
-- MAGIC
-- MAGIC The question *"what changed between the initial load and now?"* becomes a single
-- MAGIC `FULL JOIN`, with a `CASE` to classify each row.

-- COMMAND ----------

SELECT
  coalesce(old.sku, new.sku) AS sku,
  old.quantity               AS quantity_at_v1,
  new.quantity               AS quantity_now,
  CASE
    WHEN old.sku IS NULL                        THEN 'ADDED since v1'
    WHEN new.sku IS NULL                        THEN 'REMOVED since v1'
    WHEN old.quantity IS DISTINCT FROM new.quantity THEN 'QUANTITY CHANGED'
    ELSE 'unchanged'
  END                        AS change_type
FROM      stock_levels@v1 AS old
FULL JOIN stock_levels    AS new ON old.sku = new.sku
ORDER BY sku;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Just the differences, with `EXCEPT`
-- MAGIC A blunter tool for the common question *"which rows are not the same?"*.

-- COMMAND ----------

SELECT 'only in v1' AS found_in, * FROM (SELECT * FROM stock_levels@v1 EXCEPT SELECT * FROM stock_levels)
UNION ALL
SELECT 'only in current', * FROM (SELECT * FROM stock_levels EXCEPT SELECT * FROM stock_levels@v1)
ORDER BY sku;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 7 — A realistic use: reproducing an old report
-- MAGIC
-- MAGIC Someone asks why January's stock report showed a different total. Rather than
-- MAGIC arguing, run the **same query** against the version that existed then, and against
-- MAGIC today, side by side.
-- MAGIC
-- MAGIC This is the pattern that ends most "the numbers don't match" disputes.

-- COMMAND ----------

SELECT 'as at version 1 (initial load)' AS reported_on,
       count(*) AS sku_count, sum(quantity) AS total_units
FROM stock_levels@v1
UNION ALL
SELECT 'as at version 3 (after restock)',
       count(*), sum(quantity)
FROM stock_levels@v3
UNION ALL
SELECT 'current',
       count(*), sum(quantity)
FROM stock_levels;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 8 — Change Data Feed: the row-by-row story
-- MAGIC
-- MAGIC Comparing versions tells you the **net difference**. Change Data Feed tells you
-- MAGIC the **individual changes** — including the before and after image of every updated
-- MAGIC row, and changes that later cancelled out and would be invisible in a diff.
-- MAGIC
-- MAGIC `table_changes()` takes the table name and a starting version. The `_change_type`
-- MAGIC column is the interesting one:
-- MAGIC
-- MAGIC | `_change_type` | Meaning |
-- MAGIC |---|---|
-- MAGIC | `insert` | Row was added |
-- MAGIC | `delete` | Row was removed |
-- MAGIC | `update_preimage` | The row **before** an update |
-- MAGIC | `update_postimage` | The row **after** an update |
-- MAGIC
-- MAGIC **Why this matters:** it is how you feed downstream systems only what changed,
-- MAGIC instead of reprocessing the whole table every night. It is also the cleanest
-- MAGIC possible audit answer to *"show me the exact prior value of this field"*.

-- COMMAND ----------

SELECT
  _change_type,
  _commit_version,
  sku,
  warehouse,
  quantity,
  updated_on
FROM table_changes('stock_levels', 1)
ORDER BY _commit_version, sku, _change_type;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Before and after, on one line
-- MAGIC Pairing the pre- and post-images turns the feed into a plain-English change log —
-- MAGIC *"SKU-200 went from 120 to 95 in version 2"*.

-- COMMAND ----------

SELECT
  before._commit_version           AS version,
  before.sku,
  before.quantity                  AS quantity_before,
  after.quantity                   AS quantity_after,
  after.quantity - before.quantity AS change
FROM      table_changes('stock_levels', 1) AS before
JOIN      table_changes('stock_levels', 1) AS after
       ON before.sku = after.sku
      AND before._commit_version = after._commit_version
WHERE before._change_type = 'update_preimage'
  AND after._change_type  = 'update_postimage'
ORDER BY version;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 9 — How far back can you go?
-- MAGIC
-- MAGIC Time travel is **not infinite**. Two settings control the window:
-- MAGIC
-- MAGIC | Property | Default | Controls |
-- MAGIC |---|---|---|
-- MAGIC | `delta.logRetentionDuration` | 30 days | How long the transaction log keeps version entries |
-- MAGIC | `delta.deletedFileRetentionDuration` | 7 days | How long the underlying data files are kept |
-- MAGIC
-- MAGIC **The effective limit is the smaller of the two — 7 days by default.** The log may
-- MAGIC still list version 5, but if `VACUUM` has removed its files, the query fails.
-- MAGIC
-- MAGIC For a table that must be reproducible for a year, extend both — and accept the
-- MAGIC storage cost, which is the honest trade being made.

-- COMMAND ----------

ALTER TABLE stock_levels SET TBLPROPERTIES (
  'delta.logRetentionDuration'          = 'interval 365 days',
  'delta.deletedFileRetentionDuration'  = 'interval 90 days'
);

-- COMMAND ----------

-- Confirm the retention settings and that Change Data Feed is on.
SHOW TBLPROPERTIES stock_levels;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC > **The one thing that permanently destroys time travel is `VACUUM`.** It deletes
-- MAGIC > the old files, and no setting brings them back. Shortening retention to save
-- MAGIC > storage is exactly the decision that leaves you unable to recover from a bad
-- MAGIC > load. Decide the window before you need it, not after.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 10 — `RESTORE`: travelling back for real
-- MAGIC
-- MAGIC Everything so far has been read-only. `RESTORE` makes a past version the current
-- MAGIC one — the recovery button after a bad job.
-- MAGIC
-- MAGIC Two things worth stressing:
-- MAGIC 1. **`RESTORE` is itself a new version.** Nothing is erased; the undo is on the
-- MAGIC    record, and you can undo the undo.
-- MAGIC 2. It is near-instant regardless of table size, because no data moves — the log
-- MAGIC    simply points at the earlier set of files again.

-- COMMAND ----------

RESTORE TABLE stock_levels TO VERSION AS OF 1;

-- COMMAND ----------

-- SKU-300 is back and SKU-500 is gone: this is the table as it was at version 1.
SELECT * FROM stock_levels ORDER BY sku;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### The restore is recorded, and reversible
-- MAGIC Note the new `RESTORE` entry at the top. The versions we restored *away* from are
-- MAGIC still there — so rolling forward again is just another restore.

-- COMMAND ----------

SELECT version, timestamp, operation
FROM (DESCRIBE HISTORY stock_levels)
ORDER BY version DESC;

-- COMMAND ----------

-- Roll forward again to prove nothing was lost.
RESTORE TABLE stock_levels TO VERSION AS OF 5;

SELECT * FROM stock_levels ORDER BY sku;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Recap
-- MAGIC
-- MAGIC | Step | Command | Use it for |
-- MAGIC |---|---|---|
-- MAGIC | 3 | `DESCRIBE HISTORY` | Who changed what, when, and how many rows |
-- MAGIC | 4 | `VERSION AS OF` / `@v1` | Exact, reproducible access to a known version |
-- MAGIC | 5 | `TIMESTAMP AS OF` | "What did it look like last Tuesday?" |
-- MAGIC | 6 | Join two versions | See precisely what changed between two points |
-- MAGIC | 7 | Same query, old version | Reproduce a past report and settle a dispute |
-- MAGIC | 8 | `table_changes()` | Row-level before/after; feed downstream systems |
-- MAGIC | 9 | Retention properties | Decide how far back you can go — before you need it |
-- MAGIC | 10 | `RESTORE` | Undo a bad job in seconds; itself auditable |
-- MAGIC
-- MAGIC ### Version numbers or timestamps?
-- MAGIC **Timestamps to explore, version numbers to reproduce.** A version number means
-- MAGIC exactly one state forever; a timestamp resolves to whatever version was current
-- MAGIC then, which is friendlier but less precise.
-- MAGIC
-- MAGIC ### The one-sentence takeaway
-- MAGIC **Time travel makes the history of your data a queryable asset — so recovery,
-- MAGIC auditing and reproducibility become ordinary SQL instead of special projects.**
-- MAGIC
-- MAGIC ### Cleaning up
-- MAGIC The teardown cell at the top clears everything on the next run. To remove it now,
-- MAGIC uncomment below.

-- COMMAND ----------

-- DROP CATALOG IF EXISTS demo_timetravel CASCADE;

SELECT 'Time travel demo complete' AS status;

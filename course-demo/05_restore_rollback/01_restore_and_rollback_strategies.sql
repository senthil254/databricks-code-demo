-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Topic 5 — Restore & Rollback Strategies
-- MAGIC
-- MAGIC **Pure SQL. No Python.**
-- MAGIC
-- MAGIC ## How this differs from Topic 4
-- MAGIC Topic 4 was about **reading** the past — history, `VERSION AS OF`, Change Data
-- MAGIC Feed. It showed `RESTORE` as one command among many.
-- MAGIC
-- MAGIC This notebook is about **recovering** when something has gone wrong, and choosing
-- MAGIC *which* recovery to use. `RESTORE` is only one of four options, and it is often
-- MAGIC the wrong one.
-- MAGIC
-- MAGIC | Situation | Strategy | Covered in |
-- MAGIC |---|---|---|
-- MAGIC | Whole table is wrong | `RESTORE` the table | Step 3 |
-- MAGIC | Only some rows are wrong | **Surgical repair** — merge from an old version | Step 4 |
-- MAGIC | Someone dropped the table | **`UNDROP TABLE`** | Step 5 |
-- MAGIC | Risky change you must be able to reverse | **Clone as a restore point** | Step 6 |
-- MAGIC | Big rebuild that must go live cleanly | **Blue/green swap** | Step 7 |
-- MAGIC
-- MAGIC ## The principle behind all of them
-- MAGIC **Match the size of the fix to the size of the problem.** Restoring an entire
-- MAGIC table because forty rows are wrong also throws away every *correct* change made
-- MAGIC since — including other people's work. That is a second incident caused by the
-- MAGIC response to the first.
-- MAGIC
-- MAGIC Uses its own catalog, **`demo_rollback`**, dropped first so you see it built live.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 0 — Clean slate

-- COMMAND ----------

DROP CATALOG IF EXISTS demo_rollback CASCADE;

-- COMMAND ----------

CREATE CATALOG IF NOT EXISTS demo_rollback
  COMMENT 'Training catalog for restore and rollback strategies. Safe to drop.';

CREATE SCHEMA IF NOT EXISTS demo_rollback.finance
  COMMENT 'Payments data used to demonstrate recovery strategies.';

USE CATALOG demo_rollback;
USE SCHEMA finance;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 1 — A table with a known-good state
-- MAGIC
-- MAGIC Payments across three regions. Remember these figures — after we break the table,
-- MAGIC this is what "correct" looks like.

-- COMMAND ----------

CREATE TABLE payments (
  payment_id INT           COMMENT 'Unique payment reference',
  customer   STRING        COMMENT 'Paying customer',
  region     STRING        COMMENT 'Sales region',
  amount     DECIMAL(10,2) COMMENT 'Payment amount',
  paid_on    DATE          COMMENT 'Date payment was received'
)
COMMENT 'Customer payments. Used to demonstrate rollback strategies.';

INSERT INTO payments VALUES
  (1, 'Aarav Sharma',   'South', 1500.00, DATE'2025-01-10'),
  (2, 'Priya Nair',     'South',  890.50, DATE'2025-01-14'),
  (3, 'Rohan Iyer',     'West',  2400.00, DATE'2025-01-20'),
  (4, 'Meera Krishnan', 'West',   650.75, DATE'2025-02-02'),
  (5, 'Vikram Rao',     'North', 1100.00, DATE'2025-02-11'),
  (6, 'Nisha Menon',    'North',  330.25, DATE'2025-02-18');

-- COMMAND ----------

SELECT region, count(*) AS payments, sum(amount) AS total
FROM payments GROUP BY region ORDER BY region;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 2 — Establish a named restore point *before* the risky change
-- MAGIC
-- MAGIC Before doing anything dangerous, **write down the version number you are at.**
-- MAGIC This is the single cheapest habit in this notebook.
-- MAGIC
-- MAGIC You cannot rely on remembering it under pressure at 2am, and you cannot rely on
-- MAGIC counting backwards from the history — a busy table may have gained versions from
-- MAGIC other jobs in the meantime.

-- COMMAND ----------

-- The current version is our known-good restore point.
SELECT max(version) AS known_good_version
FROM (DESCRIBE HISTORY payments);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 3 — Strategy A: full table `RESTORE`
-- MAGIC
-- MAGIC **Use when:** the whole table is wrong, and no correct changes have happened since
-- MAGIC the damage.
-- MAGIC
-- MAGIC The classic disaster: a job ran without its `WHERE` clause.

-- COMMAND ----------

-- The 2am mistake: intended for one region, applied to everything.
UPDATE payments SET amount = 0.00;

-- COMMAND ----------

-- Every total is now zero. This is the moment you would be paged.
SELECT region, count(*) AS payments, sum(amount) AS total
FROM payments GROUP BY region ORDER BY region;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Recovering
-- MAGIC Version 1 was our known-good point. `RESTORE` returns the table to it — in seconds,
-- MAGIC regardless of table size, because no data is copied. The log simply points at the
-- MAGIC earlier files again.

-- COMMAND ----------

RESTORE TABLE payments TO VERSION AS OF 1;

-- COMMAND ----------

-- The original totals are back.
SELECT region, count(*) AS payments, sum(amount) AS total
FROM payments GROUP BY region ORDER BY region;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### The catch nobody mentions
-- MAGIC `RESTORE` is **all or nothing for the whole table**. If a colleague had inserted
-- MAGIC ten legitimate payments *after* the bad update, restoring would silently discard
-- MAGIC those too — turning one incident into two.
-- MAGIC
-- MAGIC That is why the next strategy exists.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 4 — Strategy B: surgical repair
-- MAGIC
-- MAGIC **Use when:** only *some* rows are wrong, or good changes have happened since the
-- MAGIC damage and must be kept.
-- MAGIC
-- MAGIC The insight: **an old version is just a table.** So you can `MERGE` from the past
-- MAGIC into the present, repairing only the rows you name and leaving everything else
-- MAGIC untouched.
-- MAGIC
-- MAGIC Let us create exactly that mixed situation — some damage, and some good work.

-- COMMAND ----------

-- Damage: a bad job corrupted the South region only.
UPDATE payments SET amount = 1.00 WHERE region = 'South';

-- COMMAND ----------

-- Meanwhile, legitimate business continued: a new payment arrived.
INSERT INTO payments VALUES
  (7, 'Kavya Reddy', 'West', 980.00, DATE'2025-03-01');

-- COMMAND ----------

-- MAGIC %md
-- MAGIC South is corrupted, but payment 7 is genuine and must survive. A full `RESTORE`
-- MAGIC would fix South **and delete payment 7.** Unacceptable.

-- COMMAND ----------

SELECT * FROM payments ORDER BY payment_id;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### The surgical fix
-- MAGIC Merge the *South rows only* from the last good version back into the live table.
-- MAGIC Everything else — including payment 7 — is never touched.
-- MAGIC
-- MAGIC Note how the `WHERE` clause in the source scopes the blast radius. This is the
-- MAGIC difference between a targeted repair and a blunt rollback.

-- COMMAND ----------

MERGE INTO payments AS target
USING (
  SELECT * FROM payments VERSION AS OF 1 WHERE region = 'South'
) AS good
  ON target.payment_id = good.payment_id
WHEN MATCHED THEN UPDATE SET target.amount = good.amount;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC South is repaired **and** payment 7 survives. This is almost always the right
-- MAGIC choice on a table that more than one process writes to.

-- COMMAND ----------

SELECT * FROM payments ORDER BY payment_id;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 5 — Strategy C: `UNDROP` a deleted table
-- MAGIC
-- MAGIC **Use when:** someone dropped the table itself.
-- MAGIC
-- MAGIC `RESTORE` cannot help here — there is no table left to restore *into*. Unity
-- MAGIC Catalog keeps a dropped managed table recoverable for **7 days**, and `UNDROP`
-- MAGIC brings it back with its data and its full history intact.
-- MAGIC
-- MAGIC **Why this matters:** "someone dropped the production table" used to mean
-- MAGIC restoring from backup, if one existed. Now it is one statement.

-- COMMAND ----------

-- A table we are about to lose.
CREATE OR REPLACE TABLE payment_audit AS
SELECT payment_id, customer, amount FROM payments;

SELECT count(*) AS rows_before_drop FROM payment_audit;

-- COMMAND ----------

-- The accident.
DROP TABLE payment_audit;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Recovering it
-- MAGIC One statement, and the table is back — data and history included.

-- COMMAND ----------

UNDROP TABLE payment_audit;

-- COMMAND ----------

SELECT count(*) AS rows_after_undrop FROM payment_audit;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC > **Two limits worth stating.** The recovery window is **7 days** — after that the
-- MAGIC > table is genuinely gone. And `UNDROP` covers **managed** tables; an external
-- MAGIC > table's files were never deleted, so you re-register it instead.
-- MAGIC >
-- MAGIC > Dropping a **catalog or schema** with `CASCADE` is a much bigger event than
-- MAGIC > dropping one table. Treat `DROP ... CASCADE` on anything shared as a
-- MAGIC > change-controlled operation, not something typed casually into a notebook.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 6 — Strategy D: clone as an explicit restore point
-- MAGIC
-- MAGIC **Use when:** you are about to do something risky and want a named, obvious
-- MAGIC safety net that does not depend on retention settings or version numbers.
-- MAGIC
-- MAGIC Two kinds of clone, and the difference is the whole decision:
-- MAGIC
-- MAGIC | | `SHALLOW CLONE` | `DEEP CLONE` |
-- MAGIC |---|---|---|
-- MAGIC | Copies data files | **No** — points at the originals | **Yes** — a real copy |
-- MAGIC | Speed | Instant, even on huge tables | Proportional to size |
-- MAGIC | Extra storage | Almost none | Full second copy |
-- MAGIC | Survives `VACUUM` of the source | **No** — it breaks | **Yes** — independent |
-- MAGIC | Good for | Short-lived checkpoints, test copies | Real backups, handing data to another team |
-- MAGIC
-- MAGIC **The trap:** a shallow clone looks like a backup and is not one. It shares the
-- MAGIC source's files, so vacuuming the source can leave the clone unreadable. Use
-- MAGIC shallow for "I'll be done in an hour", deep for anything you actually rely on.

-- COMMAND ----------

-- Instant checkpoint before a risky change. Costs almost no storage.
CREATE OR REPLACE TABLE payments_checkpoint SHALLOW CLONE payments;

SELECT count(*) AS rows_in_checkpoint FROM payments_checkpoint;

-- COMMAND ----------

-- A durable backup, independent of the source's files and its VACUUM schedule.
CREATE OR REPLACE TABLE payments_backup DEEP CLONE payments;

SELECT count(*) AS rows_in_backup FROM payments_backup;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Recovering from a clone
-- MAGIC With a checkpoint in hand, recovery does not depend on reading history at all —
-- MAGIC you merge the good data back from a table you can see and query.

-- COMMAND ----------

-- Something goes wrong again.
DELETE FROM payments WHERE region = 'North';

SELECT count(*) AS rows_after_bad_delete FROM payments;

-- COMMAND ----------

-- Restore the missing rows from the checkpoint, leaving everything else alone.
MERGE INTO payments AS target
USING payments_checkpoint AS backup
  ON target.payment_id = backup.payment_id
WHEN NOT MATCHED THEN INSERT *;

SELECT count(*) AS rows_after_recovery FROM payments;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 7 — Strategy E: blue/green swap
-- MAGIC
-- MAGIC **Use when:** you are rebuilding a table that people are actively querying, and a
-- MAGIC half-finished state must never be visible.
-- MAGIC
-- MAGIC Rather than rewriting in place, you:
-- MAGIC 1. Build the new version **beside** the live table, under a different name
-- MAGIC 2. Check it — row counts, totals, spot checks
-- MAGIC 3. **Swap the names**, which is instant metadata-only
-- MAGIC 4. Keep the old table for a while as the rollback
-- MAGIC
-- MAGIC **Why bother, when Delta writes are already atomic?** Because the *checking* step
-- MAGIC is the point. A transaction guarantees the write completes; it does not guarantee
-- MAGIC the result is correct. Blue/green lets you inspect the new data before anyone sees
-- MAGIC it, and makes rollback a rename rather than a restore.

-- COMMAND ----------

-- 1. Build the new version alongside the live one.
CREATE OR REPLACE TABLE payments_new AS
SELECT payment_id, customer, upper(region) AS region, amount, paid_on
FROM payments;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### 2. Verify before swapping — this is the whole value of the pattern
-- MAGIC If these numbers disagree, you stop here and nobody downstream ever knew.

-- COMMAND ----------

SELECT 'live'   AS version, count(*) AS rows, sum(amount) AS total FROM payments
UNION ALL
SELECT 'new',              count(*),          sum(amount)          FROM payments_new;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### 3. Swap — instant, metadata only
-- MAGIC The old table is kept as `payments_old`. Rolling back is simply renaming it back.

-- COMMAND ----------

ALTER TABLE payments     RENAME TO payments_old;
ALTER TABLE payments_new RENAME TO payments;

-- COMMAND ----------

-- The live table now carries the new data.
SELECT * FROM payments ORDER BY payment_id;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 8 — What breaks your ability to roll back
-- MAGIC
-- MAGIC Every strategy above depends on old data still existing. Three things destroy that,
-- MAGIC and all three are things people do to save money:
-- MAGIC
-- MAGIC | Action | What you lose |
-- MAGIC |---|---|
-- MAGIC | `VACUUM` with short retention | Time travel and `RESTORE` before that window |
-- MAGIC | Shortening `delta.deletedFileRetentionDuration` | The same, permanently |
-- MAGIC | `VACUUM` on a shallow clone's **source** | The clone becomes unreadable |
-- MAGIC
-- MAGIC **Decide the retention window before you need it.** Nobody has ever regretted
-- MAGIC keeping seven extra days of history; plenty of people have regretted the opposite.

-- COMMAND ----------

ALTER TABLE payments SET TBLPROPERTIES (
  'delta.deletedFileRetentionDuration' = 'interval 30 days',
  'delta.logRetentionDuration'         = 'interval 90 days'
);

SHOW TBLPROPERTIES payments;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 9 — Rehearse the rollback before running it
-- MAGIC
-- MAGIC The most valuable habit in this notebook, and the one most often skipped.
-- MAGIC
-- MAGIC **Never test a recovery on production.** Clone the table, perform the recovery on
-- MAGIC the clone, confirm the numbers are what you expect, *then* do it for real. A clone
-- MAGIC is instant and nearly free — there is no excuse not to.

-- COMMAND ----------

-- Rehearse on a copy, not the real thing.
CREATE OR REPLACE TABLE payments_rehearsal SHALLOW CLONE payments;

RESTORE TABLE payments_rehearsal TO VERSION AS OF 0;

-- COMMAND ----------

-- Did the rehearsal produce what we expected? Now we know, at zero risk.
SELECT 'rehearsal after restore' AS which, count(*) AS rows FROM payments_rehearsal
UNION ALL
SELECT 'production (untouched)',            count(*)         FROM payments;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Recap — choosing a strategy
-- MAGIC
-- MAGIC | Strategy | Command | Use when | Main risk |
-- MAGIC |---|---|---|---|
-- MAGIC | **Full restore** | `RESTORE TABLE ... TO VERSION AS OF n` | Whole table wrong, nothing good since | Discards later legitimate changes |
-- MAGIC | **Surgical repair** | `MERGE` from `VERSION AS OF n` | Some rows wrong, good work must survive | Needs a key to match on |
-- MAGIC | **Undrop** | `UNDROP TABLE` | Table was dropped | 7-day window; managed tables only |
-- MAGIC | **Clone checkpoint** | `SHALLOW` / `DEEP CLONE` | Before a risky change | Shallow clone breaks if source is vacuumed |
-- MAGIC | **Blue/green swap** | Build aside, then `RENAME` | Rebuild with zero bad visibility | Needs storage for two copies |
-- MAGIC
-- MAGIC ### The three rules worth remembering
-- MAGIC 1. **Note the version number before any risky change.** Cheapest insurance there is.
-- MAGIC 2. **Match the fix to the damage.** Restoring a whole table to repair forty rows
-- MAGIC    destroys everyone else's work since — a second incident caused by the response
-- MAGIC    to the first.
-- MAGIC 3. **Rehearse on a clone.** Recovery is exactly the wrong moment for your first
-- MAGIC    attempt at a command.
-- MAGIC
-- MAGIC ### The one-sentence takeaway
-- MAGIC **Delta gives you several ways to undo; the skill is choosing the smallest one that
-- MAGIC fixes the problem.**
-- MAGIC
-- MAGIC ### Cleaning up
-- MAGIC The teardown cell at the top clears everything on the next run. To remove it now,
-- MAGIC uncomment below.

-- COMMAND ----------

-- DROP CATALOG IF EXISTS demo_rollback CASCADE;

SELECT 'Restore and rollback demo complete' AS status;

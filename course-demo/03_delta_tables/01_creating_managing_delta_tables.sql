-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Topic 3 — Creating & Managing Delta Tables
-- MAGIC
-- MAGIC **Pure SQL. No Python.**
-- MAGIC
-- MAGIC ## What is Delta Lake?
-- MAGIC Every table you create in Databricks is a **Delta table** by default. Delta is the
-- MAGIC storage format that makes a pile of files in cloud storage behave like a proper
-- MAGIC database table.
-- MAGIC
-- MAGIC ## The problem it solves
-- MAGIC Before Delta, a "data lake" was a folder of files. That meant:
-- MAGIC
-- MAGIC - **No updates or deletes.** To change one row you rewrote the whole dataset. So
-- MAGIC   "delete this customer's data" — a legal obligation under GDPR — was a genuinely
-- MAGIC   hard engineering problem.
-- MAGIC - **No safety during writes.** If a job failed halfway, readers saw half-written
-- MAGIC   data. There was no "all or nothing".
-- MAGIC - **No history.** Overwrite the wrong file and yesterday's data was gone.
-- MAGIC - **No schema checks.** Anyone could append a file with the wrong columns and
-- MAGIC   nobody noticed until a report broke weeks later.
-- MAGIC
-- MAGIC Delta fixes all four, while the data still just sits in ordinary cloud storage.
-- MAGIC
-- MAGIC ## What Delta gives you
-- MAGIC
-- MAGIC | Feature | What it means in plain terms |
-- MAGIC |---|---|
-- MAGIC | **ACID transactions** | A write either fully succeeds or fully fails. Never half. |
-- MAGIC | **UPDATE / DELETE / MERGE** | Change individual rows, like a real database |
-- MAGIC | **Time travel** | Read the table as it was at any earlier point |
-- MAGIC | **Schema enforcement** | Bad-shaped data is rejected at the door |
-- MAGIC | **Schema evolution** | Add columns deliberately, without rebuilding |
-- MAGIC | **OPTIMIZE / VACUUM** | Keep queries fast and storage costs down |
-- MAGIC
-- MAGIC ## How this notebook runs
-- MAGIC The first cell **deletes everything this lesson creates**, so you watch the tables
-- MAGIC get built live and the notebook is safely re-runnable. It uses its own catalog,
-- MAGIC **`demo_delta`** — it does not touch `demo_training` (topic 1) or `demo_uc`
-- MAGIC (topic 2).

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 0 — Clean slate
-- MAGIC
-- MAGIC `CASCADE` removes everything inside the catalog. `IF EXISTS` stops it erroring on
-- MAGIC a first run. Together they make this notebook repeatable — present it twice and
-- MAGIC get identical results.

-- COMMAND ----------

DROP CATALOG IF EXISTS demo_delta CASCADE;

-- COMMAND ----------

CREATE CATALOG IF NOT EXISTS demo_delta
  COMMENT 'Training catalog for the Delta tables lesson. Safe to drop and recreate.';

CREATE SCHEMA IF NOT EXISTS demo_delta.sales
  COMMENT 'Sales tables used to demonstrate Delta Lake features.';

-- COMMAND ----------

USE CATALOG demo_delta;
USE SCHEMA sales;

SELECT current_catalog() AS catalog, current_schema() AS schema;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 1 — Create a Delta table
-- MAGIC
-- MAGIC Notice there is no `USING DELTA` clause. **Delta is the default** — you get all
-- MAGIC of its guarantees without asking for them.
-- MAGIC
-- MAGIC Two features worth pointing out in the definition below:
-- MAGIC
-- MAGIC - **`GENERATED ALWAYS AS IDENTITY`** — Delta assigns the ID automatically. No
-- MAGIC   sequence table, no risk of two jobs picking the same number.
-- MAGIC - **`NOT NULL`** — a real constraint. A write that violates it is **rejected**,
-- MAGIC   not quietly stored. This is the difference between a table you can trust and a
-- MAGIC   folder of files you hope is right.

-- COMMAND ----------

CREATE TABLE orders (
  order_id    BIGINT GENERATED ALWAYS AS IDENTITY COMMENT 'Auto-assigned unique order id',
  customer    STRING NOT NULL                     COMMENT 'Customer name - required',
  product     STRING                              COMMENT 'Product ordered',
  quantity    INT                                 COMMENT 'Units ordered',
  unit_price  DECIMAL(10,2)                       COMMENT 'Price per unit at time of sale',
  order_date  DATE                                COMMENT 'Date the order was placed',
  status      STRING                              COMMENT 'placed, shipped, delivered or cancelled'
)
COMMENT 'Customer orders. Demonstrates Delta table management.';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 2 — Insert data
-- MAGIC
-- MAGIC We omit `order_id` because Delta generates it. This `INSERT` is a **transaction**:
-- MAGIC either all six rows land or none do. If the cluster died mid-write, a reader
-- MAGIC would still see the table exactly as it was before — never a partial six rows.

-- COMMAND ----------

INSERT INTO orders (customer, product, quantity, unit_price, order_date, status) VALUES
  ('Aarav Sharma',   'Laptop',   1, 1200.00, DATE'2025-01-10', 'delivered'),
  ('Priya Nair',     'Monitor',  2,  300.00, DATE'2025-01-12', 'shipped'),
  ('Rohan Iyer',     'Keyboard', 3,   80.00, DATE'2025-01-15', 'placed'),
  ('Meera Krishnan', 'Laptop',   1, 1200.00, DATE'2025-02-02', 'delivered'),
  ('Vikram Rao',     'Mouse',    5,   25.00, DATE'2025-02-08', 'placed'),
  ('Aarav Sharma',   'Monitor',  1,  300.00, DATE'2025-02-14', 'cancelled');

-- COMMAND ----------

SELECT * FROM orders ORDER BY order_id;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 3 — What is this table, really?
-- MAGIC
-- MAGIC `DESCRIBE DETAIL` shows the physical facts: the format is `delta`, how many files
-- MAGIC the data occupies, and how big it is.
-- MAGIC
-- MAGIC **The `numFiles` column matters later.** Delta writes new files rather than
-- MAGIC editing existing ones, so this number grows with every change — and that is what
-- MAGIC `OPTIMIZE` in Step 10 exists to fix.

-- COMMAND ----------

DESCRIBE DETAIL orders;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 4 — `UPDATE`: change rows in place
-- MAGIC
-- MAGIC **This is the headline feature.** In a plain data lake you could not do this at
-- MAGIC all — you rewrote the entire dataset to change one value.
-- MAGIC
-- MAGIC Suppose an order shipped. One statement, and only the matching rows change.

-- COMMAND ----------

UPDATE orders
SET status = 'shipped'
WHERE status = 'placed' AND order_date < DATE'2025-02-01';

-- COMMAND ----------

SELECT order_id, customer, product, status FROM orders ORDER BY order_id;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 5 — `DELETE`: remove rows
-- MAGIC
-- MAGIC The cancelled order should come out of the sales table.
-- MAGIC
-- MAGIC **Why this matters beyond convenience:** "delete everything about this person" is
-- MAGIC a legal right under GDPR. On a plain data lake that request was a project. Here it
-- MAGIC is one statement, and the change is recorded in the table's history so you can
-- MAGIC *prove* you did it.

-- COMMAND ----------

DELETE FROM orders WHERE status = 'cancelled';

-- COMMAND ----------

SELECT count(*) AS rows_remaining FROM orders;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 6 — `MERGE`: the upsert
-- MAGIC
-- MAGIC `MERGE` is the single most useful Delta statement, and the one worth slowing down
-- MAGIC for. It handles the everyday problem of **applying a batch of changes**:
-- MAGIC
-- MAGIC > *"Here is today's file from the source system. Some rows are updates to orders we
-- MAGIC > already have; some are brand new. Sort it out."*
-- MAGIC
-- MAGIC Without `MERGE` you would write that as a delete-then-insert, in a transaction,
-- MAGIC and get it subtly wrong. `MERGE` does it in one atomic step:
-- MAGIC
-- MAGIC - **matched** → update the existing row
-- MAGIC - **not matched** → insert it as new
-- MAGIC
-- MAGIC First, a small batch of incoming changes.

-- COMMAND ----------

CREATE OR REPLACE TEMP VIEW incoming_orders AS
SELECT * FROM VALUES
  (1, 'Aarav Sharma', 'Laptop',  1, 1200.00, DATE'2025-01-10', 'returned'),  -- existing -> update
  (2, 'Priya Nair',   'Monitor', 2,  300.00, DATE'2025-01-12', 'delivered'), -- existing -> update
  (99,'Nisha Menon',  'Tablet',  1,  450.00, DATE'2025-03-01', 'placed')     -- new     -> insert
AS t(order_id, customer, product, quantity, unit_price, order_date, status);

SELECT * FROM incoming_orders;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### One statement, both outcomes
-- MAGIC Read it as a sentence: *match the incoming rows to existing orders by id; where
-- MAGIC they match, update the status; where they don't, insert the whole row.*

-- COMMAND ----------

MERGE INTO orders AS target
USING incoming_orders AS source
  ON target.order_id = source.order_id

WHEN MATCHED THEN
  UPDATE SET target.status = source.status

WHEN NOT MATCHED THEN
  INSERT (customer, product, quantity, unit_price, order_date, status)
  VALUES (source.customer, source.product, source.quantity,
          source.unit_price, source.order_date, source.status);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC Orders 1 and 2 now carry their new status, and Nisha Menon's tablet order has
-- MAGIC appeared. **All of it, or none of it** — a `MERGE` cannot half-apply.

-- COMMAND ----------

SELECT order_id, customer, product, status FROM orders ORDER BY order_id;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 7 — History: who changed what, and when
-- MAGIC
-- MAGIC Delta records **every** change as a numbered version. This is not something you
-- MAGIC switch on — it is simply how the table works.
-- MAGIC
-- MAGIC Read the `operation` column top to bottom and you can see the whole story of this
-- MAGIC notebook: `CREATE TABLE`, `WRITE`, `UPDATE`, `DELETE`, `MERGE`. For an auditor,
-- MAGIC that is a complete, tamper-evident record of how the data reached its current state.

-- COMMAND ----------

DESCRIBE HISTORY orders;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 8 — Time travel
-- MAGIC
-- MAGIC You can query any earlier version directly. Nothing is restored and nothing is
-- MAGIC copied — the old versions are simply still there.
-- MAGIC
-- MAGIC **What this is worth in practice:**
-- MAGIC - Reproduce last quarter's report *exactly* as it was published
-- MAGIC - Compare today against yesterday to find what a job actually changed
-- MAGIC - Recover from a bad load without going near a backup
-- MAGIC
-- MAGIC Version 1 is the state right after the initial insert — before the update, the
-- MAGIC delete and the merge.

-- COMMAND ----------

SELECT order_id, customer, product, status
FROM orders VERSION AS OF 1
ORDER BY order_id;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Compare two points in time in one query
-- MAGIC Because versions are just tables, you can join them. Here we show which rows
-- MAGIC changed status between version 1 and now — the kind of check that used to require
-- MAGIC keeping manual snapshots.

-- COMMAND ----------

SELECT
  old.order_id,
  old.customer,
  old.status AS status_at_version_1,
  new.status AS status_now
FROM      orders VERSION AS OF 1 AS old
FULL JOIN orders                 AS new  ON old.order_id = new.order_id
WHERE old.status IS DISTINCT FROM new.status
ORDER BY old.order_id;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 9 — `RESTORE`: undo
-- MAGIC
-- MAGIC Time travel *reads* the past. `RESTORE` **returns the table to it**.
-- MAGIC
-- MAGIC This is the "someone ran the wrong job at 2am" button. Recovery takes seconds
-- MAGIC rather than a restore-from-backup exercise — and note that `RESTORE` is itself
-- MAGIC recorded as a new version, so the undo is auditable too. You can even undo the undo.
-- MAGIC
-- MAGIC We restore, look, then merge again to get back to where we were.

-- COMMAND ----------

RESTORE TABLE orders TO VERSION AS OF 1;

-- COMMAND ----------

-- Back to the original six rows, cancelled order included.
SELECT order_id, customer, product, status FROM orders ORDER BY order_id;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 10 — Schema evolution: adding a column
-- MAGIC
-- MAGIC Business needs change. Delta lets you add a column **without rebuilding the
-- MAGIC table** — existing rows simply show `NULL` for it.
-- MAGIC
-- MAGIC The important word is *deliberately*. Delta's **schema enforcement** means a write
-- MAGIC with unexpected columns is rejected by default; changing the shape of a table is
-- MAGIC something you must state explicitly, as below. That combination — locked down by
-- MAGIC default, changeable on purpose — is what stops silent data corruption.

-- COMMAND ----------

ALTER TABLE orders ADD COLUMN region STRING COMMENT 'Sales region for this order';

-- COMMAND ----------

UPDATE orders SET region = 'South' WHERE customer IN ('Aarav Sharma', 'Vikram Rao');
UPDATE orders SET region = 'West'  WHERE region IS NULL;

SELECT order_id, customer, product, region FROM orders ORDER BY order_id;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 11 — Constraints: refuse bad data at the door
-- MAGIC
-- MAGIC A `CHECK` constraint is a rule the table enforces on every future write. Here:
-- MAGIC quantity must be positive.
-- MAGIC
-- MAGIC **Why enforce it in the table rather than in the pipeline?** Because tables usually
-- MAGIC have more than one writer. A rule in one job protects one path; a rule on the table
-- MAGIC protects every path, forever, including the ad-hoc `INSERT` someone runs at 6pm.
-- MAGIC
-- MAGIC Adding the constraint also **validates the rows already there** — so it fails
-- MAGIC immediately if existing data violates it.

-- COMMAND ----------

ALTER TABLE orders ADD CONSTRAINT positive_quantity CHECK (quantity > 0);

-- COMMAND ----------

-- MAGIC %md
-- MAGIC The constraint now appears in the table's properties. Any future insert with
-- MAGIC `quantity <= 0` is rejected outright — the write fails rather than storing nonsense.
-- MAGIC
-- MAGIC *(We do not demonstrate the rejection itself, because a deliberately failing cell
-- MAGIC would stop the notebook. Mention it verbally, or run it in a scratch cell.)*

-- COMMAND ----------

DESCRIBE EXTENDED orders;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 12 — `OPTIMIZE`: keep queries fast
-- MAGIC
-- MAGIC Remember `numFiles` from Step 3. Every update, delete and merge wrote new files,
-- MAGIC so a busy table drifts towards thousands of small ones. Reading a thousand small
-- MAGIC files is far slower than reading a few large ones — the **small file problem**.
-- MAGIC
-- MAGIC `OPTIMIZE` compacts them. It changes no data and no results; it only reorganises
-- MAGIC storage. Run it on a schedule for tables that change often.
-- MAGIC
-- MAGIC `ZORDER BY` goes further: it physically co-locates related rows, so a query
-- MAGIC filtering on those columns can skip whole files. On a large table that is often
-- MAGIC the difference between seconds and minutes.
-- MAGIC
-- MAGIC *(Our table is tiny, so the gain here is theoretical — but the command is the
-- MAGIC same one you would run on a billion rows.)*

-- COMMAND ----------

OPTIMIZE orders ZORDER BY (customer);

-- COMMAND ----------

-- Compare numFiles and sizeInBytes with Step 3.
DESCRIBE DETAIL orders;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 13 — `VACUUM`: reclaim storage
-- MAGIC
-- MAGIC Old versions are what make time travel possible — but they occupy storage you pay
-- MAGIC for. `VACUUM` deletes files that are no longer referenced and are older than the
-- MAGIC retention period (**7 days by default**).
-- MAGIC
-- MAGIC > **The trade-off to state clearly: `VACUUM` permanently destroys your ability to
-- MAGIC > time travel past the retention window.** It is not reversible. Shortening the
-- MAGIC > window to save money is exactly the decision that leaves you unable to recover
-- MAGIC > from a bad load. Treat 7 days as a floor, not a target.
-- MAGIC
-- MAGIC `DRY RUN` lists what *would* be deleted without deleting anything — always run this
-- MAGIC first. Nothing here is old enough to qualify, which is the expected result.

-- COMMAND ----------

VACUUM orders DRY RUN;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 14 — Copying tables: `CTAS` and `CLONE`
-- MAGIC
-- MAGIC ### `CREATE TABLE AS SELECT` — a new table from a query
-- MAGIC The standard way to build a derived table. The result is an independent Delta
-- MAGIC table with its own history.

-- COMMAND ----------

CREATE OR REPLACE TABLE order_summary
COMMENT 'Revenue per customer. Derived from orders.'
AS
SELECT
  customer,
  count(*)                        AS order_count,
  sum(quantity * unit_price)      AS total_revenue,
  max(order_date)                 AS most_recent_order
FROM orders
GROUP BY customer;

SELECT * FROM order_summary ORDER BY total_revenue DESC;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### `DEEP CLONE` — a real, independent copy
-- MAGIC Copies both the data and the full history. The clone is a separate table:
-- MAGIC changing it does not affect the original.
-- MAGIC
-- MAGIC **The everyday use:** give a team a realistic copy of production to test against,
-- MAGIC with no risk to the real thing. Far safer than "just be careful on prod".

-- COMMAND ----------

CREATE OR REPLACE TABLE orders_backup DEEP CLONE orders;

SELECT count(*) AS rows_in_clone FROM orders_backup;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 15 — What did we build?

-- COMMAND ----------

SHOW TABLES IN demo_delta.sales;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Recap
-- MAGIC
-- MAGIC | Step | Command | Why it matters |
-- MAGIC |---|---|---|
-- MAGIC | 1 | `CREATE TABLE` | Delta by default; identity columns and `NOT NULL` |
-- MAGIC | 2 | `INSERT` | All-or-nothing writes — never a half-loaded table |
-- MAGIC | 4–5 | `UPDATE` / `DELETE` | Row-level changes; makes GDPR erasure practical |
-- MAGIC | 6 | `MERGE` | Apply a batch of updates *and* inserts atomically |
-- MAGIC | 7 | `DESCRIBE HISTORY` | A complete audit trail, on by default |
-- MAGIC | 8 | `VERSION AS OF` | Reproduce any past state; diff two points in time |
-- MAGIC | 9 | `RESTORE` | Undo a bad job in seconds, not hours |
-- MAGIC | 10 | `ALTER TABLE ADD COLUMN` | Evolve the schema deliberately |
-- MAGIC | 11 | `CHECK` constraint | Bad data refused at the table, for every writer |
-- MAGIC | 12 | `OPTIMIZE` / `ZORDER` | Fix the small-file problem; skip files on read |
-- MAGIC | 13 | `VACUUM` | Reclaim storage — at the cost of time travel |
-- MAGIC | 14 | `CTAS` / `DEEP CLONE` | Derived tables; safe production copies |
-- MAGIC
-- MAGIC ### The one-sentence takeaway
-- MAGIC **Delta gives files in cloud storage the guarantees of a database — transactions,
-- MAGIC row-level changes, and a full history — so the lakehouse is somewhere you can
-- MAGIC safely run the business, not just store its data.**
-- MAGIC
-- MAGIC ### Cleaning up
-- MAGIC Leave the tables in place to explore in Catalog Explorer. The teardown cell at the
-- MAGIC top clears them on the next run. To remove everything now, uncomment below.

-- COMMAND ----------

-- DROP CATALOG IF EXISTS demo_delta CASCADE;

SELECT 'Delta tables demo complete' AS status;

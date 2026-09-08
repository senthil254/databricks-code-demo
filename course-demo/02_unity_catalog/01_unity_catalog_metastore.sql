-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Topic 2 — Unity Catalog & the Metastore
-- MAGIC
-- MAGIC **This notebook is pure SQL. There is no Python anywhere in it.**
-- MAGIC Everything Unity Catalog does — creating objects, granting access, inspecting
-- MAGIC who owns what — is plain SQL that an analyst can read.
-- MAGIC
-- MAGIC ## What is Unity Catalog, in one sentence?
-- MAGIC It is the **single place that records what data exists, who owns it, and who is
-- MAGIC allowed to see it** — across every workspace in the company.
-- MAGIC
-- MAGIC ## What is a metastore?
-- MAGIC The **metastore** is the top-level container: the company's master catalogue of
-- MAGIC data. There is normally **one per region**, shared by every workspace in it.
-- MAGIC
-- MAGIC Think of a library:
-- MAGIC
-- MAGIC | Library | Unity Catalog | Example |
-- MAGIC |---|---|---|
-- MAGIC | The library building | **Metastore** | one per region |
-- MAGIC | A floor | **Catalog** | `demo_uc` |
-- MAGIC | A shelf | **Schema** (database) | `governance` |
-- MAGIC | A book | **Table / View / Volume** | `customers` |
-- MAGIC
-- MAGIC That gives the **three-level name** you will see all through this notebook:
-- MAGIC `catalog.schema.table` — for example `demo_uc.governance.customers`.
-- MAGIC
-- MAGIC ## Why it matters to the business
-- MAGIC - **One set of permissions.** Grant access once; it applies in every workspace,
-- MAGIC   every notebook, every dashboard and every BI tool.
-- MAGIC - **Files and tables governed the same way.** A spreadsheet in a Volume obeys the
-- MAGIC   same rules as a table.
-- MAGIC - **Auditability.** Every access is recorded — essential for GDPR, HIPAA, SOX.
-- MAGIC - **No more "which copy is correct?"** One governed source instead of extracts
-- MAGIC   scattered across laptops.
-- MAGIC
-- MAGIC ---
-- MAGIC ### About the first cell
-- MAGIC The next cell **deletes everything this demo creates.** That is deliberate: it
-- MAGIC means we start from genuinely nothing, and you watch Unity Catalog get built
-- MAGIC live rather than taking a pre-baked result on trust. It also makes the notebook
-- MAGIC safely re-runnable — present it twice and get identical results.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 0 — Clean slate (teardown)
-- MAGIC
-- MAGIC `CASCADE` means "and everything inside it" — the schemas, tables, views and
-- MAGIC volumes all go too. `IF EXISTS` means "don't error if it isn't there", which is
-- MAGIC what makes this safe to run on a brand-new workspace.
-- MAGIC
-- MAGIC > **Safety note:** this drops **`demo_uc` only** — a catalog that exists purely
-- MAGIC > for this lesson. It deliberately does **not** touch `demo_training` (the
-- MAGIC > magic-commands demo) or `lakebridge_demo` (a separate project). Dropping a
-- MAGIC > catalog is irreversible, so scoping the blast radius matters.

-- COMMAND ----------

DROP CATALOG IF EXISTS demo_uc CASCADE;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 1 — Where are we? Inspecting the metastore
-- MAGIC
-- MAGIC Before creating anything, let's see the environment we are connected to.
-- MAGIC These three functions answer: *which master catalogue am I in, which floor am I
-- MAGIC standing on, and who does the system think I am?*
-- MAGIC
-- MAGIC That last one matters more than it looks: **every permission decision Unity
-- MAGIC Catalog makes is based on that identity.**

-- COMMAND ----------

SELECT
  current_metastore() AS metastore_id,   -- the region-wide master catalogue
  current_catalog()   AS current_catalog, -- which catalog am I working in by default
  current_schema()    AS current_schema,  -- which schema within it
  current_user()      AS logged_in_as;    -- the identity all permissions are checked against

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### What already exists in this metastore?
-- MAGIC You should see `demo_training` (topic 1) and the built-in `system` and `samples`
-- MAGIC catalogs — but **no `demo_uc`**, because we just dropped it. We are about to
-- MAGIC create it in front of you.

-- COMMAND ----------

SHOW CATALOGS;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 2 — Create a catalog (the "floor")
-- MAGIC
-- MAGIC A catalog is the top-level grouping teams actually work with. Most organisations
-- MAGIC use one per business domain (`finance`, `hr`, `marketing`) or per environment
-- MAGIC (`dev`, `prod`) — because **permissions are usually granted at this level**, so
-- MAGIC the catalog boundary becomes the security boundary.
-- MAGIC
-- MAGIC `COMMENT` is not decoration. It appears in the Catalog Explorer UI and in search,
-- MAGIC so a colleague who finds this data later knows what it is and whether they should
-- MAGIC be using it. **Undocumented data is data nobody trusts.**

-- COMMAND ----------

CREATE CATALOG IF NOT EXISTS demo_uc
  COMMENT 'Training catalog for the Unity Catalog lesson. Safe to drop and recreate.';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC It now exists. Notice it appeared instantly and is immediately visible to every
-- MAGIC workspace attached to this metastore — no copying, no syncing, no waiting.

-- COMMAND ----------

SHOW CATALOGS LIKE 'demo*';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 3 — Create a schema (the "shelf")
-- MAGIC
-- MAGIC A schema groups related tables inside a catalog. A very common convention is the
-- MAGIC **medallion** layout — `bronze` (raw), `silver` (cleaned), `gold` (ready for the
-- MAGIC business) — so anyone can tell how trustworthy a table is from its address alone.
-- MAGIC
-- MAGIC We use one schema, `governance`, to keep the lesson focused.

-- COMMAND ----------

CREATE SCHEMA IF NOT EXISTS demo_uc.governance
  COMMENT 'Objects used to demonstrate Unity Catalog governance features.';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### `USE` — set a default so we can stop typing the full name
-- MAGIC Instead of writing `demo_uc.governance.customers` every time, we can set the
-- MAGIC current catalog and schema and then just write `customers`.
-- MAGIC
-- MAGIC **A word of caution:** in a saved or scheduled query, always write the **full
-- MAGIC three-level name**. Relying on a default is how a job silently reads `dev` data
-- MAGIC while everyone believes it is reading `prod`.

-- COMMAND ----------

USE CATALOG demo_uc;
USE SCHEMA governance;

-- COMMAND ----------

SELECT current_catalog() AS now_in_catalog, current_schema() AS now_in_schema;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 4 — Create a managed table
-- MAGIC
-- MAGIC **Managed** means Unity Catalog owns the data as well as the definition: it picks
-- MAGIC the storage location, optimises the files, and — importantly — **when you drop the
-- MAGIC table, the data really is deleted.** That is what makes "delete this customer's
-- MAGIC records" a request you can actually honour.
-- MAGIC
-- MAGIC (The alternative, an **external** table, means UC governs access but the files
-- MAGIC live in a storage account you manage, and dropping the table leaves them behind.
-- MAGIC Managed is the recommended default.)
-- MAGIC
-- MAGIC Note the per-column `COMMENT`s — this is where a data dictionary comes from.

-- COMMAND ----------

CREATE TABLE IF NOT EXISTS customers (
  customer_id INT       COMMENT 'Unique identifier for the customer',
  name        STRING    COMMENT 'Customer full name',
  email       STRING    COMMENT 'Contact email - personal data, restrict access',
  city        STRING    COMMENT 'City the customer is based in',
  tier        STRING    COMMENT 'Loyalty tier: bronze, silver or gold',
  signup_date DATE      COMMENT 'Date the customer first registered'
)
COMMENT 'Demo customer master table. Contains personal data.';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Add some rows
-- MAGIC A small, readable dataset — the point of the lesson is governance, not volume.

-- COMMAND ----------

INSERT INTO customers VALUES
  (1, 'Aarav Sharma',  'aarav@example.com',  'Chennai',   'gold',   DATE'2024-03-11'),
  (2, 'Priya Nair',    'priya@example.com',  'Bangalore', 'silver', DATE'2024-05-02'),
  (3, 'Rohan Iyer',    'rohan@example.com',  'Mumbai',    'gold',   DATE'2024-06-21'),
  (4, 'Meera Krishnan','meera@example.com',  'Delhi',     'bronze', DATE'2024-08-09'),
  (5, 'Vikram Rao',    'vikram@example.com', 'Pune',      'silver', DATE'2025-01-15');

-- COMMAND ----------

SELECT * FROM customers ORDER BY customer_id;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 5 — Create a Volume (governed files)
-- MAGIC
-- MAGIC Not all data is tabular. A **Volume** is a folder for files — CSVs, PDFs, images,
-- MAGIC model artefacts — that lives *inside* the catalog and inherits the same
-- MAGIC permissions as your tables.
-- MAGIC
-- MAGIC **Why this is a genuine advance:** before Volumes, tables were governed but files
-- MAGIC sat in cloud storage with a separate, usually weaker, set of rules. Volumes close
-- MAGIC that gap. One permission model covers **both** your tables and your files.

-- COMMAND ----------

CREATE VOLUME IF NOT EXISTS demo_uc.governance.landing_zone
  COMMENT 'Governed folder for incoming files. Path: /Volumes/demo_uc/governance/landing_zone';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 6 — What have we built? Inspecting objects
-- MAGIC
-- MAGIC The `SHOW` and `DESCRIBE` commands are how you explore Unity Catalog from SQL.
-- MAGIC Everything visible in the Catalog Explorer UI is available here too — which means
-- MAGIC it can be automated and version-controlled.

-- COMMAND ----------

SHOW SCHEMAS IN demo_uc;

-- COMMAND ----------

SHOW TABLES IN demo_uc.governance;

-- COMMAND ----------

SHOW VOLUMES IN demo_uc.governance;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### `DESCRIBE EXTENDED` — the full picture of a table
-- MAGIC Columns and their comments, plus the metadata that matters for governance:
-- MAGIC **who owns it**, whether it is managed or external, where it is stored, and when
-- MAGIC it was created.

-- COMMAND ----------

DESCRIBE EXTENDED demo_uc.governance.customers;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 7 — `information_schema`: the catalog is queryable
-- MAGIC
-- MAGIC This is a favourite with data teams. Unity Catalog exposes its own metadata as
-- MAGIC **ordinary tables you can query with SQL**. So questions that used to require a
-- MAGIC person and a spreadsheet become one query:
-- MAGIC
-- MAGIC - *Which tables hold a column called `email`?*
-- MAGIC - *Which tables have no description?*
-- MAGIC - *How many tables does each team own?*
-- MAGIC
-- MAGIC This is how you audit a data estate at scale instead of by hand.

-- COMMAND ----------

-- Every column we defined, with its documentation, straight from the catalog.
SELECT table_name, column_name, data_type, comment
FROM demo_uc.information_schema.columns
WHERE table_schema = 'governance'
ORDER BY table_name, ordinal_position;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### A real governance question
-- MAGIC "Find every column that might contain personal data." On a five-column demo this
-- MAGIC is trivial; across ten thousand tables it is the difference between a compliance
-- MAGIC programme that works and one that doesn't.

-- COMMAND ----------

SELECT table_catalog, table_schema, table_name, column_name, comment
FROM demo_uc.information_schema.columns
WHERE lower(column_name) LIKE '%email%'
   OR lower(column_name) LIKE '%phone%'
   OR lower(comment)     LIKE '%personal data%';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 8 — Tags: label data so policy can find it
-- MAGIC
-- MAGIC A **tag** is a searchable key/value label on a catalog, schema, table or column.
-- MAGIC Tagging a column `pii = true` lets you later ask *"show me every PII column in the
-- MAGIC company"* and get a complete, current answer — rather than relying on a
-- MAGIC spreadsheet that went stale the day it was written.

-- COMMAND ----------

ALTER TABLE demo_uc.governance.customers
  SET TAGS ('data_classification' = 'confidential', 'demo' = 'unity_catalog');

-- COMMAND ----------

-- Tag the specific column that carries personal data.
ALTER TABLE demo_uc.governance.customers
  ALTER COLUMN email SET TAGS ('pii' = 'true');

-- COMMAND ----------

SELECT * FROM demo_uc.information_schema.column_tags
WHERE schema_name = 'governance';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 9 — Views: share an answer, not the raw data
-- MAGIC
-- MAGIC A **view** is a saved query that behaves like a table. The critical governance use:
-- MAGIC grant someone access to the *view* but not the underlying table, and they see only
-- MAGIC the rows and columns you chose to expose.
-- MAGIC
-- MAGIC Below, `customers_public` deliberately **omits the email column**. Someone with
-- MAGIC access to only this view can analyse customers by city and tier without ever
-- MAGIC seeing personal contact details. **Analysis without exposure.**

-- COMMAND ----------

CREATE OR REPLACE VIEW demo_uc.governance.customers_public
  COMMENT 'Customer data with personal contact details removed. Safe for wide access.'
AS
SELECT customer_id, name, city, tier, signup_date  -- note: no email
FROM demo_uc.governance.customers;

-- COMMAND ----------

SELECT * FROM demo_uc.governance.customers_public ORDER BY customer_id;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 10 — Permissions: who can see what
-- MAGIC
-- MAGIC This is the heart of Unity Catalog. Access is granted with `GRANT` and removed
-- MAGIC with `REVOKE` — the same SQL any database administrator already knows.
-- MAGIC
-- MAGIC ### The rule that trips everyone up
-- MAGIC Permissions are **hierarchical**. To read a table you need permission at *every
-- MAGIC level above it*:
-- MAGIC
-- MAGIC `USE CATALOG` → `USE SCHEMA` → `SELECT` on the table
-- MAGIC
-- MAGIC Miss one and the table is simply invisible. **"I can't see the table" is almost
-- MAGIC always a missing `USE CATALOG` or `USE SCHEMA`,** not a missing `SELECT`.
-- MAGIC
-- MAGIC ### Grant to groups, never to individuals
-- MAGIC Granting to a person means unpicking it when they change role or leave. Granting
-- MAGIC to a group means access is managed by adding and removing people from that group.
-- MAGIC We use the built-in `account users` group here purely for demonstration.

-- COMMAND ----------

-- Level 1: allow entry to the catalog. On its own this reveals nothing.
GRANT USE CATALOG ON CATALOG demo_uc TO `account users`;

-- COMMAND ----------

-- Level 2: allow entry to the schema. Still no data access.
GRANT USE SCHEMA ON SCHEMA demo_uc.governance TO `account users`;

-- COMMAND ----------

-- Level 3: allow reading the SAFE VIEW only - not the underlying table.
-- This is the whole point: broad access to the anonymised view, while the raw
-- table containing email addresses stays restricted.
GRANT SELECT ON VIEW demo_uc.governance.customers_public TO `account users`;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### `SHOW GRANTS` — answering "who has access to this?"
-- MAGIC An auditor can ask this question at any time and get a definitive answer, in
-- MAGIC seconds. Compare with the traditional approach of asking three teams and hoping.

-- COMMAND ----------

SHOW GRANTS ON VIEW demo_uc.governance.customers_public;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### And the raw table, for contrast
-- MAGIC Note that `account users` does **not** appear here. Everyone can read the safe
-- MAGIC view; only the owner can read the table with the email addresses in it.

-- COMMAND ----------

SHOW GRANTS ON TABLE demo_uc.governance.customers;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Removing access is just as easy
-- MAGIC `REVOKE` is the mirror of `GRANT`. Being able to withdraw access instantly — and
-- MAGIC prove that you did — is as important to an auditor as granting it.

-- COMMAND ----------

REVOKE SELECT ON VIEW demo_uc.governance.customers_public FROM `account users`;

-- COMMAND ----------

-- Confirm it is gone. The account users SELECT entry has disappeared.
SHOW GRANTS ON VIEW demo_uc.governance.customers_public;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 11 — Ownership
-- MAGIC
-- MAGIC Every object has exactly one **owner**, who can always grant and revoke access to
-- MAGIC it. Governance best practice is to own objects with a **group** rather than a
-- MAGIC person, so that data does not become orphaned when someone leaves the company.
-- MAGIC
-- MAGIC (We only display ownership here. Transferring it would need a second group to
-- MAGIC transfer to, which this training workspace does not have.)

-- COMMAND ----------

DESCRIBE TABLE EXTENDED demo_uc.governance.customers;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 12 — History and time travel
-- MAGIC
-- MAGIC Every governed table keeps a full **version history**. You can see who changed
-- MAGIC what and when — and read the table as it was at any earlier point.
-- MAGIC
-- MAGIC **Why the business cares:** a bad load at 2am no longer means restoring from
-- MAGIC backup. You read yesterday's version, or roll straight back to it. It is also how
-- MAGIC you reproduce last quarter's report exactly as it was published.

-- COMMAND ----------

DESCRIBE HISTORY demo_uc.governance.customers;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### Make a change, then look back at the original
-- MAGIC First an update, so there is something to travel back through.

-- COMMAND ----------

UPDATE demo_uc.governance.customers
SET tier = 'gold'
WHERE customer_id = 4;

-- COMMAND ----------

-- The table as it is NOW - customer 4 is gold.
SELECT customer_id, name, tier FROM demo_uc.governance.customers ORDER BY customer_id;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### The same table, as it was before the update
-- MAGIC `VERSION AS OF 1` reads the state right after the initial insert. Customer 4 is
-- MAGIC `bronze` again. **Nothing was restored and nothing was copied** — the old version
-- MAGIC is simply still there, and reading it costs nothing.

-- COMMAND ----------

SELECT customer_id, name, tier
FROM demo_uc.governance.customers VERSION AS OF 1
ORDER BY customer_id;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 13 — Lineage: where did this data come from?
-- MAGIC
-- MAGIC Unity Catalog records, automatically, which tables feed which other tables — no
-- MAGIC configuration required. We created `customers_public` from `customers`, so that
-- MAGIC relationship is captured.
-- MAGIC
-- MAGIC **Why it matters:** when a number looks wrong, lineage tells you what it depends
-- MAGIC on. Before changing a table, lineage tells you what will break. It answers
-- MAGIC *"if I drop this column, whose dashboard dies?"*
-- MAGIC
-- MAGIC > **Expect this to be empty during the demo.** Lineage is collected asynchronously
-- MAGIC > and can take several minutes to appear. That delay is itself worth mentioning —
-- MAGIC > it is a real operational characteristic, not a fault. The Catalog Explorer UI
-- MAGIC > shows the same information as a diagram.

-- COMMAND ----------

SELECT
  source_table_full_name,
  target_table_full_name,
  event_time
FROM system.access.table_lineage
WHERE target_table_full_name LIKE 'demo_uc.governance.%'
  AND event_date >= current_date() - 1
ORDER BY event_time DESC
LIMIT 20;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Recap — what Unity Catalog gave us
-- MAGIC
-- MAGIC In one SQL notebook, with no Python, we:
-- MAGIC
-- MAGIC | Step | What we did | Why it matters |
-- MAGIC |---|---|---|
-- MAGIC | 1 | Inspected the metastore | One master catalogue per region, shared by all workspaces |
-- MAGIC | 2–3 | Created a catalog and schema | The `catalog.schema.table` address every user relies on |
-- MAGIC | 4 | Created a managed table | UC owns the data, so deletion is real deletion |
-- MAGIC | 5 | Created a Volume | Files governed by the same rules as tables |
-- MAGIC | 6–7 | Inspected objects, queried `information_schema` | The catalogue audits itself, with SQL |
-- MAGIC | 8 | Applied tags | Find every PII column on demand |
-- MAGIC | 9 | Built a safe view | Analysis without exposing personal data |
-- MAGIC | 10 | Granted and revoked access | Hierarchical permissions; group-based; instantly provable |
-- MAGIC | 11 | Looked at ownership | Every object has an accountable owner |
-- MAGIC | 12 | Used history and time travel | Recover from a bad load without a backup |
-- MAGIC | 13 | Queried lineage | Know what breaks before you change something |
-- MAGIC
-- MAGIC ### The one-sentence takeaway
-- MAGIC **Unity Catalog turns governance from paperwork into something the platform
-- MAGIC enforces for you — and every part of it is queryable with ordinary SQL.**
-- MAGIC
-- MAGIC ### Optional: clean up
-- MAGIC Leave the objects in place if you want to explore them in Catalog Explorer after
-- MAGIC the session. The teardown cell at the top will clear them on the next run anyway.
-- MAGIC To remove everything now, run the cell below.

-- COMMAND ----------

-- Uncomment to remove everything this notebook created.
-- DROP CATALOG IF EXISTS demo_uc CASCADE;

SELECT 'Unity Catalog demo complete' AS status;

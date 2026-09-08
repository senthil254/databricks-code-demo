# Session memory — where we left off

**Last updated:** 2026-09-09
**Read `CLAUDE.md` first** for the hard rules, then this file for current state.

## The goal

Build a Databricks demo/training course, one topic at a time. The user presents it
live to a mixed technical / non-technical audience, so **every cell needs comments
explaining what the code does, why it exists, and what benefit it delivers.**

## Topic status

| # | Topic | Status | Where |
|---|---|---|---|
| 1 | Notebook magic commands | **DONE — verified 6/6 passing** | `course-demo/01_magic_commands/` |
| 2 | Unity Catalog metastore | **In progress** | `course-demo/02_unity_catalog/` |
| 3 | Creating & managing Delta tables | **DONE — verified running clean** | `course-demo/03_delta_tables/` |
| 4 | Time travel — querying historical versions | **DONE — verified running clean** | `course-demo/04_time_travel/` |
| 5 | Restore & rollback strategies | **DONE — verified running clean** | `course-demo/05_restore_rollback/` |
| 6+ | Not yet chosen | — | — |

## Topic 1 — magic commands (complete, do not modify without asking)

Six lessons, all verified passing on serverless:
`t_core` (`%md`/`%python`/`%sql`), `t_run` (`%run`), `t_pip` (`%pip`),
`t_sh` (`%sh`), `t_dbutils` (widgets/secrets/notebook.run), `t_fs_vol` (`dbutils.fs`).

Three entry points:
- `01_all_in_one.py` — **best for presenting**, all six inline, run top to bottom
- `00_demo_walkthrough.py` — runs the six as separate notebooks, prints a scoreboard
- `t_*.py` — individual lessons

`%pip` is deliberately placed **first** in `01_all_in_one` because it restarts the
Python interpreter and would wipe earlier variables. Do not "fix" this ordering.

Data: `demo_training.magic_cmds` — customers 100, orders 300, events 500, plus
volume `demo_vol`. Rebuild with `sql/00_setup_demo_training.sql`.

## Topic 2 — Unity Catalog metastore (current work)

User's requirements, verbatim in intent:
- **SQL only — no Python** in this notebook.
- **Drop the catalog/schema/volume in the first cell**, so the audience watches
  Unity Catalog objects get created live in the following cells.
- Same commenting standard as topic 1.

Uses catalog **`demo_uc`** — deliberately NOT `demo_training`, so the live teardown
cannot destroy topic 1's data.

Two notebooks, both verified running clean:
- `01_unity_catalog_metastore.sql` — metastore, catalog/schema/table/volume,
  information_schema, tags, views, GRANT/REVOKE, ownership, time travel, lineage
- `02_external_locations.sql` — storage credentials & external locations

**On `02`:** creating a *new* storage credential needs an AWS IAM role with a
Databricks trust policy (~30-45 min of AWS console work, admin rights). The user
has AWS, not Azure, and did not want to spend the time. So the notebook **inspects
the real auto-created `__databricks_managed_storage_credential` and
`__databricks_managed_storage_location`** (which return genuine output) and shows
the `CREATE STORAGE CREDENTIAL` / `CREATE EXTERNAL LOCATION` syntax as documented
reference cells in **AWS `s3://` form**, not the Azure `abfss://` form used by the
online course the user was following. **The user has explicitly asked to revisit this** - see `docs/BACKLOG.md` item 1
for the full step-by-step plan (bucket, IAM role, VALIDATE, external location,
mapping, grants). Do not start it unprompted, but do not treat it as closed.

Also note: `LIST '<path>'` is the SQL equivalent of `%fs ls` and works on
serverless — worth preferring in all SQL material.

## Repo layout (restructured 2026-09-09)

```
course-demo/
  01_magic_commands/      topic 1  (+ not_supported/)
  02_unity_catalog/       topic 2
  03_delta_tables/        topic 3
  04_time_travel/         topic 4
  05_restore_rollback/    topic 5
```

Mirrored in the workspace at
`/Workspace/Users/selvarajaa13@gmail.com/course-demo/`.
The move was safe because every cross-notebook reference is relative (`./child`,
`./t_core`) and there are no hardcoded `/Workspace/` paths. Keep it that way -
relative refs are what make the folders movable. All notebooks re-verified passing
after the move.

## Topic 3 — Delta tables (complete)

`course-demo/03_delta_tables/01_creating_managing_delta_tables.sql` — pure SQL,
teardown-first, own catalog **`demo_delta`** (schema `sales`). Covers CREATE with
identity columns and NOT NULL, INSERT, DESCRIBE DETAIL, UPDATE, DELETE, MERGE,
DESCRIBE HISTORY, time travel + version diff, RESTORE, ALTER ADD COLUMN, CHECK
constraint, OPTIMIZE/ZORDER, VACUUM DRY RUN, CTAS and DEEP CLONE.

**Catalog-per-topic pattern** — each topic drops and recreates only its own
catalog, so a live teardown can never damage another topic:
topic 1 `demo_training` · topic 2 `demo_uc` · topic 3 `demo_delta`.

## Topic 4 — Time travel (complete)

`course-demo/04_time_travel/01_query_historical_versions.sql` — pure SQL,
teardown-first, own catalog **`demo_timetravel`** (schema `inventory`). Deep dive
beyond topic 3's brief coverage: DESCRIBE HISTORY as a readable audit log,
VERSION AS OF, the `@v1` shorthand, version diffing with FULL JOIN and EXCEPT,
reproducing an old report, **Change Data Feed** (`table_changes()`, pre/post
images), retention properties, and RESTORE (including restoring forward again).

**Gotcha discovered the hard way — do not "fix" this:** `TIMESTAMP AS OF` is
shown as documentation, not executed. Delta rejects a timestamp before the first
commit *or* after the latest commit, so a table created seconds ago has **no
valid literal timestamp**. Variables and subqueries are also rejected — the
clause needs a constant. The notebook explains both error modes and draws the
rule: **timestamps to explore, version numbers to reproduce.**

CDF must be enabled at CREATE time (`delta.enableChangeDataFeed = true`); it
cannot backfill changes made before it was switched on.

## Topic 5 — Restore & rollback (complete)

`course-demo/05_restore_rollback/01_restore_and_rollback_strategies.sql` — pure
SQL, teardown-first, own catalog **`demo_rollback`** (schema `finance`).

Deliberately scoped **away from topic 4**: topic 4 is about *reading* history,
topic 5 is about *choosing a recovery*. Five strategies, each with when-to-use
and its main risk: full `RESTORE`, surgical `MERGE` from an old version,
`UNDROP TABLE`, clone checkpoints (shallow vs deep), and blue/green swap via
`RENAME`. Plus what destroys rollback ability (VACUUM/retention) and rehearsing
a recovery on a clone first.

All five were probed against the live workspace before writing — `UNDROP TABLE`,
`SHALLOW CLONE`, `ALTER TABLE RENAME` and merge-from-old-version all work here.

## Full audit — 2026-09-09

Every notebook in the course was run and confirmed error-free: **12/12 passed**
(6 magic-command lessons, all_in_one, walkthrough, both UC notebooks, delta,
time travel). Topic 5 verified separately. Re-run this audit after any edit.

**Ordering note for audits:** the two `02_unity_catalog` notebooks must run
**sequentially** — `01` drops `demo_uc`, which `02` reads. Everything else uses
its own catalog and is parallel-safe.

## Environment

- Profile `demo-training` → `https://dbc-73857455-1589.cloud.databricks.com`
- Workspace notebooks under `/Workspace/Users/selvarajaa13@gmail.com/`
- Serverless only. See `CLAUDE.md` for the full constraint list.

## Open items

See **`docs/BACKLOG.md`** — it holds the deferred work with the reasoning and the
plan for each. Headlines: revisit external locations / AWS IAM (the user asked for
this), rotate the compromised PAT, choose topic 3.

## Useful docs in this repo

- `CLAUDE.md` — rules and environment gotchas
- `docs/magic-commands-test-report.md` — full topic-1 test results and findings
- `course-demo/01_magic_commands/not_supported/README.md` — what fails here and why

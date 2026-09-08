# databricks-code-demo

Demo / training repo for Databricks. **Fully isolated from the Lakebridge migration work** —
everything here lives in the `demo_training` catalog and nothing touches `lakebridge_demo`.

- Workspace: `https://dbc-73857455-1589.cloud.databricks.com`
- CLI profile: `demo-training`
- Catalog / schema: `demo_training.magic_cmds` (+ volume `demo_vol`)

## Topics

1. **Notebook magic commands** — `course-demo/01_magic_commands/`
2. **Unity Catalog & the metastore** — `course-demo/02_unity_catalog/`
3. **Creating & managing Delta tables** — `course-demo/03_delta_tables/`
4. **Time travel: querying historical versions** — `course-demo/04_time_travel/`

See `MEMORY.md` for current state, `CLAUDE.md` for the rules, and
`docs/BACKLOG.md` for deferred work.

## Layout

| Path | What |
|---|---|
| `sql/00_setup_demo_training.sql` | Creates catalog, schema, volume, 3 demo tables, loads 900 rows |
| `sql/99_teardown.sql` | Drops **only** `demo_training` |
| `course-demo/01_magic_commands/00_demo_walkthrough.py` | Runs the six lesson notebooks in order, prints a scoreboard |
| `course-demo/01_magic_commands/01_all_in_one.py` | **Best for presenting** — all six lessons inline in one notebook, run top to bottom |
| `course-demo/01_magic_commands/` | **Demo-ready** — every notebook here passes on serverless |
| `course-demo/02_unity_catalog/01_unity_catalog_metastore.sql` | **Topic 2** — Unity Catalog & metastore, pure SQL, teardown-first |
| `course-demo/02_unity_catalog/02_external_locations.sql` | **Topic 2b** — storage credentials & external locations (AWS) |
| `course-demo/03_delta_tables/01_creating_managing_delta_tables.sql` | **Topic 3** — Delta: MERGE, time travel, RESTORE, OPTIMIZE, CLONE |
| `course-demo/04_time_travel/01_query_historical_versions.sql` | **Topic 4** — history, `@v`, version diffing, Change Data Feed, RESTORE |
| `course-demo/01_magic_commands/not_supported/` | Parked failures (`%scala`, `%r`, `%fs`, `%conda`) — not for the demo |
| `docs/magic-commands-test-report.md` | Results of the serverless test run |

## Running the tests

Each notebook is isolated so one failure doesn't mask the rest.

```bash
databricks workspace import /Workspace/Users/<you>/magic_cmds_test/t_core \
  --file course-demo/01_magic_commands/t_core.py --format SOURCE --language PYTHON --overwrite \
  --profile demo-training

databricks jobs submit --json '{
  "run_name":"magic-t_core",
  "tasks":[{"task_key":"main","notebook_task":{"notebook_path":"/Workspace/Users/<you>/magic_cmds_test/t_core"},"environment_key":"env"}],
  "environments":[{"environment_key":"env","spec":{"client":"4"}}]}' --profile demo-training
```

Fetch results with the **task** run id (not the parent run id):

```bash
databricks jobs get-run-output <TASK_RUN_ID> --profile demo-training
```

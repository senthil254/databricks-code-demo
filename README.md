# databricks-code-demo

Demo / training repo for Databricks. **Fully isolated from the Lakebridge migration work** —
everything here lives in the `demo_training` catalog and nothing touches `lakebridge_demo`.

- Workspace: `https://dbc-73857455-1589.cloud.databricks.com`
- CLI profile: `demo-training`
- Catalog / schema: `demo_training.magic_cmds` (+ volume `demo_vol`)

## Layout

| Path | What |
|---|---|
| `sql/00_setup_demo_training.sql` | Creates catalog, schema, volume, 3 demo tables, loads 900 rows |
| `sql/99_teardown.sql` | Drops **only** `demo_training` |
| `notebooks/magic_commands/00_demo_walkthrough.py` | **Start here** — runs all six lessons in order, prints a scoreboard |
| `notebooks/magic_commands/` | **Demo-ready** — every notebook here passes on serverless |
| `notebooks/not_supported/` | Parked failures (`%scala`, `%r`, `%fs`, `%conda`) — not for the demo |
| `docs/magic-commands-test-report.md` | Results of the serverless test run |

## Running the tests

Each notebook is isolated so one failure doesn't mask the rest.

```bash
databricks workspace import /Workspace/Users/<you>/magic_cmds_test/t_core \
  --file notebooks/magic_commands/t_core.py --format SOURCE --language PYTHON --overwrite \
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

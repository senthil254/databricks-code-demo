# Agent instructions — read this first

This file is loaded automatically at the start of every session. If you have lost
context (compaction, new session, plan limit), read `MEMORY.md` next and you will
be able to continue exactly where the previous session stopped.

## What this repo is

A **Databricks demo / training** repo. Each "topic" is a self-contained lesson the
user presents live to an audience of mixed technical skill.

## Hard rules — do not break these

1. **Never touch `lakebridge_demo` or the `demo_cat` catalog.** They belong to a
   separate Lakebridge migration project. All work here goes in `demo_*` catalogs
   created by this repo.
2. **Never drop `demo_training`.** It holds the topic-1 demo data. The topic-2
   notebook drops `demo_uc` only — a deliberately separate catalog so a live
   teardown demo cannot destroy topic 1.
3. **Use `--profile demo-training`** on every `databricks` CLI call. Never
   auto-select a profile; never use the `lakebridge-*` profiles.
4. **Verify before claiming done.** Run the notebook and report the real result.
   Never state a notebook works without having run it.

## Environment facts that cost time to rediscover

- Workspace `https://dbc-73857455-1589.cloud.databricks.com` is **serverless-only**.
  It has **no classic compute and cannot have any** — cluster creation fails with
  `does not have any associated worker environments`. Do not retry this.
- **`databricks clusters create` exits 0 and prints nothing on that failure.** Only
  the raw REST call surfaces the error. Do not trust its exit code.
- `%scala`, `%r`, `%fs`, `%conda` **cannot work here**. Parked in
  `notebooks/not_supported/` with reasons. Do not try to "fix" them.
- DBFS root is disabled. Use **UC Volumes** (`/Volumes/<cat>/<schema>/<vol>/`).
- The `databricks-mcp` MCP server fails to connect. Use the CLI instead.

## How to run a notebook

```bash
databricks workspace import /Workspace/Users/selvarajaa13@gmail.com/<folder>/<name> \
  --file <local.py> --format SOURCE --language PYTHON --overwrite --profile demo-training

databricks jobs submit --no-wait --profile demo-training --json '{
  "run_name":"x",
  "tasks":[{"task_key":"main","notebook_task":{"notebook_path":"<workspace path>"},"environment_key":"env"}],
  "environments":[{"environment_key":"env","spec":{"client":"4"}}]}'
```

Then poll `databricks jobs get-run <RUN_ID>` until `TERMINATED`, and fetch output
with `databricks jobs get-run-output <TASK_RUN_ID>` — **the task run id from
`.tasks[0].run_id`, not the parent run id**, or it errors.

## Two-place rule

Notebooks live in **both** git and the Databricks workspace. A change in one is not
a change in the other. When you move, rename or delete a notebook, **do it in both**
and say so. This has already caused one bug.

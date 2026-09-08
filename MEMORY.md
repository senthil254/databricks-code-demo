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
| 1 | Notebook magic commands | **DONE — verified 6/6 passing** | `notebooks/magic_commands/` |
| 2 | Unity Catalog metastore | **In progress** | `notebooks/unity_catalog/` |
| 3+ | Not yet chosen | — | — |

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

## Environment

- Profile `demo-training` → `https://dbc-73857455-1589.cloud.databricks.com`
- Workspace notebooks under `/Workspace/Users/selvarajaa13@gmail.com/`
- Serverless only. See `CLAUDE.md` for the full constraint list.

## Open items

- **Rotate the PAT.** `dapicea78...` was pasted into a chat transcript and is
  compromised. The user chose to defer this until after the demo.
- Topic 3 not yet chosen — ask the user.

## Useful docs in this repo

- `CLAUDE.md` — rules and environment gotchas
- `docs/magic-commands-test-report.md` — full topic-1 test results and findings
- `notebooks/not_supported/README.md` — what fails here and why

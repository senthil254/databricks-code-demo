# Databricks magic commands — test report

- **Workspace:** `dbc-73857455-1589.cloud.databricks.com`
- **Compute:** Serverless notebook (jobs, `client: "4"`)
- **Catalog:** `demo_training.magic_cmds` — 100 customers / 300 orders / 500 events
- **Method:** one notebook per magic, submitted as independent one-time runs

## Results

| Magic / API | Result | Notes |
|---|---|---|
| `%md` | PASS | |
| `%python` | PASS | Read 100 rows from UC table |
| `%sql` | PASS | Created temp view |
| cross-language temp view (`%sql` → `%python`) | PASS | 33 gold rows visible in both |
| `%run` | PASS | Child notebook's variable in caller's scope |
| `%pip install` | PASS | `tabulate==0.9.0` installed & imported |
| `%sh` | PASS | `echo/whoami/pwd` all ran |
| `dbutils.widgets` | PASS | text widget get/set |
| `dbutils.notebook.run` | PASS | |
| `dbutils.secrets.listScopes` | PASS | Returns 0 — no scopes defined yet |
| `dbutils.fs` on **UC Volume** | PASS | mkdirs / put / cp / ls / rm |
| `dbutils.fs.ls("/")` | PASS | 3 entries |
| `%fs` | **FAIL** | Blocked as Scala — see below |
| `%scala` | **FAIL** | Not supported on serverless |
| `%r` | **FAIL** | Workspace policy: SQL + Python only |
| `%conda` | **FAIL** (expected) | Removed from modern DBR; use `%pip` |
| magic not on first line | **FAIL** (expected) | `SyntaxError` — correct behaviour |
| `dbutils.fs` on **DBFS root** | **FAIL** | `DBFS_DISABLED` — public DBFS root off |

## Key findings

**1. `%fs` is unusable on serverless.** It fails with:

> `PERMISSION_DENIED: [UNAUTHORIZED_COMMAND] Scala is not yet supported by Serverless compute.`

`%fs` is implemented as a Scala shim, so the serverless Scala ban takes it out even though
the command itself is language-neutral. Confirmed by isolating `%fs ls /` in its own notebook.
**Use `dbutils.fs.*` instead** — the Python API works fine.

**2. DBFS root is disabled in this workspace.** `dbutils.fs` against `/tmp/...` fails with
`[DBFS_DISABLED] Public DBFS root is disabled`. All file work must go through UC Volumes
(`/Volumes/<cat>/<schema>/<vol>/...`), which tested clean.

**3. `%scala` and `%r` will not run here.** Scala is a serverless platform limitation;
R is blocked by a workspace policy allowing only SQL and Python. Both need a classic
interactive cluster — and this workspace currently has **zero clusters**.

**4. `get-run-output` needs the task run id,** not the parent run id, or it errors with
"Retrieving the output of runs with multiple tasks is not supported".

## Recommendation for training material

Teach `%md`, `%python`, `%sql`, `%run`, `%pip`, `%sh` and `dbutils.*` as the serverless-safe
set. Present `%fs`, `%scala`, `%r`, `%conda` as "know these exist, here's why they fail" —
they're good teaching moments for the serverless vs classic distinction.

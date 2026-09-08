# Parked — do not use in the demo

These notebooks all FAIL on this workspace. Reasons are permanent, not fixable
before the demo:

| Notebook | Why it fails |
|---|---|
| `t_scala.py` | Scala unsupported on serverless; no classic cluster possible |
| `t_r.py` | Workspace policy allows SQL + Python only |
| `t_fs.py`, `t_fs_magic.py` | `%fs` is a Scala shim → blocked on serverless. Use `dbutils.fs` |
| `t_fs_dbutils.py` | DBFS root disabled. Use UC Volumes (`t_fs_vol.py` instead) |
| `t_conda.py` | `%conda` removed from modern DBR. Use `%pip` |
| `t_neg_notfirst.py` | Intentional negative test — raises SyntaxError by design |

Requires a workspace with classic compute enabled. See
`docs/magic-commands-test-report.md`.

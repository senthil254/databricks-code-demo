# Backlog — work deliberately deferred

Items here were **consciously postponed**, not forgotten. Each records why, so a
future session does not re-litigate the decision or assume it was an oversight.

---

## 1. External locations: real credential + AWS IAM setup  — HIGH VALUE, REVISIT

**Status:** deferred on 2026-09-09. The user explicitly asked to revisit this.

**What exists today:** `course-demo/02_unity_catalog/02_external_locations.sql`
*inspects* the auto-created `__databricks_managed_storage_credential` and
`__databricks_managed_storage_location` (real output), and shows the `CREATE`
syntax as documented reference cells. Nothing is actually created.

**Why deferred:** creating a real storage credential needs an AWS IAM role with a
Databricks trust policy and self-assume permission — roughly 30-45 minutes of AWS
console work requiring admin rights. The user was preparing for a demo and chose
to skip it. The user has **AWS, not Azure** (the online course they referenced
used Azure `abfss://`; all our material uses AWS `s3://`).

**What to do when we come back to it — in order:**

1. **Create the S3 bucket** for the demo data lake (region should match the
   metastore; check `current_metastore()`).
2. **Create the AWS IAM role.** In Databricks: Catalog → External Data → Credentials
   → Create credential. Databricks generates the exact trust policy JSON — use it
   verbatim rather than hand-writing it. The role must be able to **assume itself**
   (a self-referencing trust statement); this is the step people most often miss.
3. **Attach the S3 access policy** to that role (`s3:GetObject`, `PutObject`,
   `DeleteObject`, `ListBucket`, `GetBucketLocation` on the bucket and its contents).
4. **`CREATE STORAGE CREDENTIAL`** with the role ARN, then run
   **`VALIDATE STORAGE CREDENTIAL`** — validate before going further, or later
   failures are very hard to diagnose.
5. **`CREATE EXTERNAL LOCATION`** pointing at the bucket path, using that credential.
6. **Test the mapping and usage** end to end:
   - `LIST 's3://<bucket>/<path>/'`
   - `CREATE EXTERNAL VOLUME` at that path, upload a file, read it back
   - `CREATE TABLE ... LOCATION 's3://...'` over existing files
   - Confirm `DROP TABLE` on the external table leaves the files in place
     (the key managed-vs-external difference)
7. **Test the permission model:** `GRANT READ FILES` / `WRITE FILES` /
   `CREATE EXTERNAL TABLE`, then `SHOW GRANTS ON EXTERNAL LOCATION`, then `REVOKE`.
8. **Then convert the reference cells in `02_external_locations.sql` into live,
   executing cells** and re-verify the notebook end to end.

**Watch out for:** IAM propagation delay (a fresh role can take a couple of minutes
to become assumable — `VALIDATE` may fail once and then succeed); and the
external-location URL must not overlap an existing location, or creation is refused.

---

## 2. Rotate the Databricks PAT — SECURITY

The token `dapicea78...` was pasted into a chat transcript and must be treated as
compromised. The user deferred rotation until after the demo.

Settings → Developer → Access tokens → revoke it and issue a new one, then update
the `demo-training` profile in `~/.databrickscfg`.

---

## 3. Classic compute — BLOCKED, not deferred

`%scala`, `%r` and `%fs` cannot run on this workspace: it is serverless-only and
cannot host classic compute (`does not have any associated worker environments`).
Covering them needs a **new workspace** created with AWS cloud credentials, which
is the same IAM work as item 1. See `docs/magic-commands-test-report.md`.

---

## 4. Topic 5 — not yet chosen

Topics 1-4 are done (magic commands, Unity Catalog, Delta tables, time travel).
Ask the user what comes next.

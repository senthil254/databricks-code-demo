-- Databricks notebook source
-- MAGIC %md
-- MAGIC # Topic 2b — Cloud Storage Access: Credentials & External Locations
-- MAGIC
-- MAGIC **Pure SQL. No Python.**
-- MAGIC
-- MAGIC Notebook `01` covered governing data that lives *inside* Unity Catalog. This one
-- MAGIC covers the other half: **data that lives in your own cloud storage account**, and
-- MAGIC how Unity Catalog governs access to it.
-- MAGIC
-- MAGIC ## The problem this solves
-- MAGIC Your company already has data in cloud storage — an S3 bucket full of CSVs a
-- MAGIC partner drops each night, years of exported files, a data lake built before
-- MAGIC Databricks arrived. You want to use it **without copying it** and **without
-- MAGIC handing out the storage keys.**
-- MAGIC
-- MAGIC The old way was to paste an access key into a notebook. That is a disaster:
-- MAGIC the key is in the code, in Git, in screenshots, and it grants whoever finds it
-- MAGIC full access to the bucket with no audit trail.
-- MAGIC
-- MAGIC ## How Unity Catalog does it — three objects
-- MAGIC
-- MAGIC | Object | What it is | Analogy |
-- MAGIC |---|---|---|
-- MAGIC | **Storage Credential** | The identity UC uses to reach your cloud account (an AWS IAM role) | The **key** to the building |
-- MAGIC | **External Location** | A specific path, paired with a credential | The **address of one room** |
-- MAGIC | **External Table / Volume** | A table or folder registered at that path | The **furniture** in the room |
-- MAGIC
-- MAGIC The important part: **the key is held once, by an administrator.** Everyone else
-- MAGIC is granted access to a *location*, never to the credential. Nobody ever sees a
-- MAGIC secret, and every access is logged.
-- MAGIC
-- MAGIC > **Note on this workspace.** Creating a *new* storage credential requires an AWS
-- MAGIC > IAM role to be set up first, which is an administrator task in the AWS console.
-- MAGIC > This notebook therefore **inspects the real credential and location that already
-- MAGIC > exist here**, and shows the creation syntax as documentation. Everything that
-- MAGIC > runs below returns genuine output from this workspace.
-- MAGIC
-- MAGIC > **If you have seen a course that used `abfss://...windows.net/`** — that is the
-- MAGIC > Azure form. The concepts are identical; only the URL scheme differs.
-- MAGIC > Azure: `abfss://container@account.dfs.core.windows.net/` · AWS: `s3://bucket/path/`

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 1 — Which metastore are we attached to?
-- MAGIC
-- MAGIC Storage credentials and external locations belong to the **metastore**, not to a
-- MAGIC workspace. Define one once and every workspace on this metastore can use it —
-- MAGIC that is the "govern once, apply everywhere" promise in practice.
-- MAGIC
-- MAGIC The value returned encodes the cloud and region, e.g. `aws:us-west-2:<id>`.

-- COMMAND ----------

SELECT current_metastore() AS metastore, current_user() AS logged_in_as;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 2 — Storage credentials that exist today
-- MAGIC
-- MAGIC A credential is a **stored identity**, not a password. On AWS it points at an IAM
-- MAGIC role that your cloud administrator has allowed Databricks to assume.
-- MAGIC
-- MAGIC **Notice what you cannot see:** there is no key, no secret, no token in the output.
-- MAGIC That is the entire point. Even a metastore administrator reading this list cannot
-- MAGIC extract a usable credential from it.

-- COMMAND ----------

SHOW STORAGE CREDENTIALS;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ### A closer look
-- MAGIC `__databricks_managed_storage_credential` is created automatically when the
-- MAGIC metastore is set up. It is what managed tables and volumes use behind the scenes —
-- MAGIC so this mechanism has been quietly at work throughout notebook `01`.
-- MAGIC
-- MAGIC Note the **owner** field. Ownership is what controls who may grant others the
-- MAGIC right to use this credential.

-- COMMAND ----------

DESCRIBE STORAGE CREDENTIAL `__databricks_managed_storage_credential`;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 3 — External locations that exist today
-- MAGIC
-- MAGIC An external location joins a **path** to a **credential** and gives the pair a name.
-- MAGIC From then on, permissions are granted on that *name* — nobody deals with the
-- MAGIC underlying key again.
-- MAGIC
-- MAGIC Look at the `url` column in the output: a real `s3://` path in this account.

-- COMMAND ----------

SHOW EXTERNAL LOCATIONS;

-- COMMAND ----------

DESCRIBE EXTERNAL LOCATION `__databricks_managed_storage_location`;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 4 — Who is allowed to use it?
-- MAGIC
-- MAGIC This is the question an auditor actually asks. `SHOW GRANTS` answers it for a
-- MAGIC storage path exactly as it did for a table in notebook `01` — one consistent
-- MAGIC permission model covering databases, files and cloud storage alike.
-- MAGIC
-- MAGIC The three privileges that matter on a location:
-- MAGIC
-- MAGIC | Privilege | Allows |
-- MAGIC |---|---|
-- MAGIC | `READ FILES` | Read files at this path |
-- MAGIC | `WRITE FILES` | Write files at this path |
-- MAGIC | `CREATE EXTERNAL TABLE` | Register a table over data at this path |
-- MAGIC
-- MAGIC Granting `READ FILES` and withholding `WRITE FILES` gives an analyst genuine
-- MAGIC read-only access to a bucket — enforced by the platform, not by a policy document.

-- COMMAND ----------

SHOW GRANTS ON EXTERNAL LOCATION `__databricks_managed_storage_location`;

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 5 — Listing files with SQL
-- MAGIC
-- MAGIC SQL has a `LIST` command for browsing a governed path. **This is the SQL
-- MAGIC equivalent of `%fs ls`** — and it is the one to teach, because `%fs` does not work
-- MAGIC on serverless compute at all (it is implemented in Scala; see
-- MAGIC `course-demo/01_magic_commands/not_supported/`).
-- MAGIC
-- MAGIC Below we list the volume created in notebook `01`. Access is checked against
-- MAGIC Unity Catalog, exactly as it would be for a table.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC First make sure the volume exists. Notebook `01` creates it, but `01` also drops
-- MAGIC the catalog at its start — so if the two notebooks are run out of order, or `01`
-- MAGIC is re-run mid-session, the volume may be gone. These `IF NOT EXISTS` statements
-- MAGIC make this notebook **safe to run on its own, in any order**.
-- MAGIC
-- MAGIC Writing setup defensively like this is a habit worth teaching: a notebook that
-- MAGIC only works when run in exactly one sequence is a notebook that will fail in front
-- MAGIC of an audience.

-- COMMAND ----------

CREATE CATALOG IF NOT EXISTS demo_uc
  COMMENT 'Training catalog for the Unity Catalog lesson.';
CREATE SCHEMA  IF NOT EXISTS demo_uc.governance
  COMMENT 'Objects used to demonstrate Unity Catalog governance features.';
CREATE VOLUME  IF NOT EXISTS demo_uc.governance.landing_zone
  COMMENT 'Governed folder for incoming files.';

-- COMMAND ----------

LIST '/Volumes/demo_uc/governance/landing_zone';

-- COMMAND ----------

-- MAGIC %md
-- MAGIC An empty result is the correct answer here — we never put files in that volume.
-- MAGIC The point is that the command was **authorised and executed**, not refused.

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Step 6 — The creation syntax (reference)
-- MAGIC
-- MAGIC These are the statements an administrator runs once. **They are shown here as
-- MAGIC documentation and are deliberately not executed** — they require an AWS IAM role
-- MAGIC that has been configured to trust Databricks, which is a task in the AWS console.
-- MAGIC
-- MAGIC ### 6a. Create the storage credential
-- MAGIC ```sql
-- MAGIC CREATE STORAGE CREDENTIAL demo_aws_credential
-- MAGIC   WITH IAM ROLE 'arn:aws:iam::<your-aws-account-id>:role/databricks-uc-access'
-- MAGIC   COMMENT 'Credential for the demo data lake bucket';
-- MAGIC ```
-- MAGIC The IAM role must trust the Databricks account and be able to assume itself.
-- MAGIC Databricks generates the exact trust policy for you in the UI.
-- MAGIC
-- MAGIC ### 6b. Create the external location
-- MAGIC ```sql
-- MAGIC CREATE EXTERNAL LOCATION IF NOT EXISTS demo_landing_zone
-- MAGIC   URL 's3://my-company-data-lake/landing/'
-- MAGIC   WITH (STORAGE CREDENTIAL demo_aws_credential)
-- MAGIC   COMMENT 'Nightly partner file drop';
-- MAGIC ```
-- MAGIC *(The Azure equivalent differs only in the URL:
-- MAGIC `abfss://demo@myaccount.dfs.core.windows.net/`.)*
-- MAGIC
-- MAGIC ### 6c. Grant access to the location — never to the credential
-- MAGIC ```sql
-- MAGIC GRANT READ FILES ON EXTERNAL LOCATION demo_landing_zone TO `data_analysts`;
-- MAGIC GRANT WRITE FILES, CREATE EXTERNAL TABLE
-- MAGIC   ON EXTERNAL LOCATION demo_landing_zone TO `data_engineers`;
-- MAGIC ```
-- MAGIC **This is the payoff.** Analysts read; engineers write and register tables; the
-- MAGIC IAM role is known to neither. Revoking access is one `REVOKE`, effective
-- MAGIC immediately, with no key rotation and no redeployment.
-- MAGIC
-- MAGIC ### 6d. Register data at that path
-- MAGIC ```sql
-- MAGIC -- A governed folder for files
-- MAGIC CREATE EXTERNAL VOLUME demo_uc.governance.partner_drop
-- MAGIC   LOCATION 's3://my-company-data-lake/landing/partner/';
-- MAGIC
-- MAGIC -- A table over files that already exist - no copying, no ingestion
-- MAGIC CREATE TABLE demo_uc.governance.partner_orders
-- MAGIC   USING DELTA
-- MAGIC   LOCATION 's3://my-company-data-lake/landing/partner/orders/';
-- MAGIC ```

-- COMMAND ----------

-- MAGIC %md
-- MAGIC ## Managed vs external — which should you choose?
-- MAGIC
-- MAGIC | | **Managed** (notebook 01) | **External** (this notebook) |
-- MAGIC |---|---|---|
-- MAGIC | Who chooses the storage path | Unity Catalog | You do |
-- MAGIC | `DROP TABLE` deletes the files | **Yes** | **No** — files remain |
-- MAGIC | Performance tuning | Automatic | Your responsibility |
-- MAGIC | Best for | New data you are creating | Data that already exists elsewhere |
-- MAGIC
-- MAGIC **Recommendation: managed by default.** Choose external when the data genuinely
-- MAGIC must live somewhere specific — another tool writes it, a regulator dictates the
-- MAGIC location, or it predates Databricks.
-- MAGIC
-- MAGIC The `DROP` row is the one that catches people out. With an external table, `DROP`
-- MAGIC removes only the registration; the files stay and keep costing money. That is
-- MAGIC occasionally what you want, and frequently a nasty surprise.
-- MAGIC
-- MAGIC ## Recap
-- MAGIC
-- MAGIC - **Storage Credential** = the identity (an IAM role). Held once, by an admin.
-- MAGIC - **External Location** = credential + path, given a name.
-- MAGIC - **Grants go on the location, never the credential.** Nobody sees a secret.
-- MAGIC - `LIST` is the SQL way to browse a path — `%fs` does not work on serverless.
-- MAGIC - Same `GRANT` / `REVOKE` / `SHOW GRANTS` model as tables. One system, one
-- MAGIC   mental model, one audit trail.

-- COMMAND ----------

SELECT 'External locations demo complete' AS status;

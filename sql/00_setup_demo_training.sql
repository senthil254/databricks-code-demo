-- Demo/training catalog for Databricks magic-command testing.
-- Isolated from the lakebridge migration catalogs. Safe to drop and recreate.
CREATE CATALOG IF NOT EXISTS demo_training
  COMMENT 'Databricks demo/training repo. NOT lakebridge.';
CREATE SCHEMA IF NOT EXISTS demo_training.magic_cmds;
CREATE VOLUME IF NOT EXISTS demo_training.magic_cmds.demo_vol;

CREATE OR REPLACE TABLE demo_training.magic_cmds.customers
  (customer_id INT, name STRING, city STRING, signup_date DATE, tier STRING);
CREATE OR REPLACE TABLE demo_training.magic_cmds.orders
  (order_id INT, customer_id INT, amount DECIMAL(10,2), order_ts TIMESTAMP, status STRING);
CREATE OR REPLACE TABLE demo_training.magic_cmds.events
  (event_id INT, customer_id INT, event_type STRING, event_ts TIMESTAMP);

INSERT INTO demo_training.magic_cmds.customers
SELECT id, concat('customer_', id),
       element_at(array('Chennai','Bangalore','Mumbai','Delhi','Pune'), cast(pmod(id,5)+1 AS INT)),
       date_add(DATE'2024-01-01', cast(pmod(id*7,600) AS INT)),
       element_at(array('bronze','silver','gold'), cast(pmod(id,3)+1 AS INT))
FROM range(1,101);

INSERT INTO demo_training.magic_cmds.orders
SELECT id, cast(pmod(id,100)+1 AS INT),
       cast(round(rand(42)*900+10,2) AS DECIMAL(10,2)),
       timestampadd(HOUR, cast(-pmod(id*13,4000) AS INT), TIMESTAMP'2025-06-01 00:00:00'),
       element_at(array('placed','shipped','delivered','cancelled'), cast(pmod(id,4)+1 AS INT))
FROM range(1,301);

INSERT INTO demo_training.magic_cmds.events
SELECT id, cast(pmod(id,100)+1 AS INT),
       element_at(array('login','view','click','purchase','logout'), cast(pmod(id,5)+1 AS INT)),
       timestampadd(MINUTE, cast(-pmod(id*37,90000) AS INT), TIMESTAMP'2025-06-01 00:00:00')
FROM range(1,501);

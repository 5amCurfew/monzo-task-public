- [Create dbt venv](#create-dbt-venv)
- [Database Environment](#database-environment)
  * [Assumptions](#assumptions)
  * [Overview of Data Model](#overview-of-data-model)
- [Task 1 Accounts](#task-1-accounts)
  * [Task](#task)
  * [Outcome](#outcome)
- [Task 2 7-day Active Users](#task-2-7-day-active-users)
  * [Task](#task-1)
  * [Outcome](#outcome-1)
- [Misc](#misc)

## Create dbt venv

Ensure that Python is installed on your machine.

Locally I use `pyenv` as a python version manager. This project was built using Python 3.9.6. If you already use `pyenv` this will be set by the `.python_version` file when opening a terminal in this directory.

Create the virtual environment by running the following in your terminal when in this directory:

1. `python3 -m venv dbt-env`
2. `source dbt-env/bin/activate`
3. `python3 -m pip install -r requirements.txt`

Running `which dbt` once the virtual environment is activated should point to the version then installed. For example:

```bash
samuel.knight@SA00049-SamuelK monzo-task-public % source dbt-env/bin/activate
(dbt-env) samuel.knight@SA00049-SamuelK monzo-task-public % which dbt
/Users/samuel.knight/git/monzo-task-public/dbt-env/bin/dbt
```

Ensure `dbt` has been installed and activated correctly by running `dbt --version` in your terminal. If it has been successful, move into the `monzo_task/` and run `dbt deps` for installing dbt packages used in this project. Your output should mirror:

```bash
(dbt-env) samuel.knight@SA00049-SamuelK monzo-task-public % dbt --version
Core:
  - installed: 1.3.2
  - latest:    1.3.2 - Up to date!

Plugins:
  - bigquery: 1.3.0 - Up to date!
```

(Note that it might require activating the virtual environment again following `cd monzo_task`)

```bash
(dbt-env) samuel.knight@SA00049-SamuelK monzo-task-public % cd monzo_task
(dbt-env) samuel.knight@SA00049-SamuelK monzo_task % source ../dbt-env/bin/activate
(dbt-env) samuel.knight@SA00049-SamuelK monzo_task % which dbt
/Users/samuel.knight/git/monzo-task-public/dbt-env/bin/dbt
(dbt-env) samuel.knight@SA00049-SamuelK monzo_task % dbt deps
13:21:29  Running with dbt=1.3.2
13:21:30  Installing dbt-labs/dbt_utils
13:21:30    Installed from version 1.0.0
13:21:30    Up to date!
```

## Database Environment

* `monzo_datawarehouse.account_closed`
* `monzo_datawarehouse.account_created`
* `monzo_datawarehouse.account_reopened`
* `monzo_datawarehouse.account_transactions`

This dbt project has been materialised in a personal (samueltobyknight@gmail.com) Google Cloud Project named `dbt-monzo-task`. All models have been materialised in the `monzo_task` dataset (i.e. schema).

Exports from the `monzo_datawarehouse` dataset provided were loaded into this project using `dbt seed --profiles-dir ./.dbt` where the `dbt` profile is using a `service-account` with credentials stored in `dbt-monzo-task-credentials.json`. Data modelling will be implemented using this project throughout (note an export of 66,666 transactions are used).

To mirror this set up please create `monzo_task/.dbt` that reflects the `monzo_task/.dbt_template` to create your own access credentials and run this project in your desired GCP project. The `keyfile` can be generated and exported using the Google Cloud Console. Check your connection is valid using `dbt debug --profiles-dir ./.dbt` when in the `monzo_task/` directory that contains the dbt project. Your output should be similar to below if succcessful.

```bash
(dbt-env) samuel.knight@SA00049-SamuelK monzo-task-public % cd monzo_task
(dbt-env) samuel.knight@SA00049-SamuelK monzo_task % dbt debug --profiles-dir ./.dbt
12:59:32  Running with dbt=1.3.2
dbt version: 1.3.2
python version: 3.9.6
python path: /Users/samuel.knight/git/monzo-task-public/dbt-env/bin/python3
os info: macOS-10.16-x86_64-i386-64bit
Using profiles.yml file at /Users/samuel.knight/git/monzo-task-public/monzo_task/.dbt/profiles.yml
Using dbt_project.yml file at /Users/samuel.knight/git/monzo-task-public/monzo_task/dbt_project.yml

Configuration:
  profiles.yml file [OK found and valid]
  dbt_project.yml file [OK found and valid]

Required dependencies:
 - git [OK found]

Connection:
  method: service-account
  database: dbt-monzo-task
  schema: monzo_task
  location: EU
  priority: interactive
  timeout_seconds: 300
  maximum_bytes_billed: None
  execution_project: dbt-monzo-task
  job_retry_deadline_seconds: None
  job_retries: 1
  job_creation_timeout_seconds: None
  job_execution_timeout_seconds: 300
  gcs_bucket: None
  Connection test: [OK connection ok]

All checks passed!
```

The full `dbt` project can be found in the `monzo_task/` directory. It follows suggested dbt patterns with the use of a *staging* step. This step is to write raw data and explicitly cast and rename fields for use later ("downstream").

All *staging* tables are written incrementally (see assumptions below for reasoning). For example `stg_accounts_created`:
```SQL
{{
    config(
        materialized='incremental',
        tags=['monzo', 'staging']
    )
}}

WITH source as (
    
    SELECT
        CAST(created_ts AS TIMESTAMP) as recorded_at,
        account_type,
        account_id_hashed as account_id,
        user_id_hashed as user_id
    FROM
      {{ source('monzo', 'account_created') }}
    
    {% if is_incremental() %}

  -- this filter will only be applied on an incremental run
    WHERE created_ts > (SELECT max(created_ts) FROM {{ this }})

    {% endif %}

)

SELECT * FROM source
```

`dbt` command examples (for more information please see the [dbt documentation](https://docs.getdbt.com/docs/introduction)):

```bash
dbt seed --profiles-dir ./.dbt
```

```bash
dbt run --models stg_accounts_created --profiles-dir ./.dbt --full-refresh
```

```bash
dbt test --profiles-dir ./.dbt
```

### Assumptions
 *"Each table is fully refreshed on a nightly basis from Monzo's append only logs"* suggests:

* 66,666 rows have been used from `account_transactions` in this project (see Database Environment above)
* existing data is immutable
* An *accounts* state is one of either *open* or *closed* and that the state of the account (e.g. its `type`) is not subject to change over its lifetime. This can also be seen using `select account_id_hashed, count(*) from monzo_task.account_created group by 1 order by 2 desc`
* An account requires `user_id_hash` and is always *one-to-one*
* Further metadata will be appended at the `account_created` data source
* An account can be closed an infinite amount of times without being reopened (discovered) but only created once. An account must have been created to be closed/reopened.
* `account_type` is not required (2 instances where `account_type` is `null`) (discovery)
* `user_id_hashed` is required
* Building models incrementally will capture all rows (*append only*) as it is suggested this mirrors event data
* Hard-deletes do not occur (accounts remain in a *closed* state)
* transactions can only exist for accounts that have been created
* No account closures from 2020-08-12 10:06:51.001000 UTC (discovery)
* `transaction_num` is the transaction number of the account in the given day (`account_transactions.date`) on `account_transactions`

### Overview of Data Model

In the previous stage I was asked which tools I would use to visualise a database schema. I read a post on the Monzo blog that stated using dbt generated documentation isn't feasible due to the scale of the the dbt project (4700+ models). I typically manually generate schema images in tools such as Miro. After the first-stage interview I thought a Javascript tool that reads the `manifest.json` and visualises the resulting schema in a similar way might be useful to explore/build. I had a quick go at building this (not complete at the time of writing, Node.js used) and the output of my schema for this task is below.

![alt text](https://github.com/5amCurfew/monzo-task-public/blob/main/img/overview.png)

The resulting data model follows a Fact & Dimensions model, using SCD2 for both accounts and users. A report table is also introduced for Task 2. Naming and casting is explicit in the staging step (which I would typically separate into a different schema).

## Task 1 Accounts
### Task

The business needs a very reliable and accurate data model that represents all the different accounts at Monzo. Your first task is to create a table using the existing data as outlined above. The most important requirements are that this model is accurate, complete, intuitive to use and well documented.

After implementing the model, please outline five of the most important tests that you would implement to give you the confidence in the output of your process. For this example, you should assume that upstream tables will change and that source data is not validated using contracts.

### Outcome

The resulting model: `monzo_task.dim_users`

`dim_users` is a slowly-changing-type2 (for more information check out [Kimball docs here](https://www.kimballgroup.com/data-warehouse-business-intelligence-resources/kimball-techniques/dimensional-modeling-techniques/type-2/)) dimension of *accounts* at Monzo. Each row represents an account and the corresponding state (either open or closed). Logical steps to build this model are as follows:

1. Create a CTE that contains the metadata of an account (this is found on `stg_accounts_created` and assumed the metadata - namely `user_id` and `account_type` doesn't change)
2. Build a *spine* CTE of each account update (for each `account_id_hashed` find each update - creation, closure and re-opening) using the commonly named `recorded_at` in the *staging* tables
3. Join on metadata on this spine (assumed this does not change for the purpose of the task)
4. Create fields `valid_from` and `valid_to` that reflect the period of an account in the given state. Note that these ranges should be *mutually exclusive* as this is what will be used later on event data such as `account_transactions`. This is ensure using a dbt test. Please see `_analytics_models.yml` for further information on the tests used.

```SQL
{{ config(
    materialized="view",
    tags=['monzo']
)}}

WITH account_meta AS (

    SELECT
        {{ dbt_utils.star(ref("stg_accounts_created"), except=["recorded_at"]) }}
    FROM
        {{ ref("stg_accounts_created") }}

),

spine AS (

    SELECT DISTINCT
        account_id,
        recorded_at,
        CAST('true' AS BOOLEAN) as is_open
    FROM
        {{ ref("stg_accounts_created") }}

    UNION ALL

    SELECT DISTINCT
        account_id,
        recorded_at,
        CAST('false' AS BOOLEAN) as is_open
    FROM
        {{ ref("stg_accounts_closed") }}

    UNION ALL

    SELECT DISTINCT
        account_id,
        recorded_at,
        CAST('true' AS BOOLEAN) as is_open
    FROM
        {{ ref("stg_accounts_reopened") }}
    
)

SELECT
    {{ dbt_utils.generate_surrogate_key(["spine.account_id", "spine.recorded_at"]) }} AS surrogate_key,
    spine.account_id as natural_key,
    spine.is_open,
    {{ dbt_utils.star(ref("stg_accounts_created"), relation_alias='account_meta', except=["recorded_at", "account_id"]) }},
    spine.recorded_at as valid_from,
    COALESCE(LEAD(spine.recorded_at) OVER (PARTITION BY spine.account_id ORDER BY spine.recorded_at ASC), CURRENT_TIMESTAMP()) AS valid_to
FROM
    spine
    INNER JOIN account_meta ON account_meta.account_id = spine.account_id
ORDER BY
    natural_key,
    valid_from
```

Historical accuracy is ensured using this model (e.g. used in Task 2) given the state is explicitly followed. This model reflects *all* accounts (none are lost from the raw data). Tests regarding uniqueness of the rows (using `surrogate_key`), mutually exclusive `valid_from/to` ranges with no gaps from initial account creation have been implemented using `dbt`.

The potential for new metadata being introduced is captured by the use of `+on_schema_change: "sync_all_columns"` (for more information please see [this documentation](https://docs.getdbt.com/docs/build/incremental-models#what-if-the-columns-of-my-incremental-model-change))

```yml
models:
  monzo_task:
    +on_schema_change: "sync_all_columns"
```

The model is documented in `monzo_task/models/analytics/_analytics_models.yml` that can then be viewed in the dbt-generated documentation:
```yml
  - name: dim_accounts
    description: |
      A [SCD2](https://www.kimballgroup.com/data-warehouse-business-intelligence-resources/kimball-techniques/dimensional-modeling-techniques/type-2/) of accounts at Monzo. Currently this model reflects the state (either open or closed) and associated user over time.
    columns:
      - name: surrogate_key
        description: The unique identifier of the account and state (open or closed)
        tests:
          - not_null
          - unique
      
      - name: natural_key
        description: The unique identifier of the account
        tests:
          - not_null

      - name: is_open
        description: A boolean flag for if the account is open
        tests:
          - not_null

      - name: valid_from
        description: The beginning of the interval the account was seen in the given state (inclusive)
        tests:
          - not_null
      
      - name: valid_to
        description: The end of the interval the account was seen in the given state (exclusive)
        tests:
          - not_null

    tests:
      - dbt_utils.mutually_exclusive_ranges:
          lower_bound_column: valid_from
          upper_bound_column: valid_to
          partition_by: natural_key
          gaps: not_allowed
```

![alt text](https://github.com/5amCurfew/monzo-task-public/blob/main/img/dim_accounts.png)

## Task 2 7-day Active Users

### Task

`7d_active_users` represents the number of users that had *a transaction over the last running 7 days*, divided by all the users with at least one open account at that point. Monzo needs to be able to analyse the activity of our users (remember, one user can be active across multiple accounts). In particular, we are looking at a metric aptly named `7d_active_users` (defined above). The goal for this part is to build a data model that will enable analysts on the team to explore this data very quickly and without friction.

### Outcome

Please find the model below (dates are hard-coded for ease of development - in a production environment these would be dynamic)

* the creation of `dim_users` following a similar structure to `dim_accounts` in Task 1 (state w.r.t a user is the number of open accounts)
* this allows for accuracy with respect to *"Users with only closed accounts should be excluded from the metric calculation.*"
* The creation of `first_created` on this model allow for cohort exploration (*"for example analyse the activity rate for certain age groups or for different signup cohorts (i.e. when the first account of this user was opened)."*)
* Flexibility added using `+on_schema_change: "sync_all_columns"` in the incremental models for the possibility of new metadata being added (recall assumption that this will exist on `account_created` source table)
* Filtering/exploration can be added using filtering in CTEs below (e.g. "users who joined Monzo in January, 2020": `AND date_trunc(dim_users.first_created, MONTH) = CAST('2020-01-01' AS TIMESTAMP)` or "users with account type UK Retail": `AND dim_users.open_account_types ILIKE '%uk_retail%'`)
* A materalised example can be found in `report_7d_active_users.sql`

Logic is as follows:
1. Create a spine of dates
2. Find all users that had an open account on each day
3. Count distinct users that had an open account that existed on at least one day within 7 days of the period start date (this creates the ceiling)
4. Count the number of transactions, and number of distinct users making transactions within 7 days of period start date
5. LEFT JOIN onto spine and calculate `7d_active_users`

```SQL
{{ config(
    materialized="view",
    tags=['monzo', 'report']
)}}

WITH spine AS (

  SELECT 
    CAST(day AS TIMESTAMP) as day
  FROM 
    UNNEST(GENERATE_DATE_ARRAY(DATE('2019-01-14'), DATE('2020-01-01'), INTERVAL 1 DAY)) as day

),

users_daily AS (

  SELECT
    spine.day,
    dim_users.natural_key
  FROM
    spine
    INNER JOIN {{ ref('dim_users') }} ON dim_users.valid_from <= spine.day
      AND dim_users.valid_to > spine.day
      AND dim_users.open_account_total > 0

),

users_7d AS (

  SELECT
    spine.day as period_start,
    COUNT(DISTINCT users_daily.natural_key) as total_users
  FROM
    spine
    LEFT JOIN users_daily ON users_daily.day >= spine.day
      AND users_daily.day < DATE_ADD(spine.day, INTERVAL 7 DAY)
  GROUP BY
    1

),

transactions_7d AS (

  SELECT
    spine.day as period_start,
    COUNT(fct_transactions.unique_key) as total_transactions,
    COUNT(DISTINCT dim_users.natural_key) as active_users
  FROM
    spine
    LEFT JOIN {{ ref('fct_transactions') }} ON fct_transactions.recorded_at >= spine.day
      AND fct_transactions.recorded_at < DATE_ADD(spine.day, INTERVAL 7 DAY)
    LEFT JOIN {{ ref('dim_users') }} ON dim_users.surrogate_key = fct_transactions.user_surrogate_key
  GROUP BY
    1

)

SELECT
  spine.day as period_start,
  DATE_ADD(spine.day, INTERVAL 6 DAY) as period_end,
  users_7d.total_users,
  transactions_7d.active_users,
  transactions_7d.total_transactions,
  ROUND(CAST(active_users/total_users AS DECIMAL), 2) as active_users_7d
FROM
  spine
  LEFT JOIN users_7d ON users_7d.period_start = spine.day
  LEFT JOIN transactions_7d ON transactions_7d.period_start = spine.day
ORDER BY
  1
```

![alt text](https://github.com/5amCurfew/monzo-task-public/blob/main/img/report_7d_active_users.png)

## Orchestrate with Airflow

In my previous interview we spoke about Airflow as the tool for orchestration. Following this I have also implemented a solution to automate (daily) the suggested data model above.

Prerequisites: both [Docker](https://docs.docker.com/) and [Make](https://www.gnu.org/software/make/manual/make.html) installed.

To run:

```bash
make start
```

This will build the container (defined in the `Dockerfile`) and then subsequently start up the Airflow server (using the entry point `init.sh`). Following a successful start-up the airflow webser ver can be viewed at `http://localhost:8080`.

For more information the dag `scheduled_dbt_daily` is written in the `dags` directory.

Example:

![alt text](https://github.com/5amCurfew/monzo-task-public/blob/airflow/img/airflow.png)

## Misc

```bash
(dbt-env) samuel.knight@SA00049-SamuelK monzo_task % dbt test --profiles-dir ./.dbt
13:37:22  Running with dbt=1.3.2
13:37:22  Found 7 models, 25 tests, 0 snapshots, 0 analyses, 431 macros, 0 operations, 4 seed files, 4 sources, 0 exposures, 0 metrics
13:37:22
13:37:23  Concurrency: 1 threads (target='dev')
13:37:23
13:37:23  1 of 25 START test dbt_utils_mutually_exclusive_ranges_dim_accounts_not_allowed__valid_from__natural_key__valid_to  [RUN]
13:37:25  1 of 25 PASS dbt_utils_mutually_exclusive_ranges_dim_accounts_not_allowed__valid_from__natural_key__valid_to  [PASS in 2.46s]
13:37:25  2 of 25 START test dbt_utils_mutually_exclusive_ranges_dim_users_not_allowed__valid_from__natural_key__valid_to  [RUN]
13:37:28  2 of 25 PASS dbt_utils_mutually_exclusive_ranges_dim_users_not_allowed__valid_from__natural_key__valid_to  [PASS in 2.86s]
13:37:28  3 of 25 START test not_null_dim_accounts_is_open ............................... [RUN]
13:37:29  3 of 25 PASS not_null_dim_accounts_is_open ..................................... [PASS in 0.95s]
13:37:29  4 of 25 START test not_null_dim_accounts_natural_key ........................... [RUN]
13:37:31  4 of 25 PASS not_null_dim_accounts_natural_key ................................. [PASS in 1.51s]
13:37:31  5 of 25 START test not_null_dim_accounts_surrogate_key ......................... [RUN]
13:37:32  5 of 25 PASS not_null_dim_accounts_surrogate_key ............................... [PASS in 1.25s]
13:37:32  6 of 25 START test not_null_dim_accounts_valid_from ............................ [RUN]
13:37:33  6 of 25 PASS not_null_dim_accounts_valid_from .................................. [PASS in 1.45s]
13:37:33  7 of 25 START test not_null_dim_accounts_valid_to .............................. [RUN]
13:37:35  7 of 25 PASS not_null_dim_accounts_valid_to .................................... [PASS in 1.80s]
13:37:35  8 of 25 START test not_null_dim_users_natural_key .............................. [RUN]
13:37:37  8 of 25 PASS not_null_dim_users_natural_key .................................... [PASS in 2.24s]
13:37:37  9 of 25 START test not_null_dim_users_surrogate_key ............................ [RUN]
13:37:39  9 of 25 PASS not_null_dim_users_surrogate_key .................................. [PASS in 2.10s]
13:37:39  10 of 25 START test not_null_dim_users_valid_from .............................. [RUN]
13:37:41  10 of 25 PASS not_null_dim_users_valid_from .................................... [PASS in 1.94s]
13:37:41  11 of 25 START test not_null_dim_users_valid_to ................................ [RUN]
13:37:44  11 of 25 PASS not_null_dim_users_valid_to ...................................... [PASS in 2.69s]
13:37:44  12 of 25 START test not_null_fct_transactions_unique_key ....................... [RUN]
13:37:47  12 of 25 PASS not_null_fct_transactions_unique_key ............................. [PASS in 2.95s]
13:37:47  13 of 25 START test not_null_stg_accounts_closed_account_id .................... [RUN]
13:37:48  13 of 25 PASS not_null_stg_accounts_closed_account_id .......................... [PASS in 1.19s]
13:37:48  14 of 25 START test not_null_stg_accounts_closed_recorded_at ................... [RUN]
13:37:49  14 of 25 PASS not_null_stg_accounts_closed_recorded_at ......................... [PASS in 1.23s]
13:37:49  15 of 25 START test not_null_stg_accounts_created_account_id ................... [RUN]
13:37:50  15 of 25 PASS not_null_stg_accounts_created_account_id ......................... [PASS in 1.03s]
13:37:50  16 of 25 START test not_null_stg_accounts_created_recorded_at .................. [RUN]
13:37:51  16 of 25 PASS not_null_stg_accounts_created_recorded_at ........................ [PASS in 0.96s]
13:37:51  17 of 25 START test not_null_stg_accounts_created_user_id ...................... [RUN]
13:37:52  17 of 25 PASS not_null_stg_accounts_created_user_id ............................ [PASS in 0.91s]
13:37:52  18 of 25 START test not_null_stg_accounts_reopened_account_id .................. [RUN]
13:37:53  18 of 25 PASS not_null_stg_accounts_reopened_account_id ........................ [PASS in 0.83s]
13:37:53  19 of 25 START test not_null_stg_accounts_reopened_recorded_at ................. [RUN]
13:37:54  19 of 25 PASS not_null_stg_accounts_reopened_recorded_at ....................... [PASS in 1.06s]
13:37:54  20 of 25 START test relationships_fct_transactions_account_surrogate_key__surrogate_key__ref_dim_accounts_  [RUN]
13:37:57  20 of 25 PASS relationships_fct_transactions_account_surrogate_key__surrogate_key__ref_dim_accounts_  [PASS in 2.93s]
13:37:57  21 of 25 START test relationships_fct_transactions_user_surrogate_key__surrogate_key__ref_dim_users_  [RUN]
13:38:00  21 of 25 PASS relationships_fct_transactions_user_surrogate_key__surrogate_key__ref_dim_users_  [PASS in 2.90s]
13:38:00  22 of 25 START test unique_dim_accounts_surrogate_key .......................... [RUN]
13:38:01  22 of 25 PASS unique_dim_accounts_surrogate_key ................................ [PASS in 1.28s]
13:38:01  23 of 25 START test unique_dim_users_surrogate_key ............................. [RUN]
13:38:03  23 of 25 PASS unique_dim_users_surrogate_key ................................... [PASS in 1.86s]
13:38:03  24 of 25 START test unique_fct_transactions_unique_key ......................... [RUN]
13:38:06  24 of 25 PASS unique_fct_transactions_unique_key ............................... [PASS in 2.66s]
13:38:06  25 of 25 START test unique_stg_accounts_created_account_id ..................... [RUN]
13:38:07  25 of 25 PASS unique_stg_accounts_created_account_id ........................... [PASS in 1.17s]
13:38:07
13:38:07  Finished running 25 tests in 0 hours 0 minutes and 44.61 seconds (44.61s).
13:38:07
13:38:07  Completed successfully
13:38:07
13:38:07  Done. PASS=25 WARN=0 ERROR=0 SKIP=0 TOTAL=25
```
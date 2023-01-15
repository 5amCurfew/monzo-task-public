## Create `dbt` venv

Ensure that Python is installed on your machine.

Locally I use `pyenv` as a python version manager. This project was built using Python 3.9.6. If you already use `pyenv` this will be set by the `.python_version` file.

Create the virtual environment by running the following in your terminal when in this directory:

1. `python3 -m venv dbt-env`
2. `source dbt-env/bin/activate`
3. `python3 -m pip install -r requirements.txt`

Running `which dbt` once the virtual environment is activated should point to the version then installed:
```bash
which dbt
<YOUR_DIRECTORY_LOCATION>/monzo-task/dbt-env/bin/dbt
```

Ensure `dbt` has been installed and activated correctly by running `dbt --version` in your terminal. If it has been successful, ensure you run `dbt deps` for installing dbt packages.

```bash
Core:
  - installed: 1.3.2
  - latest:    1.3.2 - Up to date!

Plugins:
  - bigquery: 1.3.0 - Up to date!
```
## Database Environment

Following some difficulties regarding credentials and access in the shared `analytics-take-home-test` project on GCP I have exported results of the tables

* `monzo_datawarehouse.account_closed`
* `monzo_datawarehouse.account_created`
* `monzo_datawarehouse.account_reopened`
* `monzo_datawarehouse.account_transactions`

and written the data to tables in a personal Google Cloud project `dbt-monzo-task` using `dbt seed --profiles-dir ./.dbt` where the `dbt` profile is using a `service-account` with credentials stored in `dbt-monzo-task-credentials.json`. Data modelling will be implemented using this project throughout.

Please create `monzo_task/.dbt` mirroring the `monzo_task/.dbt_template` to create your own access credentials and run this project. The `keyfile` can be generated using the Google Cloud Console. Check your connection is valid using `dbt debug` when in the `monzo_task/` directory that contains the dbt project. Your output should reflect similar to below if succcessful.

```bash
dbt debug --profiles-dir ./.dbt
11:48:15  Running with dbt=1.3.2
dbt version: 1.3.2
python version: 3.9.6
python path: /Users/samuel.knight/git/monzo-task/dbt-env/bin/python3
os info: macOS-10.16-x86_64-i386-64bit
Using profiles.yml file at /Users/samuel.knight/git/monzo-task/monzo_task/.dbt/profiles.yml
Using dbt_project.yml file at /Users/samuel.knight/git/monzo-task/monzo_task/dbt_project.yml

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
```

The full `dbt` project can be found in the `monzo_task/` directory. It follows a suggested dbt patterns with the use of a *staging* step. This step is to write raw data and explicitly cast and rename fields for use later ("downstream").

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

Examples:

```bash
dbt seed --profiles-dir ./.dbt
```

```bash
dbt run --models stg_accounts_created --profiles-dir ./.dbt --full-refresh
```

```bash
dbt test --profiles-dir ./.dbt
```

### Assumptions & Discoveries
 *"Each table is fully refreshed on a nightly basis from Monzo's append only logs"* suggests:

* existing data is immutable
* That an *accounts* state is one of either *open* or *closed* and that the state of the account (e.g. its `type`) is not subject to change over its lifetime. This can also be seen using `select account_id_hashed, count(*) from monzo_task.account_created group by 1 order by 2 desc`
* An account requires `user_id_hash` and is always *one-to-one*
* Further metadata will be appended at the `account_created` data source
* An account can be closed an infinite amount of times without being reopened (discovered) but only created once. An account must have been created to be closed/reopened.
* `account_type` is not required (2 instances where `account_type` is `null`) (discovery)
* `user_id_hashed` is required
* Building models incrementally will capture all rows (*append only*) as it is suggested this mirrors event data
* Hard-deletes do not occur (accounts remain in a closed state)
* transactions can only exist for accounts that have been created
* No account closures from 2020-08-12 10:06:51.001000 UTC (discovery)
* `transaction_num` is the transaction number of the account in the given day (`account_transactions.date`) on `account_transactions`

### Overview of Resulting Data Model


## Task 1: Accounts

### Task

The business needs a very reliable and accurate data model that represents all the different accounts at Monzo. Your first task is to create a table using the existing data as outlined above. The most important requirements are that this model is accurate, complete, intuitive to use and well documented.

After implementing the model, please outline five of the most important tests that you would implement to give you the confidence in the output of your process. For this example, you should assume that upstream tables will change and that source data is not validated using contracts.

### Outcome

The resulting model: `monzo_task.dim_users`

`dim_users` is a slowly-changing-type2 (for more information check out [Kimball docs here](https://www.kimballgroup.com/data-warehouse-business-intelligence-resources/kimball-techniques/dimensional-modeling-techniques/type-2/)) dimension of *accounts* at Monzo. Each row represents an account and the corresponding state (either open or closed). Logical steps to build this model are as follows:

1. Create a CTE that contains the metadata of an account (this is found on `stg_accounts_created` and assumed the metadata - namely `user_id` and `account_type` doesn't change)
2. Build a *spine* CTE of each account update (for each `account_id_hashed` find each update - creation, closure and re-opening) using the commonly named `recorded_at` in the *staging* tables
3. Join on metadata on this spine
4. Create fields `valid_from` and `valid_to` that reflect the period of an account in the given state. Note that these ranges should be *mutually exclusive* as this is what will be used later on event data such as `account_transactions`. This is ensure using a dbt test. Please see `_analytics_models.yml` for further information on the tests used.

Historical accuracy is ensured using this model (e.g. used in Task 2) given the state is explicitly followed. This model reflects *all* accounts (none are lost from the raw data).

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



## Task 2: 7-day Active Users

### Task

`7d_active_users` represents the number of users that had *a transaction over the last running 7 days*, divided by all the users with at least one open account at that point. Monzo needs to be able to analyse the activity of our users (remember, one user can be active across multiple accounts). In particular, we are looking at a metric aptly named `7d_active_users` (defined above). The goal for this part is to build a data model that will enable analysts on the team to explore this data very quickly and without friction.

### Outcome
## Create `dbt` venv

Ensure that Python is installed on your machine.

Locally I use `pyenv` as a python version manager. This project was built using Python 3.9.6. If you already use `pyenv` this will be set by the `.python_version` file.

Create the virtual environment by running the following in your terminal:

1. `python3 -m venv dbt-env`
2. `source dbt-env/bin/activate`
3. `python3 -m pip install -r requirements.txt`

Ensure `dbt` has been installed and activated correctly by running `dbt --version` in your terminal. If it has been successful, ensure you run `dbt deps` for installing dbt packages.
```bash
Core:
  - installed: 1.3.2
  - latest:    1.3.2 - Up to date!

Plugins:
  - bigquery: 1.3.0 - Up to date!
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

## Database Environment

Following some difficulties regarding credentials and access in the shared `analytics-take-home-test` project on GCP I have exported results of the tables

* `monzo_datawarehouse.account_closed`
* `monzo_datawarehouse.account_created`
* `monzo_datawarehouse.account_reopened`
* `monzo_datawarehouse.account_transactions`

and written the data to tables in a personal Google Cloud project `dbt-monzo-task` using `dbt seed --profiles-dir ./.dbt` where the `dbt` profile is using a `service-account` with credentials stored in `dbt-monzo-task-credentials.json`. Data modelling will be implemented using this project throughout.

Please create `monzo_task/.dbt` mirroring the `monzo_task/.dbt_template` to create your own access credentials and run this project. The `keyfile` can be generated using the Google Cloud Console.

The full `dbt` project can be found in the `monzo_task` directory.

### Assumptions
 *"Each table is fully refreshed on a nightly basis from Monzo's append only logs"* suggests:

* existing data is immutable
* That an *accounts* state is one of either *open* or *closed* and that the state of the account (e.g. its `type`) is not subject to change over its lifetime. This can also be seen using `select account_id_hashed, count(*) from monzo_task.account_created group by 1 order by 2 desc`
* An account requires `user_id_hash` and is always *one-to-one*
* Further metadata will be appended at the `account_created` data source
* An account can be closed an infinite amount of times without being reopened (discovered) but only created once. An account must have been created to be closed/reopened.
* `account_type` is not required (2 instances where `account_type` is `null`)
* `user_id_hashed` is required
* Building models incrementally will capture all rows (*append only*) as it is suggested this mirrors event data
* Hard-deletes do not occur (accounts remain either open or closed)
* transactions can only exist for accounts that have been created
* No account closures from 2020-08-12 10:06:51.001000 UTC (discovery)
* `transaction_num` is the transaction number of the account in the given day on `account_transactions`

## Task 1: Accounts

### Task

The business needs a very reliable and accurate data model that represents all the different accounts at Monzo. Your first task is to create a table using the existing data as outlined above. The most important requirements are that this model is accurate, complete, intuitive to use and well documented.

After implementing the model, please outline five of the most important tests that you would implement to give you the confidence in the output of your process. For this example, you should assume that upstream tables will change and that source data is not validated using contracts.

### Outcome


## Task 2: 7-day Active Users

### Task

`7d_active_users` represents the number of users that had *a transaction over the last running 7 days*, divided by all the users with at least one open account at that point. Monzo needs to be able to analyse the activity of our users (remember, one user can be active across multiple accounts). In particular, we are looking at a metric aptly named `7d_active_users` (defined above). The goal for this part is to build a data model that will enable analysts on the team to explore this data very quickly and without friction.

### Outcome
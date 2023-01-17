#!/bin/bash -x 
export DBT_PROJECT_PATH=/dbt
export AIRFLOW_PROJECT_PATH=/dags

# configure dbt, install dbt deps, dbt compile
python3 -m venv dbt-env
source dbt-env/bin/activate
python3 -m pip install -r requirements.txt

cd $DBT_PROJECT_PATH 
source ../dbt-env/bin/activate 
dbt deps 
dbt debug --profiles-dir ./.dbt 
dbt compile --profiles-dir ./.dbt 

# configure Airflow, start Airflow
export AIRFLOW_HOME=/root/airflow
airflow db init
airflow users create \
    --username admin \
    --password admin \
    --firstname Samuel \
    --lastname Knight \
    --role Admin \
    --email samueltobyknight@gmail.com

mkdir /root/airflow/dags
cp $AIRFLOW_PROJECT_PATH/* /root/airflow/dags

airflow webserver --port 8080 -D & airflow scheduler

FROM python:3.9.6

# airflow
RUN pip install "apache-airflow==2.5.0" --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-2.5.0/constraints-3.9.txt"

# Copy into Container hh
COPY requirements.txt /
RUN mkdir /dbt
RUN mkdir /dags/
COPY monzo_task/ /dbt/
COPY dags/ /dags/
COPY init.sh /

EXPOSE 8080
RUN chmod +x /init.sh
ENTRYPOINT [ "/init.sh" ]
# docker build -t monzo-task .
# docker run -p 8080:8080 monzo-task --rm
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 \
    DBT_PROFILES_DIR=/app DBT_PROJECT_DIR=/app DBT_SEND_ANONYMOUS_USAGE_STATS=false
WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .
RUN dbt deps

# dbt writes target/ and logs/ at run time.
RUN chown -R nobody /app
USER nobody
ENTRYPOINT ["python", "run_dbt.py"]

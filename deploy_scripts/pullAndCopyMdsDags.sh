#!/bin/bash

set -e

echo "🚀 Starting Airflow MAIN deployment..."

# Verify we're not affecting test environment
echo "📋 Current stacks:"
# Pull latest code
cd /docker/airflow-main
git pull origin main

# Build and push image
cd /docker/airflow-default

# Verify SSH key exists
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "❌ SSH key not found at ~/.ssh/id_rsa"
    exit 1
fi

# Copy DAGs
rsync -avz --delete -e "ssh -i ~/.ssh/id_rsa" /docker/airflow-main/dags/ root@10.0.0.7:/docker/airflow-mds-production/dags/
ssh -i ~/.ssh/id_rsa root@10.0.0.7 "chown -R 50000:0 /docker/airflow-mds-production/dags && chmod -R 755 /docker/airflow-mds-production/dags"


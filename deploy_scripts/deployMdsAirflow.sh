#!/bin/bash

set -e

echo "🚀 Starting Airflow MAIN deployment..."

# Verify we're not affecting test environment
echo "📋 Current stacks:"
docker stack ls | grep airflow || echo "No airflow stacks running"

# Pull latest code
cd /docker/projects/mds/airflow
git pull origin main

# Build and push image
#cd /docker/airflow-default
#docker build -t 10.0.0.2:5000/airflow:main .
#docker push 10.0.0.2:5000/airflow:main

# Verify SSH key exists
if [ ! -f ~/.ssh/id_rsa ]; then
    echo "❌ SSH key not found at ~/.ssh/id_rsa"
    exit 1
fi

# Copy DAGs
rsync -avz --delete -e "ssh -i ~/.ssh/id_rsa" /docker/projects/mds/airflow/dags/ root@10.0.0.5:/docker/airflow-mds/dags/
ssh -i ~/.ssh/id_rsa root@10.0.0.5 "chown -R 50000:0 /docker/airflow-mds/dags && chmod -R 755 /docker/airflow-mds/dags"

# Deploy stack (only affects MAIN environment)
echo "🔄 Deploying MAIN stack (mdsairflow-stack-main)..."
docker stack rm mdsairflow-stack-main || true
sleep 5  # Wait for cleanup
docker stack deploy -c /docker/projects/mds/airflow/docker-compose-main.yaml mdsairflow-stack-main

echo "✅ MAIN Deployment complete!"
echo "🌐 Production Access: https://importermds.insights.zirsee.com"
echo ""
echo "📊 Current stacks:"
docker stack ls | grep mdsairflow
echo ""
echo "📋 MAIN stack services:"
docker service ps mdsairflow-stack-main
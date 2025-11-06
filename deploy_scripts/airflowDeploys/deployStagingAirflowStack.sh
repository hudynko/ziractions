#!/bin/bash

# Simple Staging Airflow Stack Deploy Script
# Removes existing stack and deploys new one

STACK_NAME="reportingostaging-airflow"
COMPOSE_FILE="/docker/projects/reportingo/reportingo_staging_defaults/docker-composeAirflow.yml"

echo "🚀 Deploying staging Airflow stack..."

# Check if stack exists and remove it
if docker stack ls | grep -q "$STACK_NAME"; then
    echo "📦 Removing existing $STACK_NAME stack..."
    docker stack rm "$STACK_NAME"
    
    # Wait for removal to complete
    echo "⏳ Waiting for stack removal..."
    sleep 15  # Airflow takes longer to shut down
fi

# Deploy new stack
echo "🏗️ Deploying new $STACK_NAME stack..."
if docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME"; then
    echo "✅ Stack deployed successfully!"
    
    # Show services
    echo "📋 Current services:"
    docker service ls | grep "$STACK_NAME"
    
    # Wait a bit for services to start
    echo "⏳ Waiting for Airflow to initialize..."
    sleep 30
    
    # Show webserver status
    echo "🌐 Airflow webserver should be available at: https://airflow.staging.zirsee.com"
else
    echo "❌ Stack deployment failed!"
    exit 1
fi

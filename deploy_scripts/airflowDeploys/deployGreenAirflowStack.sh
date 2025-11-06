#!/bin/bash

# Simple Green Airflow Stack Deploy Script
# Removes existing stack and deploys new one

STACK_NAME="reportingogreen-airflow"
COMPOSE_FILE="/docker/projects/reportingo/reportingo_green_defaults/docker-composeAirflow.yml"
NETWORK_NAME="green-overlay-network"

echo "🚀 Deploying green Airflow stack..."

# Create overlay network if it doesn't exist
if ! docker network ls | grep -q "$NETWORK_NAME"; then
    echo "🌐 Creating overlay network: $NETWORK_NAME..."
    docker network create --driver overlay --attachable "$NETWORK_NAME"
    echo "✅ Network created successfully!"
else
    echo "✅ Network already exists: $NETWORK_NAME"
fi

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
    echo "🌐 Airflow webserver should be available at: https://airflow.green.zirsee.com"
else
    echo "❌ Stack deployment failed!"
    exit 1
fi

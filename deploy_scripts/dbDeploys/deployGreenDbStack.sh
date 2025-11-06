#!/bin/bash

# Simple Staging DB Stack Deploy Script
# Removes existing stack and deploys new one

STACK_NAME="reportingogreen-db"
COMPOSE_FILE="/docker/projects/reportingo/reportingo_green_defaults/docker-composeDb.yml"

echo "🚀 Deploying green database stack..."
echo ""
echo "⚠️  WARNING: This will remove the existing '$STACK_NAME' stack if it exists!"
echo "Stack name: $STACK_NAME"
echo "Compose file: $COMPOSE_FILE"
echo ""
read -p "Do you want to continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Deployment cancelled."
    exit 1
fi

echo ""

# Check if stack exists and remove it
if docker stack ls | grep -q "$STACK_NAME"; then
    echo "📦 Removing existing $STACK_NAME stack..."
    docker stack rm "$STACK_NAME"
    
    # Wait for removal to complete
    echo "⏳ Waiting for stack removal..."
    sleep 10
fi

# Deploy new stack
echo "🏗️ Deploying new $STACK_NAME stack..."
if docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME"; then
    echo "✅ Stack deployed successfully!"
    
    # Show services
    echo "📋 Current services:"
    docker service ls | grep "$STACK_NAME"
else
    echo "❌ Stack deployment failed!"
    exit 1
fi
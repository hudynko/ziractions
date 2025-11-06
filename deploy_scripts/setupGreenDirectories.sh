#!/bin/bash

# Green Environment Directory Setup Script
# Creates all required directories on both servers for green environment

echo "🚀 Setting up Green Environment directories..."
echo ""

# Server configuration
DB_SERVER="10.0.0.8"
APP_SERVER="10.0.0.3"
SSH_KEY="~/.ssh/id_rsa"

# Directory arrays for each server
DB_SERVER_DIRS=(
    "/docker/green/redis"
    "/docker/green/maindb/pgdata"
    "/docker/green/maindb/pg_backups"
    "/docker/green/airflow/pg_backups"
    "/docker/green/airflow/postgres-data"
    "/docker/green/airflow/redis-data"
    "/docker/airflow-green/logs"
    "/docker/airflow-green/dags"
    "/docker/airflow-green/plugins"
    "/docker/airflow-green/config"
)

APP_SERVER_DIRS=(
    "/docker/projects/reportingo/workdirs/reportingo-green"
)

echo "📋 Directories to create:"
echo "Database Server ($DB_SERVER):"
for dir in "${DB_SERVER_DIRS[@]}"; do
    echo "  - $dir"
done
echo ""
echo "Application Server ($APP_SERVER):"
for dir in "${APP_SERVER_DIRS[@]}"; do
    echo "  - $dir"
done
echo ""

read -p "Do you want to continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "❌ Setup cancelled."
    exit 1
fi

echo ""

# Function to create directories on remote server
create_remote_directories() {
    local server=$1
    local dirs=("${!2}")
    
    echo "🔧 Creating directories on $server..."
    
    # Create directories
    for dir in "${dirs[@]}"; do
        echo "  Creating: $dir"
        if ssh -i "$SSH_KEY" root@"$server" "mkdir -p '$dir'"; then
            echo "  ✅ Created: $dir"
        else
            echo "  ❌ Failed to create: $dir"
        fi
    done
    
    echo ""
}

# Function to set permissions on remote server
set_remote_permissions() {
    local server=$1
    
    echo "🔐 Setting permissions on $server..."
    
    if [ "$server" == "$DB_SERVER" ]; then
        # Database server permissions
        echo "  Setting database permissions (999:999)..."
        ssh -i "$SSH_KEY" root@"$server" "chown -R 999:999 /docker/green/maindb /docker/green/redis"
        
        echo "  Setting Airflow permissions (50000:0)..."
        ssh -i "$SSH_KEY" root@"$server" "chown -R 50000:0 /docker/green/airflow /docker/airflow-green"
        
        echo "  ✅ Database server permissions set"
    
    elif [ "$server" == "$APP_SERVER" ]; then
        # Application server permissions
        echo "  Setting application permissions..."
        ssh -i "$SSH_KEY" root@"$server" "chown -R root:root /docker/projects/reportingo/workdirs/reportingo-green"
        
        echo "  ✅ Application server permissions set"
    fi
    
    echo ""
}

# Create directories on Database Server
echo "🗂️  Database Server Setup:"
create_remote_directories "$DB_SERVER" DB_SERVER_DIRS[@]
set_remote_permissions "$DB_SERVER"

# Create directories on Application Server  
echo "🗂️  Application Server Setup:"
create_remote_directories "$APP_SERVER" APP_SERVER_DIRS[@]
set_remote_permissions "$APP_SERVER"

# Verify directories were created
echo "🔍 Verifying directory creation..."
echo ""

echo "Database Server ($DB_SERVER):"
for dir in "${DB_SERVER_DIRS[@]}"; do
    if ssh -i "$SSH_KEY" root@"$DB_SERVER" "[ -d '$dir' ]"; then
        echo "  ✅ $dir"
    else
        echo "  ❌ $dir"
    fi
done

echo ""
echo "Application Server ($APP_SERVER):"
for dir in "${APP_SERVER_DIRS[@]}"; do
    if ssh -i "$SSH_KEY" root@"$APP_SERVER" "[ -d '$dir' ]"; then
        echo "  ✅ $dir"
    else
        echo "  ❌ $dir"
    fi
done

echo ""
echo "✅ Green Environment directory setup completed!"
echo ""
echo "📋 Next steps:"
echo "1. Deploy database stack: /docker/projects/deploy_scripts/dbDeploys/deployGreenDbStack.sh"
echo "2. Deploy Airflow stack: /docker/projects/deploy_scripts/airflowDeploys/deployGreenAirflowStack.sh"
echo "3. Deploy application: /docker/projects/deploy_scripts/reportingoDeployGreen.sh main"
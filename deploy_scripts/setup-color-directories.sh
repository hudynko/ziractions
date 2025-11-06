#!/bin/bash
# Setup script to create required directories for color-based deployments

COLOR=${1:-blue}
if [ -z "$COLOR" ]; then
    echo "Usage: $0 <color>"
    echo "Example: $0 blue"
    exit 1
fi

echo "🔧 Setting up directories for $COLOR environment..."

# Create directories on DbServerDevelop
ssh DbServerDevelop "
    sudo mkdir -p /docker/$COLOR/{pgdata-v2,redis,pg_backups}
    sudo mkdir -p /mnt/HC_Volume_103016026/$COLOR/{pgdata-analytics,pg_backups}
    
    # Set correct ownership for PostgreSQL (UID 999)
    sudo chown -R 999:999 /docker/$COLOR/pgdata-v2
    sudo chown -R 999:999 /docker/$COLOR/redis
    sudo chown -R 999:999 /mnt/HC_Volume_103016026/$COLOR/pgdata-analytics
    
    echo '✅ Directories created for $COLOR environment'
    ls -la /docker/$COLOR/
    ls -la /mnt/HC_Volume_103016026/$COLOR/
"

echo "✅ Setup complete for $COLOR environment!"
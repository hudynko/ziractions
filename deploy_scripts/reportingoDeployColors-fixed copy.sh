#!/bin/bash

# Color-based Reportingo Deployment Script
# Usage: ./reportingodeploycolors.sh <color> <branch-or-tag> [mode] [backend_option] [backup_option]
# Colors: blue, red
# Modes: quick, full
# Backend: own, staging
# Backup: skip, create

# Usage check
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <color> <branch-or-tag> [mode] [backend_option] [backup_option]"
  echo ""
  echo "Parameters:"
  echo "  color: blue, red"
  echo "  branch-or-tag: git branch or tag to deploy"
  echo "  mode: quick (default) | full - quick skips build steps"
  echo "  backend_option: own (default) | staging - use own backend or connect to staging"
  echo "  backup_option: skip (default) | create - skip or create fresh backups"
  echo ""
  echo "Examples:"
  echo "  $0 blue main                         # Deploy blue environment with own backend, skip backups"
  echo "  $0 red feature-branch full own       # Deploy red with full build, own backend, skip backups"
  echo "  $0 blue main quick staging          # Deploy blue using staging backend"
  echo "  $0 blue main quick own create       # Deploy blue with fresh database backups"
  exit 1
fi

COLOR="$1"
BRANCH="$2"
MODE="${3:-quick}"
BACKEND_OPTION="${4:-own}"
BACKUP_OPTION="${5:-skip}"

# Validate color
if [[ "$COLOR" != "blue" && "$COLOR" != "red" ]]; then
  echo "❌ Error: Color must be 'blue' or 'red'"
  exit 1
fi

# Set environment variables based on color
case "$COLOR" in
  "blue")
    REDIS_PORT=6382
    POSTGRES_ANALYTICS_PORT=5450
    POSTGRES_V2_PORT=5451
    ;;
  "red")
    REDIS_PORT=6383
    POSTGRES_ANALYTICS_PORT=5446
    POSTGRES_V2_PORT=5447
    ;;
esac

SRC_DIR="/docker/projects/reportingo/reportingo_staging_defaults"
WORKDIR="/docker/projects/reportingo/workdirs/reportingo-${COLOR}"

echo "🎨 Color-based Reportingo Deployment"
echo "======================================"
echo "Color: $COLOR"
echo "Branch: $BRANCH"
echo "Mode: $MODE"
echo "Backend: $BACKEND_OPTION"
echo "Backup: $BACKUP_OPTION"
echo "Ports - Redis: $REDIS_PORT, Postgres: $POSTGRES_PORT"
echo ""

# Set replicas based on options
if [ "$BACKEND_OPTION" = "staging" ]; then
  API_REPLICAS=0
  POSTGRES_REPLICAS=0
  DB_HOST="reportingostaging_postgresreportingostaging"
  FRONTEND_IMAGE_SUFFIX="staging"  # Use staging frontend image
  DOCKER_COMPOSE_FILE="docker-compose-colors.yml"
  echo "🔗 Using staging backend and database (with staging frontend image)"
else
  API_REPLICAS=1
  POSTGRES_REPLICAS=1
  DB_HOST="postgres${COLOR}"     # Analytics database host
  DB_NEW_ANALYTICS_HOST="postgres-analytics${COLOR}"  # New analytics database host
  DB_NEW_ANALYTICS_PORT="5432"            # New analytics database port
  FRONTEND_IMAGE_SUFFIX="${COLOR}"  # Use color-specific frontend image
  DOCKER_COMPOSE_FILE="docker-compose-colors-with-restore.yml"
  echo "🏠 Using own backend and database (with ${COLOR} frontend image)"
  
  # Only create database backups if explicitly requested
  if [ "$BACKUP_OPTION" = "create" ]; then
    echo "📋 Creating fresh database backups from staging..."
    echo "🔄 Running backup script on dbserverdevelop for color: ${COLOR}"
    
    # Run the backup script on the remote server via SSH
    if ssh dbserverdevelop "/docker/scripts/createStagingDump.sh ${COLOR}"; then
      echo "✅ Remote backup creation completed successfully"
      
      # Move backup files to the correct location on dbServerDevelop
      echo "📁 Moving backup files to deployment location on dbServerDevelop..."
      ssh dbserverdevelop "mkdir -p /docker/${COLOR}/pg_backups"
      ssh dbserverdevelop "mkdir -p /mnt/HC_Volume_103016026/${COLOR}/pgdata-analytics"
      ssh dbserverdevelop "cp /docker/scripts/backups/reportingo_analytics_${COLOR}.dump.gz /docker/${COLOR}/pg_backups/"
      ssh dbserverdevelop "cp /docker/scripts/backups/reportingo_v2_${COLOR}.dump.gz /docker/${COLOR}/pg_backups/"
      
      echo "✅ Backup files ready for database restoration on dbServerDevelop"
    else
      echo "❌ Failed to create backups on remote server! Continuing with deployment anyway..."
    fi
  else
    echo "⏭️  Skipping database backup creation (using existing backups)"
    echo "💡 Use 'create' as 5th parameter to create fresh backups: $0 $COLOR $BRANCH $MODE $BACKEND_OPTION create"
    
    # Still ensure directories exist for existing backups
    ssh dbserverdevelop "mkdir -p /docker/${COLOR}/pg_backups"
    ssh dbserverdevelop "mkdir -p /mnt/HC_Volume_103016026/${COLOR}/pgdata-analytics"
  fi
fi

# Check if quick deploy mode
if [ "$MODE" = "quick" ]; then
  echo "🚀 Quick deploy mode - skipping build steps, going straight to deployment"
  
  # Just ensure working directory exists with basic files
  if [ ! -d "$WORKDIR" ]; then
    echo "Working directory doesn't exist, creating minimal setup..."
    mkdir -p "$WORKDIR"
    cp -a "$SRC_DIR"/. "$WORKDIR/"
  fi
  
  cd "$WORKDIR" || exit 1
  cd dabl-reportingo || exit 1
  version=$(git rev-parse --short HEAD)
  
  # Skip to deployment section
  echo "⚡ Jumping to deployment..."
else
  echo "🔧 Full deployment mode - preparing ${COLOR} environment for branch: $BRANCH"
  
  # Clean and copy default files to color-specific working dir
  rm -rf "$WORKDIR"
  sleep 2
  mkdir -p "$WORKDIR"
  echo "📁 Copying files from $SRC_DIR to $WORKDIR"
  shopt -s dotglob nullglob
  cp -a "$SRC_DIR"/. "$WORKDIR/"
  shopt -u dotglob nullglob

  cd "$WORKDIR" || exit 1
  
  # Git clone and checkout
  echo "📥 Git clone and checkout branch: $BRANCH"
  git clone -b "$BRANCH" git@github.com:TaskLogy/dabl-reportingo.git
  cd dabl-reportingo || exit 1
  version=$(git rev-parse --short HEAD)
  cd ..
  echo "📌 Current git version: $version"

  # Configure environment files for color-based deployment
  echo "🔧 Configuring environment files for ${COLOR} environment"
  
  # Update frontend environment (.envfrontend)
  echo "📝 Updating .envfrontend for ${COLOR} environment"
  sed -i "s|VITE_API_URL=.*|VITE_API_URL=https://api.${COLOR}.zirsee.com|g" .envfrontend
  sed -i "s|VITE_REDIRECT_URI=.*|VITE_REDIRECT_URI=https://api.${COLOR}.zirsee.com/cb|g" .envfrontend
  
  # Ensure CHOKIDAR_USEPOLLING is set for development
  if ! grep -q "CHOKIDAR_USEPOLLING" .envfrontend; then
    echo "CHOKIDAR_USEPOLLING=true" >> .envfrontend
  else
    sed -i "s|CHOKIDAR_USEPOLLING=.*|CHOKIDAR_USEPOLLING=true|g" .envfrontend
  fi
  
  echo "✅ Updated .envfrontend:"
  cat .envfrontend
  echo ""
  
  # Update backend environment (.envbackend) 
  echo "📝 Updating .envbackend for ${COLOR} environment"
  
  # Set database hosts based on color
  sed -i "s|DB_HOST=.*|DB_HOST=postgres-v2${COLOR}|g" .envbackend
  grep -q "^DB_NEW_ANALYTICS_HOST=" .envbackend && sed -i "s|DB_NEW_ANALYTICS_HOST=.*|DB_NEW_ANALYTICS_HOST=postgres-analytics${COLOR}|g" .envbackend || echo "DB_NEW_ANALYTICS_HOST=postgres-analytics${COLOR}" >> .envbackend
  grep -q "^DB_NEW_ANALYTICS_PORT=" .envbackend && sed -i "s|DB_NEW_ANALYTICS_PORT=.*|DB_NEW_ANALYTICS_PORT=5432|g" .envbackend || echo "DB_NEW_ANALYTICS_PORT=5432" >> .envbackend
  
  # Set database ports
  if ! grep -q "DB_PORT=" .envbackend; then
    echo "DB_PORT=5432" >> .envbackend
  else
    sed -i "s|DB_PORT=.*|DB_PORT=5432|g" .envbackend
  fi
  
  if ! grep -q "DB_NEW_ANALYTICS_PORT=" .envbackend; then
    echo "DB_NEW_ANALYTICS_PORT=5432" >> .envbackend
  else
    sed -i "s|DB_NEW_ANALYTICS_PORT=.*|DB_NEW_ANALYTICS_PORT=5432|g" .envbackend
  fi
  
  # Set V2 database host
  if ! grep -q "DB_V2_HOST=" .envbackend; then
    echo "DB_V2_HOST=postgres-v2${COLOR}" >> .envbackend
  else
    sed -i "s|DB_V2_HOST=.*|DB_V2_HOST=postgres-v2${COLOR}|g" .envbackend
  fi
  
  # Set Redis host
  if ! grep -q "REDIS_HOST=" .envbackend; then
    echo "REDIS_HOST=redis${COLOR}" >> .envbackend
  else
    sed -i "s|REDIS_HOST=.*|REDIS_HOST=redis${COLOR}|g" .envbackend
  fi
  
  # Set API URL for backend
  if ! grep -q "API_URL=" .envbackend; then
    echo "API_URL=https://api.${COLOR}.zirsee.com" >> .envbackend
  else
    sed -i "s|API_URL=.*|API_URL=https://api.${COLOR}.zirsee.com|g" .envbackend
  fi
  
  echo "✅ Updated .envbackend:"
  cat .envbackend
  echo ""

  # Build and push backend (if using own backend)
  if [ "$API_REPLICAS" = "1" ]; then
    BACKEND_IMAGE="localhost:5000/reportingobackend${COLOR}:$version"
    
    echo "� Checking if backend image exists: $BACKEND_IMAGE"
    if docker manifest inspect "$BACKEND_IMAGE" > /dev/null 2>&1; then
        echo "✅ Backend image already exists, skipping build"
    else
        echo "�🔧 Building and pushing backend image for ${COLOR}: $version"
        if ! docker build -t "$BACKEND_IMAGE" -f DockerfileBackEnd .; then
            echo "❌ Backend build failed! Stopping deployment."
            exit 1
        fi
        docker push "$BACKEND_IMAGE"
    fi
  fi

  # Build and push frontend
  FRONTEND_IMAGE="localhost:5000/reportingofrontend${FRONTEND_IMAGE_SUFFIX}:$version"
  
  echo "🔍 Checking if frontend image exists: $FRONTEND_IMAGE"
  if docker manifest inspect "$FRONTEND_IMAGE" > /dev/null 2>&1; then
      echo "✅ Frontend image already exists, skipping build"
  else
      echo "🎨 Building and pushing frontend image with suffix '${FRONTEND_IMAGE_SUFFIX}': $version"
      if ! docker build -t "$FRONTEND_IMAGE" -f DockerfileFrontEnd .; then
          echo "❌ Frontend build failed! Stopping deployment."
          exit 1
      fi
      docker push "$FRONTEND_IMAGE"
  fi
fi

# Deployment section
echo "🚀 Starting ${COLOR} environment deployment..."

cd "$WORKDIR" || exit 1

# For quick deploy, use branch name as version
if [ "$MODE" = "quick" ]; then
  version="$BRANCH"
  echo "Quick deploy - using version: $version"
else
  echo "Full deploy - using git version: $version"
fi


#ssh dbserverdevelop "mkdir -p /mnt/HC_Volume_103016026/${COLOR}/pgdata-analytics"

# Stack deployment section
STACK_NAME="reportingo${COLOR}"
echo "🗂️ Deploying stack: $STACK_NAME"

# Remove existing stack
docker stack rm "$STACK_NAME"

ssh dbserverdevelop "rm -rf /docker/${COLOR}/pgdata-v2/"
ssh dbserverdevelop "mkdir -p /docker/${COLOR}/pgdata-v2"
ssh dbserverdevelop "chown -R 999:999 /docker/${COLOR}/pgdata-v2"  # PostgreSQL runs as UID 999
ssh dbserverdevelop "rm -rf /mnt/HC_Volume_103016026/${COLOR}/pgdata-analytics/"
ssh dbserverdevelop "mkdir -p /mnt/HC_Volume_103016026/${COLOR}/pgdata-analytics"
ssh dbserverdevelop "chown -R 999:999 /mnt/HC_Volume_103016026/${COLOR}/pgdata-analytics"

echo "⏳ Waiting for stack removal..."
while docker stack ls | grep -q "$STACK_NAME"; do sleep 2; done

# Generate deployment environment
TIMESTAMP=$(date +%s)
export COLOR=$COLOR
export TAG=$BRANCH
export VERSION=$version
export REDIS_PORT=$REDIS_PORT
export POSTGRES_ANALYTICS_PORT=$POSTGRES_ANALYTICS_PORT
export POSTGRES_V2_PORT=$POSTGRES_V2_PORT
export API_REPLICAS=$API_REPLICAS
export POSTGRES_REPLICAS=$POSTGRES_REPLICAS
export DB_HOST=$DB_HOST
export DB_NEW_ANALYTICS_HOST=${DB_NEW_ANALYTICS_HOST:-$DB_HOST}  # Default to main DB_HOST if not set (for staging)
export DB_NEW_ANALYTICS_PORT=${DB_NEW_ANALYTICS_PORT:-5432}      # Default to 5432 if not set
export FRONTEND_IMAGE_SUFFIX=$FRONTEND_IMAGE_SUFFIX

echo "🔧 Deployment configuration:"
echo "  COLOR=$COLOR"
echo "  TAG=$TAG"
echo "  VERSION=$VERSION"
echo "  API_REPLICAS=$API_REPLICAS"
echo "  POSTGRES_REPLICAS=$POSTGRES_REPLICAS"
echo "  DB_HOST=$DB_HOST"
echo "  DB_NEW_ANALYTICS_HOST=$DB_NEW_ANALYTICS_HOST"
echo "  DB_NEW_ANALYTICS_PORT=$DB_NEW_ANALYTICS_PORT"
echo "  FRONTEND_IMAGE_SUFFIX=$FRONTEND_IMAGE_SUFFIX"

# Deploy with color-specific compose file
echo "🚀 Using docker-compose file: $DOCKER_COMPOSE_FILE"
envsubst < "$WORKDIR/$DOCKER_COMPOSE_FILE" | docker stack deploy -c - "$STACK_NAME"

echo ""
echo "✅ ${COLOR} environment deployment completed successfully!"
echo "🌐 Frontend URL: https://${COLOR}.zirsee.com"
if [ "$API_REPLICAS" = "1" ]; then
  echo "🔗 API URL: https://api.${COLOR}.zirsee.com"
else
  echo "🔗 Using staging API: https://api.staging.zirsee.com"
fi
echo ""
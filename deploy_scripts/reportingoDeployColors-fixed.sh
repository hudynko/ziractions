#!/bin/bash

# Color-based Reportingo Deployment Script
# Usage: ./reportingodeploycolors.sh <color> <branch-or-tag> [mode] [backend_option] [backup_option] [frontend_env] [backend_env] [build_type]
# Colors: blue, red, black, white
# Modes: quick, full, update
# Backend: own, staging
# Backup: skip, create
# Build Types: full, backend, frontend

update_env_variables() {
    local env_vars="$1"
    local env_file="$2"
    local env_type="$3"  # "frontend" or "backend" for display
    
    if [ -n "$env_vars" ]; then
        echo "🔧 Updating $env_type environment variables: $env_vars"
        
        # Use semicolon delimiter for variables
        IFS=';' read -ra ENV_VARS <<< "$env_vars"
        for line in "${ENV_VARS[@]}"; do
            # Trim whitespace
            line=$(echo "$line" | xargs)
            if [[ "$line" == *=* ]]; then
                VAR_NAME=$(echo "$line" | cut -d= -f1)
                VAR_VALUE=$(echo "$line" | cut -d= -f2-)
                echo "Updating $VAR_NAME = $VAR_VALUE in $env_file"
                
                # Remove old value if exists
                sed -i "/^${VAR_NAME}=/d" "$WORKDIR/$env_file"
                # Add new value - use the full line to preserve commas
                echo "$line" >> "$WORKDIR/$env_file"
            fi
        done
        
        # Verify the changes
        echo "🔍 Current $env_file content:"
        cat "$WORKDIR/$env_file"
    fi
}

# Usage check
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <color> <branch-or-tag> [mode] [backend_option] [backup_option] [frontend_env] [backend_env] [build_type]"
  echo ""
  echo "Parameters:"
  echo "  color: blue, red, black, white"
  echo "  branch-or-tag: git branch or tag to deploy"
  echo "  mode: quick (default) | full | update - quick skips build, full rebuilds, update just refreshes services"
  echo "  backend_option: own (default) | staging - use own backend or connect to staging"
  echo "  backup_option: skip (default) | create - skip or create fresh backups"
  echo "  frontend_env: semicolon-separated env vars for frontend (e.g., 'VAR1=value1;VAR2=value2')"
  echo "  backend_env: semicolon-separated env vars for backend (e.g., 'DB_HOST=localhost;API_KEY=123')"
  echo "  build_type: full (default) | backend | frontend - what to build/update"
  echo ""
  echo "Examples:"
  echo "  $0 blue main                                    # Deploy blue environment, full build"
  echo "  $0 red feature-branch full own skip            # Deploy red with full build, own backend"
  echo "  $0 blue main update '' '' 'VAR1=test' '' backend    # Update only backend service with env var"
  echo "  $0 white main quick staging                     # Deploy white using staging backend"
  echo "  $0 black main full own create '' 'DB_HOST=newhost' frontend  # Deploy black with backend env var, frontend only"
  exit 1
fi

COLOR="$1"
BRANCH="$2"
MODE="${3:-quick}"
BACKEND_OPTION="${4:-own}"
BACKUP_OPTION="${5:-skip}"
FRONTEND_ENV="$6"
BACKEND_ENV="$7"
BUILD_TYPE="${8:-full}"

# Validate color
if [[ "$COLOR" != "blue" && "$COLOR" != "red" && "$COLOR" != "black" && "$COLOR" != "white" ]]; then
  echo "❌ Error: Color must be 'blue', 'red', 'black', or 'white'"
  exit 1
fi

# Validate build type
if [[ "$BUILD_TYPE" != "full" && "$BUILD_TYPE" != "backend" && "$BUILD_TYPE" != "frontend" ]]; then
  echo "❌ Error: Build type must be 'full', 'backend', or 'frontend'"
  exit 1
fi

# Validate mode
if [[ "$MODE" != "quick" && "$MODE" != "full" && "$MODE" != "update" ]]; then
  echo "❌ Error: Mode must be 'quick', 'full', or 'update'"
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
  "black")
    REDIS_PORT=6384
    POSTGRES_ANALYTICS_PORT=5448
    POSTGRES_V2_PORT=5449
    ;;
  "white")
    REDIS_PORT=6385
    POSTGRES_ANALYTICS_PORT=5452
    POSTGRES_V2_PORT=5453
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
echo "Build Type: $BUILD_TYPE"
echo "Frontend Env: $FRONTEND_ENV"
echo "Backend Env: $BACKEND_ENV"
echo "Ports - Redis: $REDIS_PORT, Postgres Analytics: $POSTGRES_ANALYTICS_PORT, Postgres V2: $POSTGRES_V2_PORT"
echo ""

# Set replicas based on options
if [ "$BACKEND_OPTION" = "staging" ]; then
  API_REPLICAS=0
  POSTGRES_REPLICAS=0
  DB_HOST="reportingostaging_postgresreportingostaging"
  FRONTEND_IMAGE_SUFFIX="staging"  # Use staging frontend image
  DOCKER_COMPOSE_FILE="docker-compose-colors-with-restore.yml"
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

# Check deployment mode and handle accordingly
if [ "$MODE" = "update" ]; then
  echo "⚡ UPDATE MODE - Quick service refresh with --force flag"
  
  # Ensure working directory exists
  if [ ! -d "$WORKDIR" ]; then
    echo "Working directory doesn't exist, creating minimal setup..."
    mkdir -p "$WORKDIR"
    cp -a "$SRC_DIR"/. "$WORKDIR/"
  fi
  
  cd "$WORKDIR" || exit 1  
  cd dabl-reportingo || exit 1
  git pull
  version="$COLOR"  # Use color as version for update mode
  cd "$WORKDIR" || exit 1
  
  # Update environment variables if provided
  if [ -n "$FRONTEND_ENV" ]; then    
    update_env_variables "$FRONTEND_ENV" ".envfrontend" "frontend"    
  fi
  if [ -n "$BACKEND_ENV" ]; then    
    update_env_variables "$BACKEND_ENV" ".envbackend" "backend"    
  fi  
  
  # 🔨 BUILD first, then update services based on BUILD_TYPE (builds happen in WORKDIR where Dockerfiles are)
  STACK_NAME="reportingo${COLOR}"  
  
  if [ "$BUILD_TYPE" = "backend" ] && [ "$API_REPLICAS" = "1" ]; then
    echo "🔨 Building backend image for update..."
    BACKEND_IMAGE="localhost:5000/reportingobackend${COLOR}:$version"
    if ! docker build -t "$BACKEND_IMAGE" -f DockerfileBackEnd .; then
        echo "❌ Backend build failed! Stopping deployment."
        exit 1
    fi
    docker push "$BACKEND_IMAGE"    
    echo "🔄 Updating ONLY backend service..."
    docker service update --force --image "$BACKEND_IMAGE" "${STACK_NAME}_reportingo-${COLOR}-api"
    echo "✅ Backend service updated successfully!"
    exit 0
    
  elif [ "$BUILD_TYPE" = "frontend" ]; then
    echo "🎨 Building frontend image for update..."
    FRONTEND_IMAGE="localhost:5000/reportingofrontend${FRONTEND_IMAGE_SUFFIX}:$version"
    if ! docker build -t "$FRONTEND_IMAGE" -f DockerfileFrontEnd .; then
        echo "❌ Frontend build failed! Stopping deployment."
        exit 1
    fi
    docker push "$FRONTEND_IMAGE"    
    echo "🔄 Updating ONLY frontend service..."
    docker service update --force --image "$FRONTEND_IMAGE" "${STACK_NAME}_reportingo-${COLOR}-frontend"
    echo "✅ Frontend service updated successfully!"
    exit 0
    
  else  # BUILD_TYPE = "full"
    echo "� Building both images for update..."
    
    # Build backend if needed
    if [ "$API_REPLICAS" = "1" ]; then
      BACKEND_IMAGE="localhost:5000/reportingobackend${COLOR}:$version"
      if ! docker build -t "$BACKEND_IMAGE" -f DockerfileBackEnd .; then
          echo "❌ Backend build failed! Stopping deployment."
          exit 1
      fi
      docker push "$BACKEND_IMAGE"
    fi
    
    # Build frontend
    FRONTEND_IMAGE="localhost:5000/reportingofrontend${FRONTEND_IMAGE_SUFFIX}:$version"
    if ! docker build -t "$FRONTEND_IMAGE" -f DockerfileFrontEnd .; then
        echo "❌ Frontend build failed! Stopping deployment."
        exit 1
    fi
    docker push "$FRONTEND_IMAGE"
    
    echo "🔄 Updating BOTH services..."
    if [ "$API_REPLICAS" = "1" ]; then
      docker service update --force --image "$BACKEND_IMAGE" "${STACK_NAME}_reportingo-${COLOR}-api"
    fi
    docker service update --force --image "$FRONTEND_IMAGE" "${STACK_NAME}_reportingo-${COLOR}-frontend"
    echo "✅ Both services updated successfully!"
    exit 0
  fi

elif [ "$MODE" = "quick" ]; then
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
  #version=$(git rev-parse --short HEAD)
  version="$COLOR"  # ✅ Use color as version instead of git hash
  cd ..
  echo "📌 Current git version: $version"

  # Configure environment files for color-based deployment
  echo "🔧 Configuring environment files for ${COLOR} environment"
  
  # Update frontend environment (.envfrontend)
  echo "📝 Updating .envfrontend for ${COLOR} environment"
  
  # Set API URLs based on backend option
  if [ "$BACKEND_OPTION" = "staging" ]; then
    echo "🔗 Configuring frontend to use staging API"
    sed -i "s|VITE_API_URL=.*|VITE_API_URL=https://api.staging.zirsee.com|g" .envfrontend
    sed -i "s|VITE_REDIRECT_URI=.*|VITE_REDIRECT_URI=https://api.staging.zirsee.com/cb|g" .envfrontend
  else
    echo "🏠 Configuring frontend to use color-specific API"
    sed -i "s|VITE_API_URL=.*|VITE_API_URL=https://api.${COLOR}.zirsee.com|g" .envfrontend
    sed -i "s|VITE_REDIRECT_URI=.*|VITE_REDIRECT_URI=https://api.${COLOR}.zirsee.com/cb|g" .envfrontend
  fi
  
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

  # Apply custom environment variable updates if provided
  if [ -n "$FRONTEND_ENV" ]; then
    echo "🔧 Applying custom frontend environment variables..."
    update_env_variables "$FRONTEND_ENV" ".envfrontend" "frontend"
  fi
  
  if [ -n "$BACKEND_ENV" ]; then
    echo "🔧 Applying custom backend environment variables..."
    update_env_variables "$BACKEND_ENV" ".envbackend" "backend"
  fi

  # 🎯 Selective building based on BUILD_TYPE
  echo "🔧 Building components based on BUILD_TYPE: $BUILD_TYPE"
  
  if [ "$BUILD_TYPE" = "backend" ] && [ "$API_REPLICAS" = "1" ]; then
    echo "🔨 Building ONLY backend for ${COLOR}..."
    BACKEND_IMAGE="localhost:5000/reportingobackend${COLOR}:$version"
    
    if ! docker build -t "$BACKEND_IMAGE" -f DockerfileBackEnd .; then
        echo "❌ Backend build failed! Stopping deployment."
        exit 1
    fi
    docker push "$BACKEND_IMAGE"
    echo "✅ Backend build completed!"
    
  elif [ "$BUILD_TYPE" = "frontend" ]; then
    echo "🎨 Building ONLY frontend for ${COLOR}..."
    FRONTEND_IMAGE="localhost:5000/reportingofrontend${FRONTEND_IMAGE_SUFFIX}:$version"
    
    if ! docker build -t "$FRONTEND_IMAGE" -f DockerfileFrontEnd .; then
        echo "❌ Frontend build failed! Stopping deployment."
        exit 1
    fi
    docker push "$FRONTEND_IMAGE"
    echo "✅ Frontend build completed!"
    
  else  # BUILD_TYPE = "full"
    echo "🔨 Building BOTH backend and frontend for ${COLOR}..."
    
    # Build backend (if using own backend)
    if [ "$API_REPLICAS" = "1" ]; then
      BACKEND_IMAGE="localhost:5000/reportingobackend${COLOR}:$version"
      
          echo "🔧 Building and pushing backend image for ${COLOR}: $version"
          if ! docker build -t "$BACKEND_IMAGE" -f DockerfileBackEnd .; then
              echo "❌ Backend build failed! Stopping deployment."
              exit 1
          fi
          docker push "$BACKEND_IMAGE"
      
    fi

    # Build frontend
    FRONTEND_IMAGE="localhost:5000/reportingofrontend${FRONTEND_IMAGE_SUFFIX}:$version"
    
    echo "🔍 Checking if frontend image exists: $FRONTEND_IMAGE"

        echo "🎨 Building and pushing frontend image with suffix '${FRONTEND_IMAGE_SUFFIX}': $version"
        if ! docker build -t "$FRONTEND_IMAGE" -f DockerfileFrontEnd .; then
            echo "❌ Frontend build failed! Stopping deployment."
            exit 1
        fi
        docker push "$FRONTEND_IMAGE"
        echo "✅ Frontend build completed!"
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

# Only setup database directories if using own backend (not staging)
if [ "$BACKEND_OPTION" = "own" ]; then
  echo "🗃️ Setting up database directories for own backend..."
  ssh dbserverdevelop "rm -rf /docker/${COLOR}/pgdata-v2/"
  ssh dbserverdevelop "mkdir -p /docker/${COLOR}/pgdata-v2"
  ssh dbserverdevelop "chown -R 999:999 /docker/${COLOR}/pgdata-v2"  # PostgreSQL runs as UID 999
  ssh dbserverdevelop "rm -rf /mnt/HC_Volume_103016026/${COLOR}/pgdata-analytics/"
  ssh dbserverdevelop "mkdir -p /mnt/HC_Volume_103016026/${COLOR}/pgdata-analytics"
  ssh dbserverdevelop "chown -R 999:999 /mnt/HC_Volume_103016026/${COLOR}/pgdata-analytics"
else
  echo "🔗 Using staging backend - skipping database directory setup"
fi

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
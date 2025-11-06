#!/bin/bash

# Usage check
if [ -z "$1" ]; then
  echo "Usage: $0 <branch-or-tag> [frontend_env] [backend_env] [skip_cleanup] [build_type] [quick_deploy]"
  echo "  build_type: full|backend|frontend (default: full)"
  echo "  quick_deploy: update - skip build/stack removal, just update services"
  echo "Examples:"
  echo "  $0 main                                    # Full build + stack deployment"
  echo "  $0 main '' '' '' backend                   # Build & update only backend"
  echo "  $0 main '' '' '' frontend                  # Build & update only frontend"
  echo "  $0 main '' '' '' full update               # Update both services (no build/stack removal) just refresh"
  exit 1
fi

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

BRANCH="$1"
EXTRA_ENV="$2"       # Frontend environment variables
BACKEND_ENV="$3"     # Backend environment variables
SKIP_CLEANUP="$4"    # Skip PostgreSQL cleanup
BUILD_TYPE="${5:-full}"  # Build type: full|backend|frontend
QUICK_DEPLOY="${6:-full}"  # Quick deploy mode
SRC_DIR="/docker/reportingo/reportingo_staging_defaults"
WORKDIR="/docker/reportingo/reportingo_staging"

echo "branch: $BRANCH"
echo "Build type: $BUILD_TYPE"
echo "Quick deploy: $QUICK_DEPLOY"
echo "Extraenvironment variables frontend: $EXTRA_ENV"
echo "Extraenvironment variables backend: $BACKEND_ENV"

# Validate build type
if [ "$BUILD_TYPE" != "full" ] && [ "$BUILD_TYPE" != "backend" ] && [ "$BUILD_TYPE" != "frontend" ]; then
    echo "❌ Invalid build type: $BUILD_TYPE. Must be one of: full, backend, frontend."
    exit 1
fi

# Check if quick deploy mode
if [ "$QUICK_DEPLOY" = "update" ]; then
  echo "🚀 Quick deploy mode - skipping build steps, going straight to deployment"
  
  # Just ensure working directory exists with basic files
  if [ ! -d "$WORKDIR" ]; then
    echo "Working directory doesn't exist, creating minimal setup..."
    mkdir -p "$WORKDIR"
    cp -a "$SRC_DIR"/. "$WORKDIR/"
  fi
  
  cd "$WORKDIR" || exit 1
  
  # Skip to deployment section
  echo "⚡ Jumping to deployment..."
else
  echo "🔧 Full deployment mode - preparing Reportingo staging deployment for branch: $BRANCH"
  
  # Clean and copy default files to branch-specific working dir
  rm -rf "$WORKDIR"
  sleep 5
  mkdir -p "$WORKDIR"
  echo "Copying files from $SRC_DIR to $WORKDIR"
  shopt -s dotglob nullglob
  cp -a "$SRC_DIR"/. "$WORKDIR/"
  shopt -u dotglob nullglob

  # Copy airflow defaults and update
  echo "📁 Copying airflow defaults to $WORKDIR/airflow-main"
  mkdir -p "$WORKDIR/airflow-main"
  cp -a "/docker/airflow-default"/. "$WORKDIR/airflow-main/"

  cd "$WORKDIR/airflow-main" || exit 1
  echo "🔄 Updating airflow repository"
  git pull
  cd "$WORKDIR" || exit 1
  echo "Git clone and checkout branch: $BRANCH"
  echo "Current working directory: $(pwd)"
  # OPTIONAL: Checkout correct git branch inside copied folder (if .git is copied)
  git clone -b "$BRANCH" git@github.com:TaskLogy/dabl-reportingo.git
  cd dabl-reportingo || exit 1
  version=$(git rev-parse --short HEAD)
  cd ..
  echo "Current git version: $version"

  echo "Extraenvironment variables: $EXTRA_ENV"
  if [ -n "$EXTRA_ENV" ]; then
    update_env_variables "$EXTRA_ENV" ".envfrontend" "frontend"
  fi
  # backendenv
  echo "Extraenvironment variables: $BACKEND_ENV"
  if [ -n "$BACKEND_ENV" ]; then
    update_env_variables "$BACKEND_ENV" ".envbackend" "backend"
  fi

  echo $version
  # Build and push based on build type

if [ "$BUILD_TYPE" = "backend" ]; then
    echo "🔧 Building backend only..."
    docker rmi "localhost:5000/reportingobackendstaging:$version" 2>/dev/null || true
    
    # Remove from registry (optional but ensures fresh push)
    curl -X DELETE "http://localhost:5000/v2/reportingobackendstaging/manifests/latest" 2>/dev/null || true
    if ! docker build --no-cache -t "localhost:5000/reportingobackendstaging:$version" -f DockerfileBackEnd . ; then
        echo "❌ Backend build failed! Stopping deployment."
        exit 1
    fi
    docker push "localhost:5000/reportingobackendstaging:$version" > /dev/null 2>&1
    
    echo "� Backend-only deployment - updating service..."
    docker service update --image --force "localhost:5000/reportingobackendstaging:$version" reportingostaging_reportingo-staging-api
    echo "✅ Backend service updated successfully!"
    exit 0
    
elif [ "$BUILD_TYPE" = "frontend" ]; then
    echo "🔧 Building frontend only..."
    if ! docker build --no-cache -t "localhost:5000/reportingofrontendstaging:$version" -f DockerfileFrontEnd .; then
        echo "❌ Frontend build failed! Stopping deployment."
        exit 1
    fi
    docker push "localhost:5000/reportingofrontendstaging:$version" > /dev/null 2>&1
    
    echo "🚀 Frontend-only deployment - updating service..."
    docker service update --image --force "localhost:5000/reportingofrontendstaging:$version" reportingostaging_reportingo-staging-frontend
    echo "✅ Frontend service updated successfully!"
    exit 0
    
else  # BUILD_TYPE = "full"
    if [ "$QUICK_DEPLOY" = "update" ]; then
        # UPDATE-ONLY MODE: Just update both services
        echo "🚀 Quick update mode - updating both services with latest images..."
        
        docker service update --force --image "localhost:5000/reportingobackendstaging:$version" reportingostaging_reportingo-staging-api
        docker service update --force --image "localhost:5000/reportingofrontendstaging:$version" reportingostaging_reportingo-staging-frontend
        
        echo "✅ Both services updated successfully!"
        exit 0
    else
        # FULL DEPLOYMENT MODE: Build + deploy stack
        echo "� Building both backend and frontend..."
        
        # Build backend
        if ! docker build --no-cache -t "localhost:5000/reportingobackendstaging:$version" -f DockerfileBackEnd .; then
            echo "❌ Backend build failed! Stopping deployment."
            exit 1
        fi
        docker push "localhost:5000/reportingobackendstaging:$version" > /dev/null 2>&1
        
        # Build frontend
        if ! docker build --no-cache -t "localhost:5000/reportingofrontendstaging:$version" -f DockerfileFrontEnd .; then
            echo "❌ Frontend build failed! Stopping deployment."
            exit 1
        fi
        docker push "localhost:5000/reportingofrontendstaging:$version" > /dev/null 2>&1
        
        # Continue to full stack deployment (the code at the bottom runs)
    fi
fi
fi

# Deployment section (runs for both full and quick deploy)
echo "🚀 Starting deployment..."

cd "$WORKDIR" || exit 1

# For quick deploy, we need to get version from existing image or use branch name
if [ "$QUICK_DEPLOY" = "update" ]; then
  # Use latest version from registry for update deploy
  latest_backend=$(curl -s http://localhost:5000/v2/reportingobackendstaging/tags/list | jq -r '.tags[-1]')
  version="$latest_backend"
  echo "Update deploy - using latest version: $version"
fi

# Environment variable updates (for quick deploy mode)
if [ "$QUICK_DEPLOY" = "update" ]; then
  echo "Extraenvironment variables: $EXTRA_ENV"
  if [ -n "$EXTRA_ENV" ]; then
    update_env_variables "$EXTRA_ENV" ".envfrontend" "frontend"
  fi

  # backendenv
  echo "Extraenvironment variables: $BACKEND_ENV"
  if [ -n "$BACKEND_ENV" ]; then
    update_env_variables "$BACKEND_ENV" ".envbackend" "backend"
  fi
fi

# Stack deployment section
STACK_NAME="reportingostaging"
docker stack rm "$STACK_NAME"
while docker stack ls | grep -q "$STACK_NAME"; do sleep 2; done

# Clean PostgreSQL lock files after stack removal
if [ "$SKIP_CLEANUP" != "skip" ]; then
    echo "🧹 Cleaning PostgreSQL lock files..."
    
    # Remove PostgreSQL lock files to prevent startup issues
    sudo rm -f /var/lib/postgresql/*/main/postmaster.pid 2>/dev/null || true
    sudo rm -f /var/lib/postgresql/*/main/*.lock 2>/dev/null || true
    
    # Clean any leftover PostgreSQL processes
    sudo pkill -f "postgres.*airflow" 2>/dev/null || true
    
    # Give it a moment
    sleep 3
    
    echo "✅ PostgreSQL cleanup completed"
else
    echo "⏩ Skipping PostgreSQL cleanup"
fi


TIMESTAMP=$(date +%s)
export TAG=$BRANCH
if [ -z "$version" ]; then
  latest_backend=$(curl -s http://localhost:5000/v2/reportingobackendstaging/tags/list | jq -r '.tags[-1]')
  version="$latest_backend"
fi
export VERSION=$version
export DBTAG="${BRANCH}-${TIMESTAMP}"

echo "🔧 Generated docker-compose content:"
envsubst < "$WORKDIR/docker-compose.yml"

envsubst < "$WORKDIR/docker-compose.yml" | docker stack deploy -c - reportingostaging
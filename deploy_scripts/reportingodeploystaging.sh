#!/bin/bash

# Usage check
if [ -z "$1" ]; then
  echo "Usage: $0 <branch-or-tag> [quick]"
  echo "  quick: skip rm, clone, cp, build - just redeploy existing images"
  exit 1
fi

BRANCH="$1"
QUICK_DEPLOY="$2"
EXTRA_ENV="$3"
BACKEND_ENV="$4"
SKIP_CLEANUP="$5"
SRC_DIR="/docker/reportingo/reportingo_staging_defaults"
WORKDIR="/docker/reportingo/reportingo_staging"

echo "branch: $BRANCH"
echo "Quick deploy: $QUICK_DEPLOY"
echo "Extraenvironment variables frontend: $EXTRA_ENV"
echo "Extraenvironment variables backend: $BACKEND_ENV"

# Check if quick deploy mode
if [ "$QUICK_DEPLOY" = "quick" ]; then
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
    echo "🔧 Updating environment variables: $EXTRA_ENV"
    
    # Use a different delimiter - assume variables are separated by semicolon
    # Call script like: ./script.sh branch "VITE_FEATURE_FLAGS=CHATBOT_REPORT,CHATBOT_MENU;OTHER_VAR=value"
    IFS=';' read -ra ENV_VARS <<< "$EXTRA_ENV"
    for line in "${ENV_VARS[@]}"; do
      # Trim whitespace
      line=$(echo "$line" | xargs)
      if [[ "$line" == *=* ]]; then
        VAR_NAME=$(echo "$line" | cut -d= -f1)
        VAR_VALUE=$(echo "$line" | cut -d= -f2-)
        echo "Updating $VAR_NAME = $VAR_VALUE in .envfrontend"
        
        # Remove old value if exists
        sed -i "/^${VAR_NAME}=/d" "$WORKDIR/.envfrontend"
        # Add new value - use the full line to preserve commas
        echo "$line" >> "$WORKDIR/.envfrontend"
      fi
    done
    
    # Verify the changes
    echo "🔍 Current .envfrontend content:"
    cat "$WORKDIR/.envfrontend"
  fi

  # backendenv
  echo "Extraenvironment variables: $BACKEND_ENV"
  if [ -n "$BACKEND_ENV" ]; then
    echo "🔧 Updating environment variables: $BACKEND_ENV"
    # If BACKEND_ENV is set, update the .envbackend file      
    # Use a different delimiter - assume variables are separated by semicolon
    # Call script like: ./script.sh branch "VITE_FEATURE_FLAGS=CHATBOT_REPORT,CHATBOT_MENU;OTHER_VAR=value"
    IFS=';' read -ra ENV_VARS <<< "$BACKEND_ENV"
    for line in "${ENV_VARS[@]}"; do
      # Trim whitespace
      line=$(echo "$line" | xargs)
      if [[ "$line" == *=* ]]; then
        VAR_NAME=$(echo "$line" | cut -d= -f1)
        VAR_VALUE=$(echo "$line" | cut -d= -f2-)
        echo "Updating $VAR_NAME = $VAR_VALUE in .envbackend"
        
        # Remove old value if exists
        sed -i "/^${VAR_NAME}=/d" "$WORKDIR/.envbackend"
        # Add new value - use the full line to preserve commas
        echo "$line" >> "$WORKDIR/.envbackend"
      fi
    done
    
    # Verify the changes
    echo "🔍 Current .envbackend content:"
    cat "$WORKDIR/.envbackend"
  fi

  # Build and push backend
  echo "🔧 Building and pushing backend image for branch: $BRANCH, version: $version"
  if ! docker build -t "localhost:5000/reportingobackendstaging:$version" -f DockerfileBackEnd .; then
      echo "❌ Backend build failed! Stopping deployment."
      exit 1
  fi
  docker push "localhost:5000/reportingobackendstaging:$version"

  # Build and push frontend
  if ! docker build -t "localhost:5000/reportingofrontendstaging:$version" -f DockerfileFrontEnd .; then
      echo "❌ Frontend build failed! Stopping deployment."
      exit 1
  fi
  docker push "localhost:5000/reportingofrontendstaging:$version"
fi

# Deployment section (runs for both full and quick deploy)
echo "🚀 Starting deployment..."

cd "$WORKDIR" || exit 1

# For quick deploy, we need to get version from existing image or use branch name
if [ "$QUICK_DEPLOY" = "quick" ]; then
  # Use branch name as version for quick deploy
  version="$BRANCH"
  echo "Quick deploy - using version: $version"
fi

# Environment variable updates (for quick deploy mode)
if [ "$QUICK_DEPLOY" = "quick" ]; then
  echo "Extraenvironment variables: $EXTRA_ENV"
  if [ -n "$EXTRA_ENV" ]; then
    echo "🔧 Updating environment variables: $EXTRA_ENV"
    
    # Use a different delimiter - assume variables are separated by semicolon
    # Call script like: ./script.sh branch "VITE_FEATURE_FLAGS=CHATBOT_REPORT,CHATBOT_MENU;OTHER_VAR=value"
    IFS=';' read -ra ENV_VARS <<< "$EXTRA_ENV"
    for line in "${ENV_VARS[@]}"; do
      # Trim whitespace
      line=$(echo "$line" | xargs)
      if [[ "$line" == *=* ]]; then
        VAR_NAME=$(echo "$line" | cut -d= -f1)
        VAR_VALUE=$(echo "$line" | cut -d= -f2-)
        echo "Updating $VAR_NAME = $VAR_VALUE in .envfrontend"
        
        # Remove old value if exists
        sed -i "/^${VAR_NAME}=/d" "$WORKDIR/.envfrontend"
        # Add new value - use the full line to preserve commas
        echo "$line" >> "$WORKDIR/.envfrontend"
      fi
    done
    
    # Verify the changes
    echo "🔍 Current .envfrontend content:"
    cat "$WORKDIR/.envfrontend"
  fi

  # backendenv
  echo "Extraenvironment variables: $BACKEND_ENV"
  if [ -n "$BACKEND_ENV" ]; then
    echo "🔧 Updating environment variables: $BACKEND_ENV"
    # If BACKEND_ENV is set, update the .envbackend file      
    # Use a different delimiter - assume variables are separated by semicolon
    # Call script like: ./script.sh branch "VITE_FEATURE_FLAGS=CHATBOT_REPORT,CHATBOT_MENU;OTHER_VAR=value"
    IFS=';' read -ra ENV_VARS <<< "$BACKEND_ENV"
    for line in "${ENV_VARS[@]}"; do
      # Trim whitespace
      line=$(echo "$line" | xargs)
      if [[ "$line" == *=* ]]; then
        VAR_NAME=$(echo "$line" | cut -d= -f1)
        VAR_VALUE=$(echo "$line" | cut -d= -f2-)
        echo "Updating $VAR_NAME = $VAR_VALUE in .envbackend"
        
        # Remove old value if exists
        sed -i "/^${VAR_NAME}=/d" "$WORKDIR/.envbackend"
        # Add new value - use the full line to preserve commas
        echo "$line" >> "$WORKDIR/.envbackend"
      fi
    done
    
    # Verify the changes
    echo "🔍 Current .envbackend content:"
    cat "$WORKDIR/.envbackend"
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
latest_backend=$(curl -s http://10.0.0.2:5000/v2/reportingobackendstaging/tags/list | jq -r '.tags[-1]')
version="$latest_backend"
export VERSION=$version
export DBTAG="${BRANCH}-${TIMESTAMP}"

echo "🔧 Generated docker-compose content:"
envsubst < "$WORKDIR/docker-compose.yml"

envsubst < "$WORKDIR/docker-compose.yml" | docker stack deploy -c - reportingostaging
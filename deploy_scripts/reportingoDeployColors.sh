#!/bin/bash

# Color-based Reportingo Deployment Script
# Usage: ./reportingodeploycolors.sh <color> <branch-or-tag> [mode] [backend_option]
# Colors: blue, red
# Modes: quick, full
# Backend: own, staging

# Usage check
if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <color> <branch-or-tag> [mode] [backend_option]"
  echo ""
  echo "Parameters:"
  echo "  color: blue, red"
  echo "  branch-or-tag: git branch or tag to deploy"
  echo "  mode: quick (default) | full - quick skips build steps"
  echo "  backend_option: own (default) | staging - use own backend or connect to staging"
  echo ""
  echo "Examples:"
  echo "  $0 blue main                    # Deploy blue environment with own backend"
  echo "  $0 red feature-branch full own  # Deploy red with full build, own backend"
  echo "  $0 blue main quick staging     # Deploy blue using staging backend"
  exit 1
fi

COLOR="$1"
BRANCH="$2"
MODE="${3:-quick}"
BACKEND_OPTION="${4:-own}"

# Validate color
if [[ "$COLOR" != "blue" && "$COLOR" != "red" ]]; then
  echo "❌ Error: Color must be 'blue' or 'red'"
  exit 1
fi

# Set environment variables based on color
case "$COLOR" in
  "blue")
    REDIS_PORT=6382
    POSTGRES_PORT=5445
    ;;
  "red")
    REDIS_PORT=6383
    POSTGRES_PORT=5446
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
echo "Ports - Redis: $REDIS_PORT, Postgres: $POSTGRES_PORT"
echo ""

# Set replicas based on options
if [ "$BACKEND_OPTION" = "staging" ]; then
  API_REPLICAS=0
  POSTGRES_REPLICAS=0
  DB_HOST="reportingostaging_postgresreportingostaging"
  FRONTEND_IMAGE_SUFFIX="staging"  # Use staging frontend image
  echo "🔗 Using staging backend and database (with staging frontend image)"
else
  API_REPLICAS=1
  POSTGRES_REPLICAS=1
  DB_HOST="postgres${COLOR}"
  FRONTEND_IMAGE_SUFFIX="${COLOR}"  # Use color-specific frontend image
  echo "🏠 Using own backend and database (with ${COLOR} frontend image)"
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

  # Build and push backend (if using own backend)
  if [ "$API_REPLICAS" = "1" ]; then
    echo "🔧 Building and pushing backend image for ${COLOR}: $version"
    if ! docker build -t "localhost:5000/reportingobackend${COLOR}:$version" -f DockerfileBackEnd .; then
        echo "❌ Backend build failed! Stopping deployment."
        exit 1
    fi
    docker push "localhost:5000/reportingobackend${COLOR}:$version"
  fi

  # Build and push frontend
  echo "🎨 Building and pushing frontend image with suffix '${FRONTEND_IMAGE_SUFFIX}': $version"
  if ! docker build -t "localhost:5000/reportingofrontend${FRONTEND_IMAGE_SUFFIX}:$version" -f DockerfileFrontEnd .; then
      echo "❌ Frontend build failed! Stopping deployment."
      exit 1
  fi
  docker push "localhost:5000/reportingofrontend${FRONTEND_IMAGE_SUFFIX}:$version"
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

# Stack deployment section
STACK_NAME="reportingo${COLOR}"
echo "🗂️ Deploying stack: $STACK_NAME"

# Remove existing stack
docker stack rm "$STACK_NAME"
echo "⏳ Waiting for stack removal..."
while docker stack ls | grep -q "$STACK_NAME"; do sleep 2; done

# Generate deployment environment
TIMESTAMP=$(date +%s)
export COLOR=$COLOR
export TAG=$BRANCH
export VERSION=$version
export REDIS_PORT=$REDIS_PORT
export POSTGRES_PORT=$POSTGRES_PORT
export API_REPLICAS=$API_REPLICAS
export POSTGRES_REPLICAS=$POSTGRES_REPLICAS
export DB_HOST=$DB_HOST
export FRONTEND_IMAGE_SUFFIX=$FRONTEND_IMAGE_SUFFIX

echo "🔧 Deployment configuration:"
echo "  COLOR=$COLOR"
echo "  TAG=$TAG"
echo "  VERSION=$VERSION"
echo "  API_REPLICAS=$API_REPLICAS"
echo "  POSTGRES_REPLICAS=$POSTGRES_REPLICAS"
echo "  DB_HOST=$DB_HOST"
echo "  FRONTEND_IMAGE_SUFFIX=$FRONTEND_IMAGE_SUFFIX"

# Deploy with color-specific compose file
envsubst < "$WORKDIR/docker-compose-colors.yml" | docker stack deploy -c - "$STACK_NAME"

echo ""
echo "✅ ${COLOR} environment deployment completed successfully!"
echo "🌐 Frontend URL: https://${COLOR}.zirsee.com"
if [ "$API_REPLICAS" = "1" ]; then
  echo "🔗 API URL: https://api.${COLOR}.zirsee.com"
else
  echo "🔗 Using staging API: https://api.staging.zirsee.com"
fi
echo ""
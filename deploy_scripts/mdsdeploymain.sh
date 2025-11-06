#!/bin/bash

# Usage check
if [ -z "$1" ]; then
  echo "Usage: $0 <branch-or-tag>"
  exit 1
fi
BRANCH="$1"
EXTRA_ENV="$2"
BACKEND_ENV="$3"
SRC_DIR="/docker/mds/mds_defaults"
WORKDIR="/docker/mds/mdsmain"

echo "branch: $BRANCH"
echo "Extraenvironment variables: $EXTRA_ENV"
echo "Extraenvironment variables 2: $BACKEND_ENV"

# Clean and copy default files to branch-specific working dir
echo "🔧 Preparing mds deployment for branch: $BRANCH"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
echo "Copying files from $SRC_DIR to $WORKDIR"
shopt -s dotglob nullglob
cp -a "$SRC_DIR"/. "$WORKDIR/"
shopt -u dotglob nullglob

echo "Extraenvironment variables: $EXTRA_ENV"

cd "$WORKDIR" || exit 1
echo "Git clone and checkout branch: $BRANCH"
echo "Current working directory: $(pwd)"
# OPTIONAL: Checkout correct git branch inside copied folder (if .git is copied)
git clone -b "$BRANCH" git@github.com:hudynko/dabl-reportingo.git

cd dabl-reportingo || exit 1
version=$(git rev-parse --short HEAD)
cd ..

# Find available port in range 5400-5499
echo "🔧 Finding available PostgreSQL port..."
used_ports=$(ss -tuln | awk '{print $5}' | grep ':54' | awk -F: '{print $2}')
for p in $(seq 5400 5499); do
  if ! echo "$used_ports" | grep -q "$p"; then
    export POSTGRES_PORT="$p"
    break
  fi
done

if [ -z "$POSTGRES_PORT" ]; then
  echo "❌ No available ports found in range 5400-5499"
  exit 1
fi

echo "✅ Using PostgreSQL port: $POSTGRES_PORT"
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
#exit 1
echo "Extraenvironment variables: $EXTRA_ENV"
echo "Extraenvironment variables 2: $BACKEND_ENV"
# Build and push backend
echo "🔧 Building and pushing backend image for branch: $BRANCH and $version"

if ! docker build -t "localhost:5000/mdsbackend:$version" -f DockerfileBackEnd .; then
    echo "❌ Backend build failed! Stopping deployment."
    exit 1
fi
docker push "localhost:5000/mdsbackend:$version"
if ! docker build -t "localhost:5000/mdsfrontend:$version" -f DockerfileFrontEnd .; then
    echo "❌ Frontend build failed! Stopping deployment."
    exit 1
fi
docker push "localhost:5000/mdsfrontend:$version"

echo "🔧 Updating .envfrontend with branch name"
#sed -i "s/reportingoapitest/reportingoapi${BRANCH}/g" "$WORKDIR/.envfrontend"


STACK_NAME="mmdsProductiondsmain"
#docker stack rm "$STACK_NAME"
TIMESTAMP=$(date +%s)
export TAG=$BRANCH
export DBTAG="${BRANCH}-${TIMESTAMP}"
export VERSION="$version"
export POSTGRES_PORT="$POSTGRES_PORT"

echo "🔧 Generated docker-compose content:"
envsubst < "$WORKDIR/docker-compose.yml"

envsubst < "$WORKDIR/docker-compose.yml" | docker stack deploy -c - mdsProduction --detach=false

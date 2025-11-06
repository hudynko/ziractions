#!/bin/bash

# Usage check
if [ -z "$1" ]; then
  echo "Usage: $0 <branch-or-tag> [quick] [frontend_env] [backend_env] [skip]"
  echo "  quick: skip rm, clone, cp, build - just redeploy existing images"
  echo "  frontend_env: environment variables for frontend (semicolon-separated)"
  echo "  backend_env: environment variables for backend (semicolon-separated)"
  echo "  skip: skip cleanup and PostgreSQL operations"
  exit 1
fi

BRANCH="$1"
QUICK_DEPLOY="$2"
EXTRA_ENV="$3"
BACKEND_ENV="$4"
SKIP_CLEANUP="$5"
SRC_DIR="/docker/projects/zirconads/default_production"
WORKDIR="/docker/projects/zirconads/workdirs/zirconads-production"

echo "branch: $BRANCH"
echo "Quick deploy: $QUICK_DEPLOY"
echo "Extraenvironment variables frontend: $EXTRA_ENV"
echo "Extraenvironment variables backend: $BACKEND_ENV"

# Clean and copy default files to branch-specific working dir
# Check if quick deploy mode
if [ "$QUICK_DEPLOY" = "quick" ]; then
  echo "🚀 Quick deploy mode - skipping build steps, going straight to deployment"
  
  # Just ensure working directory exists with basic files
  if [ ! -d "$WORKDIR" ]; then
    echo "Working directory doesn't exist, creating minimal setup..."
    mkdir -p "$(dirname "$WORKDIR")"
    mkdir -p "$WORKDIR"
    cp -a "$SRC_DIR"/. "$WORKDIR/"
  fi
  
  cd "$WORKDIR" || exit 1
  
  # Skip to deployment section
  echo "⚡ Jumping to deployment..."
elif [ "$SKIP_CLEANUP" = "skip" ]; then
  echo "🔧 Skipping cleanup for branch: $BRANCH"
  cd "$WORKDIR" || exit 1
else
  echo "🔧 Full deployment mode - preparing zirconadds deployment for branch: $BRANCH"
  
  # Ensure parent directory exists
  mkdir -p "$(dirname "$WORKDIR")"
  
  rm -rf "$WORKDIR"
  mkdir -p "$WORKDIR"
  echo "Copying files from $SRC_DIR to $WORKDIR"
  shopt -s dotglob nullglob
  cp -a "$SRC_DIR"/. "$WORKDIR/"
  shopt -u dotglob nullglob

#echo "🔧 Updating .envfrontend with branch name"
#sed -i "s/adsapitest/adsapi${BRANCH}/g" "$WORKDIR/.envfrontend"

  cd "$WORKDIR" || exit 1
  echo "Git clone and checkout branch: $BRANCH"
  echo "Current working directory: $(pwd)"
  # OPTIONAL: Checkout correct git branch inside copied folder (if .git is copied)
  git clone -b "$BRANCH" git@github.com:TaskLogy/dabl-zircon-ads.git
  cd dabl-zircon-ads || exit 1
  version=$(git rev-parse --short HEAD)
  cd ..
  echo "Current git version: $version"

  echo "Extraenvironment variables: $EXTRA_ENV"
  if [ -n "$EXTRA_ENV" ]; then
    echo "🔧 Updating environment variables: $EXTRA_ENV"
    
    # Use a different delimiter - assume variables are separated by semicolon
    # Call script like: ./script.sh branch quick "VITE_FEATURE_FLAGS=CHATBOT_REPORT,CHATBOT_MENU;OTHER_VAR=value"
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
    # Call script like: ./script.sh branch quick "VAR1=value1;VAR2=value2"
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

# Skip build steps for quick deploy
if [ "$QUICK_DEPLOY" != "quick" ]; then
  # Build and push backend
  echo "🔧 Building and pushing backend image for branch: $BRANCH, version: $version"
  if ! docker build -t "localhost:5000/zirconaddsbackend:$version" -f DockerfileBackEnd .; then
      echo "❌ Backend build failed! Stopping deployment."
      exit 1
  fi

  docker push "localhost:5000/zirconaddsbackend:$version"

  # Build and push frontend
  echo "🔧 Building and pushing frontend image for branch: $BRANCH, version: $version"
  if ! DOCKER_BUILDKIT=1 docker build \
      --progress=plain \
      --no-cache \
      -t "localhost:5000/zirconaddsfrontend:$version" \
      -f DockerfileFrontEnd .; then
      echo "❌ Frontend build failed! Stopping deployment."
      exit 1
  fi

  docker push "localhost:5000/zirconaddsfrontend:$version"
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
    # Call script like: ./script.sh branch quick "VITE_FEATURE_FLAGS=CHATBOT_REPORT,CHATBOT_MENU;OTHER_VAR=value"
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
    # Call script like: ./script.sh branch quick "VAR1=value1;VAR2=value2"
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


echo "🔧 Finding available PostgreSQL port..."

# Get ports that are actually listening
used_listening=$(ss -tuln | awk '{print $5}' | grep ':54' | awk -F: '{print $2}' | sort -u)

# Get ports reserved by Docker services
used_docker=$(docker service ls --format "{{.Ports}}" | grep -oE ':54[0-9]{2}->' | sed 's/://g' | sed 's/->//g' | sort -u)

# Combine and get unique used ports
all_used=$(echo -e "$used_listening\n$used_docker" | sort -u | grep -v '^$')

echo "🔍 Used ports in 54xx range:"
echo "$all_used" | sed 's/^/  /'

# Find available port
POSTGRES_PORT=""
for p in $(seq 5400 5499); do
  if ! echo "$all_used" | grep -q "^$p$"; then
    POSTGRES_PORT="$p"
    break
  fi
done

if [ -z "$POSTGRES_PORT" ]; then
  echo "❌ No available ports found in range 5400-5499"
  echo "📋 All ports 5400-5499 are in use!"
  exit 1
fi

export POSTGRES_PORT
echo "✅ Using PostgreSQL port: $POSTGRES_PORT"

# Stack deployment section
STACK_NAME="zircon_ads_production"
docker stack rm "$STACK_NAME"
while docker stack ls | grep -q "$STACK_NAME"; do sleep 2; done

TIMESTAMP=$(date +%s)
export TAG="$BRANCH"
# For full deploy, use the git version; for quick deploy, use branch name
if [ "$QUICK_DEPLOY" = "quick" ]; then
    export VERSION="$BRANCH"
else
    export VERSION="$version"
fi
export DBTAG="${BRANCH}-${TIMESTAMP}"

echo "🔧 Generated docker-compose content:"
envsubst < "$WORKDIR/docker-compose.yml"

envsubst < "$WORKDIR/docker-compose.yml" | docker stack deploy -c - "$STACK_NAME"

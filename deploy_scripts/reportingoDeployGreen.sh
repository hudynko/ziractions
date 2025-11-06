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
EXTRA_ENV="$2"       # ✅ Shift parameters up
BACKEND_ENV="$3"
SKIP_CLEANUP="$4"
BUILD_TYPE="${5:-full}"  # ✅ Shift up
QUICK_DEPLOY="${6:-full}"

SRC_DIR="/docker/projects/reportingo/reportingo_green_defaults"
WORKDIR="/docker/projects/reportingo/workdirs/reportingo-green"

echo "branch: $BRANCH"
echo "Extraenvironment variables frontend: $EXTRA_ENV"
echo "Extraenvironment variables backend: $BACKEND_ENV"
echo "Build type: $BUILD_TYPE"

if [ "$BUILD_TYPE" = "full" ] && [ "$QUICK_DEPLOY" != "update" ]; then
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
else
  cd "$WORKDIR" || exit 1
  shopt -s dotglob nullglob
  cp -a "$SRC_DIR"/. "$WORKDIR/"
  shopt -u dotglob nullglob
  git pull || true
fi

#cd "$WORKDIR/dabl-reportingo" || exit 1

version="green"

# Check if quick deploy mode

echo "🔧 Full deployment mode - preparing Reportingo green deployment for branch: $BRANCH"

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
  # Build and push backend

if [ "$BUILD_TYPE" != "full" ] && [ "$BUILD_TYPE" != "backend" ] && [ "$BUILD_TYPE" != "frontend" ]; then
    echo "❌ Invalid build type: $BUILD_TYPE. Must be one of: full, backend, frontend."
    exit 1
fi


if [ "$BUILD_TYPE" = "backend" ]; then
    echo "🔧 Building backend only..."
    docker rmi "10.0.0.2:5000/reportingobackendgreen:$version" 2>/dev/null || true
    
    # Registry cleanup removed - not necessary for deployment
    if ! docker build --no-cache -t "10.0.0.2:5000/reportingobackendgreen:$version" -f DockerfileBackEnd . ; then
        echo "❌ Backend build failed! Stopping deployment."
        exit 1
    fi
    docker push "10.0.0.2:5000/reportingobackendgreen:$version" > /dev/null 2>&1
    
    echo "🚀 Backend-only deployment - updating service..."
    docker service update --image "10.0.0.2:5000/reportingobackendgreen:$version"  --force reportingogreen_reportingoapigreen
    echo "✅ Backend service updated successfully!"
    exit 0
    
elif [ "$BUILD_TYPE" = "frontend" ]; then
    docker rmi "10.0.0.2:5000/reportingofrontendgreen:$version" 2>/dev/null || true
    
    # Registry cleanup removed - not necessary for deployment
    echo "🔧 Building frontend only..."
    if ! docker build --no-cache -t "10.0.0.2:5000/reportingofrontendgreen:$version" -f DockerfileFrontEnd .; then
        echo "❌ Frontend build failed! Stopping deployment."
        exit 1
    fi
    docker push "10.0.0.2:5000/reportingofrontendgreen:$version" > /dev/null 2>&1
    
    echo "🚀 Frontend-only deployment - updating service..."
    docker service update --image "10.0.0.2:5000/reportingofrontendgreen:$version" --force reportingogreen_reportingofrontendgreen
    echo "✅ Frontend service updated successfully!"
    exit 0
    
else  # BUILD_TYPE = "full"
    if [ "$QUICK_DEPLOY" != "full" ]; then
        # ✅ UPDATE-ONLY MODE: Just update both services
        echo "🚀 Quick update mode - updating both services with latest images..."

        docker service update --image "10.0.0.2:5000/reportingobackendgreen:$version" --force reportingogreen_reportingoapigreen
        docker service update --image "10.0.0.2:5000/reportingofrontendgreen:$version" --force reportingogreen_reportingofrontendgreen

        echo "✅ Both services updated successfully!"
        exit 0
    else
        # ✅ FULL DEPLOYMENT MODE: Build + deploy stack
        echo "🔧 Building both backend and frontend..."
        
        # Build backend
        if ! docker build --no-cache -t "10.0.0.2:5000/reportingobackendgreen:$version" -f DockerfileBackEnd .; then
            echo "❌ Backend build failed! Stopping deployment."
            exit 1
        fi
        docker push "10.0.0.2:5000/reportingobackendgreen:$version" > /dev/null 2>&1
        
        # Build frontend
        if ! docker build --no-cache -t "10.0.0.2:5000/reportingofrontendgreen:$version" -f DockerfileFrontEnd .; then
            echo "❌ Frontend build failed! Stopping deployment."
            exit 1
        fi
        docker push "10.0.0.2:5000/reportingofrontendgreen:$version" > /dev/null 2>&1
        
        # Continue to full stack deployment (the code at the bottom runs)
    fi
fi



# Deployment section (runs for both full and quick deploy)
echo "🚀 Starting deployment..."

cd "$WORKDIR" || exit 1

# Environment variable updates (for quick deploy mode)

# Stack deployment section
STACK_NAME="reportingogreen"
docker stack rm "$STACK_NAME"
#while docker stack ls | grep -q "$STACK_NAME"; do sleep 2; done

# Clean PostgreSQL lock files after stack removal
# if [ "$SKIP_CLEANUP" = "notskip" ]; then
#     echo "🧹 Cleaning PostgreSQL lock files..."
#     sudo rm -f /var/lib/postgresql/*/main/postmaster.pid 2>/dev/null || true
#     sudo rm -f /var/lib/postgresql/*/main/*.lock 2>/dev/null || true
    
#     # Clean any leftover PostgreSQL processes
#     sudo pkill -f "postgres.*airflow" 2>/dev/null || true
    
#     # Give it a moment
#     sleep 3
    
#     echo "✅ PostgreSQL cleanup completed"
# else
#     echo "⏩ Skipping PostgreSQL cleanup"
# fi

TIMESTAMP=$(date +%s)
export TAG=$BRANCH
#latest_backend=$(curl -s http://10.0.0.2:5000/v2/reportingobackendgreen/tags/list | jq -r '.tags[-1]')
#version="$latest_backend"
export VERSION=$version
export DBTAG="${BRANCH}-${TIMESTAMP}"

echo "🔧 Generated docker-compose content:"
envsubst < "$WORKDIR/docker-compose.yml"

envsubst < "$WORKDIR/docker-compose.yml" | docker stack deploy -c - reportingogreen
echo "✅ Deployment completed successfully!"


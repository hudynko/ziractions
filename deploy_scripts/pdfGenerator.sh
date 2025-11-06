#!/bin/bash
BRANCH="main"

SRC_DIR="/docker/projects/pdfGenerator/pdfgenerator_defaults"
WORKDIR="/docker/projects/pdfGenerator/pdfgenerator"

echo "branch: $BRANCH"

# Clean and copy default files to branch-specific working dir
echo "🔧 Preparing Reportingo deployment for branch: $BRANCH"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
echo "Copying files from $SRC_DIR to $WORKDIR"
shopt -s dotglob nullglob
cp -a "$SRC_DIR"/. "$WORKDIR/"
shopt -u dotglob nullglob


cd "$WORKDIR" || exit 1
echo "Git clone and checkout branch: $BRANCH"
echo "Current working directory: $(pwd)"
# OPTIONAL: Checkout correct git branch inside copied folder (if .git is copied)
git clone -b "$BRANCH" git@github.com:TaskLogy/pdf-generator.git

# Find available port in range 5400-5499

# Build and push backend
echo "🔧 Building and pushing backend image for branch: $BRANCH"
docker build -t localhost:5000/pdf-generator:main -f DockerfilePdfGenerator . --no-cache
docker push localhost:5000/pdf-generator:main

STACK_NAME="pdfgenerator"
docker stack rm "$STACK_NAME"
echo "🔧 Generated docker-compose content:"
envsubst < "$WORKDIR/docker-compose.yml"

envsubst < "$WORKDIR/docker-compose.yml" | docker stack deploy -c - pdfgenerator --detach=false

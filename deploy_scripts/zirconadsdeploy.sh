#!/bin/bash

# Usage check
if [ -z "$1" ]; then
  echo "Usage: $0 <branch-or-tag>"
  exit 1
fi

BRANCH="$1"
EXTRA_ENV="$2"
SRC_DIR="/docker/ads/adstest_defaults"
WORKDIR="/docker/ads/adds-$BRANCH"

echo "Extraenvironment variables: $EXTRA_ENV"

# Clean and copy default files to branch-specific working dir
echo "🔧 Preparing zirconadds deployment for branch: $BRANCH	"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
echo "Copying files from $SRC_DIR to $WORKDIR"
shopt -s dotglob nullglob
cp -a "$SRC_DIR"/. "$WORKDIR/"
shopt -u dotglob nullglob

echo "🔧 Updating .envfrontend with branch name"
sed -i "s/adsapitest/adsapi${BRANCH}/g" "$WORKDIR/.envfrontend"

cd "$WORKDIR" || exit 1
echo "Git clone and checkout branch: $BRANCH"
echo "Current working directory: $(pwd)"
# OPTIONAL: Checkout correct git branch inside copied folder (if .git is copied)
git clone -b "$BRANCH" git@github.com:TaskLogy/dabl-zircon-ads.git

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


# Build and push backend
echo "🔧 Building and pushing backend image for branch: $BRANCH"
docker build -t "localhost:5000/zirconaddsbackend:$BRANCH" -f DockerfileBackEnd .
docker push "localhost:5000/zirconaddsbackend:$BRANCH"

# Build and push frontend
docker build -t "localhost:5000/zirconaddsfrontend:$BRANCH" -f DockerfileFrontEnd .
docker push "localhost:5000/zirconaddsfrontend:$BRANCH"



STACK_NAME="zirconadds-production"
docker stack rm "$STACK_NAME"
export TAG="$BRANCH"
echo "🔧 Generated docker-compose content:"

envsubst < "$WORKDIR/docker-compose.yml"

envsubst < "$WORKDIR/docker-compose.yml" | docker stack deploy -c - ads-$BRANCH --detach=false

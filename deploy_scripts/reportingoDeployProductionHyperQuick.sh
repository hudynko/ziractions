
WORKDIR="/docker/projects/reportingo/workdirs/reportingo-production"
cd "$WORKDIR" || exit 1

TIMESTAMP=$(date +%s)
export TAG="main"
#latest_backend=$(curl -s http://10.0.0.2:5000/v2/reportingobackendproduction/tags/list | jq -r '.tags[-1]')
#version="$latest_backend"
export VERSION="latest"
BRANCH="main"
export DBTAG="${BRANCH}-${TIMESTAMP}"

echo "🗑️ Removing existing stack to apply label changes..."
docker stack rm reportingoproduction
while docker stack ls | grep -q reportingoproduction; do sleep 10; done

echo "🔧 Generated docker-compose content:"
envsubst < "$WORKDIR/docker-compose.yml"

envsubst < "$WORKDIR/docker-compose.yml" | docker stack deploy -c - reportingoproduction
echo "✅ Deployment completed successfully!"
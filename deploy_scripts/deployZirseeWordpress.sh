#!/bin/bash

set -e
echo "🚀 Starting Zirsee WordPress deployment..."
docker stack deploy -c /docker/projects/wordpress/docker-compose.yml zirseeWordpress
echo "✅ Deployment complete!"
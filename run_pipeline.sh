#!/bin/bash
set -e

echo "Lancement de la chaîne de traitement..."

docker-compose build
docker-compose run --rm gene-graph-type-commits

echo "Pipeline terminé."

#!/bin/bash
set -e

echo "=== Pipeline d'analyse automatique ==="
docker-compose build
echo ""

if [ ! -f "3-activite-contributeurs/data/raw_commits_data.json" ]; then
    echo "[INFO] raw_commits_data.json introuvable"
    echo "=== Collecte des commits (peut prendre du temps) ==="
    docker-compose run --rm analysis python 3-activite-contributeurs/collect_commits.py
    echo ""
fi

echo "=== Etape 1/4: Recuperation du nombre de contributeurs ==="
docker-compose run --rm analysis python 2-nombre-contributeurs/get_contributors.py
echo ""

echo "=== Etape 2/4: Analyse des types de commits ==="
docker-compose run --rm analysis python 3-activite-contributeurs/get_commits_types.py
echo ""

echo "=== Etape 3/4: Generation des premiers graphiques ==="
docker-compose run --rm analysis python 3-activite-contributeurs/generate_graphs.py
echo ""

echo "=== Etape 4/4: Generation des derniers graphiques ==="
docker-compose run --rm analysis python 4-generation-graphiques/generate_graphs.py
docker-compose run --rm analysis python 4-generation-graphiques/generate-violin-graph.py
echo ""

echo "=== Pipeline termine avec succes! ==="
echo ""
echo "Resultats:"
echo "  - 2-nombre-contributeurs/data/contributors.csv"
echo "  - 3-activite-contributeurs/data/commits_types.csv"
echo "  - 3-activite-contributeurs/outputs/graphs/*.png"
echo "  - 4-generation-graphiques/outputs/graphs/*.png"
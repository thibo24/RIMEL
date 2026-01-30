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

# echo "=== Etape 1/5: Recuperation du nombre de contributeurs ==="
# docker-compose run --rm analysis python 2-nombre-contributeurs/get_contributors.py
# echo ""

echo "=== Etape 2/5: Classification par patterns ==="
docker-compose run --rm analysis python 3-activite-contributeurs/get_commits_types.py
echo ""

if [ -f "3-activite-contributeurs/data/commits_other_for_ml.csv" ]; then
    echo "=== Etape 3/5: Classification ML des commits non reconnus ==="
    docker-compose run --rm analysis python 3-activite-contributeurs/train_and_apply_commit_classifier.py
    echo ""
else
    echo "[INFO] Aucun dataset annoté ML trouvé, étape ML ignorée"
fi

echo "=== Etape 4/5: Generation des premiers graphiques ==="
docker-compose run --rm analysis python 3-activite-contributeurs/generate_graphs.py
echo ""

# echo "=== Etape 5/5: Generation des derniers graphiques ==="
# docker-compose run --rm analysis python 4-generation-graphiques/generate_graphs.py
# docker-compose run --rm analysis python 4-generation-graphiques/generate-violin-graph.py
# echo ""

echo "=== Pipeline termine avec succes! ==="

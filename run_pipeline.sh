#!/bin/bash
set -e

echo "=== Pipeline d'analyse automatique ==="
echo ""
echo "📦 Construction de l'image Docker..."
docker-compose build --quiet
echo "   ✅ Image prête"
echo ""

echo "=== Etape 0/3: Analyse SonarQube + Commits + Contributeurs ==="
bash 1-qualite/scan_repos.sh
echo ""

echo "=== Etape 1/3: Analyse des types de commits ==="
docker-compose run --rm analysis python 3-activite-contributeurs/get_commits_types.py
echo ""

echo "=== Etape 2/3: Generation des graphiques ==="
echo "  -> Graphiques qualite (question 1)..."
docker-compose run --rm analysis python 1-qualite/generate-graphs.py
docker-compose run --rm analysis python 1-qualite/generate-violin-graph.py
echo "  -> Graphiques qualite par groupe (question 2)..."
docker-compose run --rm analysis python 2-nombre-contributeurs/generate_quality_graphs.py
echo "  -> Graphiques activite (question 3)..."
docker-compose run --rm analysis python 3-activite-contributeurs/generate_graphs.py
echo ""

echo "=== Pipeline termine avec succes! ==="
echo ""
echo "Resultats:"
echo "  - 1-qualite/outputs/summary.csv"
echo "  - 1-qualite/outputs/reports/*.csv"
echo "  - 1-qualite/outputs/*.png (question 1)"
echo "  - 2-nombre-contributeurs/data/contributors.csv"
echo "  - 2-nombre-contributeurs/graphs/*.png (question 2)"
echo "  - 3-activite-contributeurs/data/commits_types.csv"
echo "  - 3-activite-contributeurs/outputs/graphs/*.png (question 3)"
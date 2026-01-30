#!/bin/bash
set -e
INLY_Q1=false
ONLY_Q3=false
REPOS_FILE="repos.csv"



while getopts "13f:" opt; do
  case "$opt" in
    1) Q1=true ;;
    3) Q3=true ;;
    f) REPOS_FILE="$OPTARG" ;;
    \?) echo "Usage: $0 [-1] [-3] [-f repos.csv]" >&2; exit 1 ;;
  esac
done
shift $((OPTIND-1))

RUN_ALL=false
if [ "$Q1" = false ] && [ "$Q3" = false ]; then
  RUN_ALL=true
fi

echo "=== Pipeline d'analyse automatique ==="
echo ""
REPLAY=0
if [ "$1" = "--replay" ] || [ "$1" = "-r" ]; then
	REPLAY=1
	echo "🔁 run_pipeline: mode replay activé — utilisation des SHA dans repos_url.csv"
fi

echo "📦 Construction de l'image Docker..."
# Supprimer les warnings bruyants de docker-compose
docker-compose build --quiet >/dev/null 2>&1 || true
echo "   ✅ Image prête"
echo ""

echo "=== Etape 0/3: Analyse SonarQube + Commits + Contributeurs ==="
if [ "$REPLAY" -eq 1 ]; then
	bash 1-qualite/scan_repos.sh --replay
else
	bash 1-qualite/scan_repos.sh
fi
echo ""

echo "=== Etape 1/3: Analyse des types de commits ==="
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
echo "  -> Graphiques qualite (question 1)..."
docker-compose run --rm analysis python 1-qualite/generate-graphs.py
docker-compose run --rm analysis python 1-qualite/generate-violin-graph.py
echo "  -> Graphiques qualite par groupe (question 2)..."
docker-compose run --rm analysis python 2-nombre-contributeurs/compute_repo_groups.py
docker-compose run --rm analysis python 2-nombre-contributeurs/generate_quality_graphs.py
echo "  -> Graphiques activite (question 3)..."echo ""



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
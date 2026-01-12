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
docker-compose build
echo ""
echo "== Run analyses =="
if [ "$Q1" = true ] || [ "$RUN_ALL" = true ]; then
  if [ ! -f "$REPOS_FILE" ]; then
    echo "ERREUR: fichier repos introuvable: $REPOS_FILE" >&2
    exit 1
  fi
  ./1-qualite/sonar/scan.sh -f "$REPOS_FILE"
else
  echo "[SKIP] analyses Sonar (flag -1 pour les run)"
fi

if [ "$Q3" = true ] || [ "$RUN_ALL" = true ]; then
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

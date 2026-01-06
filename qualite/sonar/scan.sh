#!/bin/bash

# ==========================================
# CONFIGURATION
# Collez votre token généré ici (entre les guillemets)
SONAR_TOKEN="sqa_db9586e56cd8c54ffd69f67c2d813564e8d3a47c"

OUT_ROOT="$(pwd)/output"
OUT_DIR="$OUT_ROOT"
SRC_BASE="$OUT_DIR/src"
SRC_DIR="$SRC_BASE/$REPO_NAME"
REPORT_DIR="$OUT_DIR/reports"
mkdir -p "$SRC_DIR" "$REPORT_DIR"

# ==========================================

# --- 1. Gestion des arguments ---
CONVERT_NOTEBOOKS=false

while getopts "n" opt; do
  case $opt in
    n) CONVERT_NOTEBOOKS=true ;;
    \?) echo "Option invalide: -$OPTARG" >&2; exit 1 ;;
  esac
done
shift $((OPTIND-1))

REPO_URL=$1

if [ -z "$REPO_URL" ]; then
  echo "Usage: ./scan.sh [-n] <URL_DU_REPO_GITHUB>"
  echo "Exemple: ./scan.sh -n https://github.com/..."
  exit 1
fi


REPO_NAME=$(basename $REPO_URL .git)
PROJECT_KEY="${REPO_NAME}_$(date +%s)"
SRC_DIR="$(pwd)/src/$REPO_NAME"

# --- 2. Vérification SonarQube ---
echo "🐳 Vérification de SonarQube..."
if [ ! "$(docker ps -q -f name=sonarqube-server)" ]; then
    echo "   -> Démarrage..."
    docker-compose up -d
    until curl -s http://localhost:9000 > /dev/null; do sleep 5; echo -n "."; done
    echo ""
fi

if [[ -z "$SONAR_TOKEN" || "$SONAR_TOKEN" == "votre_token_colle_ici_sqa_xxxxxx" ]]; then
    echo "❌ ERREUR : Vous devez configurer le SONAR_TOKEN dans le script."
    exit 1
fi

# Détection du réseau
SONAR_NETWORK=$(docker inspect sonarqube-server -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}')

# --- 3. Clonage ---
echo "⬇️  Clonage du dépôt..."
rm -rf "$SRC_DIR"
git clone --quiet "$REPO_URL" "$SRC_DIR"

# --- 4. Conversion Notebooks ---
if [ "$CONVERT_NOTEBOOKS" = true ]; then
    echo "📒 Conversion récursive des .ipynb en .py..."
    docker run --rm \
        -v "$SRC_DIR:/code" \
        python:3.9-slim \
        /bin/bash -c "pip install nbconvert --quiet && \
                      find /code -name '*.ipynb' -exec jupyter nbconvert --to python {} \;" > /dev/null 2>&1
    echo "✅ Conversion terminée."
fi

# --- 5. Lancement Analyse ---
echo "🔍 Lancement du Scanner..."

docker run --rm \
    --network "$SONAR_NETWORK" \
    -v "$SRC_DIR:/usr/src" \
    sonarsource/sonar-scanner-cli \
    -Dsonar.projectKey="$PROJECT_KEY" \
    -Dsonar.host.url=http://sonarqube-server:9000 \
    -Dsonar.token="$SONAR_TOKEN" \
    -Dsonar.scm.provider=git \
    -Dsonar.sources=. \
    -Dsonar.exclusions="**/*.ipynb"


# --- 6. Export CSV (NOUVEAU) ---
echo "📊 Génération du rapport CSV..."

CSV_FILENAME="${REPO_NAME}_report.csv"
CSV_PATH="$REPORT_DIR/$CSV_FILENAME"

# On lance le script python DANS le réseau Docker pour qu'il voit le serveur Sonar
docker run --rm \
    --network "$SONAR_NETWORK" \
    -v "$(pwd):/app" \
    python:3.9-slim \
    python /app/export_to_csv.py "$PROJECT_KEY" "$SONAR_TOKEN" "/app/$CSV_FILENAME"
# Vérification si le fichier est vide (taille < 100 octets = juste les entêtes)
FILE_SIZE=$(wc -c < "$CSV_FILENAME")
if [ "$FILE_SIZE" -lt 100 ]; then
    echo "⚠️  ATTENTION : Le fichier CSV semble vide."
    echo "   -> Vérifiez sur http://localhost:9000 si l'analyse est bien terminée."
    echo "   -> Si l'analyse est encore en cours ('in progress'), relancez juste l'export plus tard."
else
    echo "✅ Fichier CSV généré avec succès !"
fiecho ""
echo "--------------------------------------------------------"
echo "✅ Analyse terminée !"
echo "📊 Dashboard : http://localhost:9000/dashboard?id=$PROJECT_KEY"
echo "💾 Fichier CSV : $(pwd)/$CSV_FILENAME"
echo "--------------------------------------------------------"
#!/bin/bash
set -euo pipefail

# ==========================================
# CONFIGURATION
SONAR_TOKEN="sqa_db9586e56cd8c54ffd69f67c2d813564e8d3a47c"

OUT_ROOT="$(pwd)/output"
REPORT_DIR="$OUT_ROOT/reports"
SRC_BASE="$OUT_ROOT/src"
mkdir -p "$SRC_BASE" "$REPORT_DIR"
# ==========================================

REPOS_FILE=""

while getopts "f:" opt; do
  case $opt in
    f) REPOS_FILE="$OPTARG" ;;
    \?) echo "Option invalide: -$OPTARG" >&2; exit 1 ;;
  esac
done
shift $((OPTIND-1))

REPO_URL="${1:-}"

if [[ -z "$REPOS_FILE" && -z "$REPO_URL" ]]; then
  echo "Usage:"
  echo "  ./scan.sh  <URL_DU_REPO>"
  echo "  ./scan.sh -f <repos.csv>"
  exit 1
fi

if [[ -n "$REPOS_FILE" && ! -f "$REPOS_FILE" ]]; then
  echo "❌ ERREUR: fichier introuvable: $REPOS_FILE"
  exit 1
fi

if [[ -z "$SONAR_TOKEN" || "$SONAR_TOKEN" == "votre_token_colle_ici_sqa_xxxxxx" ]]; then
  echo "❌ ERREUR : Vous devez configurer le SONAR_TOKEN dans le script."
  exit 1
fi

# --- SonarQube up ---
echo "🐳 Vérification de SonarQube..."
if [ ! "$(docker ps -q -f name=sonarqube-server)" ]; then
  echo "   -> Démarrage..."
  docker-compose up -d
  until curl -s http://localhost:9000 > /dev/null; do sleep 5; echo -n "."; done
  echo ""
fi

# Détection du réseau (robuste)
SONAR_NETWORK="$(docker inspect -f '{{.HostConfig.NetworkMode}}' sonarqube-server 2>/dev/null || true)"
if [ -z "$SONAR_NETWORK" ] || [ "$SONAR_NETWORK" = "default" ]; then
  echo "❌ ERREUR : Impossible de détecter le réseau Docker de 'sonarqube-server'."
  docker network ls
  exit 1
fi

SUMMARY_CSV="$OUT_ROOT/summary.csv"
echo "repo_url,sha_commit,score,reliability,maintainability,security,duplication,avg_cognitive_per_file,complexity" > "$SUMMARY_CSV"

scan_one() {
  local REPO_URL="$1"
  local REPO_NAME
  local SHA_COMMIT
  local PROJECT_KEY
  local SRC_DIR
  local CSV_FILENAME
  local CSV_OUT_PATH
  local PY_OUT
  local SUMMARY_LINE

  REPO_NAME="$(basename "$REPO_URL" .git)"
  PROJECT_KEY="${REPO_NAME}_$(date +%s)"
  SRC_DIR="$SRC_BASE/$REPO_NAME"

  echo "========================================================"
  echo "⬇️  Repo: $REPO_NAME"
  echo "   URL:  $REPO_URL"
  echo "   KEY:  $PROJECT_KEY"

  echo "⬇️  Clonage..."
  rm -rf "$SRC_DIR"
  git clone "$REPO_URL" "$SRC_DIR"
  SHA_COMMIT="$(git -C "$SRC_DIR" rev-parse HEAD)"
  echo "   SHA:  $SHA_COMMIT"

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
    -Dsonar.exclusions="**/*.html" \
    -Dsonar.javascript.node.maxspace=4096

  sleep 5  # attendre que SonarQube traite l'analyse
  # Export
  CSV_FILENAME="${REPO_NAME}_report.csv"
  CSV_OUT_PATH="/app/output/reports/$CSV_FILENAME"
  mkdir -p "$REPORT_DIR"

  echo "📊 Export CSV... run : $PROJECT_KEY $SONAR_TOKEN $CSV_OUT_PATH"
  docker run --rm \
    --network "$SONAR_NETWORK" \
    -v "$(pwd):/app" \
    -w /app \
    python:3.9-slim \
    python /app/export_to_csv.py "$PROJECT_KEY" "$SONAR_TOKEN" "$CSV_OUT_PATH" 

  # Lire la ligne data (2e ligne) du CSV généré
  HOST_CSV_PATH="$REPORT_DIR/$CSV_FILENAME"
  SCORE_LINE="$(tail -n +2 "$HOST_CSV_PATH" | head -n 1 || true)"

  if [ -z "$SCORE_LINE" ]; then
    echo "⚠️ CSV vide: $HOST_CSV_PATH"
    echo "$REPO_URL,$REPO_NAME,$PROJECT_KEY,,,,,,,,,,$CSV_OUT_PATH" >> "$SUMMARY_CSV"
    return 0
  fi

  # SCORE_LINE est déjà un CSV: project_key,score,reliability,...
  echo "$REPO_URL,$SHA_COMMIT,$SCORE_LINE" >> "$SUMMARY_CSV"

  echo "✅ OK -> $SUMMARY_CSV"
}

if [[ -n "$REPOS_FILE" ]]; then
  echo "📥 Lecture repos depuis: $REPOS_FILE"
  # CSV simple: une URL par ligne (avec ou sans header). On ignore lignes vides et commentaires.
  while IFS= read -r line; do
    line="$(echo "$line" | tr -d '\r')"
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^# ]] && continue

    # si format "repo_url,..." on prend la 1ere colonne
    repo="$(echo "$line" | awk -F',' '{print $1}')"

    # skip header
    if [[ "$repo" == "repo_url" ]]; then
      continue
    fi

    scan_one "$repo"
  done < "$REPOS_FILE"
else
  scan_one "$REPO_URL"
fi

echo "--------------------------------------------------------"
echo "✅ Terminé"
echo "📊 Summary : $SUMMARY_CSV"
echo "📁 Reports : $REPORT_DIR"
echo "--------------------------------------------------------"
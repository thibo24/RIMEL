#!/bin/bash
set -e

SONAR_TOKEN="sqa_db9586e56cd8c54ffd69f67c2d813564e8d3a47c"
OUT_ROOT="1-qualite/outputs"
REPORT_DIR="$OUT_ROOT/reports"
SRC_BASE="$OUT_ROOT/src"
SUMMARY_CSV="$OUT_ROOT/summary.csv"
COMMITS_JSON="3-activite-contributeurs/data/raw_commits_data.json"

mkdir -p "$REPORT_DIR" "$SRC_BASE" "3-activite-contributeurs/data"

echo "=== Analyse SonarQube des dépôts ==="
echo ""

# Démarrer SonarQube si nécessaire
echo "🐳 Vérification de SonarQube..."
if [ ! "$(docker ps -q -f name=sonarqube-server)" ]; then
  echo "   -> Démarrage de SonarQube..."
  docker-compose up -d sonarqube >/dev/null 2>&1
  echo "   -> Attente du démarrage..."
  until curl -s http://localhost:9000 > /dev/null 2>&1; do 
    sleep 5
    echo -n "."
  done
  echo ""
  echo "   ✅ SonarQube est prêt!"
else
  echo "   ✅ SonarQube est déjà actif"
fi

# Détecter le réseau Docker
SONAR_NETWORK="$(docker inspect -f '{{.HostConfig.NetworkMode}}' sonarqube-server)"
if [ -z "$SONAR_NETWORK" ] || [ "$SONAR_NETWORK" = "default" ]; then
  echo "❌ ERREUR : Impossible de détecter le réseau Docker"
  exit 1
fi

# Initialiser le CSV summary
echo "repo_url,sha_commit,score,reliability,maintainability,security,duplication,complexity" > "$SUMMARY_CSV"

# Initialiser les fichiers de métadonnées
> "$OUT_ROOT/commits_meta.txt"
echo "repo,contributors" > "2-nombre-contributeurs/data/contributors.csv"

# Lire les repos
REPOS_CSV="repos_url.csv"
if [ ! -f "$REPOS_CSV" ]; then
  echo "❌ ERREUR: $REPOS_CSV introuvable!"
  exit 1
fi

echo ""
echo "📥 Lecture des dépôts depuis: $REPOS_CSV"
echo ""

# Compteur
TOTAL_REPOS=$(tail -n +2 "$REPOS_CSV" | wc -l)
CURRENT=0

# Créer un fichier temporaire avec les repos (stable path)
TEMP_REPOS="$OUT_ROOT/repos_list.tmp"
tail -n +2 "$REPOS_CSV" > "$TEMP_REPOS"

# Traiter chaque repo
# Ouvrir la liste sur le FD 3 pour éviter que des commandes dans la boucle lisent
# depuis stdin et vident le fichier de la boucle.
exec 3< "$TEMP_REPOS"
while IFS=, read -r repo_name repo_url <&3 || [ -n "$repo_name" ]; do
  CURRENT=$((CURRENT + 1))
  
  echo "========================================"
  echo "[$CURRENT/$TOTAL_REPOS] $repo_name"
  echo "   URL: $repo_url"
  
  PROJECT_KEY="${repo_name}_$(date +%s)"
  SRC_DIR="$SRC_BASE/$repo_name"
  
  # 1. Clonage
  echo "⬇️  Clonage..."
  rm -rf "$SRC_DIR"
  git clone --quiet "$repo_url" "$SRC_DIR" 2>/dev/null || {
    echo "❌ Échec du clonage"
    continue
  }
  
  SHA_COMMIT=$(git -C "$SRC_DIR" rev-parse HEAD)
  echo "   SHA: $SHA_COMMIT"
  
  # 2. Scan SonarQube
  echo "🔍 Lancement du Scanner SonarQube..."
  echo "   ⏳ Analyse en cours (peut prendre 2-5 minutes)..."
  
  # Chemin absolu pour éviter les problèmes Windows
  ABS_SRC_DIR="$(cd "$SRC_DIR" && pwd)"
  
  docker run --rm \
    --network "$SONAR_NETWORK" \
    -v "$ABS_SRC_DIR:/usr/src" \
    -w /usr/src \
    sonarsource/sonar-scanner-cli \
    -Dsonar.projectKey="$PROJECT_KEY" \
    -Dsonar.host.url=http://sonarqube-server:9000 \
    -Dsonar.token="$SONAR_TOKEN" \
    -Dsonar.scm.provider=git \
    -Dsonar.sources=. \
    -Dsonar.exclusions="**/*.html" \
    -Dsonar.javascript.node.maxspace=4096 \
    </dev/null 2>&1 | grep -v "Downloading\|Download" | grep --line-buffered -E "(INFO: |EXECUTION|Analysis report|Load |Process |Index |Sensor )" || true
  
  echo "   ✅ Scan terminé"
  echo "   ⏳ Attente du traitement SonarQube..."
  sleep 5
  
  # 3. Export CSV
  CSV_FILENAME="${repo_name}_report.csv"
  CSV_OUT_PATH="/app/1-qualite/outputs/reports/$CSV_FILENAME"
  
  echo "📊 Export des métriques SonarQube..."
  docker-compose run --rm analysis python 1-qualite/export_to_csv.py \
    "$PROJECT_KEY" "$SONAR_TOKEN" "$CSV_OUT_PATH" </dev/null 2>&1 | grep -E "(OK|ERREUR|🔑)" || true
  
  # Lire le CSV et ajouter au summary
  HOST_CSV_PATH="$REPORT_DIR/$CSV_FILENAME"
  if [ -f "$HOST_CSV_PATH" ]; then
    SCORE_LINE=$(tail -n +2 "$HOST_CSV_PATH" | head -n 1 | tr -d '\r')
    if [ -n "$SCORE_LINE" ]; then
      SCORES=$(echo "$SCORE_LINE" | awk -F',' '{print $2","$3","$4","$5","$6","$7}')
      echo "$repo_url,$SHA_COMMIT,$SCORES" >> "$SUMMARY_CSV"
      echo "   ✅ Métriques exportées"
    fi
  fi
  
  # 4. Extraire les commits avec git log
  echo "📝 Extraction des commits..."
  COMMITS_LIST=$(git -C "$SRC_DIR" log --pretty=format:%s 2>/dev/null || echo "")
  COMMITS_COUNT=$(echo "$COMMITS_LIST" | grep -c . || echo 0)
  
  # Sauvegarder dans un fichier temporaire
  OWNER=$(echo "$repo_url" | awk -F'/' '{print $(NF-1)}')
  TEMP_FILE="$OUT_ROOT/temp_commits_${repo_name}.txt"
  echo "$COMMITS_LIST" > "$TEMP_FILE"
  echo "$repo_name|$OWNER|$TEMP_FILE" >> "$OUT_ROOT/commits_meta.txt"
  
  echo "   ✅ $COMMITS_COUNT commits extraits"
  
  # 5. Compter les contributeurs — utiliser l'API GitHub (non-anonyme) avec cache
  echo "👥 Comptage des contributeurs (API + cache)..."

  OWNER=$(echo "$repo_url" | awk -F'/' '{print $(NF-1)}')
  REPO=$(echo "$repo_url" | awk -F'/' '{print $NF}' | sed 's/.git$//')
  CACHE_FILE="2-nombre-contributeurs/data/.contributors_cache"

  API_COUNT=""
  if [ -f "$CACHE_FILE" ]; then
    API_COUNT=$(grep "^$repo_name," "$CACHE_FILE" | cut -d',' -f2 || true)
  fi

  if [ -z "$API_COUNT" ]; then
    echo "   ⏳ Appel API GitHub (non-anonyme)..."
    RESPONSE_HEADERS=$(curl -s -I "https://api.github.com/repos/$OWNER/$REPO/contributors?per_page=1") || RESPONSE_HEADERS=""
    if echo "$RESPONSE_HEADERS" | grep -q 'rel="last"'; then
      API_COUNT=$(echo "$RESPONSE_HEADERS" | sed -n 's/.*[?&]page=\([0-9]\+\).*rel="last".*/\1/p' | tail -n1 || true)
    else
      API_COUNT=$(curl -s "https://api.github.com/repos/$OWNER/$REPO/contributors?per_page=100" | grep -c '"login"' || echo 0)
    fi
    API_COUNT=${API_COUNT:-0}
    mkdir -p "$(dirname "$CACHE_FILE")"
    echo "$repo_name,$API_COUNT" >> "$CACHE_FILE"
    echo "   ✅ API = $API_COUNT (appelé & stocké)"
  else
    echo "   ✅ API (depuis cache) = $API_COUNT"
  fi

  CONTRIBUTORS_COUNT=$API_COUNT
  echo "   ✅ $CONTRIBUTORS_COUNT contributeurs (API)"

  echo "$repo_name,$CONTRIBUTORS_COUNT" >> "2-nombre-contributeurs/data/contributors.csv"
  # 6. Supprimer le clone (force removal)
  echo "🗑️  Suppression du clone..."
  chmod -R +w "$SRC_DIR" 2>/dev/null || true
  rm -rf "$SRC_DIR"
  # Nettoyer aussi les résidus avec ;C si présents
  rm -rf "${SRC_DIR};C" 2>/dev/null || true
  
  echo ""
done
exec 3<&-

# Nettoyer le fichier temporaire
rm -f "$TEMP_REPOS"

# Convertir tous les commits en JSON
echo ""
echo "📦 Création du fichier JSON des commits..."
docker-compose run --rm analysis python </dev/null -c "
import json
from pathlib import Path

data = {}
meta_file = Path('1-qualite/outputs/commits_meta.txt')

if meta_file.exists():
    for line in meta_file.read_text().strip().split('\n'):
        if not line:
            continue
        parts = line.split('|')
        if len(parts) == 3:
            repo_name, owner, temp_file = parts
            commits_file = Path(temp_file)
            if commits_file.exists():
                commits = [c for c in commits_file.read_text().strip().split('\n') if c]
                data[repo_name] = {
                    'repo': repo_name,
                    'owner': owner,
                    'commits': commits
                }
                commits_file.unlink()  # Supprimer le fichier temporaire

# Sauvegarder le JSON final
output = Path('3-activite-contributeurs/data/raw_commits_data.json')
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(data, indent=2, ensure_ascii=False))

total = sum(len(d['commits']) for d in data.values())
print(f'✅ {len(data)} repos, {total} commits sauvegardés')
"

echo ""
echo "=========================================="
echo "✅ Terminé"
echo "📊 Summary : $SUMMARY_CSV"
echo "📁 Reports : $REPORT_DIR"
echo "📝 Commits : $COMMITS_JSON"
echo "=========================================="

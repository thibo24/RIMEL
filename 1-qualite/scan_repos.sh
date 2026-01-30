#!/bin/bash
set -e

SONAR_TOKEN="sqa_ad1b7bb27fdb49b882502b90d5833b081dff42d3"
OUT_ROOT="1-qualite/outputs"
REPORT_DIR="$OUT_ROOT/reports"
SRC_BASE="$OUT_ROOT/src"
SUMMARY_CSV="$OUT_ROOT/summary.csv"
COMMITS_JSON="3-activite-contributeurs/data/raw_commits_data.json"

mkdir -p "$REPORT_DIR" "$SRC_BASE" "3-activite-contributeurs/data"

echo "=== Analyse SonarQube des dépôts ==="
echo ""

# Parse options
REPLAY=0
if [ "$1" = "--replay" ] || [ "$1" = "-r" ]; then
  REPLAY=1
  shift
  echo "🔁 Mode replay activé — utilisation des SHA depuis $SUMMARY_CSV"
fi

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

# Initialiser le CSV summary (sans SHA)
echo "repo_url,score,reliability,maintainability,security,duplication,complexity" > "$SUMMARY_CSV"

# (plus de fichiers de métadonnées temporaires; on écrira directement le JSON final)
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

# Lire la liste des dépôts directement depuis le CSV (évite fichier temporaire)
exec 3< <(tail -n +2 "$REPOS_CSV")

# Traiter chaque repo
# Ouvrir la liste sur le FD 3 pour éviter que des commandes dans la boucle lisent
# depuis stdin et vident le fichier de la boucle.
while IFS=, read -r repo_name repo_url repo_sha <&3 || [ -n "$repo_name" ]; do
  CURRENT=$((CURRENT + 1))
  
  echo "========================================"
  echo "[$CURRENT/$TOTAL_REPOS] $repo_name"
  echo "   URL: $repo_url"
  
  PROJECT_KEY="${repo_name}_$(date +%s)"
  SRC_DIR="$SRC_BASE/$repo_name"
  
  # 1. Clonage
  echo "⬇️  Clonage..."
  rm -rf "$SRC_DIR"
  if ! git clone "$repo_url" "$SRC_DIR"; then
    echo "❌ Échec du clonage"
    continue
  fi
  
  # Si on est en mode replay, tenter de récupérer le SHA depuis repos_url.csv (3ème colonne)
  if [ "$REPLAY" = "1" ]; then
    if [ -n "$repo_sha" ]; then
      echo "   -> Checkout sur le SHA fourni dans repos_url.csv: $repo_sha"
      git -C "$SRC_DIR" checkout --quiet "$repo_sha" || echo "   ⚠️ Échec du checkout sur $repo_sha"
    else
      echo "   ⚠️ Aucun SHA fourni pour $repo_name dans $REPOS_CSV; utilisation du HEAD actuel"
    fi
  fi

  SHA_COMMIT=$(git -C "$SRC_DIR" rev-parse HEAD)
  echo "   SHA: $SHA_COMMIT"

  # Si on n'est PAS en mode replay, enregistrer/mettre à jour le SHA dans repos_url.csv
  if [ "$REPLAY" -ne 1 ]; then
    if [ -f "$REPOS_CSV" ]; then
      awk -F',' -v OFS=',' -v name="$repo_name" -v sha="$SHA_COMMIT" '
        NR==1 { print; next }
        $1==name { $3=sha; print; next }
        { print }
      ' "$REPOS_CSV" > "$REPOS_CSV.tmp" && mv "$REPOS_CSV.tmp" "$REPOS_CSV"
    fi
  fi
  
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
    "$PROJECT_KEY" "$SONAR_TOKEN" "$CSV_OUT_PATH" </dev/null 2>/dev/null | grep -E "(OK|ERREUR|🔑)" || true
  
  # Lire le CSV et ajouter au summary
  HOST_CSV_PATH="$REPORT_DIR/$CSV_FILENAME"
  if [ -f "$HOST_CSV_PATH" ]; then
    SCORE_LINE=$(tail -n +2 "$HOST_CSV_PATH" | head -n 1 | tr -d '\r')
    if [ -n "$SCORE_LINE" ]; then
      SCORES=$(echo "$SCORE_LINE" | awk -F',' '{print $2","$3","$4","$5","$6","$7}')
      echo "$repo_url,$SCORES" >> "$SUMMARY_CSV"
      echo "   ✅ Métriques exportées"
    fi
  fi
  
  # 4. Extraire les commits avec git log
  echo "📝 Extraction des commits..."
  COMMITS_LIST=$(git -C "$SRC_DIR" log --pretty=format:%s 2>/dev/null || echo "")
  COMMITS_COUNT=$(echo "$COMMITS_LIST" | grep -c . || echo 0)
  
    OWNER=$(echo "$repo_url" | awk -F'/' '{print $(NF-1)}')

    echo "   ✅ $COMMITS_COUNT commits extraits"

    # Écrire directement dans le JSON final via le script Python séparé
  printf '%s
' "$COMMITS_LIST" | docker-compose run --rm -T analysis python 1-qualite/save_commits.py "$repo_name" "$OWNER" 2>/dev/null
  
  # 5. Compter les contributeurs (git local — adresses e-mail uniques)
  echo "👥 Comptage des contributeurs (git local — adresses e-mail uniques)..."
  # Compter les adresses e-mail uniques des auteurs de commit
  # Exclure les contributeurs anonymes / emails no-reply
  CONTRIBUTORS_COUNT=$(git -C "$SRC_DIR" log --format='%aN <%aE>' 2>/dev/null \
    | sed '/^$/d' \
    | grep -i -v -E 'noreply|no-reply|users\.noreply' \
    | grep -v -E '<>' \
    | grep -v -E '^[[:space:]]*(unknown|anonymous)' \
    | sort -u \
    | wc -l || echo 0)
  CONTRIBUTORS_COUNT=${CONTRIBUTORS_COUNT:-0}
  echo "   ✅ $CONTRIBUTORS_COUNT contributeurs (emails uniques, sans anonymes)"
  echo "$repo_name,$CONTRIBUTORS_COUNT" >> "2-nombre-contributeurs/data/contributors.csv"
  # 6. Supprimer le clone (force removal)
  echo "🗑️  Suppression du clone..."
  chmod -R +w "$SRC_DIR" 2>/dev/null || true
  rm -rf "$SRC_DIR"
  # Nettoyer aussi les résidus avec ;C si présents
  rm -rf "${SRC_DIR};C" 2>/dev/null || true
  
  echo ""
done
# Nettoyer le fichier temporaire
exec 3<&-

echo ""
echo "=========================================="
echo "✅ Terminé"
echo "📊 Summary : $SUMMARY_CSV"
echo "📁 Reports : $REPORT_DIR"
echo "📝 Commits : $COMMITS_JSON"
echo "=========================================="

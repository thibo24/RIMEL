import urllib.request
import json
import csv
import sys
import base64

# Récupération des arguments passés par le script bash
if len(sys.argv) < 4:
    print("Usage: python export_to_csv.py <PROJECT_KEY> <SONAR_TOKEN> <OUTPUT_FILE>")
    sys.exit(1)

PROJECT_KEY = sys.argv[1]
TOKEN = sys.argv[2]
OUTPUT_FILE = sys.argv[3]
SONAR_URL = "http://sonarqube-server:9000"

# Préparation de l'authentification
auth_str = f"{TOKEN}:"
b64_auth = base64.b64encode(auth_str.encode()).decode()
headers = {"Authorization": f"Basic {b64_auth}"}

def rating_to_score(v) -> int:
    # Sonar renvoie souvent "1.0".."5.0" pour *_rating (A..E)
    # 1->A, 2->B, 3->C, 4->D, 5->E
    mapping_num = {1: 100, 2: 80, 3: 60, 4: 40, 5: 20}
    mapping_letter = {"A": 100, "B": 80, "C": 60, "D": 40, "E": 20}

    if v is None:
        return 0
    s = str(v).strip().upper()
    if s in mapping_letter:
        return mapping_letter[s]
    try:
        n = int(float(s))
        return mapping_num.get(n, 0)
    except Exception:
        return 0

def clamp_0_100(x: float) -> float:
    return max(0.0, min(100.0, x))

def fetch_project_score(project_key: str) -> dict:
    # Notes + duplication + cognitive complexity via measures
    metric_keys = "reliability_rating,sqale_rating,security_rating,duplicated_lines_density,cognitive_complexity"
    url = f"{SONAR_URL}/api/measures/component?component={project_key}&metricKeys={metric_keys}"

    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read().decode("utf-8"))

    measures = {m["metric"]: m.get("value") for m in data.get("component", {}).get("measures", [])}

    reliability = rating_to_score(measures.get("reliability_rating"))
    maintainability = rating_to_score(measures.get("sqale_rating"))
    security = rating_to_score(measures.get("security_rating"))

    # Duplication: max(0, 100 - duplication(%))
    try:
        duplication_density = float(measures.get("duplicated_lines_density") or 0.0)
    except Exception:
        duplication_density = 0.0
    duplication = max(0.0, 100.0 - duplication_density)

    # Complexity: max(0, 100 - cognitive_complexity)
    try:
        cognitive = float(measures.get("cognitive_complexity") or 0.0)
    except Exception:
        cognitive = 0.0
    complexity = max(0.0, 100.0 - cognitive)

    score = (
        0.25 * reliability +
        0.20 * maintainability +
        0.15 * security +
        0.20 * duplication +
        0.20 * complexity
    )

    return {
        "reliability": float(reliability),
        "maintainability": float(maintainability),
        "security": float(security),
        "duplication": clamp_0_100(duplication),
        "complexity": clamp_0_100(complexity),
        "score": clamp_0_100(score),
    }

print(f"📥 Récupération des données pour {PROJECT_KEY}...")

# 0) Récupération métriques + calcul score
try:
    score_info = fetch_project_score(PROJECT_KEY)
    print(
        f"🏁 Score={score_info['score']:.2f}/100 "
        f"(R={score_info['reliability']:.0f}, M={score_info['maintainability']:.0f}, "
        f"S={score_info['security']:.0f}, D={score_info['duplication']:.2f}, C={score_info['complexity']:.2f})"
    )
except Exception as e:
    print(f"⚠️ Impossible de récupérer les métriques pour le score: {e}")
    score_info = {"reliability": 0, "maintainability": 0, "security": 0, "duplication": 0, "complexity": 0, "score": 0}

issues_all = []
page = 1
page_size = 500  # Max autorisé par l'API par page

while True:
    # On appelle l'API pour chercher les issues
    url = f"{SONAR_URL}/api/issues/search?componentKeys={PROJECT_KEY}&ps={page_size}&p={page}"

    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())

            issues = data.get('issues', [])
            if not issues:
                break

            issues_all.extend(issues)

            # Pagination : si on a moins de résultats que la taille de page, c'est fini
            if len(issues) < page_size:
                break

            page += 1
            print(f"   ... Page {page} récupérée")

    except Exception as e:
        print(f"❌ Erreur lors de l'appel API: {e}")
        sys.exit(1)

print(f"💾 Écriture de {len(issues_all)} problèmes dans {OUTPUT_FILE}...")

# Écriture du CSV
with open(OUTPUT_FILE, 'w', newline='', encoding='utf-8') as csvfile:
    # 1) Une ligne "meta" au début avec le score global
    csvfile.write(
        "# "
        f"project_key={PROJECT_KEY}, "
        f"project_score={score_info['score']:.2f}/100, "
        f"reliability={score_info['reliability']:.0f}, "
        f"maintainability={score_info['maintainability']:.0f}, "
        f"security={score_info['security']:.0f}, "
        f"duplication={score_info['duplication']:.2f}, "
        f"complexity={score_info['complexity']:.2f}"
        "\n"
    )

    fieldnames = ['severity', 'type', 'component', 'line', 'message', 'effort', 'status', 'project_score']
    writer = csv.DictWriter(csvfile, fieldnames=fieldnames)

    writer.writeheader()
    for issue in issues_all:
        writer.writerow({
            'severity': issue.get('severity', ''),
            'type': issue.get('type', ''),
            'component': issue.get('component', ''),
            'line': issue.get('line', ''),
            'message': issue.get('message', ''),
            'effort': issue.get('effort', ''),
            'status': issue.get('status', ''),
            'project_score': f"{score_info['score']:.2f}",
        })

print("✅ Export CSV terminé !")
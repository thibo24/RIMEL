"""
Collect raw commit data from local git repositories.
This script uses the cloned repos from 1-qualite/outputs/src/
to extract commit messages using git log (no API calls needed).

Usage:
    python collect_commits.py
"""
import csv
import subprocess
import json
from pathlib import Path

def get_repo_name(url):
    """Extract repo name from URL."""
    return url.rstrip('/').split('/')[-1]

def collect_commits_from_local(repo_path):
    """Extract commit messages using git log."""
    try:
        result = subprocess.run(
            ["git", "log", "--pretty=format:%s"],
            cwd=repo_path,
            capture_output=True,
            text=True,
            check=True
        )
        commits = result.stdout.strip().split('\n')
        return [c for c in commits if c]  # Filter empty lines
    except Exception as e:
        print(f"  [ERREUR] {e}")
        return []

def main():
    print("=== Collecte des donnees de commits (depuis clones locaux) ===\n")
    
    repos_csv = Path("repos_url.csv")
    if not repos_csv.exists():
        print(f"[ERREUR] repos_url.csv introuvable!")
        return
    
    clones_dir = Path("1-qualite/outputs/src")
    if not clones_dir.exists():
        print(f"[ERREUR] Le dossier {clones_dir} n'existe pas!")
        print("Lancez d'abord l'analyse SonarQube pour cloner les dépôts.")
        return
    
    repos = []
    with open(repos_csv, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row['repo_url']:
                repos.append((row['repo_name'], row['repo_url']))
    
    all_data = {}
    
    for i, (repo_name, repo_url) in enumerate(repos, 1):
        repo_path = clones_dir / repo_name
        
        print(f"[{i}/{len(repos)}] {repo_name}")
        
        if not repo_path.exists():
            print(f"  [WARN] Dépôt non trouvé: {repo_path}")
            print(f"  Clonage...")
            try:
                subprocess.run(["git", "clone", repo_url, str(repo_path)], check=True)
            except Exception as e:
                print(f"  [ERREUR] Échec du clonage: {e}")
                continue
        
        print(f"  Extraction des commits via git log...")
        commits = collect_commits_from_local(repo_path)
        
        owner = repo_url.rstrip('/').split('/')[-2]
        all_data[repo_name] = {
            "repo": repo_name,
            "owner": owner,
            "commits": commits
        }
        
        print(f"  [OK] {len(commits)} commits collectes\n")
    
    output_file = Path("3-activite-contributeurs/data/raw_commits_data.json")
    output_file.parent.mkdir(parents=True, exist_ok=True)
    
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(all_data, f, indent=2, ensure_ascii=False)
    
    total_commits = sum(len(d['commits']) for d in all_data.values())
    print(f"Donnees sauvegardees dans {output_file}")
    print(f"     {len(all_data)} repos, {total_commits} commits")
    
    # Nettoyer les clones pour libérer l'espace disque
    print(f"\n🗑️  Nettoyage des dépôts clonés...")
    try:
        subprocess.run(["rm", "-rf", str(clones_dir)], check=True)
        print(f"✅ Dépôts supprimés: {clones_dir}")
    except Exception as e:
        print(f"⚠️  Erreur lors du nettoyage: {e}")

if __name__ == "__main__":
    main()

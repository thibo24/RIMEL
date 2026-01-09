"""
Collect raw commit data from GitHub repositories.
This script should be run ONCE to gather all commit messages.
Without token: 60 req/h (slow)
With token: 5000 req/h (fast)

Usage:
    python collect_commits.py
    python collect_commits.py your_token
"""
import csv
import requests
import json
import sys
from time import sleep
from pathlib import Path

def get_repo_info(url):
    parts = url.rstrip('/').split('/')
    return parts[-2], parts[-1]

def collect_commits(owner, repo, token=None):
    headers = {'Authorization': f'token {token}'} if token else {}
    commits = []
    page = 1
    
    print(f"  Collecte des commits...")
    
    while True:
        url = f"https://api.github.com/repos/{owner}/{repo}/commits"
        params = {'per_page': 100, 'page': page}
        
        try:
            response = requests.get(url, params=params, headers=headers, timeout=30)
            
            if response.status_code == 403:
                print(f"  [WARN] Limite atteinte - attente de 5min...")
                sleep(300)
                continue
            elif response.status_code != 200:
                print(f"  [ERREUR] Status {response.status_code}")
                break
            
            data = response.json()
            if not data:
                break
            
            for commit in data:
                commits.append(commit['commit']['message'].split('\n')[0])
            
            print(f"  -> {len(commits)} commits...", end='\r')
            
            if len(data) < 100:
                break
            
            page += 1
            sleep(0.5)
            
        except Exception as e:
            print(f"  [ERREUR] {e}")
            break
    
    print(f"  [OK] {len(commits)} commits collectes")
    return commits

def main():
    print("=== Collecte des donnees de commits ===\n")
    
    token = sys.argv[1] if len(sys.argv) > 1 else None
    
    if token:
        print("[INFO] Token fourni - Limite: 5000 req/h")
    else:
        print("[INFO] Pas de token - Limite: 60 req/h")
        print("       Pour accelerer: python collect_commits.py YOUR_TOKEN")
    
    repos_csv = Path("repos_url.csv")
    if not repos_csv.exists():
        print(f"[ERREUR] repos_url.csv introuvable!")
        return
    
    repos = []
    with open(repos_csv, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row['repo_url']:
                repos.append(row['repo_url'])
    
    all_data = {}
    
    for i, repo_url in enumerate(repos, 1):
        owner, repo_name = get_repo_info(repo_url)
        print(f"[{i}/{len(repos)}] {repo_name}")
        
        commits = collect_commits(owner, repo_name, token)
        
        all_data[repo_name] = {
            "repo": repo_name,
            "owner": owner,
            "commits": commits
        }
        
        print()
    
    output_file = Path("data/raw_commits_data.json")
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(all_data, f, indent=2, ensure_ascii=False)
    
    total_commits = sum(len(d['commits']) for d in all_data.values())
    print(f"Donnees sauvegardees dans {output_file}")
    print(f"     {len(all_data)} repos, {total_commits} commits")

if __name__ == "__main__":
    main()

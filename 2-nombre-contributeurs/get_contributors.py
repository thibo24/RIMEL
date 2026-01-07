import csv
import requests
from time import sleep
from pathlib import Path

def get_contributors_count(owner, repo):
    url = f"https://api.github.com/repos/{owner}/{repo}/contributors"
    
    try:
        response = requests.get(url, params={'per_page': 1, 'anon': 'true'}, timeout=10)
        
        if response.status_code == 403:
            print(f"  [WARN] Rate limit - attente de 5min...")
            sleep(300)
            return get_contributors_count(owner, repo)
        elif response.status_code != 200:
            print(f"  [WARN] Erreur {response.status_code}")
            return 0
        
        link_header = response.headers.get('Link', '')
        if 'rel="last"' in link_header:
            import re
            match = re.search(r'page=(\d+)>; rel="last"', link_header)
            if match:
                return int(match.group(1))
        
        return len(response.json())
    except Exception as e:
        print(f"  [ERREUR] {e}")
        return 0

def get_repo_info(url):
    parts = url.rstrip('/').split('/')
    return parts[-2], parts[-1]

def main():
    repos_csv = Path("repos_url.csv")
    if not repos_csv.exists():
        print(f"[ERREUR] {repos_csv} introuvable!")
        return
    
    repos = []
    with open(repos_csv, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if row['repo_url']:
                repos.append(row['repo_url'])
    
    print(f"Trouve {len(repos)} repos\n")
    
    results = []
    
    for i, repo_url in enumerate(repos, 1):
        owner, repo_name = get_repo_info(repo_url)
        print(f"[{i}/{len(repos)}] {repo_name}")
        
        contributors = get_contributors_count(owner, repo_name)
        print(f"  -> {contributors} contributeurs\n")
        
        results.append({
            "repo": repo_name,
            "contributors": contributors
        })
        
        sleep(0.5)
    
    output_file = Path("2-nombre-contributeurs/data/contributors.csv")
    with open(output_file, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=['repo', 'contributors'])
        writer.writeheader()
        writer.writerows(results)
    
    print(f"[OK] Resultats dans {output_file}")

if __name__ == "__main__":
    main()

import pandas as pd
from plotnine import (
    ggplot, aes, geom_bar, geom_hline,
    labs, theme_minimal, theme, element_text
)
from pathlib import Path

SUMMARY_CSV = "1-qualite/sonar/output/summary.csv"
REPOS_GROUPS_CSV = "2-nombre-contributeurs/repos_groups.csv"
CONTRIBUTORS_CSV = "2-nombre-contributeurs/data/contributors.csv"
OUTPUT_DIR = Path("2-nombre-contributeurs/graphs")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

df_summary = pd.read_csv(SUMMARY_CSV)
df_groups = pd.read_csv(REPOS_GROUPS_CSV)
df_contributors = pd.read_csv(CONTRIBUTORS_CSV)

df_summary["repo_name"] = df_summary["repo_url"].str.extract(
    r"dataforgoodfr/(.+)$"
)[0]

df = pd.merge(df_summary, df_groups, on="repo_name", how="inner")
df = pd.merge(df, df_contributors, left_on="repo_name", right_on="repo", how="inner")

def get_group_label(contributors):
    if contributors < 9:
        return "Groupe 1 (0-8 contributeurs)"
    elif contributors < 20:
        return "Groupe 2 (9-19 contributeurs)"
    else:
        return "Groupe 3 (20+ contributeurs)"

df["group_label"] = df["contributors"].apply(get_group_label)

groups = [
    (1, "Groupe 1 (0-8 contributeurs)"),
    (2, "Groupe 2 (9-19 contributeurs)"),
    (3, "Groupe 3 (20+ contributeurs)")
]

print(f"Analyse de {len(df)} repos")

for group_num, group_label in groups:
    df_group = df[df["repo_group"] == group_num].copy()
    
    if len(df_group) == 0:
        print(f"Aucune donnée pour le {group_label}")
        continue
    
    median_score = df_group["score"].median()
    print(f"{group_label}: {len(df_group)} repos, médiane = {median_score:.2f}")
    df_group = df_group.sort_values("score")
    
    plot = (
        ggplot(df_group, aes(x="repo_name", y="score"))
        + geom_bar(stat="identity", fill="steelblue", alpha=0.7)
        + geom_hline(yintercept=median_score, color="red", linetype="dashed", size=1)
        + theme_minimal()
        + theme(
            axis_text_x=element_text(rotation=45, hjust=1, size=8),
            figure_size=(12, 6)
        )
        + labs(
            title=f"Score de qualité par rapport à la médiane pour les dépôts de {group_label.split('(')[1].split(')')[0]}",
            x="Nom du dépôt",
            y="Score de qualité",
            caption=f"Ligne rouge: médiane = {median_score:.2f}"
        )
    )
    
    filename = f"qualite_groupe_{group_num}.png"
    plot.save(
        OUTPUT_DIR / filename,
        width=12,
        height=6,
        dpi=300
    )
    print(f"Graphique sauvegardé: {filename}")

print("\nTous les graphiques ont été générés avec succès dans", OUTPUT_DIR)

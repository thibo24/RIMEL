import pandas as pd
from plotnine import (
    ggplot, aes, geom_point, geom_smooth,
    labs, theme_minimal
)
from pathlib import Path

INPUT_CSV = "/data/repo_commits.csv"
OUTPUT_DIR = Path("/outputs/graphs")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

df = pd.read_csv(INPUT_CSV)

df["ratio_fix"] = df["fix"] / df["total_commits"]

df_refactor = df[df["feat"] > 0].copy()
df_refactor["ratio_refactor_feat"] = (
    df_refactor["refactor"] / df_refactor["feat"]
)

plot_fix = (
    ggplot(df, aes(x="nombre_contributeurs", y="ratio_fix"))
    + geom_point(alpha=0.7)
    + geom_smooth(method="lm", se=True)
    + theme_minimal()
    + labs(
        title="Ratio fix / total commits selon le nombre de contributeurs",
        x="Nombre de contributeurs",
        y="Ratio fix / total commits"
    )
)

plot_fix.save(
    OUTPUT_DIR / "ratio_fix_vs_contributeurs.png",
    width=8,
    height=5,
    dpi=300
)

plot_refactor = (
    ggplot(df_refactor, aes(
        x="nombre_contributeurs",
        y="ratio_refactor_feat"
    ))
    + geom_point(alpha=0.7)
    + geom_smooth(method="lm", se=True)
    + theme_minimal()
    + labs(
        title="Ratio refactor / feat selon le nombre de contributeurs",
        x="Nombre de contributeurs",
        y="Ratio refactor / feat"
    )
)

plot_refactor.save(
    OUTPUT_DIR / "ratio_refactor_feat_vs_contributeurs.png",
    width=8,
    height=5,
    dpi=300
)

print("Graphes générés avec succès.")

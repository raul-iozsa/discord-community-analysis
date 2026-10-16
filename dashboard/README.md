# Dashboard

The Tableau dashboards for this project, published on
[Tableau Public](https://public.tableau.com/app/profile/raul.c.4596/viz/DiscordAnalysis/Thedecline).

- `Discord Analysis.twbx`: the workbook (opens in Tableau Desktop or Tableau Public).
- `screenshots/`: each dashboard, including the interactive states.
- `data/`: the tables the workbook reads, built by `scripts/build_dashboard_data.py` from
  `outputs/tables/` only, so every number in the dashboards comes from a notebook output.

| File | One row per | Used for |
|---|---|---|
| `headline.csv` | metric | the big-number tiles: 2022 against 2025, with the change |
| `yearly.csv` | year | headline numbers, the decomposition (indexed to 2022 = 100), message length, reply share |
| `daily.csv` | day | daily volume with a 7-day average; `window` marks tournaments and their controls |
| `tournaments.csv` | tournament or control window | multiplier and extra messages per day |
| `pairs_directed.csv` | period × replier × target | reply heatmaps: raw replies and lift |
| `pairs_undirected.csv` | period × pair | busiest pairs, with their lift |
| `staircase_grid.csv` | member × month | the change-point staircase (activity as a share of own peak); all 24 analysed members, the 3 without a change point at the bottom |

2020 is pre-community and 2026 is partial (to 9 August); both are flagged in `note`.
Members appear by pseudonym only.

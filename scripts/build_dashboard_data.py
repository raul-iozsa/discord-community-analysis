"""Builds the tidy CSVs the Tableau dashboards read (dashboard/data/) from outputs/tables/ only."""
import os

import numpy as np
import pandas as pd

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TABLES = os.path.join(REPO_ROOT, "outputs", "tables")
OUT = os.path.join(REPO_ROOT, "dashboard", "data")
os.makedirs(OUT, exist_ok=True)


def read(name, **kw):
    return pd.read_csv(os.path.join(TABLES, f"{name}.csv"), **kw)


def write(df, name):
    df.to_csv(os.path.join(OUT, f"{name}.csv"), index=False)
    print(f"{name}.csv: {len(df):,} rows")


YEAR_NOTE = {2020: "pre-community", 2026: "partial (to 9 Aug)"}

# daily volume, zero days filled, 7-day mean, tournament / control labels
daily = read("daily_volume", parse_dates=["day"]).set_index("day")
daily = daily.reindex(pd.date_range(daily.index.min(), daily.index.max(), name="day"), fill_value=0)
daily["messages_7day_avg"] = daily["messages"].rolling(7, min_periods=1).mean().round(1)
daily["window"] = ""
daily["window_kind"] = ""
for _, w in read("event_windows", parse_dates=["start_date", "end_date"]).iterrows():
    days = (daily.index >= w["start_date"]) & (daily.index <= w["end_date"])
    if w["kind"] == "tournament":
        daily.loc[days, "window"] = w["event"]
        daily.loc[days, "window_kind"] = "tournament"
    else:   # the summer controls overlap, so they share one label
        daily.loc[days & (daily["window_kind"] == ""), "window"] = "control (same dates, no tournament)"
        daily.loc[days & (daily["window_kind"] == ""), "window_kind"] = "control"
write(daily.reset_index(), "daily")

# one row per year: the decomposition, text volume, reply share
dec = read("decomposition").set_index("year")
text = read("member_year_text").groupby("year")[["messages", "chars", "words"]].sum()
reply = read("reply_share_year").set_index("year")
yearly = pd.DataFrame({
    "messages": dec["total_messages"],
    "days_observed": dec["days_observed"],
    "messages_per_day": dec["messages_per_day"].round(1),
    "active_members": dec["active_members"],
    "messages_per_active_member_per_day": dec["messages_per_active_member_per_day"].round(2),
    "characters_per_day": (text["chars"] / dec["days_observed"]).round(1),
    "mean_characters_per_message": (text["chars"] / text["messages"]).round(1),
    "reply_share": reply["reply_share"].round(4),
})
base = yearly.loc[2022]
for col in ["messages_per_day", "active_members", "messages_per_active_member_per_day", "characters_per_day"]:
    yearly[f"{col}_index_2022"] = (100 * yearly[col] / base[col]).round(1)
yearly["note"] = [YEAR_NOTE.get(y, "") for y in yearly.index]
write(yearly.reset_index(), "yearly")

# headline tiles: 2022 (peak) against 2025 (last full year)
rows = [("Messages per day", "messages_per_day"),
        ("Active members", "active_members"),
        ("Messages per active member per day", "messages_per_active_member_per_day"),
        ("Characters written per day", "characters_per_day"),
        ("Average message length (characters)", "mean_characters_per_message"),
        ("Share of messages that are replies", "reply_share")]
scale = {"reply_share": 100}
write(pd.DataFrame([{"metric": m + (" (%)" if c in scale else ""),
                     "value_2022": round(yearly.loc[2022, c] * scale.get(c, 1), 1),
                     "value_2025": round(yearly.loc[2025, c] * scale.get(c, 1), 1),
                     "change": round(yearly.loc[2025, c] / yearly.loc[2022, c] - 1, 4)}
                    for m, c in rows]), "headline")

# tournaments and their controls
ev = read("event_metrics")
write(ev[["event", "kind", "year", "start_date", "end_date", "baseline_mean_per_day",
          "during_mean_per_day", "volume_multiplier", "volume_lift_per_day"]].round(3), "tournaments")

# who talks to whom
pairs = read("pair_lift_directed")
pairs["log2_lift"] = np.where(pairs["lift"] > 0, np.log2(pairs["lift"].where(pairs["lift"] > 0)), np.nan).round(3)
pairs["enough_replies"] = pairs["replies"] >= 20
write(pairs, "pairs_directed")

und = pairs.assign(member_a=pairs[["source", "target"]].min(axis=1),
                   member_b=pairs[["source", "target"]].max(axis=1))
und = (und.groupby(["period", "member_a", "member_b"])
          .agg(replies=("replies", "sum"), expected=("expected", "sum")).reset_index())
und["lift"] = (und["replies"] / und["expected"]).round(3)
und["pair"] = und["member_a"] + " & " + und["member_b"]
write(und, "pairs_undirected")

# change points
grid = read("changepoint_grid", parse_dates=["month"])
grid["pct_of_peak"] = grid["pct_of_peak"].round(3)
write(grid, "staircase_grid")

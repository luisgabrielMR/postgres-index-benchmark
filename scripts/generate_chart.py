from pathlib import Path
from typing import Optional

import matplotlib.pyplot as plt
import pandas as pd
from matplotlib.ticker import FuncFormatter


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SUMMARY_PATH = PROJECT_ROOT / "results" / "summary.csv"
RESOURCE_SUMMARY_PATH = PROJECT_ROOT / "results" / "resource-summary.csv"
OUTPUT_PATH = PROJECT_ROOT / "results" / "benchmark-results.png"
LEGACY_OUTPUT_PATH = PROJECT_ROOT / "results" / "execution-time-comparison.png"

BEFORE_COLOR = "#6c757d"
AFTER_COLOR = "#198754"
READ_COLOR = "#0d6efd"
TEXT_COLOR = "#1f2933"
MUTED_TEXT_COLOR = "#6b7280"
GRID_COLOR = "#d9dee3"
BACKGROUND_COLOR = "#f7f9fb"
PANEL_COLOR = "#ffffff"


def format_number(value: float) -> str:
    return f"{value:,.0f}"


def format_ms(value: float) -> str:
    return f"{value:,.3f} ms"


def normalize_scenario(value: str) -> str:
    return value.replace("_", " ").title()


def style_axis(ax) -> None:
    ax.set_facecolor(PANEL_COLOR)
    ax.grid(axis="x", color=GRID_COLOR, linewidth=0.8, alpha=0.7)
    ax.set_axisbelow(True)
    ax.tick_params(colors=MUTED_TEXT_COLOR, labelsize=9)
    for spine in ax.spines.values():
        spine.set_visible(False)


def add_panel_title(ax, title: str, subtitle: Optional[str] = None) -> None:
    ax.set_title(title, loc="left", fontsize=12, fontweight="bold", color=TEXT_COLOR, pad=14)
    if subtitle:
        ax.text(
            0,
            1.01,
            subtitle,
            transform=ax.transAxes,
            ha="left",
            va="bottom",
            fontsize=8.5,
            color=MUTED_TEXT_COLOR,
        )


def main() -> None:
    if not SUMMARY_PATH.exists():
        raise SystemExit(f"File not found: {SUMMARY_PATH}")
    if not RESOURCE_SUMMARY_PATH.exists():
        raise SystemExit(f"File not found: {RESOURCE_SUMMARY_PATH}")

    timing = pd.read_csv(SUMMARY_PATH)
    resources = pd.read_csv(RESOURCE_SUMMARY_PATH)

    timing["execution_time_ms"] = pd.to_numeric(
        timing["execution_time_ms"],
        errors="coerce",
    )
    timing = timing.dropna(subset=["execution_time_ms"])

    if timing.empty:
        raise SystemExit(
            "No execution times found. Run the benchmark first or fill results/summary.csv."
        )

    for column in resources.columns:
        if column != "scenario":
            resources[column] = pd.to_numeric(resources[column], errors="coerce").fillna(0)

    timing = timing.set_index("scenario")
    resources = resources.set_index("scenario")
    ordered_scenarios = [scenario for scenario in ["before_index", "after_index"] if scenario in timing.index]

    if len(ordered_scenarios) != 2:
        raise SystemExit("Expected before_index and after_index rows in results/summary.csv.")

    before_ms = float(timing.loc["before_index", "execution_time_ms"])
    after_ms = float(timing.loc["after_index", "execution_time_ms"])
    speedup = before_ms / after_ms if after_ms else 0
    time_saved = before_ms - after_ms

    plt.rcParams.update(
        {
            "font.family": "DejaVu Sans",
            "axes.titleweight": "bold",
            "axes.labelcolor": MUTED_TEXT_COLOR,
            "figure.facecolor": BACKGROUND_COLOR,
            "savefig.facecolor": BACKGROUND_COLOR,
        }
    )

    fig = plt.figure(figsize=(12, 8), constrained_layout=True)
    fig.suptitle(
        "PostgreSQL Composite Index Benchmark",
        fontsize=18,
        fontweight="bold",
        color=TEXT_COLOR,
        x=0.04,
        ha="left",
    )
    fig.text(
        0.04,
        0.942,
        "Generated from results/summary.csv and results/resource-summary.csv",
        fontsize=9.5,
        color=MUTED_TEXT_COLOR,
        ha="left",
    )

    layout = fig.add_gridspec(3, 4, height_ratios=[0.8, 2.4, 2.0])
    kpi_axes = [fig.add_subplot(layout[0, i]) for i in range(4)]
    ax_time = fig.add_subplot(layout[1, :2])
    ax_buffers = fig.add_subplot(layout[1, 2:])
    ax_rows = fig.add_subplot(layout[2, :2])
    ax_details = fig.add_subplot(layout[2, 2:])

    kpis = [
        ("Before index", format_ms(before_ms), "Parallel Seq Scan + Sort", BEFORE_COLOR),
        ("After index", format_ms(after_ms), "Index Scan", AFTER_COLOR),
        ("Speedup", f"{speedup:,.2f}x", "Lower execution time", AFTER_COLOR),
        ("Time saved", format_ms(time_saved), "Same query, same dataset", TEXT_COLOR),
    ]

    for ax, (label, value, caption, color) in zip(kpi_axes, kpis):
        ax.set_facecolor(PANEL_COLOR)
        ax.set_xticks([])
        ax.set_yticks([])
        for spine in ax.spines.values():
            spine.set_visible(False)
        ax.text(0.04, 0.72, label, transform=ax.transAxes, fontsize=9, color=MUTED_TEXT_COLOR)
        ax.text(0.04, 0.36, value, transform=ax.transAxes, fontsize=18, fontweight="bold", color=color)
        ax.text(0.04, 0.12, caption, transform=ax.transAxes, fontsize=8.5, color=MUTED_TEXT_COLOR)

    labels = [normalize_scenario(scenario) for scenario in ordered_scenarios]
    times = [float(timing.loc[scenario, "execution_time_ms"]) for scenario in ordered_scenarios]
    colors = [BEFORE_COLOR, AFTER_COLOR]
    y_positions = range(len(labels))

    style_axis(ax_time)
    add_panel_title(ax_time, "Execution time", "Lower is better")
    bars = ax_time.barh(y_positions, times, color=colors, height=0.52)
    ax_time.set_yticks(list(y_positions), labels)
    ax_time.invert_yaxis()
    ax_time.set_xlabel("Milliseconds")
    ax_time.xaxis.set_major_formatter(FuncFormatter(lambda value, _: format_number(value)))
    ax_time.bar_label(bars, labels=[format_ms(value) for value in times], padding=6, color=TEXT_COLOR, fontsize=9)
    ax_time.set_xlim(0, max(times) * 1.22)

    style_axis(ax_buffers)
    add_panel_title(ax_buffers, "Top-level shared buffers", "Blocks reported by EXPLAIN BUFFERS")
    hits = [float(resources.loc[scenario, "shared_hit_blocks"]) for scenario in ordered_scenarios]
    reads = [float(resources.loc[scenario, "shared_read_blocks"]) for scenario in ordered_scenarios]
    hit_bars = ax_buffers.barh(y_positions, hits, color=colors, height=0.52, label="shared hit")
    ax_buffers.barh(y_positions, reads, left=hits, color=READ_COLOR, height=0.52, label="shared read")
    ax_buffers.set_yticks(list(y_positions), labels)
    ax_buffers.invert_yaxis()
    ax_buffers.set_xlabel("Blocks")
    ax_buffers.xaxis.set_major_formatter(FuncFormatter(lambda value, _: format_number(value)))
    ax_buffers.legend(frameon=False, loc="lower right", fontsize=8)
    buffer_totals = [hit + read for hit, read in zip(hits, reads)]
    ax_buffers.bar_label(
        hit_bars,
        labels=[format_number(total) for total in buffer_totals],
        padding=6,
        color=TEXT_COLOR,
        fontsize=9,
    )
    ax_buffers.set_xlim(0, max(buffer_totals) * 1.22 if max(buffer_totals) else 1)

    style_axis(ax_rows)
    add_panel_title(ax_rows, "Rows removed by filter", "Work avoided by the index path")
    rows_removed = [float(resources.loc[scenario, "rows_removed_by_filter"]) for scenario in ordered_scenarios]
    row_bars = ax_rows.barh(y_positions, rows_removed, color=colors, height=0.52)
    ax_rows.set_yticks(list(y_positions), labels)
    ax_rows.invert_yaxis()
    ax_rows.set_xlabel("Rows")
    ax_rows.xaxis.set_major_formatter(FuncFormatter(lambda value, _: format_number(value)))
    ax_rows.bar_label(
        row_bars,
        labels=[format_number(value) for value in rows_removed],
        padding=6,
        color=TEXT_COLOR,
        fontsize=9,
    )
    ax_rows.set_xlim(0, max(rows_removed) * 1.22 if max(rows_removed) else 1)

    ax_details.set_facecolor(PANEL_COLOR)
    ax_details.set_xticks([])
    ax_details.set_yticks([])
    for spine in ax_details.spines.values():
        spine.set_visible(False)
    add_panel_title(ax_details, "Plan resource details", "Values extracted from resource-summary.csv")

    detail_rows = [
        ("Sort memory", "sort_memory_kb", "kB"),
        ("Workers launched", "workers_launched", ""),
        ("Shared reads", "shared_read_blocks", "blocks"),
    ]
    y = 0.72
    ax_details.text(0.38, 0.84, "Before", transform=ax_details.transAxes, fontsize=9, color=MUTED_TEXT_COLOR, ha="right")
    ax_details.text(0.63, 0.84, "After", transform=ax_details.transAxes, fontsize=9, color=MUTED_TEXT_COLOR, ha="right")
    for label, column, unit in detail_rows:
        before_value = float(resources.loc["before_index", column])
        after_value = float(resources.loc["after_index", column])
        before_text = format_number(before_value)
        after_text = format_number(after_value)
        if unit:
            before_text = f"{before_text} {unit}"
            after_text = f"{after_text} {unit}"
        ax_details.text(0.04, y, label, transform=ax_details.transAxes, fontsize=10, color=TEXT_COLOR)
        ax_details.text(0.38, y, before_text, transform=ax_details.transAxes, fontsize=10, color=BEFORE_COLOR, ha="right")
        ax_details.text(0.63, y, after_text, transform=ax_details.transAxes, fontsize=10, color=AFTER_COLOR, ha="right")
        y -= 0.18

    ax_details.text(
        0.04,
        0.08,
        "Note: these are PostgreSQL plan-level indicators, not OS-level CPU or RAM metrics.",
        transform=ax_details.transAxes,
        fontsize=8.5,
        color=MUTED_TEXT_COLOR,
    )

    fig.savefig(OUTPUT_PATH, dpi=180, bbox_inches="tight")
    fig.savefig(LEGACY_OUTPUT_PATH, dpi=180, bbox_inches="tight")
    plt.close(fig)

    print(f"Chart saved to {OUTPUT_PATH}")
    print(f"Compatibility copy saved to {LEGACY_OUTPUT_PATH}")


if __name__ == "__main__":
    main()

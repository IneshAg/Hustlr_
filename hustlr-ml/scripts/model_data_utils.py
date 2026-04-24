from __future__ import annotations

from typing import Iterable, Tuple

import numpy as np
import pandas as pd
from sklearn.model_selection import GroupShuffleSplit
import re


def normalize_text_groups(series: pd.Series) -> pd.Series:
    return (
        series.fillna("")
        .astype(str)
        .str.strip()
        .str.lower()
        .str.replace(r"\s+", " ", regex=True)
    )


def template_text_groups(series: pd.Series, zones: Iterable[str] | None = None) -> pd.Series:
    normalized = normalize_text_groups(series)
    if zones:
        escaped = [re.escape(str(z).strip().lower()) for z in zones if str(z).strip()]
        for zone in sorted(set(escaped), key=len, reverse=True):
            normalized = normalized.str.replace(rf"\b{zone}\b", "<zone>", regex=True)
    normalized = normalized.str.replace(r"\b\d+([.:/-]\d+)?\b", "<num>", regex=True)
    return normalized.str.replace(r"\s+", " ", regex=True).str.strip()


def cap_group_rows(
    df: pd.DataFrame,
    group_col: str,
    max_rows_per_group: int,
    random_state: int = 42,
) -> pd.DataFrame:
    if max_rows_per_group <= 0:
        raise ValueError("max_rows_per_group must be positive")

    parts = []
    for _, part in df.groupby(group_col, sort=False):
        parts.append(
            part.sample(
                n=min(len(part), max_rows_per_group),
                random_state=random_state,
            )
        )
    return pd.concat(parts, ignore_index=True)


def grouped_train_test_indices(
    groups: Iterable,
    test_size: float = 0.2,
    random_state: int = 42,
) -> Tuple[np.ndarray, np.ndarray]:
    groups_arr = np.asarray(list(groups))
    splitter = GroupShuffleSplit(
        n_splits=1,
        test_size=test_size,
        random_state=random_state,
    )
    train_idx, test_idx = next(
        splitter.split(np.zeros(len(groups_arr)), groups=groups_arr)
    )
    return train_idx, test_idx


def month_groups(series: pd.Series) -> pd.Series:
    dt = pd.to_datetime(series, errors="coerce")
    out = dt.dt.to_period("M").astype("string")
    return out.fillna("unknown")

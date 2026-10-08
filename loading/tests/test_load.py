"""Tests de la logique pure de load.py, sans appel à GCP ni à dbt."""

import json
from pathlib import Path

import pytest

from load import (
    SNAPSHOT_UNIQUE_ID,
    SOURCE_UNIQUE_ID,
    VolumeError,
    check_volume,
    read_relations,
    select_runs,
)

PREFIX = "france-travail/offers"


def test_select_runs_keeps_only_completed_runs_in_order() -> None:
    blobs = [
        f"{PREFIX}/ingested_at=20261009T050000Z/part-1.jsonl",
        f"{PREFIX}/ingested_at=20261009T050000Z/_SUCCESS",
        f"{PREFIX}/ingested_at=20261008T050000Z/_SUCCESS",
        f"{PREFIX}/ingested_at=20261010T050000Z/part-1.jsonl",  # sans _SUCCESS
    ]
    assert select_runs(blobs, None) == ["20261008T050000Z", "20261009T050000Z"]


def test_select_runs_skips_runs_up_to_marker() -> None:
    blobs = [
        f"{PREFIX}/ingested_at=20261007T050000Z/_SUCCESS",
        f"{PREFIX}/ingested_at=20261008T050000Z/_SUCCESS",
        f"{PREFIX}/ingested_at=20261009T050000Z/_SUCCESS",
    ]
    assert select_runs(blobs, "20261008T050000Z") == ["20261009T050000Z"]


def test_select_runs_ignores_unexpected_names() -> None:
    blobs = [
        f"{PREFIX}/ingested_at=2026-10-08/_SUCCESS",
        f"{PREFIX}/other/_SUCCESS",
    ]
    assert select_runs(blobs, None) == []


def test_check_volume_rejects_empty_run() -> None:
    with pytest.raises(VolumeError, match="aucune offre"):
        check_volume("20261008T050000Z", 0, 0, 0.8)


def test_check_volume_rejects_low_ratio() -> None:
    with pytest.raises(VolumeError, match="anormalement bas"):
        check_volume("20261008T050000Z", 700, 1000, 0.8)


@pytest.mark.parametrize(
    ("run_count", "open_versions", "min_ratio"),
    [
        (800, 1000, 0.8),  # au seuil
        (10, 0, 0.8),  # premier run, sans référence
        (1, 1000, 0.0),  # forcé
    ],
)
def test_check_volume_accepts(
    run_count: int, open_versions: int, min_ratio: float
) -> None:
    check_volume("20261008T050000Z", run_count, open_versions, min_ratio)


def test_read_relations(tmp_path: Path) -> None:
    manifest = tmp_path / "manifest.json"
    manifest.write_text(
        json.dumps(
            {
                "nodes": {
                    SNAPSHOT_UNIQUE_ID: {"relation_name": "`p`.`analytics`.`snap`"}
                },
                "sources": {SOURCE_UNIQUE_ID: {"relation_name": "`p`.`raw`.`ext`"}},
            }
        )
    )
    assert read_relations(manifest) == ("`p`.`analytics`.`snap`", "`p`.`raw`.`ext`")

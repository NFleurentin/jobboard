"""Tests de `parse_response` sur une réponse enregistrée (données fictives)."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest
import requests

from tap_francetravail.streams import OffersStream
from tap_francetravail.tap import TapFranceTravail

FIXTURES_DIR = Path(__file__).parent / "fixtures"
INGESTED_AT = "20261007T050000Z"


def make_response(status_code: int, content: bytes) -> requests.Response:
    """Réponse HTTP construite localement, sans appel réseau."""
    response = requests.Response()
    response.status_code = status_code
    response._content = content
    response.encoding = "utf-8"
    return response


def parse(response: requests.Response) -> list[dict[str, Any]]:
    """Parse une réponse avec le stream `offers` d'un tap configuré à vide."""
    tap = TapFranceTravail(
        config={
            "client_id": "test",
            "client_secret": "test",
            "search_queries": [{"keywords": "data engineer"}],
        },
        parse_env_config=False,
    )
    return list(OffersStream(tap).parse_response(response))


@pytest.fixture
def page() -> bytes:
    return (FIXTURES_DIR / "offers_search_page.json").read_bytes()


def test_records_have_fixed_shape(page: bytes, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("INGESTED_AT", INGESTED_AT)

    records = parse(make_response(206, page))

    assert len(records) == 2
    for record in records:
        assert set(record) == {
            "id",
            "dateActualisation",
            "_raw",
            "_extracted_at",
            "_ingested_at",
        }
        assert record["_ingested_at"] == "2026-10-07T05:00:00+00:00"
    assert [r["id"] for r in records] == ["000TEST1", "000TEST2"]
    assert records[0]["dateActualisation"] == "2026-10-01T09:30:00.000Z"


def test_raw_is_the_full_offer_serialized_as_text(
    page: bytes, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("INGESTED_AT", INGESTED_AT)
    offers = json.loads(page)["resultats"]

    records = parse(make_response(206, page))

    for record, offer in zip(records, offers, strict=True):
        # Une chaîne, pas un objet : évite le bug Decimal du target
        assert isinstance(record["_raw"], str)
        assert json.loads(record["_raw"]) == offer
    # Accents conservés tels quels (ensure_ascii=False)
    assert "é, è, à, ç" in records[1]["_raw"]


@pytest.mark.parametrize(("status_code", "content"), [(204, b""), (200, b"  \n")])
def test_empty_response_yields_no_record(status_code: int, content: bytes) -> None:
    assert parse(make_response(status_code, content)) == []


def test_missing_ingested_at_fails(
    page: bytes, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.delenv("INGESTED_AT", raising=False)

    with pytest.raises(KeyError, match="INGESTED_AT"):
        parse(make_response(206, page))

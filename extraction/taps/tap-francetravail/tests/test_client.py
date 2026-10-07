"""Tests du stream `offers` : `parse_response` sur une réponse enregistrée (données fictives) et contrôle du plafond de l'API."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest
import requests
from singer_sdk.exceptions import FatalAPIError

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


def make_stream() -> OffersStream:
    """Stream `offers` d'un tap configuré à vide."""
    tap = TapFranceTravail(
        config={
            "client_id": "test",
            "client_secret": "test",
            "search_queries": [{"keywords": "data engineer"}],
        },
        parse_env_config=False,
    )
    return OffersStream(tap)


def parse(response: requests.Response) -> list[dict[str, Any]]:
    """Parse une réponse avec le stream `offers` d'un tap configuré à vide."""
    return list(make_stream().parse_response(response))


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


def make_ranged_response(
    status_code: int, content_range: str | None
) -> requests.Response:
    """Réponse paginée, avec ou sans en-tête Content-Range."""
    response = make_response(status_code, b"")
    response.url = "https://api.example.test/offres/search?motsCles=sql&range=0-149"
    if content_range is not None:
        response.headers["Content-Range"] = content_range
    return response


@pytest.mark.parametrize(
    ("status_code", "content_range"),
    [
        (206, "offres 0-149/3150"),  # pile au plafond : lisible jusqu'à 3149
        (206, "offres 0-149/151"),
        (200, None),  # une seule page : pas de contrôle
        (204, None),  # aucun résultat
    ],
)
def test_validate_response_accepts_query_within_cap(
    status_code: int, content_range: str | None
) -> None:
    make_stream().validate_response(make_ranged_response(status_code, content_range))


def test_validate_response_fails_above_cap() -> None:
    response = make_ranged_response(206, "offres 0-149/3151")

    with pytest.raises(FatalAPIError, match="3151 results"):
        make_stream().validate_response(response)


@pytest.mark.parametrize("content_range", [None, "", "offres 0-149"])
def test_validate_response_fails_without_total(content_range: str | None) -> None:
    response = make_ranged_response(206, content_range)

    with pytest.raises(FatalAPIError, match="Content-Range"):
        make_stream().validate_response(response)

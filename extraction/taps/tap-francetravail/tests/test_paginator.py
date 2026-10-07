"""Tests du paginateur par `range` (HTTP 206 et plafond de 1 150 résultats)."""

from __future__ import annotations

import pytest
import requests

from tap_francetravail.paginator import FranceTravailPaginator

PAGE_SIZE = 150


def make_response(status_code: int) -> requests.Response:
    """Réponse HTTP minimale : seul le code de statut compte pour le paginateur."""
    response = requests.Response()
    response.status_code = status_code
    return response


@pytest.mark.parametrize(
    ("offset", "status_code", "expected"),
    [
        (0, 206, True),  # contenu partiel : il reste des pages
        (0, 200, False),  # tout le résultat tient dans la page
        (750, 206, True),  # prochaine page 900-1049, sous le plafond
        (900, 206, True),  # prochaine page ramenée à 1000-1149
        (1000, 206, False),  # 1000-1149 est la dernière page autorisée
    ],
)
def test_has_more(offset: int, status_code: int, expected: bool) -> None:
    paginator = FranceTravailPaginator(start_value=offset, page_size=PAGE_SIZE)

    assert paginator.has_more(make_response(status_code)) is expected


def test_pagination_stops_at_api_cap() -> None:
    """Avec des 206 en continu, le parcours s'arrête au plafond de l'API."""
    paginator = FranceTravailPaginator(start_value=0, page_size=PAGE_SIZE)
    offsets = []

    while not paginator.finished:
        offsets.append(paginator.current_value)
        paginator.advance(make_response(206))

    assert offsets == [0, 150, 300, 450, 600, 750, 900, 1000]

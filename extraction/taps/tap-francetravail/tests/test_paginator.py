"""Tests du paginateur par `range` (HTTP 206, total et plafond de 3 150 résultats)."""

from __future__ import annotations

import pytest
import requests

from tap_francetravail.paginator import FranceTravailPaginator, parse_total

PAGE_SIZE = 150


def make_response(status_code: int, total: int | None = None) -> requests.Response:
    """Réponse HTTP minimale : code de statut et, si fourni, total du Content-Range."""
    response = requests.Response()
    response.status_code = status_code
    if total is not None:
        response.headers["Content-Range"] = f"offres 0-149/{total}"
    return response


def paginate(status_code: int, total: int) -> list[int]:
    """Offsets demandés jusqu'à l'arrêt, chaque réponse portant le même total."""
    paginator = FranceTravailPaginator(start_value=0, page_size=PAGE_SIZE)
    offsets = []

    while not paginator.finished:
        offsets.append(paginator.current_value)
        paginator.advance(make_response(status_code, total))

    return offsets


@pytest.mark.parametrize(
    ("content_range", "expected"),
    [
        ("offres 0-149/2345", 2345),
        ("offres 0-149/", None),
        ("", None),
    ],
)
def test_parse_total(content_range: str, expected: int | None) -> None:
    response = requests.Response()
    response.headers["Content-Range"] = content_range

    assert parse_total(response) == expected


@pytest.mark.parametrize(
    ("offset", "status_code", "total", "expected"),
    [
        (0, 206, 3150, True),  # contenu partiel : il reste des pages
        (0, 200, None, False),  # tout le résultat tient dans la page
        (750, 206, 3150, True),  # prochaine page 900-1049, sous le plafond
        (2850, 206, 3150, True),  # prochaine page 3000-3149, la dernière autorisée
        (3000, 206, 3150, False),  # 3000-3149 est la dernière page autorisée
        (1800, 206, 1876, False),  # 1800-1949 contient le dernier résultat
        (1800, 206, 1950, False),  # total multiple de 150 : 1800-1949 est la dernière
        (1800, 206, 1951, True),  # un résultat reste sur la page 1950-2099
    ],
)
def test_has_more(
    offset: int, status_code: int, total: int | None, expected: bool
) -> None:
    paginator = FranceTravailPaginator(start_value=offset, page_size=PAGE_SIZE)

    assert paginator.has_more(make_response(status_code, total)) is expected


def test_pagination_stops_after_last_result() -> None:
    """Pas de page vide demandée au-delà du total, même si l'API répond 206."""
    assert paginate(206, 1876) == list(range(0, 1801, PAGE_SIZE))


def test_pagination_stops_at_api_cap() -> None:
    """Au plafond de l'API, le parcours s'arrête à la page 3000-3149."""
    assert paginate(206, 3150) == list(range(0, 3001, PAGE_SIZE))

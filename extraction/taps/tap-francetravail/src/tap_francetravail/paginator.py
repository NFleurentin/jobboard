import re

import requests
from singer_sdk.pagination import OffsetPaginator


def parse_total(response: requests.Response) -> int | None:
    """Total de résultats de la requête, lu dans l'en-tête Content-Range.

    Format attendu : "offres 0-149/2345", le total après le "/".
    Renvoie None si l'en-tête est absent ou illisible.
    """
    content_range = response.headers.get("Content-Range", "")
    match = re.search(r"/(\d+)$", content_range)
    return int(match.group(1)) if match else None


class FranceTravailPaginator(OffsetPaginator):
    """Pagination by 'range', capped at 3150 results (API limit)."""

    MAX_OFFSET = 3000  # the lower bound of the last allowed range is 3000-3149

    def has_more(self, response: requests.Response) -> bool:
        # 200 = the entire result fit in the requested range -> done
        # 206 = there are more pages (Partial Content)
        if response.status_code != 206:
            return False

        # L'API peut répondre 206 sur la page qui contient le dernier
        # résultat : le total évite de demander une page vide au-delà.
        # Sans total lisible, validate_response a déjà fait échouer le run.
        total = parse_total(response)
        if total is not None and self._value + self.page_size >= total:
            return False

        # La page à l'offset MAX_OFFSET est la dernière autorisée par l'API
        return self._value < self.MAX_OFFSET

    def get_next(self, response: requests.Response) -> int:
        # Garde-fou si la taille de page change : un offset au-delà de
        # MAX_OFFSET serait refusé par l'API, la dernière page y est ramenée.
        return min(self._value + self.page_size, self.MAX_OFFSET)

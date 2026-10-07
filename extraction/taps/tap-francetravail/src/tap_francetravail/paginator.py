import requests
from singer_sdk.pagination import OffsetPaginator


class FranceTravailPaginator(OffsetPaginator):
    """Pagination by 'range', capped at 1150 results (API limit)."""

    MAX_OFFSET = 1000  # the lower bound of the last allowed range is 1000-1149

    def has_more(self, response: requests.Response) -> bool:
        # 200 = the entire result fit in the requested range -> done
        # 206 = there are more pages (Partial Content)
        if response.status_code != 206:
            return False

        # La page à l'offset MAX_OFFSET est la dernière autorisée par l'API
        return self._value < self.MAX_OFFSET

    def get_next(self, response: requests.Response) -> int:
        # Pas de 150 non aligné sur 1000 (900 -> 1050, refusé par l'API) :
        # la dernière page est ramenée à 1000-1149 et recouvre 1000-1049.
        return min(self._value + self.page_size, self.MAX_OFFSET)

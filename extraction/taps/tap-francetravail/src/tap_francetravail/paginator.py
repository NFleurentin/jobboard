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

        return self._value + self.page_size <= self.MAX_OFFSET

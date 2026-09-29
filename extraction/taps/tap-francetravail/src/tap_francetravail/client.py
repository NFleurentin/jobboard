"""REST client handling, including FranceTravailStream base class."""

from __future__ import annotations

import decimal
import json
import sys
from datetime import UTC, datetime
from functools import cached_property
from typing import TYPE_CHECKING, Any

from singer_sdk import SchemaDirectory, StreamSchema
from singer_sdk.helpers.jsonpath import extract_jsonpath
from singer_sdk.streams import RESTStream

from tap_francetravail import schemas
from tap_francetravail.auth import FranceTravailAuthenticator
from tap_francetravail.paginator import FranceTravailPaginator

if sys.version_info >= (3, 12):
    from typing import override
else:
    from typing_extensions import override

if TYPE_CHECKING:
    from collections.abc import Iterable

    import requests
    from singer_sdk.helpers.types import Auth
    from singer_sdk.streams.rest import HTTPRequest, PageContext


SCHEMAS_DIR = SchemaDirectory(schemas)

class FranceTravailStream(RESTStream):
    """FranceTravail stream class."""

    # Update this value if necessary or override `parse_response`.
    records_jsonpath = "$.resultats[*]"

    schema = StreamSchema(SCHEMAS_DIR)

    @override
    @property
    def url_base(self) -> str:
        """The API URL root, configurable via tap settings."""
        return "https://api.francetravail.io/partenaire/offresdemploi/v2"

    @override
    @cached_property
    def authenticator(self) -> Auth:
        """An authenticator object."""
        return FranceTravailAuthenticator(
            client_id=self.config["client_id"],
            client_secret=self.config["client_secret"],
            auth_endpoint="https://entreprise.francetravail.fr/connexion/oauth2/access_token?realm=/partenaire",
            oauth_scopes=self.config.get("scope", "api_offresdemploiv2 o2dsoffre"),
        )

    @property
    @override
    def http_headers(self) -> dict:
        """A dictionary of HTTP headers."""
        return {}

    @override
    def get_new_paginator(self) -> FranceTravailPaginator:
        return FranceTravailPaginator(start_value=0, page_size=150)

    @override
    def get_http_request(self, *, page: PageContext[Any]) -> HTTPRequest:
        """Return a request object for this stream.

        Args:
            page: An object containing the stream partition or context dictionary,
                and the next page token if applicable.

        Returns:
            An HTTP request for this stream.
        """
        request = super().get_http_request(page=page)

        return request

    @override
    def parse_response(self, response: requests.Response) -> Iterable[dict]:
        """Parse the response and return an iterator of result records.

        Args:
            response: The HTTP ``requests.Response`` object.

        Yields:
            Each record from the source.
        """
        if response.status_code == 204 or not response.text.strip():
            return []

        # Payload complet
        payload = response.json(parse_float=decimal.Decimal)

        # Extraction des records
        for record in extract_jsonpath(self.records_jsonpath, input=payload):

            # On ne garde que id + dateActualisation
            minimal_record = {
                "id": record.get("id"),
                "dateActualisation": record.get("dateActualisation"),
                "_raw": json.dumps(record, default=str),  # payload brut complet
                "_extracted_at": datetime.now(UTC).isoformat(),  # date d'extraction
            }

            yield minimal_record

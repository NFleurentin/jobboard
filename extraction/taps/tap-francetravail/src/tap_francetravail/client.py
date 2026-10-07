"""REST client handling, including FranceTravailStream base class."""

from __future__ import annotations

import json
import os
from datetime import UTC, datetime
from functools import cached_property
from typing import TYPE_CHECKING, Any, override

from singer_sdk import SchemaDirectory, StreamSchema
from singer_sdk.helpers.jsonpath import extract_jsonpath
from singer_sdk.streams import RESTStream

from tap_francetravail import schemas
from tap_francetravail.auth import FranceTravailAuthenticator
from tap_francetravail.paginator import FranceTravailPaginator

if TYPE_CHECKING:
    from collections.abc import Iterable

    import requests
    from singer_sdk.helpers.types import Auth


SCHEMAS_DIR = SchemaDirectory(schemas)


class FranceTravailStream(RESTStream):
    """FranceTravail stream class."""

    # Update this value if necessary or override `parse_response`.
    records_jsonpath = "$.resultats[*]"

    schema = StreamSchema(SCHEMAS_DIR)

    @override
    @property
    def url_base(self) -> str:
        """Racine de l'API Offres d'emploi v2, en dur (non configurable)."""
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

    @override
    def get_new_paginator(self) -> FranceTravailPaginator:
        return FranceTravailPaginator(start_value=0, page_size=150)

    @override
    def parse_response(self, response: requests.Response) -> Iterable[dict[str, Any]]:
        """Parse the response and return an iterator of result records.

        Args:
            response: The HTTP ``requests.Response`` object.

        Yields:
            Each record from the source.
        """
        if response.status_code == 204 or not response.text.strip():
            return

        # Payload complet
        payload = response.json()

        # Extraction des records
        for record in extract_jsonpath(self.records_jsonpath, input=payload):
            # On ne garde que id + dateActualisation
            minimal_record = {
                "id": record.get("id"),
                "dateActualisation": record.get("dateActualisation"),
                "_raw": json.dumps(record, ensure_ascii=False),  # payload brut complet
                "_extracted_at": datetime.now(UTC).isoformat(),  # date d'extraction
                "_ingested_at": datetime.strptime(
                    os.environ["INGESTED_AT"], "%Y%m%dT%H%M%SZ"
                )
                .replace(tzinfo=UTC)
                .isoformat(),
            }

            yield minimal_record

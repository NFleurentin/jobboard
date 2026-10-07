"""REST client handling, including FranceTravailStream base class."""

from __future__ import annotations

import json
import os
from datetime import UTC, datetime
from functools import cached_property
from typing import TYPE_CHECKING, Any, override

from singer_sdk import SchemaDirectory, StreamSchema
from singer_sdk.exceptions import FatalAPIError
from singer_sdk.helpers.jsonpath import extract_jsonpath
from singer_sdk.streams import RESTStream

from tap_francetravail import schemas
from tap_francetravail.auth import FranceTravailAuthenticator
from tap_francetravail.paginator import FranceTravailPaginator, parse_total

if TYPE_CHECKING:
    from collections.abc import Iterable

    import requests
    from singer_sdk.helpers.types import Auth, Context


SCHEMAS_DIR = SchemaDirectory(schemas)

# Format de l'identifiant de run, fixé par l'appelant (run.sh)
INGESTED_AT_FORMAT = "%Y%m%dT%H%M%SZ"

# Plafond de l'API : index de début <= 3000, index de fin <= 3149
MAX_RESULTS = 3150


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

    @cached_property
    def ingested_at(self) -> str:
        """Identifiant du run lu depuis `INGESTED_AT`, validé et converti une seule fois."""
        value = os.environ.get("INGESTED_AT")
        hint = "export INGESTED_AT=$(date -u +%Y%m%dT%H%M%SZ)"
        if not value:
            msg = f"INGESTED_AT is not set: the caller must define it before the run ({hint})"
            raise ValueError(msg)
        try:
            parsed = datetime.strptime(value, INGESTED_AT_FORMAT)
        except ValueError:
            msg = f"INGESTED_AT={value!r} does not match the expected format YYYYMMDDTHHMMSSZ ({hint})"
            raise ValueError(msg) from None
        return parsed.replace(tzinfo=UTC).isoformat()

    @override
    def get_records(self, context: Context | None) -> Iterable[dict[str, Any]]:
        """Valide `INGESTED_AT` avant le premier appel à l'API, puis délègue au SDK."""
        _ = self.ingested_at
        yield from super().get_records(context)

    @override
    def get_new_paginator(self) -> FranceTravailPaginator:
        return FranceTravailPaginator(start_value=0, page_size=150)

    @override
    def validate_response(self, response: requests.Response) -> None:
        """Échoue si le total d'une requête dépasse le plafond de l'API.

        Au-delà de 3 150 résultats, l'API ne renvoie pas la suite : une requête
        tronquée fausserait le snapshot dbt (offres non lues marquées closes).
        Seules les 206 sont contrôlées : une 200 ou une 204 tient en une page.
        """
        super().validate_response(response)

        if response.status_code != 206:
            return

        total = parse_total(response)
        if total is None:
            content_range = response.headers.get("Content-Range", "")
            msg = f"Missing or unreadable Content-Range header ({content_range!r}) for {response.url}"
            raise FatalAPIError(msg, response)

        if total > MAX_RESULTS:
            msg = (
                f"Query returns {total} results, above the API cap of {MAX_RESULTS}: "
                f"split it into narrower search_queries ({response.url})"
            )
            raise FatalAPIError(msg, response)

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
                "_ingested_at": self.ingested_at,
            }

            yield minimal_record

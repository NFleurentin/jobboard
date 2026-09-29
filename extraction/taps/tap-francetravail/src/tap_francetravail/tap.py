"""FranceTravail tap class."""

from __future__ import annotations

import sys

from singer_sdk import Tap
from singer_sdk import typing as th  # JSON schema typing helpers

# TODO: Import your custom stream types here:
from tap_francetravail import streams

if sys.version_info >= (3, 12):
    from typing import override
else:
    from typing_extensions import override


class TapFranceTravail(Tap):
    """Singer tap for FranceTravail."""

    name = "tap-francetravail"

    config_jsonschema = th.PropertiesList(
        th.Property(
            "client_id",
            th.StringType,
            required=True,
            description="Client ID",
        ),
        th.Property(
            "client_secret",
            th.StringType,
            required=True,
            secret=True,
            description="Client secret",
        ),
        th.Property(
            "scope",
            th.StringType,
            default="api_offresdemploiv2 o2dsoffre",
            description="List of technical and application scopes corresponding to the APIs you want to manipulate (separated by spaces)",
        ),
        th.Property(
            "search_queries",
            th.ArrayType(
                th.ObjectType(
                    th.Property(
                        "keywords",
                        th.StringType,
                        description="""Each keyword (or phrase) must be at least 2 characters long and separated by a comma.

Searching with multiple keywords is handled using the logical "AND" operator.

Keyword search can be performed on:

    The job title (field intitule in the search response)
    The ROME code (field romeCode in the search response)
    The ROME label (field romeLibelle in the search response)
    The skills label (field competences.libelle in the search response)
    The training domains label (field formations.domaineLibelle in the search response)
    The permits label (field permis.libelle in the search response)
    The languages label (field langues.libelle in the search response)
    The job description if found in the job title and/or the ROME label (field description in the search response)

Allowed characters: [aA-zZ]+[0-9]+[space]+[@#$%^&+./-"]
""",
                        examples=["data engineer,data scientist"],
                    ),
                    th.Property(
                        "department",
                        th.StringType,
                        description="Department of the job offer. Up to 5 values possible, separated by a comma.",
                        examples=["75,92,93,94"],
                    ),
                ),
            ),
            required=True,
            description="List of independent searches, each executed separately",
        ),
    ).to_dict()

    @override
    def discover_streams(self) -> list[streams.FranceTravailStream]:
        """Return a list of discovered streams.

        Returns:
            A list of discovered streams.
        """
        return [
            streams.OffersStream(self),
        ]


if __name__ == "__main__":
    TapFranceTravail.cli()

"""Stream type classes for tap-francetravail."""

from __future__ import annotations

from typing import Any, override

from tap_francetravail.client import FranceTravailStream


class OffersStream(FranceTravailStream):
    """Define custom stream."""

    name = "offers"
    path = "/offres/search"
    primary_keys = ("id", "dateActualisation")
    replication_key = None

    @property
    def partitions(self) -> list[dict]:
        return self.config.get("search_queries", [])

    @override
    def get_url_params(self, context, next_page_token) -> dict:
        params: dict[str, Any] = {}
        context = context or {}

        if context.get("keywords"):
            params["motsCles"] = context["keywords"]
        if context.get("department"):
            params["departement"] = context["department"]

        offset = next_page_token or 0
        page_size = self.get_new_paginator().page_size
        params["range"] = f"{offset}-{offset + page_size - 1}"

        self.logger.info(f"Request params: {params}")

        return params

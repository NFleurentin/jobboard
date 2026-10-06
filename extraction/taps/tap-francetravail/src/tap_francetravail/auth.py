"""FranceTravail Authentication."""

from __future__ import annotations

from typing import override

from singer_sdk.authenticators import OAuthAuthenticator, SingletonMeta


# The SingletonMeta metaclass makes your streams reuse the same authenticator instance.
class FranceTravailAuthenticator(OAuthAuthenticator, metaclass=SingletonMeta):
    """Authenticator class for FranceTravail."""

    @override
    @property
    def oauth_request_body(self) -> dict:
        """The OAuth request body for the FranceTravail API."""

        return {
            "grant_type": "client_credentials",
            "client_id": self.client_id,
            "client_secret": self.client_secret,
            "scope": self.oauth_scopes,
        }

"""Fait entrer dans le snapshot dbt les runs d'extraction terminés (issue #85).

Le brut reste dans GCS, lu par la table externe raw.france_travail_offers_ext.
Ce script choisit les runs à traiter et les passe un par un au snapshot :

1. dernier run traité = plus grande borne du snapshot (toutes les bornes
   valent l'horodatage d'un run, voir la macro bigquery__snapshot_get_time) ;
2. runs à traiter = dossiers du bucket qui contiennent _SUCCESS (écrit par
   extraction/run.sh), postérieurs à ce marqueur, du plus ancien au plus récent ;
3. pour chaque run : garde-fou de volume, puis `dbt snapshot` ; le premier
   échec arrête la boucle, un run n'est jamais traité avant un plus ancien ;
4. `dbt build` des modèles en aval du snapshot si au moins un run est passé.

Un run sans aucun changement n'avance pas le marqueur : il est rejoué, sans
effet, au passage suivant. Le target dbt n'est pas choisi ici : profil par
défaut, ou DBT_TARGET fourni par l'appelant.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import re
import subprocess
import sys
from collections.abc import Iterable
from pathlib import Path

from google.api_core.exceptions import NotFound
from google.cloud import bigquery
from google.cloud.storage import Client as StorageClient

log = logging.getLogger("load")

TRANSFORMATION_DIR = Path(__file__).resolve().parent.parent / "transformation"
SNAPSHOT = "snap_france_travail__offers"
SNAPSHOT_UNIQUE_ID = f"snapshot.jobboard.{SNAPSHOT}"
SOURCE_UNIQUE_ID = "source.jobboard.raw.france_travail_offers_ext"

# Même chemin que key_naming_convention dans
# extraction/plugins/loaders/target-gcs--francetravail.meltano.yml.
RUNS_PREFIX = "france-travail/offers/"
SUCCESS_PATTERN = re.compile(r"ingested_at=(\d{8}T\d{6}Z)/_SUCCESS$")
INGESTED_AT_FORMAT = "%Y%m%dT%H%M%SZ"

DEFAULT_MIN_VOLUME_RATIO = 0.8
MAXIMUM_BYTES_BILLED = 10_000_000_000  # comme maximum_bytes_billed de profiles.yml
TIMEOUT_SECONDS = 300


class VolumeError(Exception):
    """Run trop petit pour être snapshoté sans risque."""


def select_runs(blob_names: Iterable[str], marker: str | None) -> list[str]:
    """Runs terminés (avec _SUCCESS) postérieurs au marqueur, du plus ancien au plus récent.

    Le format %Y%m%dT%H%M%SZ se trie dans l'ordre chronologique : la
    comparaison de chaînes suffit.
    """
    runs = {
        match.group(1) for name in blob_names if (match := SUCCESS_PATTERN.search(name))
    }
    return sorted(run for run in runs if marker is None or run > marker)


def check_volume(
    run: str, run_count: int, open_versions: int, min_ratio: float
) -> None:
    """Fait échouer un run vide, ou trop petit par rapport aux offres ouvertes.

    hard_deletes: invalidate clôt toute offre absente du run : une extraction
    partielle fermerait à tort des milliers d'offres dans un historique
    irremplaçable. La référence est le nombre de versions ouvertes du
    snapshot, soit les offres du dernier run traité. Sans référence (premier
    run), seul le run vide est refusé.
    """
    if run_count == 0:
        raise VolumeError(f"Run {run} : aucune offre dans le run, snapshot annulé.")
    if open_versions > 0 and run_count / open_versions < min_ratio:
        raise VolumeError(
            f"Run {run} : volume anormalement bas, {run_count} offres contre "
            f"{open_versions} versions ouvertes dans le snapshot (ratio "
            f"{run_count / open_versions:.3f}, seuil {min_ratio}). Extraction "
            "partielle ? Pour forcer après une baisse assumée : "
            "--min-volume-ratio 0."
        )


def read_relations(manifest_path: Path) -> tuple[str, str]:
    """Noms complets du snapshot et de la source, lus dans le manifest dbt.

    Le dataset du snapshot dépend du target (generate_schema_name) : le
    manifest évite de dupliquer cette logique ici.
    """
    manifest = json.loads(manifest_path.read_text())
    snapshot = manifest["nodes"][SNAPSHOT_UNIQUE_ID]["relation_name"]
    source = manifest["sources"][SOURCE_UNIQUE_ID]["relation_name"]
    return snapshot, source


def query_scalar(
    client: bigquery.Client,
    sql: str,
    parameters: list[bigquery.ScalarQueryParameter] | None = None,
) -> object:
    """Exécute une requête qui renvoie une seule valeur."""
    job_config = bigquery.QueryJobConfig(
        query_parameters=parameters or [],
        maximum_bytes_billed=MAXIMUM_BYTES_BILLED,
    )
    rows = client.query(sql, job_config=job_config, timeout=TIMEOUT_SECONDS).result(
        timeout=TIMEOUT_SECONDS
    )
    return next(iter(rows))[0]


def fetch_marker(client: bigquery.Client, snapshot: str) -> str | None:
    """Dernier run traité : plus grande borne du snapshot, None s'il n'existe pas.

    Le nom de table vient du manifest, pas d'une saisie : un identifiant ne
    peut pas être passé en paramètre de requête.
    """
    sql = f"""
        SELECT FORMAT_TIMESTAMP(
            '{INGESTED_AT_FORMAT}',
            GREATEST(MAX(dbt_valid_from), IFNULL(MAX(dbt_valid_to), MAX(dbt_valid_from)))
        )
        FROM {snapshot}
    """
    try:
        marker = query_scalar(client, sql)
    except NotFound:
        return None
    return marker if isinstance(marker, str) else None


def count_open_versions(client: bigquery.Client, snapshot: str) -> int:
    """Versions ouvertes du snapshot (partition NULL de dbt_valid_to), 0 s'il n'existe pas."""
    sql = f"SELECT COUNT(*) FROM {snapshot} WHERE dbt_valid_to IS NULL"
    try:
        return int(str(query_scalar(client, sql)))
    except NotFound:
        return 0


def count_run(client: bigquery.Client, source: str, run: str) -> int:
    """Offres distinctes du run ; le filtre sur la clé Hive ne lit que son dossier."""
    sql = f"SELECT COUNT(DISTINCT id) FROM {source} WHERE ingested_at = @run"
    parameters = [bigquery.ScalarQueryParameter("run", "STRING", run)]
    return int(str(query_scalar(client, sql, parameters)))


def run_dbt(*args: str) -> bool:
    """Lance une commande dbt dans transformation/, renvoie True si elle réussit."""
    command = ["dbt", *args]
    log.info("Commande : %s", " ".join(command))
    return subprocess.run(command, cwd=TRANSFORMATION_DIR, check=False).returncode == 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--min-volume-ratio",
        type=float,
        default=DEFAULT_MIN_VOLUME_RATIO,
        help="ratio minimum entre les offres du run et les versions ouvertes "
        f"du snapshot (défaut {DEFAULT_MIN_VOLUME_RATIO}, 0 pour forcer)",
    )
    return parser.parse_args()


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    args = parse_args()
    project_id = os.environ.get("GCP_PROJECT_ID")
    if not project_id:
        log.error("GCP_PROJECT_ID doit être défini avant de lancer le script")
        return 1

    if not run_dbt("parse"):
        return 1
    snapshot, source = read_relations(TRANSFORMATION_DIR / "target" / "manifest.json")

    bq_client = bigquery.Client(project=project_id)
    gcs_client = StorageClient(project=project_id)

    marker = fetch_marker(bq_client, snapshot)
    blobs = gcs_client.list_blobs(
        f"{project_id}-raw",
        prefix=RUNS_PREFIX,
        match_glob="**/_SUCCESS",
        timeout=TIMEOUT_SECONDS,
    )
    runs = select_runs((blob.name for blob in blobs), marker)
    log.info("Dernier run traité : %s ; runs à traiter : %s", marker, runs or "aucun")

    processed = 0
    failed = False
    for run in runs:
        try:
            check_volume(
                run,
                count_run(bq_client, source, run),
                count_open_versions(bq_client, snapshot),
                args.min_volume_ratio,
            )
        except VolumeError as error:
            log.error("%s", error)
            failed = True
            break
        if not run_dbt(
            "snapshot", "--select", SNAPSHOT, "--vars", json.dumps({"ingested_at": run})
        ):
            log.error("Run %s : échec du snapshot, runs suivants non traités.", run)
            failed = True
            break
        processed += 1

    if processed and not run_dbt(
        "build", "--select", f"{SNAPSHOT}+", "--exclude", SNAPSHOT
    ):
        failed = True

    log.info(
        "Chargement %s : %d run(s) snapshoté(s) sur %d, projet %s",
        "en échec" if failed else "terminé",
        processed,
        len(runs),
        project_id,
    )
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())

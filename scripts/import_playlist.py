#!/usr/bin/env python3
"""Resumable CSV importer for Apple Music Playlist CLI.

This is intentionally a thin orchestration layer around ``src/am.sh``. It keeps
CSV parsing, exclusions, resume behavior, track-id overrides, and TSV logging in
one reusable place instead of leaving agents to create one-off import scripts.
"""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Iterable, Mapping, Sequence

SUCCESS_STATUSES = {"added", "already_present"}
STATUS_FIELDS = ["row_number", "status", "title", "artist", "track_id", "message"]
TITLE_CANDIDATES = ("title", "track", "track name", "song", "song title", "name")
ARTIST_CANDIDATES = ("artist", "artist name", "performer", "band")


@dataclass(frozen=True)
class CsvColumns:
    title: str
    artist: str


@dataclass
class ImportConfig:
    csv_path: Path
    playlist: str
    mode: str = "add-gui"
    output_dir: Path = Path("runs/import-playlist")
    title_column: str | None = None
    artist_column: str | None = None
    exclude_artists: tuple[str, ...] = ()
    resume: bool = True
    dry_run: bool = False
    wait_seconds: float | None = None
    track_id_map: Path | None = None
    am_script: Path = Path("src/am.sh")
    status_filename: str = "status.tsv"

    @property
    def status_path(self) -> Path:
        return self.output_dir / self.status_filename


@dataclass
class ImportResult:
    added: int = 0
    already_present: int = 0
    skipped_existing: int = 0
    excluded: int = 0
    missing_data: int = 0
    errors: int = 0
    dry_run: int = 0

    def total(self) -> int:
        return sum(self.__dict__.values())


def _canonical(value: str) -> str:
    return " ".join(value.strip().casefold().split())


def _find_column(headers: Iterable[str], candidates: Sequence[str]) -> str | None:
    by_canonical = {_canonical(header): header for header in headers}
    for candidate in candidates:
        if candidate in by_canonical:
            return by_canonical[candidate]
    return None


def detect_columns(headers: Sequence[str], title_column: str | None = None, artist_column: str | None = None) -> CsvColumns:
    if title_column and title_column not in headers:
        raise ValueError(f"title column not found: {title_column}")
    if artist_column and artist_column not in headers:
        raise ValueError(f"artist column not found: {artist_column}")

    title = title_column or _find_column(headers, TITLE_CANDIDATES)
    artist = artist_column or _find_column(headers, ARTIST_CANDIDATES)
    if not title or not artist:
        raise ValueError(
            "Could not detect title/artist columns. "
            "Pass --title-column and --artist-column. "
            f"Headers: {', '.join(headers)}"
        )
    return CsvColumns(title=title, artist=artist)


def normalize_status_rows(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        return [{field: row.get(field, "") or "" for field in STATUS_FIELDS} for row in reader]


def load_track_id_map(path: Path | None) -> dict[str, str]:
    if path is None:
        return {}
    if not path.exists():
        raise FileNotFoundError(path)
    if path.suffix.lower() == ".json":
        data = json.loads(path.read_text(encoding="utf-8"))
        return {_canonical_key(k): str(v).strip() for k, v in data.items() if str(v).strip()}

    mapping: dict[str, str] = {}
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        headers = reader.fieldnames or []
        columns = detect_columns(headers)
        id_column = _find_column(headers, ("track id", "track_id", "trackid", "id"))
        if not id_column:
            raise ValueError("Track ID map CSV needs a track_id/id column")
        for row in reader:
            title = (row.get(columns.title) or "").strip()
            artist = (row.get(columns.artist) or "").strip()
            track_id = (row.get(id_column) or "").strip()
            if title and artist and track_id:
                mapping[_track_key(title, artist)] = track_id
    return mapping


def _track_key(title: str, artist: str) -> str:
    return f"{_canonical(title)}|{_canonical(artist)}"


def _canonical_key(key: str) -> str:
    if "|" not in key:
        return _canonical(key)
    left, right = key.split("|", 1)
    return _track_key(left, right)


class PlaylistImporter:
    def __init__(
        self,
        config: ImportConfig,
        runner: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
    ) -> None:
        self.config = config
        self.runner = runner
        self.track_ids = load_track_id_map(config.track_id_map)
        self.excluded_artists = {_canonical(artist) for artist in config.exclude_artists}

    def run(self) -> ImportResult:
        self.config.output_dir.mkdir(parents=True, exist_ok=True)
        self._ensure_status_header()
        completed_rows = self._completed_row_numbers() if self.config.resume else set()
        result = ImportResult()

        with self.config.csv_path.open(newline="", encoding="utf-8-sig") as f:
            reader = csv.DictReader(f)
            if not reader.fieldnames:
                raise ValueError("CSV has no header row")
            columns = detect_columns(reader.fieldnames, self.config.title_column, self.config.artist_column)

            for row_number, row in enumerate(reader, start=2):
                title = (row.get(columns.title) or "").strip()
                artist = (row.get(columns.artist) or "").strip()
                track_id = self.track_ids.get(_track_key(title, artist), "") if title and artist else ""

                if row_number in completed_rows:
                    self._write_status(row_number, "skipped_existing", title, artist, track_id, "previous successful status found")
                    result.skipped_existing += 1
                    continue
                if not title or not artist:
                    self._write_status(row_number, "missing_data", title, artist, track_id, "missing title or artist")
                    result.missing_data += 1
                    continue
                if _canonical(artist) in self.excluded_artists:
                    self._write_status(row_number, "excluded", title, artist, track_id, "artist excluded")
                    result.excluded += 1
                    continue

                command = self._command(title, artist, track_id)
                if self.config.dry_run:
                    message = " ".join(command)
                    self._write_status(row_number, "dry_run", title, artist, track_id, message)
                    result.dry_run += 1
                    continue

                completed = self.runner(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                message = (completed.stdout or completed.stderr or "").strip().replace("\t", " ").replace("\n", " | ")
                if completed.returncode == 0:
                    status = "already_present" if "already" in message.casefold() else "added"
                    self._write_status(row_number, status, title, artist, track_id, message)
                    if status == "already_present":
                        result.already_present += 1
                    else:
                        result.added += 1
                else:
                    self._write_status(row_number, "error", title, artist, track_id, message or f"exit {completed.returncode}")
                    result.errors += 1
        return result

    def _command(self, title: str, artist: str, track_id: str) -> list[str]:
        if self.config.mode not in {"add", "add-catalog", "add-gui"}:
            raise ValueError(f"unsupported mode: {self.config.mode}")
        command = ["zsh", str(self.config.am_script), "playlist", self.config.mode, self.config.playlist, title]
        if self.config.mode != "add":
            command.append(artist)
        if track_id and self.config.mode in {"add-catalog", "add-gui"}:
            command.extend(["--track-id", track_id])
        if self.config.mode == "add-gui" and self.config.wait_seconds is not None:
            command.extend(["--wait", str(self.config.wait_seconds)])
        return command

    def _completed_row_numbers(self) -> set[int]:
        completed = set()
        for row in normalize_status_rows(self.config.status_path):
            if row["status"] in SUCCESS_STATUSES:
                try:
                    completed.add(int(row["row_number"]))
                except ValueError:
                    pass
        return completed

    def _ensure_status_header(self) -> None:
        if not self.config.status_path.exists():
            self.config.status_path.write_text("\t".join(STATUS_FIELDS) + "\n", encoding="utf-8")

    def _write_status(self, row_number: int, status: str, title: str, artist: str, track_id: str, message: str) -> None:
        with self.config.status_path.open("a", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=STATUS_FIELDS, delimiter="\t", lineterminator="\n")
            writer.writerow(
                {
                    "row_number": row_number,
                    "status": status,
                    "title": title,
                    "artist": artist,
                    "track_id": track_id,
                    "message": message,
                }
            )


def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Resumable CSV importer for Apple Music Playlist CLI")
    parser.add_argument("csv_path", type=Path)
    parser.add_argument("playlist")
    parser.add_argument("--mode", choices=("add", "add-catalog", "add-gui"), default="add-gui")
    parser.add_argument("--output-dir", type=Path, default=Path("runs/import-playlist"))
    parser.add_argument("--title-column")
    parser.add_argument("--artist-column")
    parser.add_argument("--exclude-artist", action="append", default=[])
    parser.add_argument("--track-id-map", type=Path)
    parser.add_argument("--wait", type=float, dest="wait_seconds")
    parser.add_argument("--am-script", type=Path, default=Path("src/am.sh"))
    parser.add_argument("--no-resume", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    config = ImportConfig(
        csv_path=args.csv_path,
        playlist=args.playlist,
        mode=args.mode,
        output_dir=args.output_dir,
        title_column=args.title_column,
        artist_column=args.artist_column,
        exclude_artists=tuple(args.exclude_artist),
        resume=not args.no_resume,
        dry_run=args.dry_run,
        wait_seconds=args.wait_seconds,
        track_id_map=args.track_id_map,
        am_script=args.am_script,
    )
    result = PlaylistImporter(config).run()
    print(f"status_log={config.status_path}")
    print(
        "summary="
        f"added:{result.added} "
        f"already_present:{result.already_present} "
        f"skipped_existing:{result.skipped_existing} "
        f"excluded:{result.excluded} "
        f"missing_data:{result.missing_data} "
        f"errors:{result.errors} "
        f"dry_run:{result.dry_run}"
    )
    return 1 if result.errors else 0


if __name__ == "__main__":
    raise SystemExit(main())

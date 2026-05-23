import csv
import json
import subprocess
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from scripts.import_playlist import ImportConfig, PlaylistImporter, detect_columns, normalize_status_rows


def write_csv(path: Path, rows):
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


class ImportPlaylistTests(unittest.TestCase):
    def test_detect_columns_accepts_common_title_and_artist_headers(self):
        columns = detect_columns(["Year", "Rank", "Song", "Artist", "Notes"])

        self.assertEqual(columns.title, "Song")
        self.assertEqual(columns.artist, "Artist")

    def test_importer_skips_excluded_artists_and_existing_successes(self):
        with TemporaryDirectory() as d:
            tmp_path = Path(d)
            csv_path = tmp_path / "songs.csv"
            write_csv(
                csv_path,
                [
                    {"Year": "2004", "Rank": "1", "Song": "Numb", "Artist": "Linkin Park"},
                    {"Year": "2004", "Rank": "2", "Song": "Vertigo", "Artist": "U2"},
                    {"Year": "2004", "Rank": "3", "Song": "Float On", "Artist": "Modest Mouse"},
                ],
            )
            output_dir = tmp_path / "runs"
            output_dir.mkdir()
            status_path = output_dir / "status.tsv"
            status_path.write_text(
                "row_number\tstatus\ttitle\tartist\ttrack_id\tmessage\n"
                "2\tadded\tNumb\tLinkin Park\t\tprevious run\n",
                encoding="utf-8",
            )

            calls = []

            def runner(args, **kwargs):
                calls.append(args)
                return subprocess.CompletedProcess(args=args, returncode=0, stdout="added\n", stderr="")

            config = ImportConfig(
                csv_path=csv_path,
                playlist="Alt playlist",
                mode="add-gui",
                output_dir=output_dir,
                exclude_artists=("U2",),
                resume=True,
                wait_seconds=1.0,
            )
            result = PlaylistImporter(config, runner=runner).run()

            statuses = normalize_status_rows(status_path)
            self.assertEqual(result.added, 1)
            self.assertEqual(result.excluded, 1)
            self.assertEqual(result.skipped_existing, 1)
            self.assertEqual([row["status"] for row in statuses], ["added", "skipped_existing", "excluded", "added"])
            self.assertEqual(len(calls), 1)
            self.assertEqual(calls[0][-4:], ["Float On", "Modest Mouse", "--wait", "1.0"])

    def test_importer_uses_track_id_map_for_exact_catalog_selection(self):
        with TemporaryDirectory() as d:
            tmp_path = Path(d)
            csv_path = tmp_path / "songs.csv"
            write_csv(csv_path, [{"Song": "Na Na Na", "Artist": "My Chemical Romance"}])
            track_map = tmp_path / "track_ids.json"
            track_map.write_text(json.dumps({"Na Na Na|My Chemical Romance": "399999999"}), encoding="utf-8")

            calls = []

            def runner(args, **kwargs):
                calls.append(args)
                return subprocess.CompletedProcess(args=args, returncode=0, stdout="added\n", stderr="")

            config = ImportConfig(
                csv_path=csv_path,
                playlist="Alt playlist",
                mode="add-catalog",
                output_dir=tmp_path / "out",
                track_id_map=track_map,
            )
            PlaylistImporter(config, runner=runner).run()

            self.assertIn("--track-id", calls[0])
            self.assertEqual(calls[0][calls[0].index("--track-id") + 1], "399999999")

    def test_importer_records_errors_and_continues(self):
        with TemporaryDirectory() as d:
            tmp_path = Path(d)
            csv_path = tmp_path / "songs.csv"
            write_csv(
                csv_path,
                [
                    {"Song": "First", "Artist": "Artist One"},
                    {"Song": "Second", "Artist": "Artist Two"},
                ],
            )

            def runner(args, **kwargs):
                if "First" in args:
                    return subprocess.CompletedProcess(args=args, returncode=64, stdout="", stderr="not found")
                return subprocess.CompletedProcess(args=args, returncode=0, stdout="added\n", stderr="")

            config = ImportConfig(
                csv_path=csv_path,
                playlist="Alt playlist",
                mode="add-gui",
                output_dir=tmp_path / "out",
            )
            result = PlaylistImporter(config, runner=runner).run()

            statuses = [row["status"] for row in normalize_status_rows(config.status_path)]
            self.assertEqual(statuses, ["error", "added"])
            self.assertEqual(result.errors, 1)
            self.assertEqual(result.added, 1)


if __name__ == "__main__":
    unittest.main()

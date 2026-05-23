# Apple Music Playlist CLI

A small macOS CLI for Music.app playlist CRUD. The old player, now-playing widget,
album art, and playback controls have been removed; this repository now focuses
only on managing Music.app playlists.

The entrypoint is `src/am.sh` and can be run with the system `zsh`:

```sh
zsh src/am.sh playlist <command> [args]
```

## Commands

```sh
zsh src/am.sh playlist list
zsh src/am.sh playlist show "Playlist Name"
zsh src/am.sh playlist create "Playlist Name"
zsh src/am.sh playlist rename "Old Name" "New Name"
zsh src/am.sh playlist delete "Playlist Name" --force
zsh src/am.sh playlist add "Playlist Name" "Track Name"
zsh src/am.sh playlist search "Track Name" "Artist Name"
zsh src/am.sh playlist add-catalog "Playlist Name" "Track Name" "Artist Name"
zsh src/am.sh playlist add-catalog "Playlist Name" "Track Name" "Artist Name" --track-id 12345
zsh src/am.sh playlist add-gui "Playlist Name" "Track Name" "Artist Name"
zsh src/am.sh playlist add-gui "Playlist Name" "Track Name" "Artist Name" --track-id 12345 --manual
zsh src/am.sh playlist remove "Playlist Name" "Track Name" --force
zsh src/am.sh playlist clear "Playlist Name" --force
```

- `list` prints normal mutable user playlists.
- `show` prints playlist metadata and whether the playlist is mutable.
- `create` creates a new user playlist.
- `rename` renames a normal mutable user playlist.
- `delete --force` deletes a normal mutable user playlist.
- `add` searches the Music Library for an exact track name and duplicates that
  Library track into the target playlist.
- `search` searches Apple Music catalog matches and prints catalog track IDs.
- `add-catalog` searches the Apple Music catalog and adds a matching catalog
  song to a cloud library playlist through the Apple Music API.
- `add-gui` searches the Apple Music catalog, opens the matching song in
  Music.app, and attempts to add it through Music.app UI automation.
- `remove --force` removes matching track entries from the target playlist.
- `clear --force` removes all tracks from the target playlist.

Use `help`, `--help`, or `-h` at the top level, playlist level, or command level
for usage:

```sh
zsh src/am.sh help
zsh src/am.sh playlist help
zsh src/am.sh playlist add help
```

## Apple Music Catalog Adds

`playlist add` is still the local Music.app path. It can only add tracks that
already exist in `playlist "Library"`.

Use `playlist search` and `playlist add-catalog` when the song is available from
Apple Music but is not already in the local library:

```sh
zsh src/am.sh playlist search "Numb" "Linkin Park"
zsh src/am.sh playlist add-catalog "Playlist Name" "Numb" "Linkin Park" --dry-run
zsh src/am.sh playlist add-catalog "Playlist Name" "Numb" "Linkin Park" --track-id 528437514
```

`add-catalog` uses Apple's public catalog search to find a streamable exact
track/artist match. If multiple releases match, the first catalog result is used
unless `--track-id` is provided. Use `playlist search` first when you need a
specific release.

Actually adding the catalog song to a playlist requires Apple Music API
credentials because Music.app's AppleScript API does not expose catalog playlist
writes. Set these environment variables before running `add-catalog` without
`--dry-run`:

```sh
export APPLE_MUSIC_DEVELOPER_TOKEN="..."
export APPLE_MUSIC_USER_TOKEN="..."
```

The catalog write path targets cloud library playlists visible to the Apple
Music API. A playlist that exists only locally in Music.app may need Sync Library
enabled before the API can find it by name.

## CSV Playlist Imports

Use the reusable importer for larger song lists instead of writing one-off
scripts in the repository root:

```sh
python3 scripts/import_playlist.py songs.csv "Playlist Name" \
  --mode add-gui \
  --exclude-artist U2 \
  --exclude-artist Coldplay \
  --track-id-map track-ids.json \
  --output-dir runs/my-playlist-import \
  --wait 3
```

The importer detects common title/artist columns such as `Song` and `Artist`,
appends a resumable `status.tsv` log under the selected output directory, skips
rows that already have a successful prior status, and continues after per-track
errors. Use `--dry-run` to verify the generated CLI commands before mutating
Music.app.

Track ID maps can be JSON:

```json
{
  "Na Na Na|My Chemical Romance": "399999999"
}
```

or CSV with title, artist, and track ID columns. Use track IDs when catalog
search finds the wrong release or a title variant.

Import run output belongs under `runs/`, which is intentionally gitignored.
Reusable workflow code belongs under `scripts/` and should be tested before
committing:

```sh
python3 -m unittest discover -s tests -v
```

## No-Token GUI Fallback

`playlist add-gui` is an experimental no-developer-token fallback. It still uses
the public catalog search to find the song URL, but the write happens through the
visible Music.app UI rather than through Apple's API:

```sh
zsh src/am.sh playlist add-gui "Playlist Name" "Numb" "Linkin Park" --track-id 528437514
```

This command requires Accessibility permission for the terminal app running the
script. Grant it in System Settings > Privacy & Security > Accessibility. It
then opens the selected Apple Music URL, clicks Music.app's visible Add button
to save the song to the local Library, waits for it to appear in
`playlist "Library"`, and finally duplicates that Library track into the target
playlist.

If the menu automation is blocked by permissions or a Music.app UI change, use
manual mode:

```sh
zsh src/am.sh playlist add-gui "Playlist Name" "Numb" "Linkin Park" --track-id 528437514 --manual
```

Manual mode opens the catalog track in Music.app, copies the URL to the
clipboard, and prints the target playlist so you can choose Add to Playlist in
Music.app yourself.

The automated GUI fallback intentionally adds the song to your Library first.
That is the tradeoff that makes the no-developer-token path scriptable after the
UI click.

## Constraints

- This tool automates Music.app through AppleScript, so macOS must allow the
  terminal running the command to control Music.app. If prompted, grant
  automation permission in System Settings.
- Catalog search and catalog playlist writes require `curl` and `jq`.
- `add-gui` requires `curl`, `jq`, Music.app, and Accessibility permission for
  automated mode. It is intentionally best-effort because Music.app UI labels and
  selection behavior can change across macOS releases.
- Playlist and track names are exact matches. Quote names that contain spaces or
  shell-significant characters.
- `add` searches `playlist "Library"` by exact track name. It errors when no
  Library track matches and also errors when duplicate Library tracks share that
  exact name, because the target track would be ambiguous.
- `add-catalog` searches Apple Music by exact track and artist name. Without
  `--dry-run`, it requires `APPLE_MUSIC_DEVELOPER_TOKEN` and
  `APPLE_MUSIC_USER_TOKEN`.
- Mutation commands only target normal mutable user playlists. Library, smart,
  Genius, special, or otherwise immutable playlists are not valid mutation
  targets.
- Destructive commands require `--force`: `delete`, `remove`, and `clear`.

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

## Constraints

- This tool automates Music.app through AppleScript, so macOS must allow the
  terminal running the command to control Music.app. If prompted, grant
  automation permission in System Settings.
- Catalog search and catalog playlist writes require `curl` and `jq`.
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

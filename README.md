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
- `remove --force` removes matching track entries from the target playlist.
- `clear --force` removes all tracks from the target playlist.

Use `help`, `--help`, or `-h` at the top level, playlist level, or command level
for usage:

```sh
zsh src/am.sh help
zsh src/am.sh playlist help
zsh src/am.sh playlist add help
```

## Constraints

- This tool automates Music.app through AppleScript, so macOS must allow the
  terminal running the command to control Music.app. If prompted, grant
  automation permission in System Settings.
- Playlist and track names are exact matches. Quote names that contain spaces or
  shell-significant characters.
- `add` searches `playlist "Library"` by exact track name. It errors when no
  Library track matches and also errors when duplicate Library tracks share that
  exact name, because the target track would be ambiguous.
- Mutation commands only target normal mutable user playlists. Library, smart,
  Genius, special, or otherwise immutable playlists are not valid mutation
  targets.
- Destructive commands require `--force`: `delete`, `remove`, and `clear`.

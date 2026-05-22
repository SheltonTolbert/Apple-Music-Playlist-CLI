# Agent workflow notes

This repository is a small macOS CLI for Music.app playlist management. The entrypoint is:

```sh
zsh src/am.sh playlist <command> [args]
```

Use these notes when an agent is asked to create or populate Apple Music playlists, especially large CSV-driven catalog imports.

## Permission requirements

Before attempting write operations, verify the host can control Music.app:

```sh
osascript -e 'id of application "Music"'
zsh src/am.sh playlist list
```

For local Music.app playlist operations, macOS Automation permission is required for the terminal or agent host process that runs `osascript`. If macOS prompts, grant access in System Settings > Privacy & Security > Automation.

For the no-token GUI fallback, Accessibility permission is also required for the terminal or agent host process. Verify it with:

```sh
osascript -e 'tell application "System Events" to get UI elements enabled'
```

If it returns `false` or reports that the process is not allowed assistive access, grant the host app in System Settings > Privacy & Security > Accessibility. In some Python-based agent sessions, the host app may be Python.app rather than Terminal.app.

The API catalog write path requires these environment variables for real writes:

```sh
export APPLE_MUSIC_DEVELOPER_TOKEN="..."
export APPLE_MUSIC_USER_TOKEN="..."
```

Do not print token values in logs.

## Happy path for a large playlist import

1. Start from a clean repo and inspect the CLI help.

   ```sh
   git status --short
   zsh src/am.sh playlist help
   zsh src/am.sh playlist add-gui help
   ```

2. Inspect the input CSV or song list. Normalize title and artist fields in a separate import script, apply any requested exclusions, and de-duplicate before mutating Music.app.

3. Create or verify the target playlist.

   ```sh
   zsh src/am.sh playlist create "Playlist Name"
   zsh src/am.sh playlist show "Playlist Name"
   ```

4. Probe local-library coverage first.

   ```sh
   zsh src/am.sh playlist add "Playlist Name" "Known Track Name"
   ```

   `playlist add` only duplicates tracks already present in Music.app's Library. If common tracks are missing locally, switch to catalog search/API or the GUI fallback instead of looping local adds.

5. Resolve catalog tracks with dry runs.

   ```sh
   zsh src/am.sh playlist search "Track Name" "Artist Name"
   zsh src/am.sh playlist add-catalog "Playlist Name" "Track Name" "Artist Name" --dry-run
   ```

   If the search returns multiple variants, capture the desired catalog `trackId` and use `--track-id` for exact selection.

6. Prefer the token-backed API path for bulk writes when Apple Music tokens are available.

   ```sh
   zsh src/am.sh playlist add-catalog "Playlist Name" "Track Name" "Artist Name" --track-id 123456789
   ```

7. If tokens are not available, use the no-token GUI fallback only after a one-song smoke test succeeds.

   ```sh
   zsh src/am.sh playlist add-gui "Playlist Name" "Track Name" "Artist Name" --track-id 123456789 --wait 3
   zsh src/am.sh playlist show "Playlist Name"
   ```

8. Run the bulk import through a resumable script that logs every row. Recommended log statuses are `added`, `already_present`, `missing`, `excluded`, and `error`. Keep logs outside commits unless they are intentional fixtures.

9. Verify the final playlist count with Music.app, not only with script output.

   ```sh
   zsh src/am.sh playlist show "Playlist Name"
   ```

10. Before committing, remove generated import scripts, result TSVs, pycache files, and other one-off artifacts. Commit only reusable CLI changes and documentation.

## What eventually worked for the 97X-style import

The successful fallback path was:

1. Use public iTunes/Apple Music search to identify likely catalog songs.
2. For ambiguous or title-variant misses, use concrete iTunes/Apple Music track IDs and call `add-gui ... --track-id <id>`.
3. Open the catalog URL with `open -a Music <url>` rather than relying only on Music.app AppleScript `open location`; this was more reliable at actually navigating Music.app to the track page.
4. Let Music.app add the catalog song to the user's Library through the visible UI.
5. After the song appeared in `playlist "Library"`, duplicate the local Library track into the target user playlist.
6. Log each row and retry failures by track ID or by cleaner title variants.

## Pitfalls discovered

- `playlist add` is local-library only. It cannot add arbitrary Apple Music catalog songs that are not already in Music.app's Library.
- A successful catalog search does not guarantee a playlist write. API writes require valid MusicKit developer and user tokens, and the target playlist must be visible as a mutable cloud library playlist.
- Music.app AppleScript `open location` may leave the app on the previous page or a blank placeholder. `open -a Music <catalog-url>` worked more reliably for catalog URLs.
- The visible add control in Music.app is not always named exactly `Add`. Accessibility may expose it as `Add button` or as a button whose description is `Download button`.
- System Events can fail with no `window 1` for Music.app. Bring back the main Music window with Cmd-0, then retry.
- Some catalog entries use canonical titles that differ from radio-list titles, for example subtitles, punctuation, or featured-artist formatting. Use `playlist search` and `--track-id` rather than forcing an inexact title match.
- Do not add covers, live versions, remasters, or karaoke versions as substitutes unless the user explicitly approves them.
- Device/account limits in Music.app can block further catalog-library adds. If Music.app reports a device limit, stop and ask the user to resolve it in Account Settings.
- GUI automation is slow and fragile for 100+ songs. Test one song, then a small batch, before running a full import.

## Agent hygiene

- Keep generated import scripts and logs untracked unless the user explicitly wants them preserved.
- Do not commit credentials, tokens, MusicKit user tokens, or raw environment dumps.
- Use `--dry-run` and one-song smoke tests before bulk mutation.
- Verify final state with `playlist show` and report both source-row counts and actual playlist counts.
- If modifying `src/am.sh`, run a syntax check before committing:

  ```sh
  zsh -n src/am.sh
  ```

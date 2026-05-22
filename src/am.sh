#!/bin/zsh

program_name="${0:t}"
readonly EX_USAGE=64
readonly EX_UNAVAILABLE=69
readonly EX_SOFTWARE=70

print_error() {
	printf '%s: %s\n' "${program_name}" "$*" >&2
}

usage() {
	printf '%s\n' "Usage: ${program_name} playlist <command> [args]"
	printf '\n'
	printf '%s\n' "Playlist commands:"
	printf '%s\n' "  playlist list"
	printf '%s\n' "  playlist show <name>"
	printf '%s\n' "  playlist create <name>"
	printf '%s\n' "  playlist rename <old-name> <new-name>"
	printf '%s\n' "  playlist delete <name> --force"
	printf '%s\n' "  playlist add <playlist-name> <track-name>"
	printf '%s\n' "  playlist add-catalog <playlist-name> <track-name> <artist-name> [--track-id <id>] [--dry-run]"
	printf '%s\n' "  playlist add-gui <playlist-name> <track-name> <artist-name> [--track-id <id>] [--wait <seconds>] [--manual] [--dry-run]"
	printf '%s\n' "  playlist search <track-name> <artist-name>"
	printf '%s\n' "  playlist remove <playlist-name> <track-name> --force"
	printf '%s\n' "  playlist clear <name> --force"
}

playlist_usage() {
	printf '%s\n' "Usage: ${program_name} playlist <command> [args]"
	printf '\n'
	printf '%s\n' "Commands:"
	printf '%s\n' "  list                         List playlists"
	printf '%s\n' "  show <name>                  Show playlist details"
	printf '%s\n' "  create <name>                Create a playlist"
	printf '%s\n' "  rename <old-name> <new-name> Rename a playlist"
	printf '%s\n' "  delete <name> --force        Delete a playlist"
	printf '%s\n' "  add <playlist-name> <track-name>"
	printf '%s\n' "                               Add a track to a playlist"
	printf '%s\n' "  add-catalog <playlist-name> <track-name> <artist-name> [--track-id <id>] [--dry-run]"
	printf '%s\n' "                               Add an Apple Music catalog track to a cloud playlist"
	printf '%s\n' "  add-gui <playlist-name> <track-name> <artist-name> [--track-id <id>] [--wait <seconds>] [--manual] [--dry-run]"
	printf '%s\n' "                               Add a catalog track through Music.app UI automation"
	printf '%s\n' "  search <track-name> <artist-name>"
	printf '%s\n' "                               Search Apple Music catalog matches"
	printf '%s\n' "  remove <playlist-name> <track-name> --force"
	printf '%s\n' "                               Remove a track from a playlist"
	printf '%s\n' "  clear <name> --force         Remove all tracks from a playlist"
}

playlist_command_usage() {
	local command="${1:-}"

	case "${command}" in
		list)
			printf '%s\n' "Usage: ${program_name} playlist list"
			;;
		show)
			printf '%s\n' "Usage: ${program_name} playlist show <name>"
			;;
		create)
			printf '%s\n' "Usage: ${program_name} playlist create <name>"
			;;
		rename)
			printf '%s\n' "Usage: ${program_name} playlist rename <old-name> <new-name>"
			;;
		delete)
			printf '%s\n' "Usage: ${program_name} playlist delete <name> --force"
			;;
		add)
			printf '%s\n' "Usage: ${program_name} playlist add <playlist-name> <track-name>"
			;;
		add-catalog|add-streaming)
			printf '%s\n' "Usage: ${program_name} playlist ${command} <playlist-name> <track-name> <artist-name> [--track-id <id>] [--dry-run]"
			;;
		add-gui)
			printf '%s\n' "Usage: ${program_name} playlist add-gui <playlist-name> <track-name> <artist-name> [--track-id <id>] [--wait <seconds>] [--manual] [--dry-run]"
			;;
		search)
			printf '%s\n' "Usage: ${program_name} playlist search <track-name> <artist-name>"
			;;
		remove)
			printf '%s\n' "Usage: ${program_name} playlist remove <playlist-name> <track-name> --force"
			;;
		clear)
			printf '%s\n' "Usage: ${program_name} playlist clear <name> --force"
			;;
		*)
			print_error "Unknown playlist command: ${command}"
			playlist_usage >&2
			return "${EX_USAGE}"
			;;
	esac

}

usage_error() {
	local message="${1}"
	local usage_scope="${2:-main}"

	print_error "${message}"
	printf '\n' >&2

	case "${usage_scope}" in
		playlist)
			playlist_usage >&2
			;;
		playlist:*)
			playlist_command_usage "${usage_scope#playlist:}" >&2
			;;
		*)
			usage >&2
			;;
	esac

	return "${EX_USAGE}"
}

wants_help() {
	if (( $# != 1 )); then
		return 1
	fi

	case "${1}" in
		help|-h|--help)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

require_arg_count() {
	local usage_scope="${1}"
	local label="${2}"
	local expected="${3}"
	shift 3

	if (( $# != expected )); then
		usage_error "${label} expects ${expected} argument(s), got $#." "${usage_scope}"
		return $?
	fi
}

require_force() {
	local usage_scope="${1}"
	local label="${2}"
	local force_arg="${3:-}"

	if [[ "${force_arg}" != "--force" ]]; then
		usage_error "${label} requires --force." "${usage_scope}"
		return $?
	fi
}

require_non_empty_name() {
	local usage_scope="${1}"
	local label="${2}"
	local value="${3:-}"

	if [[ -z "${value}" ]]; then
		usage_error "${label} requires a non-empty playlist name." "${usage_scope}"
		return $?
	fi
}

require_non_empty_track_name() {
	local usage_scope="${1}"
	local label="${2}"
	local value="${3:-}"

	if [[ -z "${value}" ]]; then
		usage_error "${label} requires a non-empty track name." "${usage_scope}"
		return $?
	fi
}

require_non_empty_artist_name() {
	local usage_scope="${1}"
	local label="${2}"
	local value="${3:-}"

	if [[ -z "${value}" ]]; then
		usage_error "${label} requires a non-empty artist name." "${usage_scope}"
		return $?
	fi
}

require_command() {
	local command_name="${1}"

	if ! command -v "${command_name}" >/dev/null 2>&1; then
		print_error "Required command not found: ${command_name}"
		return "${EX_UNAVAILABLE}"
	fi
}

copy_to_clipboard() {
	if command -v pbcopy >/dev/null 2>&1; then
		printf '%s' "${1}" | pbcopy
	fi
}

url_encode() {
	require_command "jq" || return $?
	command jq -rn --arg value "${1}" '$value | @uri'
}

require_catalog_tools() {
	require_command "curl" || return $?
	require_command "jq" || return $?
}

require_apple_music_api_tokens() {
	if [[ -z "${APPLE_MUSIC_DEVELOPER_TOKEN:-}" ]]; then
		print_error "APPLE_MUSIC_DEVELOPER_TOKEN is required for Apple Music catalog playlist writes."
		return "${EX_USAGE}"
	fi

	if [[ -z "${APPLE_MUSIC_USER_TOKEN:-}" ]]; then
		print_error "APPLE_MUSIC_USER_TOKEN is required for Apple Music catalog playlist writes."
		return "${EX_USAGE}"
	fi
}

itunes_search_url() {
	local track_name="${1}"
	local artist_name="${2}"
	local storefront="${APPLE_MUSIC_ITUNES_COUNTRY:-US}"
	local encoded_query

	encoded_query="$(url_encode "${track_name} ${artist_name}")" || return $?
	printf 'https://itunes.apple.com/search?term=%s&country=%s&media=music&entity=song&limit=10\n' "${encoded_query}" "${storefront}"
}

catalog_search_response() {
	local track_name="${1}"
	local artist_name="${2}"
	local search_url

	require_catalog_tools || return $?
	search_url="$(itunes_search_url "${track_name}" "${artist_name}")" || return $?
	command curl -fsS "${search_url}"
}

catalog_matches_json() {
	local track_name="${1}"
	local artist_name="${2}"
	local response="${3}"

	printf '%s' "${response}" | command jq -c \
		--arg track_name "${track_name}" \
		--arg artist_name "${artist_name}" \
		'[
			.results[]?
			| select(.wrapperType == "track" and .kind == "song")
			| select((.trackName // "" | ascii_downcase) == ($track_name | ascii_downcase))
			| select((.artistName // "" | ascii_downcase) == ($artist_name | ascii_downcase))
			| select(.isStreamable == true)
		]'
}

catalog_match_tsv() {
	local track_name="${1}"
	local artist_name="${2}"
	local response="${3}"
	local selected_track_id="${4:-}"
	local matches
	local match_count
	local selected_match

	if [[ -n "${selected_track_id}" ]]; then
		selected_match="$(command curl -fsS "https://itunes.apple.com/lookup?id=${selected_track_id}&country=${APPLE_MUSIC_ITUNES_COUNTRY:-US}&entity=song" | command jq -r '
			.results[]?
			| select(.wrapperType == "track" and .kind == "song")
			| select((.trackId | tostring) == "'"${selected_track_id}"'")
			| [.trackId, .trackName, .artistName, .collectionName, .trackViewUrl]
			| @tsv
		')" || return $?
		if [[ -n "${selected_match}" ]]; then
			printf '%s\n' "${selected_match}"
			return 0
		fi
	fi

	matches="$(catalog_matches_json "${track_name}" "${artist_name}" "${response}")" || return $?
	match_count="$(printf '%s' "${matches}" | command jq 'length')" || return $?

	if (( match_count == 0 )); then
		print_error "No streamable Apple Music catalog match found for: ${track_name} by ${artist_name}"
		return "${EX_USAGE}"
	fi

	if [[ -n "${selected_track_id}" ]]; then
		selected_match="$(printf '%s' "${matches}" | command jq -r \
			--arg selected_track_id "${selected_track_id}" \
			'map(select((.trackId | tostring) == $selected_track_id)) | if length == 0 then empty else .[0] | [.trackId, .trackName, .artistName, .collectionName, .trackViewUrl] | @tsv end')" || return $?

		if [[ -z "${selected_match}" ]]; then
			print_error "Track ID ${selected_track_id} did not match ${track_name} by ${artist_name} in the catalog search results."
			return "${EX_USAGE}"
		fi

		printf '%s\n' "${selected_match}"
		return 0
	fi

	printf '%s' "${matches}" | command jq -r '.[0] | [.trackId, .trackName, .artistName, .collectionName, .trackViewUrl] | @tsv'
}

apple_music_api_get() {
	local path="${1}"

	require_catalog_tools || return $?
	require_apple_music_api_tokens || return $?
	command curl -fsS \
		-H "Authorization: Bearer ${APPLE_MUSIC_DEVELOPER_TOKEN}" \
		-H "Music-User-Token: ${APPLE_MUSIC_USER_TOKEN}" \
		"https://api.music.apple.com${path}"
}

apple_music_api_post_json() {
	local path="${1}"
	local body="${2}"

	require_catalog_tools || return $?
	require_apple_music_api_tokens || return $?
	command curl -fsS \
		-X POST \
		-H "Authorization: Bearer ${APPLE_MUSIC_DEVELOPER_TOKEN}" \
		-H "Music-User-Token: ${APPLE_MUSIC_USER_TOKEN}" \
		-H "Content-Type: application/json" \
		-d "${body}" \
		"https://api.music.apple.com${path}"
}

resolve_cloud_playlist_id() {
	local playlist_name="${1}"
	local path="/v1/me/library/playlists?limit=100"
	local response
	local page_ids
	local next_path
	local -a matches=()

	while [[ -n "${path}" ]]; do
		response="$(apple_music_api_get "${path}")" || return $?
		page_ids=("${(@f)$(printf '%s' "${response}" | command jq -r --arg playlist_name "${playlist_name}" '.data[]? | select(.attributes.name == $playlist_name) | .id')}")

		if (( ${#page_ids[@]} > 0 )); then
			matches+=("${page_ids[@]}")
		fi

		next_path="$(printf '%s' "${response}" | command jq -r '.next // empty')" || return $?
		path="${next_path}"
	done

	if (( ${#matches[@]} == 0 )); then
		print_error "Cloud library playlist not found through Apple Music API: ${playlist_name}"
		return "${EX_USAGE}"
	fi

	if (( ${#matches[@]} > 1 )); then
		print_error "Cloud library playlist name is ambiguous through Apple Music API: ${playlist_name}"
		return "${EX_USAGE}"
	fi

	printf '%s\n' "${matches[1]}"
}

run_applescript() {
	local description="AppleScript command"
	local -a osascript_args

	if (( $# > 0 )); then
		description="${1}"
		shift
	fi

	while (( $# > 0 )); do
		if [[ "${1}" == "--" ]]; then
			shift
			break
		fi

		osascript_args+=("-e" "${1}")
		shift
	done

	if (( ${#osascript_args[@]} == 0 )); then
		print_error "run_applescript requires at least one AppleScript line"
		return "${EX_SOFTWARE}"
	fi

	require_command "osascript" || return $?
	command osascript "${osascript_args[@]}" "$@"
	local exit_status=$?

	if (( exit_status != 0 )); then
		print_error "AppleScript failed while ${description}"
	fi

	return "${exit_status}"
}

format_plain_list() {
	local item

	if (( $# > 0 )); then
		printf '%s\n' "$@"
	else
		while IFS= read -r item; do
			printf '%s\n' "${item}"
		done
	fi | awk '
		{
			gsub(/\r$/, "")
			sub(/^[[:space:]]+/, "")
			sub(/[[:space:]]+$/, "")
			if (length($0) && !seen[$0]++) print
		}
	'
}

playlist_apple_script_helpers=(
	'on join_lines(lineItems)'
	'	set previousDelimiters to AppleScript'\''s text item delimiters'
	'	set AppleScript'\''s text item delimiters to linefeed'
	'	set joinedText to lineItems as text'
	'	set AppleScript'\''s text item delimiters to previousDelimiters'
	'	return joinedText'
	'end join_lines'
	'on two_digits(numberValue)'
	'	if numberValue < 10 then'
	'		return "0" & (numberValue as text)'
	'	end if'
	'	return numberValue as text'
	'end two_digits'
	'on format_duration(totalSeconds)'
	'	set totalSeconds to totalSeconds as integer'
	'	set totalMinutes to totalSeconds div 60'
	'	set secondsPart to totalSeconds mod 60'
	'	set hoursPart to totalMinutes div 60'
	'	set minutesPart to totalMinutes mod 60'
	'	if hoursPart > 0 then'
	'		return (hoursPart as text) & ":" & my two_digits(minutesPart) & ":" & my two_digits(secondsPart)'
	'	end if'
	'	return (minutesPart as text) & ":" & my two_digits(secondsPart)'
	'end format_duration'
	'on matching_playlists(playlistName)'
	'	tell application "Music"'
	'		return every playlist whose name is playlistName'
	'	end tell'
	'end matching_playlists'
	'on playlist_name_exists(playlistName)'
	'	set matchedPlaylists to my matching_playlists(playlistName)'
	'	return (count of matchedPlaylists) > 0'
	'end playlist_name_exists'
	'on exactly_one_playlist(playlistName)'
	'	set matchedPlaylists to my matching_playlists(playlistName)'
	'	set matchCount to count of matchedPlaylists'
	'	if matchCount = 0 then'
	'		error "Playlist not found: " & playlistName number 64'
	'	end if'
	'	if matchCount > 1 then'
	'		error "Playlist name is ambiguous because multiple playlists are named: " & playlistName number 64'
	'	end if'
	'	return item 1 of matchedPlaylists'
	'end exactly_one_playlist'
	'on exactly_one_mutable_playlist(playlistName)'
	'	set playlistRef to my exactly_one_playlist(playlistName)'
	'	if not my is_mutable_playlist(playlistRef) then'
	'		error "Playlist is not a normal mutable user playlist: " & playlistName number 64'
	'	end if'
	'	return playlistRef'
	'end exactly_one_mutable_playlist'
	'on exactly_one_library_track(trackName)'
	'	tell application "Music"'
	'		set matchedTracks to every track of playlist "Library" whose name is trackName'
	'	end tell'
	'	set matchCount to count of matchedTracks'
	'	if matchCount = 0 then'
	'		error "Track not found in Library: " & trackName number 64'
	'	end if'
	'	if matchCount > 1 then'
	'		error "Track name is ambiguous in Library: " & trackName & " (" & matchCount & " matches)" number 64'
	'	end if'
	'	return item 1 of matchedTracks'
	'end exactly_one_library_track'
	'on is_mutable_playlist(playlistRef)'
	'	tell application "Music"'
	'		try'
	'			if class of playlistRef is not user playlist then return false'
	'		on error'
	'			return false'
	'		end try'
	'		try'
	'			set specialKind to special kind of playlistRef as text'
	'		on error'
	'			return false'
	'		end try'
	'		if specialKind is not "none" then return false'
	'		try'
	'			if smart of playlistRef then return false'
	'		end try'
	'		try'
	'			if genius of playlistRef then return false'
	'		end try'
	'		return true'
	'	end tell'
	'end is_mutable_playlist'
	'on playlist_time_text(playlistRef)'
	'	tell application "Music"'
	'		try'
	'			return time of playlistRef as text'
	'		on error'
	'			try'
	'				return my format_duration(duration of playlistRef)'
	'			on error'
	'				return "unknown"'
	'			end try'
	'		end try'
	'	end tell'
	'end playlist_time_text'
	'on playlist_description_text(playlistRef)'
	'	tell application "Music"'
	'		try'
	'			set descriptionValue to description of playlistRef'
	'			if descriptionValue is missing value then return ""'
	'			return descriptionValue as text'
	'		on error'
	'			return ""'
	'		end try'
	'	end tell'
	'end playlist_description_text'
)

playlist_list() {
	if wants_help "$@"; then
		playlist_command_usage "list"
		return 0
	fi

	require_arg_count "playlist:list" "playlist list" 0 "$@" || return $?
	run_applescript "listing playlists" \
		"${playlist_apple_script_helpers[@]}" \
		'on run argv' \
		'	set playlistNames to {}' \
		'	tell application "Music"' \
		'		repeat with playlistItem in every playlist' \
		'			set playlistRef to contents of playlistItem' \
		'			if my is_mutable_playlist(playlistRef) then' \
		'				set end of playlistNames to name of playlistRef as text' \
		'			end if' \
		'		end repeat' \
		'	end tell' \
		'	if (count of playlistNames) = 0 then return ""' \
		'	return my join_lines(playlistNames)' \
		'end run'
}

playlist_show() {
	if wants_help "$@"; then
		playlist_command_usage "show"
		return 0
	fi

	require_arg_count "playlist:show" "playlist show" 1 "$@" || return $?
	require_non_empty_name "playlist:show" "playlist show" "${1}" || return $?
	run_applescript "showing playlist" \
		"${playlist_apple_script_helpers[@]}" \
		'on run argv' \
		'	set playlistName to item 1 of argv' \
		'	set playlistRef to my exactly_one_playlist(playlistName)' \
		'	tell application "Music"' \
		'		set metadataLines to {"Name: " & (name of playlistRef as text)}' \
		'		try' \
		'			set end of metadataLines to "Persistent ID: " & (persistent ID of playlistRef as text)' \
		'		on error' \
		'			set end of metadataLines to "Persistent ID: unknown"' \
		'		end try' \
		'		try' \
		'			set end of metadataLines to "Track Count: " & ((count of tracks of playlistRef) as text)' \
		'		on error' \
		'			set end of metadataLines to "Track Count: unknown"' \
		'		end try' \
		'	end tell' \
		'	set end of metadataLines to "Time: " & my playlist_time_text(playlistRef)' \
		'	set descriptionText to my playlist_description_text(playlistRef)' \
		'	if descriptionText is not "" then set end of metadataLines to "Description: " & descriptionText' \
		'	if my is_mutable_playlist(playlistRef) then' \
		'		set end of metadataLines to "Mutable: yes"' \
		'	else' \
		'		set end of metadataLines to "Mutable: no"' \
		'	end if' \
		'	return my join_lines(metadataLines)' \
		'end run' \
		-- "$1"
}

playlist_create() {
	if wants_help "$@"; then
		playlist_command_usage "create"
		return 0
	fi

	require_arg_count "playlist:create" "playlist create" 1 "$@" || return $?
	require_non_empty_name "playlist:create" "playlist create" "${1}" || return $?
	run_applescript "creating playlist" \
		"${playlist_apple_script_helpers[@]}" \
		'on run argv' \
		'	set playlistName to item 1 of argv' \
		'	if my playlist_name_exists(playlistName) then' \
		'		error "Playlist already exists: " & playlistName number 64' \
		'	end if' \
		'	tell application "Music"' \
		'		set newPlaylist to make new playlist with properties {name:playlistName}' \
		'		return "Created playlist: " & (name of newPlaylist as text)' \
		'	end tell' \
		'end run' \
		-- "$1"
}

playlist_rename() {
	if wants_help "$@"; then
		playlist_command_usage "rename"
		return 0
	fi

	require_arg_count "playlist:rename" "playlist rename" 2 "$@" || return $?
	require_non_empty_name "playlist:rename" "playlist rename" "${1}" || return $?
	require_non_empty_name "playlist:rename" "playlist rename" "${2}" || return $?
	run_applescript "renaming playlist" \
		"${playlist_apple_script_helpers[@]}" \
		'on run argv' \
		'	set oldName to item 1 of argv' \
		'	set newName to item 2 of argv' \
		'	set playlistRef to my exactly_one_playlist(oldName)' \
		'	if not my is_mutable_playlist(playlistRef) then' \
		'		error "Playlist is not a normal mutable user playlist: " & oldName number 64' \
		'	end if' \
		'	if my playlist_name_exists(newName) then' \
		'		error "Playlist already exists: " & newName number 64' \
		'	end if' \
		'	tell application "Music"' \
		'		set name of playlistRef to newName' \
		'	end tell' \
		'	return "Renamed playlist: " & oldName & " -> " & newName' \
		'end run' \
		-- "$1" "$2"
}

playlist_delete() {
	if wants_help "$@"; then
		playlist_command_usage "delete"
		return 0
	fi

	require_arg_count "playlist:delete" "playlist delete" 2 "$@" || return $?
	require_force "playlist:delete" "playlist delete" "${2}" || return $?
	require_non_empty_name "playlist:delete" "playlist delete" "${1}" || return $?
	run_applescript "deleting playlist" \
		"${playlist_apple_script_helpers[@]}" \
		'on run argv' \
		'	set playlistName to item 1 of argv' \
		'	set playlistRef to my exactly_one_playlist(playlistName)' \
		'	if not my is_mutable_playlist(playlistRef) then' \
		'		error "Playlist is not a normal mutable user playlist: " & playlistName number 64' \
		'	end if' \
		'	tell application "Music"' \
		'		delete playlistRef' \
		'	end tell' \
		'	return "Deleted playlist: " & playlistName' \
		'end run' \
		-- "$1"
}

playlist_add() {
	if wants_help "$@"; then
		playlist_command_usage "add"
		return 0
	fi

	require_arg_count "playlist:add" "playlist add" 2 "$@" || return $?
	require_non_empty_name "playlist:add" "playlist add" "${1}" || return $?
	require_non_empty_track_name "playlist:add" "playlist add" "${2}" || return $?
	run_applescript "adding track to playlist" \
		"${playlist_apple_script_helpers[@]}" \
		'on run argv' \
		'	set playlistName to item 1 of argv' \
		'	set trackName to item 2 of argv' \
		'	set playlistRef to my exactly_one_mutable_playlist(playlistName)' \
		'	set sourceTrack to my exactly_one_library_track(trackName)' \
		'	tell application "Music"' \
		'		duplicate sourceTrack to playlistRef' \
		'	end tell' \
		'	return "Added track: " & trackName & " -> " & playlistName' \
		'end run' \
		-- "$1" "$2"
}

playlist_search() {
	local response
	local matches

	if wants_help "$@"; then
		playlist_command_usage "search"
		return 0
	fi

	require_arg_count "playlist:search" "playlist search" 2 "$@" || return $?
	require_non_empty_track_name "playlist:search" "playlist search" "${1}" || return $?
	require_non_empty_artist_name "playlist:search" "playlist search" "${2}" || return $?

	response="$(catalog_search_response "${1}" "${2}")" || return $?
	matches="$(catalog_matches_json "${1}" "${2}" "${response}")" || return $?

	if (( $(printf '%s' "${matches}" | command jq 'length') == 0 )); then
		print_error "No streamable Apple Music catalog match found for: ${1} by ${2}"
		return "${EX_USAGE}"
	fi

	printf '%s\n' "Apple Music catalog matches:"
	printf '%s' "${matches}" | command jq -r \
		'.[] | "- \(.trackName) by \(.artistName) | \(.collectionName) | id:\(.trackId) | \(.trackViewUrl)"'
}

playlist_add_catalog() {
	local playlist_name="${1:-}"
	local requested_track_name="${2:-}"
	local requested_artist_name="${3:-}"
	local dry_run="false"
	local selected_track_id=""
	local response
	local match_tsv
	local track_id
	local track_name
	local artist_name
	local collection_name
	local track_url
	local cloud_playlist_id
	local request_body

	if wants_help "$@"; then
		playlist_command_usage "add-catalog"
		return 0
	fi

	if (( $# < 3 )); then
		usage_error "playlist add-catalog expects at least 3 argument(s), got $#." "playlist:add-catalog"
		return $?
	fi

	if (( $# > 6 )); then
		usage_error "playlist add-catalog expects at most 6 argument(s), got $#." "playlist:add-catalog"
		return $?
	fi

	shift 3
	while (( $# > 0 )); do
		case "${1}" in
			--dry-run)
				dry_run="true"
				shift
				;;
			--track-id)
				if (( $# < 2 )); then
					usage_error "playlist add-catalog --track-id requires a value." "playlist:add-catalog"
					return $?
				fi
				selected_track_id="${2}"
				shift 2
				;;
			*)
				usage_error "Unknown playlist add-catalog option: ${1}" "playlist:add-catalog"
				return $?
				;;
		esac
	done

	require_non_empty_name "playlist:add-catalog" "playlist add-catalog" "${playlist_name}" || return $?
	require_non_empty_track_name "playlist:add-catalog" "playlist add-catalog" "${requested_track_name}" || return $?
	require_non_empty_artist_name "playlist:add-catalog" "playlist add-catalog" "${requested_artist_name}" || return $?
	if [[ -n "${selected_track_id}" && "${selected_track_id}" != <-> ]]; then
		usage_error "playlist add-catalog --track-id must be numeric." "playlist:add-catalog"
		return $?
	fi

	response="$(catalog_search_response "${requested_track_name}" "${requested_artist_name}")" || return $?
	match_tsv="$(catalog_match_tsv "${requested_track_name}" "${requested_artist_name}" "${response}" "${selected_track_id}")" || return $?

	IFS=$'\t' read -r track_id track_name artist_name collection_name track_url <<< "${match_tsv}"

	if [[ "${dry_run}" == "true" ]]; then
		printf '%s\n' "Catalog match: ${track_name} by ${artist_name} | ${collection_name} | id:${track_id}"
		printf '%s\n' "Would add to cloud playlist: ${playlist_name}"
		printf '%s\n' "${track_url}"
		return 0
	fi

	require_apple_music_api_tokens || return $?
	cloud_playlist_id="$(resolve_cloud_playlist_id "${playlist_name}")" || return $?
	request_body="$(command jq -nc --arg track_id "${track_id}" '{data: [{id: $track_id, type: "songs"}]}')" || return $?
	apple_music_api_post_json "/v1/me/library/playlists/${cloud_playlist_id}/tracks" "${request_body}" >/dev/null || return $?
	printf '%s\n' "Added catalog track: ${track_name} by ${artist_name} -> ${playlist_name}"
}

ensure_mutable_playlist() {
	run_applescript "checking playlist mutability" \
		"${playlist_apple_script_helpers[@]}" \
		'on run argv' \
		'	set playlistName to item 1 of argv' \
		'	set playlistRef to my exactly_one_mutable_playlist(playlistName)' \
		'	return name of playlistRef as text' \
		'end run' \
		-- "$1" >/dev/null
}

open_catalog_track_in_music() {
	run_applescript "opening catalog track in Music.app" \
		'on run argv' \
		'	set trackUrl to item 1 of argv' \
		'	do shell script "open -a Music " & quoted form of trackUrl' \
		'	tell application "Music" to activate' \
		'end run' \
		-- "$1"
}

verify_playlist_track_name() {
	run_applescript "verifying playlist track" \
		"${playlist_apple_script_helpers[@]}" \
		'on run argv' \
		'	set playlistName to item 1 of argv' \
		'	set trackName to item 2 of argv' \
		'	set playlistRef to my exactly_one_playlist(playlistName)' \
		'	tell application "Music"' \
		'		set matchedTracks to every track of playlistRef whose name is trackName' \
		'		return count of matchedTracks' \
		'	end tell' \
		'end run' \
		-- "$1" "$2"
}

click_music_add_button() {
	run_applescript "clicking Music.app Add/Download button" \
		'on clickFirstAdd(rootElement)' \
		'	tell application "System Events"' \
		'		try' \
		'			set childElements to UI elements of rootElement' \
		'		on error' \
		'			set childElements to {}' \
		'		end try' \
		'		repeat with childElement in childElements' \
		'			try' \
		'				set elementName to ""' \
		'				set elementDescription to ""' \
		'				set elementRole to role description of childElement as text' \
		'				try' \
		'					set elementName to name of childElement as text' \
		'				end try' \
		'				try' \
		'					set elementDescription to description of childElement as text' \
		'				end try' \
		'				if elementRole is "button" and (elementName is "Add" or elementName is "Add button" or elementDescription is "Add" or elementDescription is "Add button" or elementDescription is "Download button") then' \
		'					click childElement' \
		'					return true' \
		'				end if' \
		'			end try' \
		'			if my clickFirstAdd(childElement) then return true' \
		'		end repeat' \
		'	end tell' \
		'	return false' \
		'end clickFirstAdd' \
		'on run argv' \
		'	set trackUrl to item 1 of argv' \
		'	set waitSeconds to item 2 of argv as number' \
		'	tell application "Music"' \
		'		activate' \
		'	end tell' \
		'	do shell script "open -a Music " & quoted form of trackUrl' \
		'	delay waitSeconds' \
		'	tell application "System Events"' \
		'		if UI elements enabled is false then' \
		'			error "Accessibility permission is required. Enable it for the terminal app running this command in System Settings > Privacy & Security > Accessibility." number 64' \
		'		end if' \
		'		tell process "Music"' \
		'			set frontmost to true' \
		'			repeat with attemptNumber from 1 to 10' \
		'				if (count of windows) > 0 then exit repeat' \
		'				keystroke "0" using command down' \
		'				delay 1' \
		'			end repeat' \
		'			if (count of windows) = 0 then error "Music.app has no open window; use Window > Music or Cmd-0, then retry." number 64' \
		'			if my clickFirstAdd(window 1) then return "Clicked Music.app Add/Download button"' \
		'		end tell' \
		'	end tell' \
		'	error "Could not find a visible Add/Download button for the opened Apple Music catalog page." number 64' \
		'end run' \
		-- "$1" "$2"
}

wait_for_library_track() {
	run_applescript "waiting for track in Music library" \
		'on run argv' \
		'	set trackName to item 1 of argv' \
		'	set artistName to item 2 of argv' \
		'	set albumName to item 3 of argv' \
		'	set timeoutSeconds to item 4 of argv as integer' \
		'	repeat with elapsedSeconds from 0 to timeoutSeconds' \
		'		tell application "Music"' \
		'			set matchedTracks to every track of playlist "Library" whose name is trackName and artist is artistName and album is albumName' \
		'			if (count of matchedTracks) > 0 then return count of matchedTracks' \
		'			set matchedTracks to every track of playlist "Library" whose name is trackName and artist is artistName' \
		'			if (count of matchedTracks) > 0 then return count of matchedTracks' \
		'		end tell' \
		'		delay 1' \
		'	end repeat' \
		'	return 0' \
		'end run' \
		-- "$1" "$2" "$3" "$4"
}

duplicate_library_track_to_playlist_by_metadata() {
	run_applescript "duplicating library track to playlist" \
		"${playlist_apple_script_helpers[@]}" \
		'on run argv' \
		'	set playlistName to item 1 of argv' \
		'	set trackName to item 2 of argv' \
		'	set artistName to item 3 of argv' \
		'	set albumName to item 4 of argv' \
		'	set playlistRef to my exactly_one_mutable_playlist(playlistName)' \
		'	tell application "Music"' \
		'		set matchedTracks to every track of playlist "Library" whose name is trackName and artist is artistName and album is albumName' \
		'		if (count of matchedTracks) = 0 then set matchedTracks to every track of playlist "Library" whose name is trackName and artist is artistName' \
		'		if (count of matchedTracks) = 0 then error "Track not found in Library after Music.app Add button click: " & trackName & " by " & artistName number 64' \
		'		duplicate item 1 of matchedTracks to playlistRef' \
		'	end tell' \
		'	return "Added track: " & trackName & " -> " & playlistName' \
		'end run' \
		-- "$1" "$2" "$3" "$4"
}

playlist_add_gui() {
	local playlist_name="${1:-}"
	local requested_track_name="${2:-}"
	local requested_artist_name="${3:-}"
	local dry_run="false"
	local manual="false"
	local selected_track_id=""
	local wait_seconds="6"
	local response
	local match_tsv
	local track_id
	local track_name
	local artist_name
	local collection_name
	local track_url
	local verify_count
	local library_count

	if wants_help "$@"; then
		playlist_command_usage "add-gui"
		return 0
	fi

	if (( $# < 3 )); then
		usage_error "playlist add-gui expects at least 3 argument(s), got $#." "playlist:add-gui"
		return $?
	fi

	if (( $# > 8 )); then
		usage_error "playlist add-gui expects at most 8 argument(s), got $#." "playlist:add-gui"
		return $?
	fi

	shift 3
	while (( $# > 0 )); do
		case "${1}" in
			--dry-run)
				dry_run="true"
				shift
				;;
			--manual)
				manual="true"
				shift
				;;
			--track-id)
				if (( $# < 2 )); then
					usage_error "playlist add-gui --track-id requires a value." "playlist:add-gui"
					return $?
				fi
				selected_track_id="${2}"
				shift 2
				;;
			--wait)
				if (( $# < 2 )); then
					usage_error "playlist add-gui --wait requires a value." "playlist:add-gui"
					return $?
				fi
				wait_seconds="${2}"
				shift 2
				;;
			*)
				usage_error "Unknown playlist add-gui option: ${1}" "playlist:add-gui"
				return $?
				;;
		esac
	done

	require_non_empty_name "playlist:add-gui" "playlist add-gui" "${playlist_name}" || return $?
	require_non_empty_track_name "playlist:add-gui" "playlist add-gui" "${requested_track_name}" || return $?
	require_non_empty_artist_name "playlist:add-gui" "playlist add-gui" "${requested_artist_name}" || return $?
	if [[ -n "${selected_track_id}" && "${selected_track_id}" != <-> ]]; then
		usage_error "playlist add-gui --track-id must be numeric." "playlist:add-gui"
		return $?
	fi
	if [[ "${wait_seconds}" != <-> ]]; then
		usage_error "playlist add-gui --wait must be a non-negative integer." "playlist:add-gui"
		return $?
	fi

	ensure_mutable_playlist "${playlist_name}" || return $?
	response="$(catalog_search_response "${requested_track_name}" "${requested_artist_name}")" || return $?
	match_tsv="$(catalog_match_tsv "${requested_track_name}" "${requested_artist_name}" "${response}" "${selected_track_id}")" || return $?
	IFS=$'\t' read -r track_id track_name artist_name collection_name track_url <<< "${match_tsv}"

	if [[ "${dry_run}" == "true" ]]; then
		printf '%s\n' "Catalog match: ${track_name} by ${artist_name} | ${collection_name} | id:${track_id}"
		printf '%s\n' "Would open in Music.app, click Add to save it to Library, then add it to playlist: ${playlist_name}"
		printf '%s\n' "${track_url}"
		return 0
	fi

	if [[ "${manual}" == "true" ]]; then
		copy_to_clipboard "${track_url}"
		open_catalog_track_in_music "${track_url}" || return $?
		printf '%s\n' "Opened catalog track in Music.app: ${track_name} by ${artist_name}"
		printf '%s\n' "Target playlist: ${playlist_name}"
		printf '%s\n' "Track URL copied to clipboard."
		printf '%s\n' "In Music.app, use the song's More menu or Song > Add to Playlist, then choose ${playlist_name}."
		return 0
	fi

	library_count="$(wait_for_library_track "${track_name}" "${artist_name}" "${collection_name}" 0)" || return $?
	if (( library_count == 0 )); then
		click_music_add_button "${track_url}" "${wait_seconds}" || return $?
		library_count="$(wait_for_library_track "${track_name}" "${artist_name}" "${collection_name}" 20)" || return $?
		if (( library_count == 0 )); then
			print_error "Clicked Music.app Add button, but ${track_name} by ${artist_name} did not appear in Library."
			return "${EX_SOFTWARE}"
		fi
	fi
	duplicate_library_track_to_playlist_by_metadata "${playlist_name}" "${track_name}" "${artist_name}" "${collection_name}" >/dev/null || return $?
	verify_count="$(verify_playlist_track_name "${playlist_name}" "${track_name}")" || return $?
	if (( verify_count > 0 )); then
		printf '%s\n' "Added catalog track through Music.app UI: ${track_name} by ${artist_name} -> ${playlist_name}"
	else
		print_error "Music.app UI automation completed, but the track was not found in the target playlist."
		return "${EX_SOFTWARE}"
	fi
}

playlist_remove() {
	if wants_help "$@"; then
		playlist_command_usage "remove"
		return 0
	fi

	require_arg_count "playlist:remove" "playlist remove" 3 "$@" || return $?
	require_force "playlist:remove" "playlist remove" "${3}" || return $?
	require_non_empty_name "playlist:remove" "playlist remove" "${1}" || return $?
	require_non_empty_track_name "playlist:remove" "playlist remove" "${2}" || return $?
	run_applescript "removing track from playlist" \
		"${playlist_apple_script_helpers[@]}" \
		'on run argv' \
		'	set playlistName to item 1 of argv' \
		'	set trackName to item 2 of argv' \
		'	set playlistRef to my exactly_one_mutable_playlist(playlistName)' \
		'	tell application "Music"' \
		'		set matchedTracks to every track of playlistRef whose name is trackName' \
		'		set removedCount to count of matchedTracks' \
		'		if removedCount = 0 then' \
		'			error "Track not found in playlist: " & trackName number 64' \
		'		end if' \
		'		repeat with trackItem in matchedTracks' \
		'			delete trackItem' \
		'		end repeat' \
		'	end tell' \
		'	return "Removed " & removedCount & " track(s): " & trackName & " from " & playlistName' \
		'end run' \
		-- "$1" "$2"
}

playlist_clear() {
	if wants_help "$@"; then
		playlist_command_usage "clear"
		return 0
	fi

	require_arg_count "playlist:clear" "playlist clear" 2 "$@" || return $?
	require_force "playlist:clear" "playlist clear" "${2}" || return $?
	require_non_empty_name "playlist:clear" "playlist clear" "${1}" || return $?
	run_applescript "clearing playlist" \
		"${playlist_apple_script_helpers[@]}" \
		'on run argv' \
		'	set playlistName to item 1 of argv' \
		'	set playlistRef to my exactly_one_mutable_playlist(playlistName)' \
		'	tell application "Music"' \
		'		set playlistTracks to every track of playlistRef' \
		'		set removedCount to count of playlistTracks' \
		'		repeat with trackItem in playlistTracks' \
		'			delete trackItem' \
		'		end repeat' \
		'	end tell' \
		'	return "Cleared playlist: " & playlistName & " (removed " & removedCount & " track(s))"' \
		'end run' \
		-- "$1"
}

playlist() {
	local command="${1:-}"

	case "${command}" in
		""|help|-h|--help)
			playlist_usage
			;;
		list)
			shift
			playlist_list "$@"
			;;
		show)
			shift
			playlist_show "$@"
			;;
		create)
			shift
			playlist_create "$@"
			;;
		rename)
			shift
			playlist_rename "$@"
			;;
		delete)
			shift
			playlist_delete "$@"
			;;
		add)
			shift
			playlist_add "$@"
			;;
		add-catalog|add-streaming)
			shift
			playlist_add_catalog "$@"
			;;
		add-gui)
			shift
			playlist_add_gui "$@"
			;;
		search)
			shift
			playlist_search "$@"
			;;
		remove)
			shift
			playlist_remove "$@"
			;;
		clear)
			shift
			playlist_clear "$@"
			;;
		*)
			usage_error "Unknown playlist command: ${command}" "playlist"
			;;
	esac
}

main() {
	local command="${1:-}"

	case "${command}" in
		""|help|-h|--help)
			usage
			;;
		playlist)
			shift
			playlist "$@"
			;;
		*)
			usage_error "Unknown command: ${command}"
			;;
	esac
}

main "$@"

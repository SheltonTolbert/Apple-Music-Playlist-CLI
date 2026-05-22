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

require_command() {
	local command_name="${1}"

	if ! command -v "${command_name}" >/dev/null 2>&1; then
		print_error "Required command not found: ${command_name}"
		return "${EX_UNAVAILABLE}"
	fi
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

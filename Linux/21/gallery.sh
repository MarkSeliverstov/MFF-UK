#!/bin/bash

set -ueo pipefail

die() {
    local exit_code="$1"
    shift

    echo "[gallery.sh] Fatal error:" "$@" >&2
    exit "${exit_code}"
}

debug_msg() {
    echo "[gallery.sh $(date '+%Y-%m-%d %H:%M:%S' || true )]" "$@" >&2
}



# Extract image name from a given filename
get_name_from_image() {
    basename "$1" .jpg | tr -cd 'a-zA-Z0-9 .-_'
}

# Prints parameters as a JSON dictionary (no nesting).
# Expects parameter pairs, e.g.
# print_simple_json_dictionary key1 "value 1" key2 "value 2"
#
# Does not handle special characters
print_simple_json_dictionary() {
    echo '{'
    while [ $# -gt 0 ]; do
        echo " \"$1\": \"$2\""
        echo ,
        shift 2
    done | sed '$d'
    echo '}'
}

# Get list of albums.
# We make the names well-behaving: we want to copy them to a webserver
# and spaces and other special characters do not mix that well with URLs.
# Hence we skip anything that does not look like a valid directory name.
get_album_list() {
    find albums \
        -mindepth 1 \
        -maxdepth 1 \
        -iregex '.*/[-a-zA-Z0-9_.]+' \
        -type d \
        -exec basename {} \; \
        | sort
}

# Prepare images for one album: copy them to public_html and ensure
# they are named correctly.
prepare_images_for_one_album() {
	local album_dir="$1"
    local source_dir="$2"
    local dest_dir="$3"
	
	unset date_time title front_image
	if [ -f "${source_dir}/album.rc" ]; then
    	. "${source_dir}/album.rc"
	fi

    local title="${title:-"${album_dir}"}"
	local front_image="${front_image:-00000001.jpg}"

    ${debug} "Preparing images for album ${album_dir} (${title})."

    mkdir -p "${dest_dir}"
    (
        echo '{'
        printf '"title": "%s",\n' "${title}"
        echo '"images": ['
    ) >"${dest_dir}/.details"

	
    find "${source_dir}" -type f -iname '*.jpg' -print0 | sort -z | (
        counter=1
        while IFS='' read -r -d $'\0' source_image; do
            dest_image="$( printf "%08d.jpg" "${counter}" )"
            cp -f "${source_image}" "${dest_dir}/${dest_image}"
            image_name="$( get_name_from_image "${source_image}" )"
			date_time=$( identify -format "%[EXIF:DateTimeOriginal]" "${source_image}" )

			convert "${source_image}" -resize "$thumbnail_size" "${dest_dir}/thumb.${dest_image}"		
			thumb_real_size="$( identify "${dest_dir}/thumb.${dest_image}" | sed 's/.*JPEG //g' | grep -o '^[^ ]*' )"
			thumb_width="${thumb_real_size//x[0-9]*/}"
			thumb_hight="${thumb_real_size//[0-9]*x/}"

			if [ "$( basename "${source_image}" )" == "${front_image}" ]; then
				local front_image="${dest_image}"
			fi
            (
                print_simple_json_dictionary \
                    "filename" "${dest_image}" \
                    "thumbnail" "thumb.${dest_image}" \
                    "name" "${image_name}" \
					"date_time" "${date_time}" \
					"thumb_width" "${thumb_width}" \
					"thumb_height" "${thumb_hight}"
                echo ','
            ) >>"${dest_dir}/.details"
            counter=$(( counter + 1 ))
        done
		
    	echo "${album_dir} ${front_image} ${title}" >"${dest_dir}/.meta"
    )
    sed -e '$s/.*/]}/' "${dest_dir}/.details" | "${json_reformat}" >"${dest_dir}/.details.json"
    rm -f "${dest_dir}/.details"
}


# Setup debugging
if "${debug:-true}"; then
    debug=debug_msg
else
    debug=:
fi

# Check tool availability
json_reformat="$( command -v json_reformat || echo "cat" )"
${debug} "Will use ${json_reformat} for reformatting JSON data."

pandoc="$( command -v pandoc || true )"
[ -z "${pandoc}" ] && die 1 "pandoc executable not found, cannot continue."
${debug} "Found Pandoc executable at ${pandoc}."


# Setup path to template files (replace the following with something like
# /usr/local/share/nswi177-gallery when installing system wide).


# Load global configuration, if available
if [ -f gallery.rc ]; then
    . gallery.rc
fi
# Default configuration values
site_title="${site_title:-My photo gallery}"
publish_dir="${publish_dir:-public_html}"
thumbnail_size="${thumbnail_size:-200x200}"

if [ -z "${theme_dir+x}" ]; then
	data_files_dir="${data_files_dir:-}"
else
	data_files_dir="${theme_dir}"
fi

opts_short="d:t:"
opts_long="publish-dir:, theme-dir:"
getopt -Q -o "$opts_short" -l "$opts_long" -- "$@" || exit 1
eval set -- "$( getopt -o "$opts_short" -l "$opts_long" -- "$@" )"

while [ $# -gt 0 ]; do
    case "$1" in
        -d|--publish-dir)
            publish_dir="$2"
			shift
            ;;
        -t|--theme-dir)
            data_files_dir="$2"
			shift
            ;;
		--)
            shift
            break
            ;;
        *)
            echo "Unknown option $1" >&2
            exit 1
            ;;
    esac
	shift
done

if [ -z "${data_files_dir}" ]; then
    data_files_dir="$( dirname "$( realpath "${BASH_SOURCE[0]}" )" )"
fi
${debug} "Loading data files from ${data_files_dir}"

# Get list of albums (see get_album_list to understand why this is
# safe to be used in for loops).
if ! [ -d "albums" ]; then
    die 2 "No albums/ directory found."
fi
albums="$( get_album_list "albums" )"
${debug} "Found albums: $( echo "${albums}" | paste -s -d ' ' )."


# Prepare images for each album first
# We do not prepare the HTML pages yet as we have not yet discovered all
# the albums and we do not have their meta information (that might be
# needed for menu, for example).
for album in ${albums}; do
    prepare_images_for_one_album "${album}" "albums/${album}" "${publish_dir}/${album}"
done


# Create meta JSON for the whole site. This meta file is then added to
# each generated page so that each album page can create global menu of
# albums etc.
${debug} "Preparing global meta JSON file."
cat "${publish_dir}"/*/.meta | (
    echo '{'
    echo '  "site": {'
    printf '    "title": "%s",\n' "${site_title}"
    echo '    "albums": ['
    while read -r album_dir album_front_image album_title; do
        print_simple_json_dictionary \
            "dir" "${album_dir}" \
            "title" "${album_title}" \
            "image" "${album_front_image}"
        echo ','
    done
) | sed -e '$s/.*/]}}/' | "${json_reformat}" >"${publish_dir}"/.meta.json


# Generate the actual HTML page for each album. Notice that we pass
# two metadata files so that we allow album.tpl.html access both
# information about the current album as well as the overview information
# about the whole site.
for album in ${albums}; do
    ${debug} "Generating HTML page for album ${album}."
    ( cat "albums/${album}/HEADER.md" 2>/dev/null || true ) \
        | "${pandoc}" \
            --template "${data_files_dir}/album.tpl.html" \
            --metadata-file="${publish_dir}/${album}/.details.json" \
            --metadata-file="${publish_dir}/.meta.json" \
            >"${publish_dir}/${album}/index.html"
done

# Generate the index page. This one needs only the overview meta information
${debug} "Generating index page."
( cat HEADER.md 2>/dev/null || true ) \
    | "${pandoc}" \
            --template "${data_files_dir}/index.tpl.html" \
            --metadata-file="${publish_dir}/.meta.json" \
            "--metadata=title:${site_title}" \
            >"${publish_dir}/index.html"

${debug} "Will try to copy CSS files."
if [ -d "${data_files_dir}/assets" ]; then
    cp "${data_files_dir}/assets/"* "${publish_dir}"/
fi


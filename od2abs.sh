#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s [-r] AUDIOBOOK_DIR\n' "${0##*/}" >&2
  printf '\n' >&2
  printf 'Without -r, AUDIOBOOK_DIR must be a single Overdrive audiobook directory.\n' >&2
  printf 'With -r, AUDIOBOOK_DIR is searched recursively for Overdrive audiobook directories.\n' >&2
  printf '\n' >&2
  printf 'Expected Overdrive source: AUDIOBOOK_DIR/metadata/metadata.json\n' >&2
  printf 'Audiobookshelf output:      AUDIOBOOK_DIR/metadata.json\n' >&2
  printf 'Archived Overdrive source:  AUDIOBOOK_DIR/metadata/metadata.overdrive\n' >&2
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

has_audiobook_media() {
  local dir=$1
  local file
  local ext

  for file in "$dir"/*; do
    [[ -f $file ]] || continue
    ext=${file##*.}

    case $ext in
      [mM][pP]3 | \
      [mM]4[aA] | \
      [mM]4[bB] | \
      [aA][aA][cC] | \
      [fF][lL][aA][cC] | \
      [oO][gG][gG] | \
      [oO][gG][aA] | \
      [oO][pP][uU][sS] | \
      [wW][aA][vV] | \
      [wW][mM][aA])
        return 0
        ;;
    esac
  done

  return 1
}

is_overdrive_metadata() {
  local input_file=$1

  jq -e '
    type == "object"
    and (.title? | type == "string")
    and (.creator? | type == "array")
    and (.spine? | type == "array")
    and (.chapters? | type == "array")
    and ((.spine | length) > 0)
    and ((.chapters | length) > 0)
    and (([.spine[]? | select(has("duration"))] | length) == (.spine | length))
    and (([.chapters[]? | select(has("title") and has("spine") and has("offset"))] | length) == (.chapters | length))
  ' "$input_file" >/dev/null 2>&1
}

is_candidate_dir() {
  local book_dir=$1
  local metadata_dir=$book_dir/metadata
  local input_file=$metadata_dir/metadata.json

  [[ -d $metadata_dir ]] || return 1
  [[ -r $input_file ]] || return 1
  has_audiobook_media "$book_dir" || return 1
  is_overdrive_metadata "$input_file" || return 1
}

validate_book_dir() {
  local book_dir=$1
  local metadata_dir=$book_dir/metadata
  local input_file=$metadata_dir/metadata.json
  local overdrive_file=$metadata_dir/metadata.overdrive

  [[ -d $book_dir ]] || die "Audiobook directory does not exist: $book_dir"
  has_audiobook_media "$book_dir" || die "No audiobook media files found in: $book_dir"
  [[ -d $metadata_dir ]] || die "Overdrive metadata directory does not exist: $metadata_dir"
  [[ -r $input_file ]] || die "Overdrive metadata JSON is not readable: $input_file"
  is_overdrive_metadata "$input_file" || die "Metadata JSON does not look like Overdrive metadata: $input_file"
  [[ ! -e $overdrive_file ]] || die "Refusing to overwrite existing file: $overdrive_file"
  [[ -w $book_dir ]] || die "Audiobook directory is not writable: $book_dir"
  [[ -w $metadata_dir ]] || die "Overdrive metadata directory is not writable: $metadata_dir"
}

convert_book_dir() {
  local book_dir=$1
  local metadata_dir=$book_dir/metadata
  local input_file=$metadata_dir/metadata.json
  local output_file=$book_dir/metadata.json
  local overdrive_file=$metadata_dir/metadata.overdrive
  local tmp_file=$output_file.tmp.$$

  [[ ! -e $overdrive_file ]] || {
    printf 'Skipped: refusing to overwrite existing file: %s\n' "$overdrive_file" >&2
    return 1
  }

  if ! jq '
    def unique_preserve:
      reduce .[] as $item
        ([]; if index($item) then . else . + [$item] end);

    def role_names($role):
      [
        .creator[]?
        | select((.role // "" | ascii_downcase) == $role)
        | .name // empty
      ]
      | unique_preserve;

    def description_html:
      (.description.full // .description.short // null)
      | if . == null then
          null
        else
          gsub("<br\\s*/?>"; "<br /><br />")
        end;

    . as $root
    | ($root.spine // []) as $spine
    | (reduce range(0; ($spine | length)) as $i
        ([]; . + [
          if $i == 0 then
            0
          else
            (.[-1] + (($spine[$i - 1].duration // 0) | tonumber))
          end
        ])) as $spine_starts
    | ($root.chapters // []) as $source_chapters
    | [
        range(0; ($source_chapters | length)) as $i
        | ($source_chapters[$i]) as $chapter
        | ($chapter.spine // 0) as $spine_index
        | ((($spine_starts[$spine_index] // 0) + (($chapter.offset // 0) | tonumber))) as $start
        | (
            if ($i + 1) < ($source_chapters | length) then
              ($source_chapters[$i + 1]) as $next_chapter
              | ($next_chapter.spine // 0) as $next_spine_index
              | if $next_spine_index == $spine_index then
                  (((($spine_starts[$next_spine_index] // 0) + (($next_chapter.offset // 0) | tonumber)) - 0.001)
                    | if . < $start then $start else . end)
                else
                  (($spine_starts[$spine_index] // 0) + (($spine[$spine_index].duration // 0) | tonumber))
                end
            else
              (($spine_starts[$spine_index] // 0) + (($spine[$spine_index].duration // 0) | tonumber))
            end
          ) as $chapter_end
        | {
            start: $start,
            end: $chapter_end,
            title: ($chapter.title // ""),
            id: $i
          }
      ] as $abs_chapters
    | {
        tags: [],
        chapters: $abs_chapters,
        title: (.title // null),
        subtitle: null,
        authors: role_names("author"),
        narrators: role_names("narrator"),
        series: [],
        genres: [],
        publishedYear: null,
        publishedDate: null,
        publisher: null,
        description: description_html,
        isbn: null,
        asin: null,
        language: null,
        explicit: false,
        abridged: false
      }
  ' "$input_file" > "$tmp_file"; then
    rm -f -- "$tmp_file"
    printf 'Failed: %s\n' "$book_dir" >&2
    return 1
  fi

  mv -f -- "$tmp_file" "$output_file"
  mv -- "$input_file" "$overdrive_file"

  printf 'Converted: %s\n' "$book_dir"
}

recursive=false

while getopts ':r' opt; do
  case $opt in
    r)
      recursive=true
      ;;
    *)
      usage
      exit 1
      ;;
  esac
done

shift $((OPTIND - 1))

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

root_dir=$1

command -v jq >/dev/null 2>&1 || die 'jq was not found in PATH'
[[ -d $root_dir ]] || die "Directory does not exist: $root_dir"

if [[ $recursive == false ]]; then
  validate_book_dir "$root_dir"
  convert_book_dir "$root_dir"
  exit 0
fi

converted_count=0

while IFS= read -r -d '' candidate_dir; do
  if is_candidate_dir "$candidate_dir"; then
    if convert_book_dir "$candidate_dir"; then
      converted_count=$((converted_count + 1))
    fi
  fi
done < <(find "$root_dir" -type d -print0)

printf 'Converted directories: %d\n' "$converted_count"

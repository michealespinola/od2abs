#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: %s AUDIOBOOK_DIR\n' "${0##*/}" >&2
  printf '\n' >&2
  printf 'Expected Overdrive source: AUDIOBOOK_DIR/metadata/metadata.json\n' >&2
  printf 'Audiobookshelf output:      AUDIOBOOK_DIR/metadata.json\n' >&2
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

cleanup() {
  if [[ ${tmp_file:-} && -e $tmp_file ]]; then
    rm -f -- "$tmp_file"
  fi
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

book_dir=$1
metadata_dir=$book_dir/metadata
input_file=$metadata_dir/metadata.json
output_file=$book_dir/metadata.json
overdrive_file=$metadata_dir/metadata.overdrive
tmp_file=$output_file.tmp.$$

trap cleanup EXIT

[[ -d $book_dir ]] || die "Audiobook directory does not exist: $book_dir"
[[ -d $metadata_dir ]] || die "Overdrive metadata directory does not exist: $metadata_dir"
[[ -r $input_file ]] || die "Overdrive metadata JSON is not readable: $input_file"
[[ ! -e $overdrive_file ]] || die "Refusing to overwrite existing file: $overdrive_file"
[[ -w $book_dir ]] || die "Audiobook directory is not writable: $book_dir"
[[ -w $metadata_dir ]] || die "Overdrive metadata directory is not writable: $metadata_dir"
command -v jq >/dev/null 2>&1 || die 'jq was not found in PATH'

jq '
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
' "$input_file" > "$tmp_file"

mv -f -- "$tmp_file" "$output_file"
tmp_file=

mv -- "$input_file" "$overdrive_file"

printf 'Wrote:   %s\n' "$output_file"
printf 'Renamed: %s -> %s\n' "$input_file" "$overdrive_file"

# od2abs
OverDrive 2 AudioBookShelf

* PLEASE NOTE: When using the `-r` recursive search option, this should be run against top-level library directories where the first subdirectory should be the author name. You can technically run it higher in the directory heirarchy, but you shouldn't unless you want to risk odd renaming behavior that might cause weird directory nesting - particularly when renaming series directories. The nesting is easy to recover from (simply move them back to were they should be), but its better to avoid making the mistake in the first place.

I created this script to work specifically with the output from [LibbyRip](https://github.com/PsychedelicPalimpsest/LibbyRip)/[LibreGRAB](https://greasyfork.org/en/scripts/498782-libregrab) TamperMonkey script. It converts the OverDrive format metadata.json into Audiobookshelf's expected JSON format and stores it side-car'd with the audio files. This makes importing books into Audiobookshelf much easier, and includes datafields that are frequently missed or inaccurate, such as the full authors list as well as the full narrators list.

I later added functionality to rename the directory structure based on first-author and book title. If you have added book series info to Audiobookshelf and have it configured to "Store metadata with item" to save the metadata to a metadata.json file in the audiobook's directory, the script will read the first-series name and use that to further organize the directory structure. It will rename accordingly to which fields are populated:

* Original -> BookTitle
* Original -> Author/BookTitle
* Original -> Author/Series/BookTitle

### Example #1

```
# tree -d -L 2 "/volume2/vault/AudioBooks/Fiction/Frank Herbert"
/volume2/vault/AudioBooks/Fiction/Frank Herbert
└── Dune
    ├── Chapterhouse Dune
    ├── Children of Dune
    ├── Dune
    ├── Dune Messiah
    ├── God Emperor of Dune
    └── Heretics of Dune
```

### Example #2

```
# tree -d -L 2 "/volume2/vault/AudioBooks/Fiction/J. K. Rowling"
/volume2/vault/AudioBooks/Fiction/J. K. Rowling
├── Harry Potter
│   ├── Harry Potter and the Chamber of Secrets
│   ├── Harry Potter and the Deathly Hallows
│   ├── Harry Potter and the Goblet of Fire
│   ├── Harry Potter and the Half-Blood Prince
│   ├── Harry Potter and the Order of the Phoenix
│   ├── Harry Potter and the Philosopher's Stone
│   └── Harry Potter and the Prisoner of Azkaban
└── Harry Potter - Hogwarts Library
    ├── Fantastic Beasts and Where to Find Them
    ├── Quidditch Through the Ages
    └── The Tales of Beedle the Bard
```

I'll add more documentation when I get back to documenting the code internally. For now, this POC works against freshly downloaded Overdrive books and makes importing into Audiobookshelf a lot cleaner and accurate. Ultimately this will be converted into a python script to possibly add to the LibbyRip repository.

To work with JSON this script requires the `jq` tool. Do you have `jq`? *It'd be a lot cooler if you did...*

### ✌️

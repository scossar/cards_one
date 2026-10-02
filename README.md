# CardsOne

## Catalogue configuration

On startup, Cards One creates `config.toml` in the operating system's user config
directory (on Linux, `$XDG_CONFIG_HOME/cards_one/config.toml`, normally
`~/.config/cards_one/config.toml`). Existing config files are preserved.

```toml
catalogue-directory = ""
```

Set `catalogue-directory` to an existing directory where your Markdown cards will
live, for example `catalogue-directory = "/home/you/notes/cards"`. Relative paths
are resolved from the config file's directory; `~/` paths are supported too.
Cards One checks that it can create and remove a temporary file in the directory.
An empty, missing, or unwritable directory produces a notice on `/`. Invalid or
unreadable config files also produce a notice. Reload `/` after editing the file
to check the updated setting. The app does not create the catalogue directory.

## Cards

Card CRUD writes Markdown files first, then updates their SQLite copies. The
filesystem remains the source of truth. New cards receive a Unix timestamp filename such as
`1790921230.md`; if it already exists, a microsecond timestamp is used instead.
The filename is also the card's title and URL identifier, and stays unchanged
when editing the body.

The editor and read view show full Markdown syntax as plain text. Bodies are
preserved in the files, including whitespace, fenced code, and HTML examples.
Phoenix escapes the displayed text so HTML and script tags cannot execute.
Empty notes are allowed; no Markdown parser is required for this stage.

Existing `.md` files in the catalogue's top level are read directly. External
file additions, edits, and deletions appear on the next visit. Subdirectories and
symbolic links are ignored. Save errors leave the editor open, and delete errors
leave the card listed with a flash notice.

## Rebuilding SQLite

The database has a unique index on `cards.filename`. Catalogue synchronization
imports new files, updates existing bodies by filename, and removes records
whose files no longer exist. It runs at app startup and whenever the card list
is opened. A failed or incomplete filesystem scan leaves the database untouched.

To rebuild the database from the configured catalogue, run:

```sh
mix cards.sync
```

This command creates a missing database, runs migrations, and synchronizes all
cards from disk. It can be used after losing the SQLite database. The Markdown
files are preserved; database row IDs and bookkeeping timestamps may change
after a rebuild. Card URLs continue to use filenames.

If a database write fails after a file was saved or deleted, the file change is
kept and the app displays a warning. Reload the card list or run `mix cards.sync`
to repair the database copy. Switching the configured catalogue replaces the
database index with the contents of the new directory.

## Search

`/search` searches card filenames and Markdown bodies with SQLite FTS5. Results
are ordered by relevance and shown in pages of 20 with plain-text excerpts and
links to the cards. Queries are kept in the URL so they can be bookmarked.

Native FTS5 queries (quoted phrases, prefixes, boolean operators, column filters,
and proximity queries) are accepted directly by the input. The interface keeps
the syntax implicit and reports malformed queries with a plain notice.

Database triggers keep the full-text index current after card writes. Each
search reconciles external file changes before querying, and `mix cards.sync`
rebuilds the full-text index as well as the SQLite card copies. Search excerpts
are HTML-escaped just like card bodies.

### Semantic search

Select **Semantic** on `/search` to search by meaning. Bumblebee/Nx runs the
pinned `sentence-transformers/all-MiniLM-L6-v2` model locally with EXLA on the CPU.
Exqlite loads the bundled sqlite-vec native library into every Repo connection and stores 384-dimensional
float32 vectors in a `vec0` table. Searches use cosine distance, group matches
by file, and paginate results. Semantic search returns the closest indexed cards;
there is currently no similarity cutoff.

Embedding records have independent integer IDs. The filename is non-unique
metadata, alongside the source card ID, content hash, model/pipeline version,
position and embedded text. Multiple embeddings can belong to one file.
Chunking is deliberately deferred: for now each nonblank card has one embedding,
and only its first 256 tokens (including special tokens) are considered. The
filename is not included in the model input. Generated documents are not indexed yet.

Model loading and indexing happen in supervised background tasks. Card writes
invalidate obsolete vectors atomically; unchanged cards keep their embeddings.
External file changes are reconciled on the next card list/search/sync. Results
report pending indexing, and stale inference results are discarded if a card
changed or disappeared while inference was running. Model failures are retried
and do not prevent card CRUD or full-text search.

`mix cards.sync` recreates the database tables and reconciles source files.
The running app then regenerates missing embeddings in the background. The
command itself does not wait for embedding generation before exiting.

The first launch downloads model assets into `~/.cache/cards_one/models`.
`CARDS_ONE_MODEL_CACHE` overrides that directory. After warming this cache,
`CARDS_ONE_MODEL_OFFLINE=true` prevents Hugging Face requests. Alternatively,
`CARDS_ONE_MODEL_DIR` loads local model assets instead; they must match the pinned
revision in `CardsOne.SemanticSearch.Model`.

For desktop distribution, ship those model assets and set `CARDS_ONE_MODEL_DIR`,
or arrange the initial download. Elixir releases include sqlite-vec from the
application's own `priv/sqlite` directory, and the tokenizer NIF and EXLA native
libraries from their dependencies. EXLA is configured to build for CPU even when
CUDA tools are installed. The `sqlite_vec` Hex wrapper is no longer a dependency,
so it no longer constrains Nx upgrades. The current stack uses Bumblebee 0.8.0,
Nx 1.0.0 and EXLA 1.0.0. This upgrade changes the embedding configuration key,
so existing semantic embeddings are automatically regenerated on startup.
The ordinary test suite uses deterministic embedding fixtures and does not download models.

### Native SQLite extension

sqlite-vec is pinned to native version **0.1.5**, the same version previously
provided by the Hex wrapper. The upstream shared libraries for Linux (glibc)
x86-64/AArch64, macOS x86-64/AArch64, and Windows x86-64 are bundled in
`priv/sqlite/0.1.5/`. Only Linux x86-64 has been execution-tested here.
The runtime selects the matching platform, verifies its SHA-256 checksum, and
resolves its absolute path relative to the installed application. No download
or build tools are needed at application startup. Missing, corrupted, or
unsupported libraries produce an explicit startup error.

Run `mix sqlite_vec.install --all` to verify bundled files offline, or
`mix sqlite_vec.install --all --force` to reproduce them from the pinned upstream
archives. `--target linux-aarch64` selects an individual platform; the default is
the current platform. Both archive and library checksums are checked before a
download replaces a file. Run restoration before building a release.
See `priv/sqlite/README.md` for provenance, licensing and upgrade instructions.

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://phoenix.hexdocs.pm/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://phoenix.hexdocs.pm/overview.html
* Docs: https://phoenix.hexdocs.pm
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

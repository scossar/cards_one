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

This configuration step does not yet change the generated card CRUD to read or
write Markdown files.

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

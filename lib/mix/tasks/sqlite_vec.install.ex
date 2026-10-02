defmodule Mix.Tasks.SqliteVec.Install do
  use Mix.Task

  @shortdoc "Verifies or restores the pinned sqlite-vec native library"
  @moduledoc """
  The native libraries are bundled in priv/sqlite and included in releases.
  This maintenance task reproduces them from upstream release archives, checking
  both the archive and extracted library against priv/sqlite/manifest.json.
  It never starts the application or connects to the database.

      mix sqlite_vec.install
      mix sqlite_vec.install --target linux-aarch64
      mix sqlite_vec.install --all --force

  Existing files are verified without network access. Missing files are downloaded.
  Use --force to download again, including when replacing a corrupted artifact.
  Run this task before assembling a release if restoring missing source artifacts.
  """
  @requirements ["app.config"]

  alias CardsOne.SQLiteExtension

  @impl true
  def run(args) do
    {opts, rest} =
      OptionParser.parse!(args, strict: [target: :string, all: :boolean, force: :boolean])

    if rest != [], do: Mix.raise("Unexpected arguments: #{Enum.join(rest, " ")}")
    if opts[:all] && opts[:target], do: Mix.raise("Use either --all or --target")

    targets =
      if opts[:all],
        do: SQLiteExtension.targets(),
        else: [opts[:target] || SQLiteExtension.target!()]

    Enum.each(targets, &install(&1, opts[:force] == true))
  end

  defp install(target, force?) do
    unless target in SQLiteExtension.targets(),
      do: Mix.raise("Unknown sqlite-vec target: #{target}")

    artifact = SQLiteExtension.artifact!(target)
    path = Path.expand(SQLiteExtension.relative_path(target))

    if File.regular?(path) and not force? do
      SQLiteExtension.verify!(File.read!(path), artifact["sha256"])
      Mix.shell().info("Verified sqlite-vec #{SQLiteExtension.version()} for #{target}")
    else
      {:ok, _} = Application.ensure_all_started(:req)

      url =
        "https://github.com/asg017/sqlite-vec/releases/download/v#{SQLiteExtension.version()}/" <>
          "sqlite-vec-#{SQLiteExtension.version()}-loadable-#{target}.tar.gz"

      response = Req.get!(url, decode_body: false, redirect_log_level: false)

      unless response.status == 200,
        do: Mix.raise("sqlite-vec download failed: HTTP #{response.status}")

      SQLiteExtension.verify!(response.body, artifact["archive_sha256"])

      # Extract in memory and write only the expected library, never archive paths.
      {:ok, files} = :erl_tar.extract({:binary, response.body}, [:compressed, :memory])

      {_, binary} =
        Enum.find(files, fn {name, _} -> to_string(name) == artifact["filename"] end) ||
          Mix.raise("sqlite-vec archive does not contain #{artifact["filename"]}")

      SQLiteExtension.verify!(binary, artifact["sha256"])
      File.mkdir_p!(Path.dirname(path))
      temporary = path <> ".#{System.unique_integer([:positive])}.tmp"

      try do
        File.write!(temporary, binary, [:exclusive])
        File.rename!(temporary, path)
      after
        File.rm(temporary)
      end

      Mix.shell().info("Installed sqlite-vec #{SQLiteExtension.version()} for #{target}")
    end
  end
end

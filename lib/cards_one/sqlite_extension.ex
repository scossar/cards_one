defmodule CardsOne.SQLiteExtension do
  @moduledoc "Resolves the bundled sqlite-vec shared library without a Hex wrapper or runtime download."

  @external_resource Path.expand("../../priv/sqlite/manifest.json", __DIR__)
  @manifest @external_resource |> File.read!() |> Jason.decode!()

  def version, do: @manifest["version"]
  def targets, do: @manifest["artifacts"] |> Map.keys() |> Enum.sort()

  def artifact!(target), do: Map.fetch!(@manifest["artifacts"], target)

  def relative_path(target) do
    Path.join(["priv", "sqlite", version(), target, artifact!(target)["filename"]])
  end

  def path! do
    path = Application.app_dir(:cards_one, relative_path(target!()))

    case File.read(path) do
      {:ok, binary} ->
        verify!(binary, artifact!(target!())["sha256"])
        path

      {:error, reason} ->
        raise "Cannot read bundled sqlite-vec library #{path}: #{:file.format_error(reason)}. " <>
                "Run mix sqlite_vec.install before building the application."
    end
  end

  def verify!(binary, expected_sha256) do
    actual = :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)

    unless actual == expected_sha256 do
      raise "sqlite-vec checksum mismatch: expected #{expected_sha256}, got #{actual}"
    end

    :ok
  end

  def target!(
        os \\ :os.type(),
        architecture \\ to_string(:erlang.system_info(:system_architecture))
      ) do
    platform =
      case os do
        {:unix, :linux} -> "linux"
        {:unix, :darwin} -> "macos"
        {:win32, _} -> "windows"
        _ -> nil
      end

    cpu =
      cond do
        String.starts_with?(architecture, ["aarch64", "arm64"]) -> "aarch64"
        String.starts_with?(architecture, ["x86_64", "amd64"]) -> "x86_64"
        architecture == "win32" and :erlang.system_info(:wordsize) == 8 -> "x86_64"
        true -> nil
      end

    target = "#{platform}-#{cpu}"

    if target in targets() and not String.contains?(architecture, "musl") do
      target
    else
      raise "No bundled sqlite-vec library for #{inspect(os)} / #{architecture}. " <>
              "Add a compatible artifact and checksum before building for this platform."
    end
  end
end

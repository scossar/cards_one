defmodule CardsOne.Config do
  @moduledoc """
  Reads the user's catalogue configuration without replacing existing settings.
  Relative catalogue paths are resolved against the config file's directory.
  """

  @default_config "catalogue-directory = \"\"\n"

  def path do
    Application.get_env(:cards_one, :config_file) ||
      Path.join(:filename.basedir(:user_config, "cards_one"), "config.toml")
  end

  def ensure_file(config_file \\ path()) do
    with :ok <- File.mkdir_p(Path.dirname(config_file)) do
      case File.write(config_file, @default_config, [:exclusive]) do
        {:error, :eexist} -> :ok
        result -> result
      end
    end
  end

  def catalogue_directory(config_file \\ path()) do
    with :ok <- ensure_config(config_file),
         {:ok, contents} <- read_config(config_file),
         {:ok, config} <- decode_config(contents, config_file),
         {:ok, directory} <- configured_directory(config, config_file),
         :ok <- check_directory(directory) do
      {:ok, directory}
    end
  end

  defp ensure_config(config_file) do
    case ensure_file(config_file) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, "Cannot create config file #{config_file}: #{file_error(reason)}."}
    end
  end

  defp read_config(config_file) do
    case File.read(config_file) do
      {:ok, contents} ->
        {:ok, contents}

      {:error, reason} ->
        {:error, "Cannot read config file #{config_file}: #{file_error(reason)}."}
    end
  end

  defp decode_config(contents, config_file) do
    case Toml.decode(contents) do
      {:ok, config} ->
        {:ok, config}

      {:error, _reason} ->
        {:error, "Invalid TOML in #{config_file}. Please check the config file."}
    end
  end

  defp configured_directory(config, config_file) do
    case Map.get(config, "catalogue-directory", "") do
      directory when is_binary(directory) ->
        if String.trim(directory) == "" do
          {:error, "Set catalogue-directory in #{config_file} to an existing writable directory."}
        else
          {:ok, Path.expand(directory, Path.dirname(config_file))}
        end

      _ ->
        {:error, "catalogue-directory in #{config_file} must be a string."}
    end
  end

  defp check_directory(directory) do
    case File.stat(directory) do
      {:ok, %File.Stat{type: :directory}} ->
        check_writable(directory)

      {:ok, _stat} ->
        {:error, "The catalogue path #{directory} is not a directory."}

      {:error, :enoent} ->
        {:error, "The catalogue directory #{directory} does not exist."}

      {:error, reason} ->
        {:error, "Cannot access the catalogue directory #{directory}: #{file_error(reason)}."}
    end
  end

  defp check_writable(directory) do
    # A real create/delete check catches filesystem and ACL restrictions too.
    probe = Path.join(directory, ".cards-one-write-check-#{Ecto.UUID.generate()}")

    case File.write(probe, "", [:exclusive]) do
      :ok ->
        case File.rm(probe) do
          :ok ->
            :ok

          {:error, reason} ->
            {:error, "Cannot remove files in #{directory}: #{file_error(reason)}."}
        end

      {:error, reason} ->
        {:error, "The catalogue directory #{directory} is not writable: #{file_error(reason)}."}
    end
  end

  defp file_error(reason), do: reason |> :file.format_error() |> to_string()
end

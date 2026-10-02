defmodule CardsOne.SQLiteExtensionTest do
  use CardsOne.DataCase

  alias CardsOne.SQLiteExtension

  test "all bundled artifacts match the pinned checksums" do
    for target <- SQLiteExtension.targets() do
      path = Application.app_dir(:cards_one, SQLiteExtension.relative_path(target))

      assert :ok =
               SQLiteExtension.verify!(
                 File.read!(path),
                 SQLiteExtension.artifact!(target)["sha256"]
               )
    end
  end

  test "loads the application-owned native library into the Repo" do
    path = SQLiteExtension.path!()
    assert String.starts_with?(path, Application.app_dir(:cards_one, "priv/sqlite/"))
    assert %{rows: [["v0.1.5"]]} = Repo.query!("SELECT vec_version()")
    assert %{rows: [[distance]]} = Repo.query!("SELECT vec_distance_cosine('[1,0]', '[1,0]')")
    assert_in_delta distance, 0, 0.00001
    refute :sqlite_vec in Application.spec(:cards_one, :applications)
  end

  test "selects the runtime OS and architecture" do
    assert SQLiteExtension.target!({:unix, :linux}, "x86_64-pc-linux-gnu") == "linux-x86_64"

    assert SQLiteExtension.target!({:unix, :linux}, "aarch64-unknown-linux-gnu") ==
             "linux-aarch64"

    assert SQLiteExtension.target!({:unix, :darwin}, "aarch64-apple-darwin") == "macos-aarch64"
    assert SQLiteExtension.target!({:unix, :darwin}, "x86_64-apple-darwin") == "macos-x86_64"
    assert SQLiteExtension.target!({:win32, :nt}, "x86_64-pc-windows-msvc") == "windows-x86_64"
  end

  test "rejects unsupported platforms instead of selecting an incompatible binary" do
    for {os, architecture} <- [
          {{:unix, :linux}, "x86_64-pc-linux-musl"},
          {{:unix, :freebsd}, "x86_64-unknown-freebsd"},
          {{:unix, :linux}, "armv7-linux-gnueabihf"},
          {{:win32, :nt}, "aarch64-pc-windows-msvc"}
        ] do
      assert_raise RuntimeError, ~r/No bundled sqlite-vec library/, fn ->
        SQLiteExtension.target!(os, architecture)
      end
    end
  end

  test "rejects a modified library before it can be loaded" do
    target = SQLiteExtension.target!()
    binary = File.read!(SQLiteExtension.path!())

    assert_raise RuntimeError, ~r/sqlite-vec checksum mismatch/, fn ->
      SQLiteExtension.verify!(binary <> "modified", SQLiteExtension.artifact!(target)["sha256"])
    end
  end
end

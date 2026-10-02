# Bundled sqlite-vec

These are unmodified loadable libraries from the upstream sqlite-vec v0.1.5
release: https://github.com/asg017/sqlite-vec/releases/tag/v0.1.5

They are application assets, independent of Elixir/Nx. All five platform files
are intentionally checked into the repository so builds and application startup
can use them offline. Linux builds target glibc, not musl. Only Linux x86-64 has
been execution-tested in this project; other binaries are verified upstream assets.

`manifest.json` pins SHA-256 digests of both the upstream archives and extracted
libraries. Archive digests were checked against the published sqlite_vec 0.1.0
downloader's v0.1.5 checksums; library digests were calculated after verifying the
archives. Files are redistributed under the included upstream MIT license.

To verify all bundled files without downloading:

```sh
mix sqlite_vec.install --all
```

To reproduce them from upstream:

```sh
mix sqlite_vec.install --all --force
```

To upgrade, review the upstream release, update the version and checksums in the
manifest, restore the artifacts, and verify migrations, vector queries, and a
relocated offline release. Do not replace the manifest hashes merely to silence
a checksum failure.

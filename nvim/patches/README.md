# Lumen sidebar selection fix

`lumen-2.32.0-sidebar.patch` fixes the sidebar snapping back to the open file
when watch mode reloads a diff. It preserves the highlighted file or directory
by path, independently of the open diff, and includes a regression test for
repeated reloads, reordered files, and removed selections.

The fix belongs to Lumen itself; the Neovim launcher needs no changes.
The patch applies to the published Lumen 2.32.0 crate.

## Rebuild and install

Run from this dotfiles checkout with Rust, curl, tar, and patch installed:

```sh
(
set -eu
patch_file="$PWD/nvim/patches/lumen-2.32.0-sidebar.patch"
mkdir -p "$HOME/.local/src"
lumen_source=$(mktemp -d "$HOME/.local/src/lumen-sidebar.XXXXXX")
curl -fL https://crates.io/api/v1/crates/lumen/2.32.0/download \
  -o "$lumen_source/source.crate"
tar -xzf "$lumen_source/source.crate" -C "$lumen_source" --strip-components=1
patch -d "$lumen_source" -p1 < "$patch_file"
cd "$lumen_source"
cargo test --release --locked --jobs 2 command::diff::state::tests
cargo install --path . --locked --force --jobs 2
)
```

Close and reopen Lumen after installation. This replaces the user-local
`lumen` binary; a later upstream installation can overwrite the patch.
Keep the source directory to reuse its build cache for subsequent rebuilds.

Validation: six sidebar-state tests passed, and the Neovim floating launcher
passed held-`j` navigation, idle time, file changes, Enter selection, and upward
navigation in both ordinary and watch modes. The original binary failed the
watch-mode navigation check.

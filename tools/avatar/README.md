# Avatar assets

The page runs locally. Flutter supplies the model bytes on native platforms, and the web page loads the model from its own directory.

The bundle pins three.js `0.187.0`, `@pixiv/three-vrm` `3.5.5`, and esbuild `0.25.10`. Rebuilding requires Node.js 20 or newer and Python 3. Texture optimization uses macOS `sips`.

With a staged dependency directory `DEPS` that includes `node_modules` and the original `Seed-san.vrm`, run from the repository root.

```sh
node --test tools/avatar/test/
python3 -I -B tools/avatar/build.py --deps "$DEPS"
python3 -I -B tools/avatar/optimize_vrm.py optimize "$DEPS/Seed-san.vrm" assets/avatar/seed.vrm
python3 -I -B tools/avatar/optimize_vrm.py check assets/avatar/seed.vrm --source "$DEPS/Seed-san.vrm"
```

For an online rebuild, omit `--deps` to install the pinned npm dependencies into a temporary directory. Obtain the original model from the [VRM specification sample directory](https://raw.githubusercontent.com/vrm-c/vrm-specification/master/samples/Seed-san/vrm/Seed-san.vrm). The source SHA-256 is `624d0d554bc205bbdc33e22a68a2c3c20edebb3e573011ead8878a65e5329b23`.

Seed-san © VirtualCast, Inc. is distributed under the VRM Public License 1.0. three.js and @pixiv/three-vrm are distributed under the MIT license. See [asset licenses](../../assets/avatar/LICENSES.md).

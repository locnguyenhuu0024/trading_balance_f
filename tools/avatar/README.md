# Avatar assets

The page runs locally. Flutter supplies the model bytes on native platforms, and the web page loads the model from its own directory.

The bundle pins three.js `0.187.0`, `@pixiv/three-vrm` `3.5.5`, and esbuild `0.25.10`. Rebuilding requires Node.js 20 or newer and Python 3. Texture optimization uses macOS `sips`.

With a staged dependency directory `DEPS` that includes `node_modules` and the original model saved as `Twist.vrm`, run from the repository root.

```sh
node --test tools/avatar/test/
python3 -I -B tools/avatar/build.py --deps "$DEPS"
python3 -I -B tools/avatar/optimize_vrm.py optimize "$DEPS/Twist.vrm" assets/avatar/avatar.vrm
python3 -I -B tools/avatar/optimize_vrm.py check assets/avatar/avatar.vrm --source "$DEPS/Twist.vrm"
```

For an online rebuild, omit `--deps` to install the pinned npm dependencies into a temporary directory. Download the [original VRM1_Constraint_Twist_Sample model](https://raw.githubusercontent.com/vrm-c/vrm-specification/master/samples/VRM1_Constraint_Twist_Sample/vrm/VRM1_Constraint_Twist_Sample.vrm) and save it as `Twist.vrm`. The source SHA-256 is `12c2b97e95e700783a6a550dc0eee2d7880aeedccef9ae67bc4c5a2f0f2631a2`.

`VRM1_Constraint_Twist_Sample` (c) 2022 pixiv Inc. is distributed under the VRM Public License 1.0. three.js and @pixiv/three-vrm are distributed under the MIT license. See [asset licenses](../../assets/avatar/LICENSES.md).

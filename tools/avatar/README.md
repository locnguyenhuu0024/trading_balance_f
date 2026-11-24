# Avatar assets

The page runs locally. Flutter supplies the model bytes on native platforms. On web, `index.html?model=donut-chan` loads Donut-Chan from the page directory. The default is `pixiv-sample`.

Send `{"v":1,"type":"setColors","colors":{"hair":"#8844cc","eyes":"#1A9FFF"}}` to recolor model parts. Both models support `hair`, `eyes`, and `shoes`. The pixiv sample also supports `top` and `bottom`. Donut-Chan also supports `accessory`, `dress`, `bows`, `socks`, and `plasters`. Each message replaces the full color state. Omitted parts use their original textures, and `"colors":{}` resets all parts. Colors received during loading apply before the first frame. Later updates apply at most once per 100 ms using the latest message.

The bundle pins three.js `0.187.0`, `@pixiv/three-vrm` `3.5.5`, and esbuild `0.25.10`. Rebuilding requires Node.js 20 or newer and Python 3. Texture optimization uses macOS `sips`.

With a staged dependency directory `DEPS` containing `node_modules`, `Twist.vrm`, and `Donut-Chan.vrm`, run from the repository root.

```sh
node --test tools/avatar/test/
python3 -I -B tools/avatar/build.py --deps "$DEPS"
python3 -I -B tools/avatar/optimize_vrm.py optimize "$DEPS/Twist.vrm" assets/avatar/pixiv-sample.vrm --thumbnail-out assets/avatar/pixiv-sample.png
python3 -I -B tools/avatar/optimize_vrm.py optimize "$DEPS/Donut-Chan.vrm" assets/avatar/donut-chan.vrm --thumbnail-out assets/avatar/donut-chan.png
python3 -I -B tools/avatar/optimize_vrm.py check assets/avatar/pixiv-sample.vrm --source "$DEPS/Twist.vrm" --max-bytes 6000000
python3 -I -B tools/avatar/optimize_vrm.py check assets/avatar/donut-chan.vrm --source "$DEPS/Donut-Chan.vrm" --max-bytes 10000000
```

The optimizer defaults to a 1024 px limit for textures and a 256 px limit for thumbnails.

For an online bundle rebuild, omit `--deps` to install the pinned npm dependencies into a temporary directory.

- Save the original VRM1_Constraint_Twist_Sample as `Twist.vrm`. Its SHA-256 is `12c2b97e95e700783a6a550dc0eee2d7880aeedccef9ae67bc4c5a2f0f2631a2`. [Original model](https://raw.githubusercontent.com/vrm-c/vrm-specification/master/samples/VRM1_Constraint_Twist_Sample/vrm/VRM1_Constraint_Twist_Sample.vrm)
- Save Donut-Chan by Kana Fuyuko (Public Domain) as `Donut-Chan.vrm`. Its SHA-256 is `e8637e8134ccba06d3751b3ed79d3f04e03a0061e4bc9012e247ec1d53d2ae58`. [BOOTH item 5975245](https://booth.pm/en/items/5975245)

`VRM1_Constraint_Twist_Sample` (c) 2022 pixiv Inc. is distributed under the VRM Public License 1.0. three.js and @pixiv/three-vrm are distributed under the MIT license. See [asset licenses](../../assets/avatar/LICENSES.md).

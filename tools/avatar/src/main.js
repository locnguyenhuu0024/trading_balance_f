import {
  AmbientLight, DirectionalLight, Group, LoadingManager, Object3D, OrthographicCamera,
  Scene, Skeleton, SkinnedMesh, Source, Vector3, WebGLRenderer,
} from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';
import {VRMLoaderPlugin, VRMUtils} from '@pixiv/three-vrm';
import {connect, send} from './bridge.js';
import {createAssembler} from './chunks.js';
import {frame as frameAvatar} from './framing.js';
import {createClassifier} from './gesture.js';
import {createHitTest} from './hit.js';
import {ITEMS, itemForMaterial, resolveOutfit} from './items.js';
import {motion, step, targets} from './mood.js';
import {MODELS, resolveModel} from './models.js';
import {axisSign, restPose} from './pose.js';
import {bindMatrix, boneKey, flipFor, flipLocal, planChain, primaryMaterial, rebindInverse} from './rebind.js';
import {colorize, luminance, parseHex, partForMaterial} from './recolor.js';

const FRAME_MS = 1000 / 30;
const MAX_DELTA = 1 / 15;
const COLOR_INTERVAL_MS = 100;
const EXPRESSIONS = ['happy', 'sad', 'relaxed', 'surprised', 'blink'];
const ITEM_IDS = Object.keys(ITEMS);

function materialName({material}) {
  return primaryMaterial(material)?.name;
}

async function fetchModel(url) {
  const response = await fetch(url, {redirect: 'error'});
  if (!response.ok) throw new Error(`Model load failed (${response.status})`);
  return response.arrayBuffer();
}

function collectResources(roots) {
  const geometries = new Set();
  const materials = new Set();
  const skeletons = new Set();
  const textures = new Set();
  for (const root of roots) {
    root.traverse(({geometry, material, skeleton}) => {
      if (geometry) geometries.add(geometry);
      if (skeleton) skeletons.add(skeleton);
      if (material) for (const entry of [].concat(material)) materials.add(entry);
    });
  }
  for (const material of materials) {
    for (const value of Object.values(material)) {
      if (value?.isTexture) textures.add(value);
    }
    for (const uniform of Object.values(material.uniforms ?? {})) {
      if (uniform.value?.isTexture) textures.add(uniform.value);
    }
  }
  return {geometries, materials, skeletons, textures};
}

function disposeDonor(scene, keptGroups) {
  const donor = collectResources([scene]);
  const kept = collectResources(keptGroups);
  for (const geometry of donor.geometries) if (!kept.geometries.has(geometry)) geometry.dispose();
  for (const material of donor.materials) if (!kept.materials.has(material)) material.dispose();
  for (const skeleton of donor.skeletons) skeleton.dispose();

  // Several textures can share the same decoded image, including retained textures.
  const keptImages = new Set([...kept.textures].map((texture) => texture.source.data));
  const releasedImages = new Set();
  for (const texture of donor.textures) {
    if (kept.textures.has(texture)) continue;
    texture.dispose();
    const image = texture.source.data;
    if (!keptImages.has(image) && typeof ImageBitmap !== 'undefined' && image instanceof ImageBitmap) {
      releasedImages.add(image);
    }
  }
  for (const image of releasedImages) image.close();
}

function transferDonor(donor, target) {
  VRMUtils.removeUnnecessaryVertices(donor.scene);
  donor.scene.updateMatrixWorld(true);
  target.scene.updateMatrixWorld(true);

  const flip = flipFor(donor.meta?.metaVersion, target.meta?.metaVersion);
  const mappedBones = new Map();
  target.scene.traverse((object) => {
    if (object.isBone && object.name.startsWith('J_Bip')) mappedBones.set(boneKey(object.name), object);
  });
  const boneAttachments = [];
  function mapBone(bone) {
    for (const source of planChain(bone, (key) => mappedBones.has(key))) {
      const copy = source.clone(false);
      copy.name = `donor:${source.name}`;
      const {position, quaternion} = flipLocal(source.position, source.quaternion, flip);
      copy.position.copy(position);
      copy.quaternion.copy(quaternion);
      const parent = source.parent && mappedBones.get(boneKey(source.parent.name));
      boneAttachments.push([parent ?? target.scene, copy]);
      mappedBones.set(boneKey(source.name), copy);
    }
    return mappedBones.get(boneKey(bone.name));
  }

  const groups = new Map(ITEM_IDS.map((id) => {
    const group = new Group();
    group.name = id;
    group.visible = false;
    return [id, group];
  }));
  const materials = new Set();
  donor.scene.traverse((mesh) => {
    if (!mesh.isSkinnedMesh) return;
    const group = groups.get(itemForMaterial(materialName(mesh)));
    if (!group) return;
    const {bones, boneInverses} = mesh.skeleton;
    const reboundBones = bones.map(mapBone);
    const inverses = boneInverses.map((inverse) => rebindInverse(flip, inverse));
    const material = primaryMaterial(mesh.material);
    const copy = new SkinnedMesh(mesh.geometry, material);
    copy.bind(new Skeleton(reboundBones, inverses), bindMatrix());
    copy.frustumCulled = false;
    group.add(copy);
    materials.add(material);
  });
  for (const [id, group] of groups) {
    if (!group.children.length) throw new Error(`No donor meshes found for ${id}`);
  }
  for (const [parent, bone] of boneAttachments) parent.add(bone);
  for (const group of groups.values()) target.scene.add(group);
  return {groups, materials: [...materials]};
}

document.addEventListener('DOMContentLoaded', () => {
  const canvas = document.querySelector('canvas');
  // CSSOM property assignments work without inline styles in the CSP.
  document.body.style.margin = '0';
  document.body.style.overflow = 'hidden';
  document.body.style.background = 'transparent';
  canvas.style.display = 'block';
  canvas.style.width = '100vw';
  canvas.style.height = '100vh';

  const native = Boolean(window.AvatarChannel);
  const motionPreference = window.matchMedia('(prefers-reduced-motion: reduce)');
  const classifier = createClassifier();
  const scene = new Scene();
  const camera = new OrthographicCamera(-0.47, 0.47, 0.47, -0.47, 0.1, 10);
  camera.position.set(0, 1.28, 2.5);
  camera.updateMatrixWorld();
  const keyLight = new DirectionalLight(0xffffff, 2);
  keyLight.position.set(2, 3, 4);
  scene.add(keyLight, new AmbientLight(0xffffff, 1));

  const hitTest = createHitTest(camera, canvas);
  const gaze = new Object3D();
  const headPosition = new Vector3();
  const weights = Object.fromEntries(EXPRESSIONS.map((name) => [name, 0]));
  const manager = new LoadingManager();
  manager.setURLModifier((url) => {
    if (url.startsWith('blob:') || url.startsWith('data:')) return url;
    throw new Error('The model references an external resource');
  });
  const loader = new GLTFLoader(manager);
  loader.register((parser) => new VRMLoaderPlugin(parser));

  let renderer;
  let vrm;
  let bones;
  let halfHeight = camera.top;
  let baseYaw;
  let boneSign;
  let armPose;
  let surpriseExpression;
  let failed = false;
  let loading = false;
  let loadedFrame = false;
  let modelChunks;
  let currentModelId;
  let supportsOutfit = false;
  let outfit = [];
  let outfitGroups = new Map();
  let borrowedMaterials = [];
  const targetMeshes = [];
  let donorState = 'none';
  let donorChunks;
  let donorBytes;
  let mood = 'neutral';
  let paused = false;
  let hostReducedMotion = false;
  let pointer;
  let reaction;
  let petting = false;
  let yaw = 0;
  let elapsed = 0;
  let nextBlink = 3 + Math.random() * 3;
  let blinkEnd = 0;
  let frameId;
  let previous;
  let accumulator = 0;
  let sinceRender = 0;
  let colors = {};
  let appliedColors = {};
  let colorTimer;
  const originalMaterials = new Map();
  const recoloredTextures = new Map();

  function recolorTexture(original, color) {
    let entry = recoloredTextures.get(original);
    if (!entry) {
      const image = original.image;
      const textureCanvas = document.createElement('canvas');
      textureCanvas.width = image.width;
      textureCanvas.height = image.height;
      const ctx = textureCanvas.getContext('2d', {willReadFrequently: true});
      ctx.drawImage(image, 0, 0);
      const imageData = ctx.getImageData(0, 0, textureCanvas.width, textureCanvas.height);
      const pixels = imageData.data.slice();
      const {lum, mean} = luminance(pixels);
      const tex = original.clone();
      // A clone shares its source until it is explicitly replaced.
      tex.source = new Source(textureCanvas);
      entry = {canvas: textureCanvas, ctx, imageData, pixels, lum, mean, tex};
      recoloredTextures.set(original, entry);
    }
    if (entry.color !== color) {
      const {ctx, imageData, pixels, lum, mean, tex} = entry;
      imageData.data.set(pixels);
      colorize(imageData.data, lum, mean, parseHex(color));
      ctx.putImageData(imageData, 0, 0);
      tex.needsUpdate = true;
      entry.color = color;
    }
    return entry.tex;
  }

  function setMaterialTextures(material, map, shade) {
    if (material.map === map && material.shadeMultiplyTexture === shade) return;
    material.map = map;
    if (shade !== undefined) material.shadeMultiplyTexture = shade;
    material.needsUpdate = true;
  }

  function applyColors(force = false) {
    vrm.scene.traverse(({material}) => {
      if (!material) return;
      for (const item of Array.isArray(material) ? material : [material]) {
        const part = partForMaterial(item.name);
        if (!part || (!force && colors[part] === appliedColors[part])) continue;
        const color = colors[part];
        let original = originalMaterials.get(item);
        if (!original) {
          if (!color || !item.map) continue;
          original = {map: item.map, shade: item.shadeMultiplyTexture};
          originalMaterials.set(item, original);
        }
        const map = color ? recolorTexture(original.map, color) : original.map;
        const shade = color && original.shade ? map : original.shade;
        setMaterialTextures(item, map, shade);
      }
    });
    appliedColors = colors;
  }

  function scheduleColors() {
    if (!vrm || colorTimer !== undefined) return;
    colorTimer = setTimeout(() => {
      colorTimer = undefined;
      try {
        applyColors();
      } catch (error) {
        fail('webgl', error);
      }
    }, COLOR_INTERVAL_MS);
  }

  function disposeColors() {
    clearTimeout(colorTimer);
    colorTimer = undefined;
    for (const [material, {map, shade}] of originalMaterials) {
      setMaterialTextures(material, map, shade);
    }
    for (const {tex} of recoloredTextures.values()) tex.dispose();
    originalMaterials.clear();
    recoloredTextures.clear();
    colors = {};
    appliedColors = {};
  }

  function fail(code, error) {
    if (failed) return;
    failed = true;
    modelChunks = undefined;
    donorChunks = undefined;
    donorBytes = undefined;
    disposeColors();
    syncLoop();
    send({v: 1, type: 'error', code, message: error instanceof Error ? error.message : String(error)});
  }

  function failOutfit(error) {
    donorState = 'failed';
    donorChunks = undefined;
    donorBytes = undefined;
    borrowedMaterials = [];
    if (outfitGroups.size) {
      for (const group of outfitGroups.values()) group.visible = false;
      for (const mesh of targetMeshes) mesh.visible = true;
    }
    send({v: 1, type: 'error', code: 'outfit', message: error instanceof Error ? error.message : String(error)});
  }

  function applyOutfit() {
    const {show, hide} = resolveOutfit(outfit, currentModelId);
    for (const [id, group] of outfitGroups) group.visible = show.has(id);
    for (const mesh of targetMeshes) mesh.visible = !hide.some((rule) => rule.test(materialName(mesh)));
    appliedColors = {};
    applyColors(true);
  }

  async function loadDonor(bytes) {
    if (failed) return;
    donorState = 'parsing';
    try {
      const gltf = await loader.parseAsync(bytes, '');
      try {
        if (failed) return;
        const donor = gltf.userData.vrm;
        if (!donor) throw new Error('The donor model has no VRM data');
        const {groups, materials} = transferDonor(donor, vrm);
        outfitGroups = groups;
        borrowedMaterials = materials;
        for (const material of borrowedMaterials) material.update?.(0);
      } finally {
        disposeDonor(gltf.scene, outfitGroups.values());
      }
      donorState = 'ready';
      applyOutfit();
    } catch (error) {
      if (!failed) failOutfit(error);
    }
  }

  function startDonor() {
    if (!supportsOutfit) return;
    if (native) {
      if (!donorBytes) return;
      const bytes = donorBytes;
      donorBytes = undefined;
      loadDonor(bytes.buffer);
    } else if (donorState === 'none' && outfit.length) {
      donorState = 'receiving';
      fetchModel(MODELS['donut-chan']).then(loadDonor, (error) => {
        if (!failed) failOutfit(error);
      });
    }
  }

  function addDonorChunk({i, n, b64}) {
    if (!native || (vrm && !supportsOutfit) || donorBytes ||
        (donorState !== 'none' && donorState !== 'receiving')) return;
    donorState = 'receiving';
    donorChunks ??= createAssembler();
    try {
      donorBytes = donorChunks.add(i, n, b64);
      if (donorBytes) {
        donorChunks = undefined;
        startDonor();
      }
    } catch (error) {
      failOutfit(error);
    }
  }

  async function loadModel(getBytes) {
    loading = true;
    try {
      const gltf = await loader.parseAsync(await getBytes(), '');
      if (failed) return;
      vrm = gltf.userData.vrm;
      if (!vrm) throw new Error('The model has no VRM data');
      if (native) {
        const names = [vrm.meta?.name, vrm.meta?.title];
        if (names.includes('VRM1_Constraint_Twist_Sample')) currentModelId = 'pixiv-sample';
        else if (names.includes('Donut-Chan')) currentModelId = 'donut-chan';
      }
      supportsOutfit = resolveOutfit(ITEM_IDS, currentModelId).show.size > 0;
      if (!supportsOutfit) {
        donorChunks = undefined;
        donorBytes = undefined;
      }
      VRMUtils.removeUnnecessaryVertices(gltf.scene);
      VRMUtils.combineSkeletons(gltf.scene);
      vrm.scene.traverse((object) => {
        object.frustumCulled = false;
        if (object.isMesh) targetMeshes.push(object);
      });
      const bone = (name) => vrm.humanoid.getNormalizedBoneNode(name);
      bones = {
        head: bone('head'),
        chest: bone('chest') ?? bone('spine'),
        hips: bone('hips'),
        leftUpperArm: bone('leftUpperArm'),
        rightUpperArm: bone('rightUpperArm'),
        leftLowerArm: bone('leftLowerArm'),
        rightLowerArm: bone('rightLowerArm'),
      };
      const isVrm0 = vrm.meta?.metaVersion === '0';
      baseYaw = isVrm0 ? Math.PI : 0;
      boneSign = axisSign(isVrm0);
      armPose = restPose(isVrm0);
      const expressions = vrm.expressionManager;
      surpriseExpression = expressions?.getExpression('surprised') ? 'surprised' : 'Surprised';
      vrm.scene.rotation.y = baseYaw;
      scene.add(vrm.scene);
      applyColors();
      vrm.scene.updateMatrixWorld(true);
      const framing = frameAvatar({
        headY: bones.head.getWorldPosition(headPosition).y,
        hipsY: bones.hips.getWorldPosition(headPosition).y,
      });
      camera.position.y = framing.centerY;
      halfHeight = framing.halfHeight;
      camera.top = halfHeight;
      camera.bottom = -halfHeight;
      resize();
      syncLoop();
      startDonor();
    } catch (error) {
      fail('load', error);
    }
  }

  function addChunk({i, n, b64}) {
    if (!native || loading) return;
    modelChunks ??= createAssembler();
    try {
      const bytes = modelChunks.add(i, n, b64);
      if (bytes) {
        modelChunks = undefined;
        loadModel(() => bytes.buffer);
      }
    } catch (error) {
      fail('load', error);
    }
  }

  function interact(kind, dx = 0) {
    switch (kind) {
      case 'pat':
        reaction = {kind, until: elapsed + 1.2};
        break;
      case 'poke':
        reaction = {kind, until: elapsed + 0.8};
        break;
      case 'pettingStart':
        petting = true;
        reaction = undefined;
        break;
      case 'pettingEnd':
        petting = false;
        break;
      case 'swipe':
        yaw = dx * 0.01;
        break;
      default:
        return;
    }
    send({v: 1, type: 'interaction', kind});
  }

  function handlePointer(msg) {
    if (!loadedFrame || paused || document.hidden) return;
    const {phase, x, y} = msg;
    const dx = pointer ? x - pointer.startX : 0;
    const region = phase === 'down' ? hitTest(x, y, bones) : undefined;
    if (phase === 'down') {
      pointer = {x, y, startX: x, region};
    } else if (phase === 'move' && pointer) {
      Object.assign(pointer, {x, y});
      if (pointer.region !== 'head') yaw = dx * 0.01;
    } else if (phase === 'up' || phase === 'cancel') {
      pointer = undefined;
    }
    interact(classifier.sample({...msg, region}), dx);
  }

  connect((msg) => {
    if (failed) return;
    switch (msg.type) {
      case 'setMood':
        mood = msg.mood;
        break;
      case 'setColors':
        colors = Object.fromEntries(Reflect.ownKeys(msg.colors).map((part) => [part, msg.colors[part]]));
        scheduleColors();
        break;
      case 'setOutfit':
        outfit = [...msg.items];
        if (donorState === 'ready') {
          try {
            applyOutfit();
          } catch (error) {
            failOutfit(error);
          }
        } else {
          startDonor();
        }
        break;
      case 'setPaused':
        paused = msg.paused;
        syncLoop();
        break;
      case 'setReducedMotion':
        hostReducedMotion = msg.on;
        break;
      case 'pointer':
        handlePointer(msg);
        break;
      case 'loadModelChunk':
        addChunk(msg);
        break;
      case 'loadDonorChunk':
        addDonorChunk(msg);
        break;
    }
  });

  function resize() {
    const width = canvas.clientWidth;
    const height = canvas.clientHeight;
    if (width && height) {
      renderer.setPixelRatio(Math.min(window.devicePixelRatio, 3));
      renderer.setSize(width, height, false);
      const halfWidth = halfHeight * width / height;
      camera.left = -halfWidth;
      camera.right = halfWidth;
    }
    camera.updateProjectionMatrix();
    camera.updateMatrixWorld();
  }

  function pose(dt) {
    elapsed += dt;
    interact(classifier.tick());
    if (reaction && elapsed >= reaction.until) reaction = undefined;
    if (elapsed >= nextBlink) {
      blinkEnd = elapsed + 0.13;
      nextBlink = elapsed + 3 + Math.random() * 3;
    }

    let expression = targets(mood);
    if (petting) expression = {relaxed: 0.55, happy: 0.45};
    if (reaction?.kind === 'pat') expression = {happy: 1, blink: 1};
    if (reaction?.kind === 'poke') expression = {surprised: 1};
    for (const name of EXPRESSIONS) {
      const target = name === 'blink' && elapsed < blinkEnd ? 1 : (expression[name] ?? 0);
      weights[name] = step(weights[name], target, dt, name === 'blink' ? 28 : 9);
      vrm.expressionManager?.setValue(name === 'surprised' ? surpriseExpression : name, weights[name]);
    }

    const reducedMotion = hostReducedMotion || motionPreference.matches;
    const {bounce, headPitch} = motion(reaction || petting ? 'neutral' : mood);
    const idle = reducedMotion ? 0 : Math.sin(elapsed * 1.8);
    vrm.scene.position.y = reducedMotion ? 0 : bounce * (1 - Math.cos(elapsed * 6)) / 2;
    vrm.scene.rotation.z = idle * 0.022;
    if (!pointer || pointer.region === 'head') yaw *= Math.exp(-4 * dt);
    vrm.scene.rotation.y = baseYaw + yaw;
    bones.chest.rotation.x = boneSign * idle * 0.024;
    bones.head.rotation.x = -boneSign * headPitch;
    const headTilt = reaction?.kind === 'pat' ? 0.18 : 0;
    const headSway = petting && !reducedMotion ? 0.14 * Math.sin(elapsed * 9) : 0;
    bones.head.rotation.z = boneSign * (headTilt + headSway);
    if (bones.leftUpperArm) bones.leftUpperArm.rotation.z = armPose.leftUpperArmZ;
    if (bones.rightUpperArm) bones.rightUpperArm.rotation.z = armPose.rightUpperArmZ;
    if (bones.leftLowerArm) bones.leftLowerArm.rotation.z = armPose.leftLowerArmZ;
    if (bones.rightLowerArm) bones.rightLowerArm.rotation.z = armPose.rightLowerArmZ;

    if (vrm.lookAt && pointer) {
      bones.head.getWorldPosition(headPosition).project(camera);
      gaze.position.set(2 * pointer.x / canvas.clientWidth - 1,
        1 - 2 * pointer.y / canvas.clientHeight, headPosition.z - 0.08).unproject(camera);
      vrm.lookAt.target = gaze;
    } else if (vrm.lookAt) {
      vrm.lookAt.target = null;
      vrm.lookAt.yaw = 0;
      vrm.lookAt.pitch = 0;
    }
    vrm.update(dt);
    for (const material of borrowedMaterials) material.update?.(dt);
  }

  function frame(time) {
    const delta = previous === undefined ? FRAME_MS : time - previous;
    previous = time;
    accumulator += delta;
    sinceRender += delta;
    if (accumulator >= FRAME_MS) {
      const dt = Math.min(MAX_DELTA, sinceRender / 1000);
      accumulator %= FRAME_MS;
      sinceRender = 0;
      try {
        pose(dt);
        renderer.render(scene, camera);
      } catch (error) {
        fail('webgl', error);
        return;
      }
      if (!loadedFrame) {
        loadedFrame = true;
        send({v: 1, type: 'modelLoaded'});
      }
    }
    if (!failed) frameId = requestAnimationFrame(frame);
  }

  function syncLoop() {
    if (failed || paused || document.hidden || !vrm) {
      if (frameId !== undefined) cancelAnimationFrame(frameId);
      frameId = undefined;
      pointer = undefined;
      interact(classifier.sample({phase: 'cancel'}));
    } else if (frameId === undefined) {
      previous = undefined;
      accumulator = 0;
      sinceRender = 0;
      vrm.springBoneManager?.reset();
      frameId = requestAnimationFrame(frame);
    }
  }

  send({v: 1, type: 'ready', version: 1});
  try {
    canvas.addEventListener('webglcontextlost', () => fail('webgl', 'WebGL context lost'));
    renderer = new WebGLRenderer({canvas, alpha: true, antialias: true, powerPreference: 'low-power'});
    renderer.setClearColor(0x000000, 0);
    resize();
    window.addEventListener('resize', resize);
    window.addEventListener('pagehide', (event) => {
      if (!event.persisted) disposeColors();
    });
    document.addEventListener('visibilitychange', syncLoop);
  } catch (error) {
    fail('webgl', error);
  }

  if (!native && !failed) {
    const url = resolveModel(location.search);
    currentModelId = Object.keys(MODELS).find((id) => MODELS[id] === url);
    loadModel(() => fetchModel(url));
  }
}, {once: true});

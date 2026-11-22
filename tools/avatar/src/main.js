import {
  AmbientLight, DirectionalLight, LoadingManager, Object3D, OrthographicCamera,
  Scene, Vector3, WebGLRenderer,
} from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';
import {VRMLoaderPlugin, VRMUtils} from '@pixiv/three-vrm';
import {connect, send} from './bridge.js';
import {createClassifier} from './gesture.js';
import {createHitTest} from './hit.js';
import {motion, step, targets} from './mood.js';

const FRAME_MS = 1000 / 30;
const MAX_DELTA = 1 / 15;
const EXPRESSIONS = ['happy', 'sad', 'relaxed', 'surprised', 'blink'];

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
  let failed = false;
  let loading = false;
  let loadedFrame = false;
  let chunks;
  let chunkCount = 0;
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

  function fail(code, error) {
    if (failed) return;
    failed = true;
    chunks = undefined;
    syncLoop();
    send({v: 1, type: 'error', code, message: error instanceof Error ? error.message : String(error)});
  }

  async function loadModel(getBytes) {
    loading = true;
    try {
      const gltf = await loader.parseAsync(await getBytes(), '');
      if (failed) return;
      vrm = gltf.userData.vrm;
      if (!vrm) throw new Error('The model has no VRM data');
      VRMUtils.removeUnnecessaryVertices(gltf.scene);
      VRMUtils.combineSkeletons(gltf.scene);
      vrm.scene.traverse((object) => { object.frustumCulled = false; });
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
      scene.add(vrm.scene);
      syncLoop();
    } catch (error) {
      fail('load', error);
    }
  }

  function addChunk({i, n, b64}) {
    if (!native || loading) return;
    chunks ??= new Map();
    if (chunkCount && chunkCount !== n) {
      fail('load', 'Inconsistent model chunk count');
      return;
    }
    chunkCount = n;
    chunks.set(i, b64);
    if (chunks.size !== n) return;

    const complete = chunks;
    chunks = undefined;
    loadModel(() => {
      const decodedChunks = [];
      let byteLength = 0;
      for (let index = 0; index < n; index += 1) {
        const decoded = atob(complete.get(index));
        const chunk = new Uint8Array(decoded.length);
        for (let byte = 0; byte < chunk.length; byte += 1) {
          chunk[byte] = decoded.charCodeAt(byte);
        }
        decodedChunks.push(chunk);
        byteLength += chunk.length;
      }
      const bytes = new Uint8Array(byteLength);
      let offset = 0;
      for (const chunk of decodedChunks) {
        bytes.set(chunk, offset);
        offset += chunk.length;
      }
      return bytes.buffer;
    });
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
    }
  });

  function resize() {
    const width = canvas.clientWidth;
    const height = canvas.clientHeight;
    if (!width || !height) return;
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setSize(width, height, false);
    const halfWidth = 0.47 * width / height;
    camera.left = -halfWidth;
    camera.right = halfWidth;
    camera.updateProjectionMatrix();
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
      vrm.expressionManager?.setValue(name, weights[name]);
    }

    const reducedMotion = hostReducedMotion || motionPreference.matches;
    const {bounce, headPitch} = motion(reaction || petting ? 'neutral' : mood);
    const idle = reducedMotion ? 0 : Math.sin(elapsed * 1.8);
    vrm.scene.position.y = reducedMotion ? 0 : bounce * (1 - Math.cos(elapsed * 6)) / 2;
    vrm.scene.rotation.z = idle * 0.022;
    if (!pointer || pointer.region === 'head') yaw *= Math.exp(-4 * dt);
    vrm.scene.rotation.y = yaw;
    bones.chest.rotation.x = idle * 0.024;
    bones.head.rotation.x = -headPitch;
    const headTilt = reaction?.kind === 'pat' ? 0.18 : 0;
    const headSway = petting && !reducedMotion ? 0.14 * Math.sin(elapsed * 9) : 0;
    bones.head.rotation.z = headTilt + headSway;
    if (bones.leftUpperArm) bones.leftUpperArm.rotation.z = 1.2;
    if (bones.rightUpperArm) bones.rightUpperArm.rotation.z = -1.2;
    if (bones.leftLowerArm) bones.leftLowerArm.rotation.z = 0.15;
    if (bones.rightLowerArm) bones.rightLowerArm.rotation.z = -0.15;

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
    renderer = new WebGLRenderer({canvas, alpha: true, antialias: false, powerPreference: 'low-power'});
    renderer.setClearColor(0x000000, 0);
    resize();
    window.addEventListener('resize', resize);
    document.addEventListener('visibilitychange', syncLoop);
  } catch (error) {
    fail('webgl', error);
  }

  if (!native && !failed) {
    loadModel(async () => {
      const response = await fetch('avatar.vrm', {redirect: 'error'});
      if (!response.ok) throw new Error(`Model load failed (${response.status})`);
      return response.arrayBuffer();
    });
  }
}, {once: true});

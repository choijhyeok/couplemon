import * as THREE from 'three';
import { GLTFLoader } from './vendor/GLTFLoader.js';
import { PetMotionPlayer } from './motion-player.js';
import { PetProps } from './pet-props.js';
import { interactionActions } from './reward-items.js';
import { CoupleScene } from './couple-scene.js';

const status = document.getElementById('status');
const notify = value => window.webkit?.messageHandlers.pet3d?.postMessage(value);
let renderer, player, props, model, ready = false;
let reducedMotion = false, yaw = 0, pitch = 0, level = 1;
let requestedAction = 'idle', requestedEvent = null;
let reward = null;
let randomEnabled = false, randomInterval = 5;
let couple, partnerURL = null, togetherEvent = null;
let illustrated = false;
const nowSeconds = () => performance.now() / 1000;
function syncRewardLock() {
  if (!player) return;
  player.interaction = props?.rewardItem.reward?.action || null;
  if (interactionActions.includes(player.name) && player.name !== player.interaction) player.play('idle', nowSeconds());
}
window.pet3D = {
  setPartner(url) { partnerURL = url; couple?.setPartner(url); },
  performTogether(event) { togetherEvent = event; couple?.perform(event); },
  setReducedMotion(value) { reducedMotion = !!value; player?.setReducedMotion(reducedMotion); },
  setLevel(value) { level = value; props?.setLevel(value); syncRewardLock(); },
  setRandomMode(enabled, interval = 5) {
    randomEnabled = !!enabled;
    randomInterval = Math.max(3, Math.min(30, Number(interval) || 5));
    if (!couple?.active) player?.setRandomMode(randomEnabled, randomInterval, nowSeconds());
  },
  setReward(value) {
    reward = value;
    props?.setReward(value);
    syncRewardLock();
  },
  playAction(name, event = null) {
    if (couple?.active) return false;
    if (interactionActions.includes(name) && name !== props?.rewardItem.reward?.action) return false;
    requestedAction = name;
    requestedEvent = event;
    player?.play(name, nowSeconds());
    props?.startLetter(event, nowSeconds());
    return true;
  },
  get state() { return { ready, yaw, pitch, illustrated, animated: !!player?.idle, action: player?.name || 'idle',
    motion: player?.illustrated?.state || null,
    clips: player ? [...player.clips.keys()] : [], decorations: props?.unlocked || [], letterVisible: props?.letter.visible || false,
    rewardLevel: props?.rewardItem.reward?.level || null, rewardKind: props?.rewardItem.reward?.kind || null,
    randomEnabled: player?.randomEnabled || false, randomInterval: player?.randomInterval || randomInterval,
    randomActionCount: player?.randomActionCount || 0, lastRandomAction: player?.lastRandomAction || null,
    partnerReady: !!couple?.partner, togetherAction: couple?.active?.action || null,
    togetherID: couple?.active?.id || null, togetherCompleted: couple?.completed || 0 }; },
};

try {
  renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true, powerPreference: 'low-power' });
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  renderer.setClearColor(0x000000, 0);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.2;
  document.body.prepend(renderer.domElement);
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(32, 1, 0.01, 100);
  camera.position.set(0, 0.05, 4.6);
  const pivot = new THREE.Group();
  scene.add(pivot, new THREE.HemisphereLight(0xffffff, 0xb4a2bd, 2.3));
  const key = new THREE.DirectionalLight(0xfff5e6, 3);
  key.position.set(3, 5, 5);
  const fill = new THREE.DirectionalLight(0xddeaff, 1.5);
  fill.position.set(-3, 1, 2);
  scene.add(key, fill);
  function resize() {
    const width = Math.max(innerWidth, 1), height = Math.max(innerHeight, 1);
    renderer.setSize(width, height);
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
  }
  new ResizeObserver(resize).observe(document.documentElement);
  resize();
  const gltf = await new GLTFLoader().loadAsync('./model.glb');
  model = gltf.scene;
  model.traverse(object => {
    if (object.userData.couplemon_render_mode === 'illustrated') illustrated = true;
  });
  if (illustrated) model.traverse(object => {
    for (const material of [object.material].flat().filter(Boolean)) material.toneMapped = false;
  });
  const bounds = new THREE.Box3().setFromObject(model);
  const size = bounds.getSize(new THREE.Vector3());
  const extent = Math.max(size.x, size.y, size.z);
  if (!Number.isFinite(extent) || extent <= 0) throw new Error('Invalid model bounds');
  const center = bounds.getCenter(new THREE.Vector3());
  const normalized = new THREE.Group();
  normalized.add(model);
  normalized.scale.setScalar(1.9 / extent);
  // Put normalization on a parent so animation keyframes cannot undo centering.
  normalized.position.copy(center).multiplyScalar(-1.9 / extent);
  pivot.add(normalized);
  player = new PetMotionPlayer(model, gltf.animations);
  player.setReducedMotion(reducedMotion);
  player.play(requestedAction, nowSeconds());
  props = new PetProps(scene, model);
  props.setLevel(level);
  props.setReward(reward);
  player.interaction = props.rewardItem.reward?.action || null;
  player.setRandomMode(randomEnabled, randomInterval, nowSeconds());
  props.startLetter(requestedEvent, nowSeconds());
  couple = new CoupleScene(scene, pivot, model, player, () => {
    player.play('idle', nowSeconds());
    player.setRandomMode(randomEnabled, randomInterval, nowSeconds());
  });
  couple.setPartner(partnerURL);
  couple.perform(togetherEvent);
  status.remove();
  ready = true;
  notify({ type: 'ready' });
  let pointer = null;
  renderer.domElement.addEventListener('pointerdown', e => {
    pointer = { id: e.pointerId, x: e.clientX, y: e.clientY, yaw, pitch, moved: false };
    if (e.isTrusted) renderer.domElement.setPointerCapture(e.pointerId);
  });
  renderer.domElement.addEventListener('pointermove', e => {
    if (!pointer) {
      player.illustrated?.setLook(e.clientX / Math.max(innerWidth, 1) * 2 - 1, 1 - e.clientY / Math.max(innerHeight, 1) * 2);
      return;
    }
    if (pointer.id !== e.pointerId) return;
    const dx = e.clientX - pointer.x, dy = e.clientY - pointer.y;
    pointer.moved ||= Math.hypot(dx, dy) > 5;
    yaw = illustrated ? THREE.MathUtils.clamp(pointer.yaw + dx * 0.008, -0.38, 0.38) : pointer.yaw + dx * 0.018;
    pitch = THREE.MathUtils.clamp(pointer.pitch + dy * 0.008, illustrated ? -0.2 : -0.55, illustrated ? 0.2 : 0.55);
  });
  renderer.domElement.addEventListener('pointerup', e => {
    if (pointer?.id !== e.pointerId) return;
    if (!pointer.moved) { window.pet3D.playAction('waving'); notify({ type: 'tap' }); }
    pointer = null;
  });
  renderer.domElement.addEventListener('pointercancel', () => { pointer = null; });
  renderer.domElement.addEventListener('pointerleave', () => player.illustrated?.setLook(null));
  let previous = performance.now() / 1000, lastFrame = previous;
  function draw(ms) {
    requestAnimationFrame(draw);
    const now = ms / 1000;
    if (now - lastFrame < 1 / 30 || document.hidden) return;
    const dt = Math.min(now - previous, 0.1);
    previous = lastFrame = now;
    couple.restorePose();
    player.update(dt, now);
    const fallback = player.fallback(now);
    pivot.position.y = reducedMotion || illustrated ? 0 : Math.sin(now * 2.1) * 0.026;
    pivot.position.y += fallback.y;
    pivot.rotation.set(pitch, yaw, fallback.z);
    props.update(now, reducedMotion, dt, player.name);
    couple.update(dt, now, reducedMotion);
    camera.position.z = couple.partner ? 3.6 : 4.6;
    renderer.render(scene, camera);
  }
  requestAnimationFrame(draw);
} catch (error) {
  status.textContent = '3D를 표시할 수 없습니다.\n다른 GLB를 선택해 주세요.';
  notify({ type: 'error', message: String(error) });
}
addEventListener('pagehide', () => {
  couple?.dispose();
  player?.mixer.stopAllAction();
  props?.dispose();
  model?.traverse(object => {
    object.geometry?.dispose();
    for (const material of [object.material].flat().filter(Boolean)) {
      for (const value of Object.values(material)) if (value?.isTexture) value.dispose();
      material.dispose();
    }
  });
  renderer?.dispose();
});

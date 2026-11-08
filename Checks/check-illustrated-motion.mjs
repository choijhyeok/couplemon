// CPU checks against real exported GLBs and the app's vendored Three.js. No npm install.
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL, fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const resources = path.join(root, 'Sources/CoupleMon/Resources/Pet3D');
const temporary = await mkdtemp(path.join(tmpdir(), 'couplemon-motion-'));
globalThis.self = globalThis;
// Textures are verified by the Blender/native checks. CPU rig checks need only their dimensions.
globalThis.createImageBitmap = async () => ({ width: 512, height: 512, close() {} });
globalThis.ProgressEvent = class extends Event { constructor(type, values) { super(type); Object.assign(this, values); } };
try {
  await writeFile(path.join(temporary, 'package.json'), '{"type":"module"}');
  const threeURL = pathToFileURL(path.join(resources, 'vendor/three.module.min.js')).href;
  for (const name of ['illustrated-motion.js', 'motion-player.js', 'vendor/GLTFLoader.js', 'vendor/BufferGeometryUtils.js']) {
    const source = (await readFile(path.join(resources, name), 'utf8')).replaceAll("from 'three'", `from '${threeURL}'`);
    await writeFile(path.join(temporary, path.basename(name)), source);
  }
  const THREE = await import(threeURL);
  const { GLTFLoader } = await import(pathToFileURL(path.join(temporary, 'GLTFLoader.js')));
  const { IllustratedMotion } = await import(pathToFileURL(path.join(temporary, 'illustrated-motion.js')));
  const { PetMotionPlayer } = await import(pathToFileURL(path.join(temporary, 'motion-player.js')));
  const load = async filename => {
    const data = await readFile(filename);
    return new GLTFLoader().parseAsync(data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength), '');
  };
  const file = process.argv[2] || path.join(root, 'dist/image-rig-review/model.glb');
  const gltf = await load(file), model = gltf.scene;
  const motion = new IllustratedMotion(model, () => 0.5);
  const surface = model.getObjectByName('original_illustration');
  assert(surface?.isSkinnedMesh);
  assert.equal(motion.eyes.length, 8, 'New models need two complete eyes');
  assert(motion.eyes.every(eye => eye.material.depthWrite && !eye.material.transparent),
    'Lids must reliably cover the original iris regardless of transparent-object sorting');
  const positions = surface.geometry.attributes.position;
  const foot = Array.from({ length: positions.count }, (_, i) => i).filter(i => positions.getY(i) < 0.00001);
  assert(foot.length > 0);
  model.updateMatrixWorld(true); surface.skeleton.update();
  const feet = foot.map(i => surface.getVertexPosition(i, new THREE.Vector3()));
  const checkFeet = () => {
    model.updateMatrixWorld(true); surface.skeleton.update();
    foot.forEach((index, n) => assert(surface.getVertexPosition(index, new THREE.Vector3()).distanceTo(feet[n]) < 1e-5,
      'Breathing/idle must not float or slide the feet'));
  };
  const states = [];
  for (let i = 0; i < 240; i++) {
    motion.update(1 / 60); states.push(motion.state);
    if (i % 30 === 0) checkFeet();
  }
  assert(Math.max(...states.map(s => s.breath)) > 0.95);
  assert(Math.min(...states.map(s => s.breath)) < 0.05);
  assert(states.some(s => s.blink > 0.95), 'A complete blink must close the eyes');
  assert(states.at(-1).blinks >= 1);
  assert(states.every(s => [s.head.x, s.head.y, s.head.z, s.bodyTilt].every(Number.isFinite)));
  assert(states.every(s => Math.abs(s.head.y) < 0.25), 'Head stays near the illustrated front view');
  assert(states.some(s => Math.abs(s.head.z - s.bodyTilt) > 0.005), 'Head and body must not move in lockstep');
  assert(Math.abs(model.getObjectByName('pet_tail').quaternion.z) > 0, 'Tail follow-through is active');
  const before = motion.state.breath;
  motion.play('waving');
  for (let i = 0; i < 45; i++) motion.update(1 / 60);
  assert.notEqual(motion.state.breath, before, 'Breathing continues during a gesture');
  const arm = model.getObjectByName('pet_arm_r'), beforeRepeat = arm.quaternion.clone();
  motion.play('waving'); motion.update(1 / 120);
  assert(beforeRepeat.angleTo(arm.quaternion) < 0.04, 'Repeating an action must crossfade without a snap');
  motion.update(0, true);
  assert.deepEqual(Array.from(positions.array), Array.from(motion.surfaces[0].original), 'Reduced motion restores the original grid');
  assert(motion.eyes.every(eye => eye.morphTargetInfluences.every(value => value === 0)), 'Reduced motion opens the eyes');

  const fresh = await load(file), player = new PetMotionPlayer(fresh.scene, fresh.animations);
  player.play('waving', 0);
  for (let i = 1; i <= 180; i++) player.update(1 / 60, i / 60);
  assert.equal(player.name, 'idle', 'Procedural one-shots must return to idle');
  assert(player.clips.size === 21, 'All existing behavior names remain available');
  player.setReducedMotion(true);
  const frozen = JSON.stringify(player.illustrated.state);
  for (let i = 0; i < 90; i++) player.update(1 / 30, 4 + i / 30);
  assert.equal(JSON.stringify(player.illustrated.state), frozen, 'Reduced motion freezes all autonomous motion');
  let legacy;
  try { legacy = await load(path.join(root, 'dist/image-rig-review/legacy-model.glb')); }
  catch (error) {
    if (error.code !== 'ENOENT') throw error;
    // A clean checkout has no archived GLB. Remove the optional eye assets from
    // the fixture to exercise the same missing-metadata path as older models.
    legacy = await load(file);
    const eyes = [];
    legacy.scene.traverse(node => {
      if (node.userData.couplemon_eye_role) eyes.push(node);
      delete node.userData.couplemon_motion_version;
    });
    eyes.forEach(eye => eye.removeFromParent());
  }
  const oldPlayer = new PetMotionPlayer(legacy.scene, legacy.animations);
  assert(oldPlayer.illustrated && oldPlayer.illustrated.eyes.length === 0, 'Existing GLBs get the driver without eye assets');
  for (let i = 0; i < 60; i++) oldPlayer.update(1 / 30, i / 30);
  assert(Number.isFinite(oldPlayer.illustrated.state.breath));
  const plain = new PetMotionPlayer(new THREE.Group(), []);
  assert.equal(plain.illustrated, null, 'Volumetric GLBs keep the existing animation path');
  console.log('PASS: fixed feet, local breathing, independent head/body, tail follow-through, full blink, smooth repeat, idle return, reduced motion, legacy/3D compatibility');
} finally {
  await rm(temporary, { recursive: true, force: true });
}

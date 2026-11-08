import * as THREE from 'three';

const clamp = THREE.MathUtils.clamp;
const smooth = x => { x = clamp(x, 0, 1); return x * x * (3 - 2 * x); };
const envelope = (t, duration) => smooth(t / 0.22) * (1 - smooth((t - duration + 0.35) / 0.35));
const noise = (t, seed) => {
  const hash = n => { const v = Math.sin(n * 127.1 + seed * 311.7) * 43758.5453; return v - Math.floor(v); };
  const i = Math.floor(t), f = smooth(t - i);
  return (hash(i) * (1 - f) + hash(i + 1) * f) * 2 - 1;
};
const durations = { waving: 2.3, review: 2.7, lookAround: 3.4, waiting: 2.6, jumping: 1.25,
  failed: 2.5, running: 2.2, runningRight: 2.2, runningLeft: 2.2, celebrate100: 4 };

export function isIllustrated(model) {
  let result = false;
  model.traverse(node => { if (node.userData.couplemon_render_mode === 'illustrated') result = true; });
  return result;
}

// All angles here are in the drawing's glTF axes: X nod, Y turn, Z tilt.
// Bones exported from Blender have different local axes; each joint caches that conversion.
export class IllustratedMotion {
  constructor(model, random = Math.random) {
    this.model = model; this.random = random;
    this.time = 0; this.seed = random() * 1000; this.moves = [];
    this.head = { x: 0, y: 0, z: 0 }; this.body = { x: 0, y: 0, z: 0 };
    this.velocity = { x: 0, y: 0, z: 0, body: 0, tail: 0, ear: 0 };
    this.tail = 0; this.ear = 0; this.follow = 0;
    this.gaze = { x: 0, y: 0 }; this.wantedGaze = { x: 0, y: 0 }; this.pointer = null;
    this.nextGaze = 1.5; this.nextGesture = 9 + random() * 8;
    this.nextBlink = 1.6 + random() * 2; this.blinkAt = -1; this.blink = 0; this.blinks = 0;
    this.breathPhase = 0; this.breathPeriod = 3.4 + random() * 1.2; this.breath = 0;
    this.joints = new Map(); this.surfaces = []; this.eyes = [];
    model.updateWorldMatrix(true, true);
    const rootRotation = model.getWorldQuaternion(new THREE.Quaternion()).invert();
    for (const name of ['pet_root', 'pet_head', 'pet_arm_l', 'pet_arm_r', 'pet_leg_l', 'pet_leg_r',
                        'pet_tail', 'pet_ear_l', 'pet_ear_r']) {
      const node = model.getObjectByName(name);
      if (!node) continue;
      const parentAxes = rootRotation.clone().multiply(node.parent?.getWorldQuaternion(new THREE.Quaternion()) || new THREE.Quaternion());
      this.joints.set(name, { node, position: node.position.clone(), rotation: node.quaternion.clone(), scale: node.scale.clone(),
        point: model.worldToLocal(node.getWorldPosition(new THREE.Vector3())),
        axes: parentAxes, inverseAxes: parentAxes.clone().invert() });
    }
    model.traverse(node => {
      if (!node.isMesh) return;
      if (node.userData.couplemon_eye_role) { this.eyes.push(node); node.frustumCulled = false; }
      if (node.name !== 'original_illustration') return;
      const attribute = node.geometry.attributes.position;
      const original = new Float32Array(attribute.array);
      node.geometry.computeBoundingBox();
      const bounds = node.geometry.boundingBox;
      const weights = node.geometry.attributes.skinWeight, indices = node.geometry.attributes.skinIndex;
      const bodyIndex = node.skeleton?.bones.findIndex(bone => bone.name === 'pet_body') ?? -1;
      const neck = this.joints.get('pet_head')?.node;
      const neckY = neck ? node.worldToLocal(neck.getWorldPosition(new THREE.Vector3())).y : bounds.max.y * 0.6;
      const field = new Float32Array(attribute.count);
      for (let i = 0; i < attribute.count; i++) {
        const height = smooth((original[i * 3 + 1] - bounds.min.y) / Math.max(0.01, neckY - bounds.min.y));
        let bodyWeight = bodyIndex < 0 ? 1 - smooth((original[i * 3 + 1] - neckY) / 0.15) : 0;
        if (bodyIndex >= 0 && weights && indices) for (let j = 0; j < 4; j++) {
          if (indices.getComponent(i, j) === bodyIndex) bodyWeight += weights.getComponent(i, j);
        }
        field[i] = height * height * bodyWeight;
      }
      this.surfaces.push({ node, attribute, original, field, center: (bounds.min.x + bounds.max.x) / 2,
        height: bounds.max.y - bounds.min.y, floor: bounds.min.y, neckY });
    });
  }

  duration(name) { return name === 'idle' ? Infinity : durations[name] || 2.8; }
  play(name) {
    for (const move of this.moves) if (move.out == null) move.out = this.time;
    if (name !== 'idle') this.moves.push({ name, start: this.time, duration: this.duration(name), out: null });
    this.moves = this.moves.slice(-4);
  }
  setLook(x, y) { this.pointer = x == null ? null : { x: clamp(x, -1, 1), y: clamp(y, -1, 1) }; }

  resetPose() {
    for (const joint of this.joints.values()) {
      joint.node.position.copy(joint.position); joint.node.quaternion.copy(joint.rotation); joint.node.scale.copy(joint.scale);
    }
  }
  rotate(name, x = 0, y = 0, z = 0) {
    const joint = this.joints.get(name);
    if (!joint) return;
    const delta = new THREE.Quaternion().setFromEuler(new THREE.Euler(x, y, z));
    delta.premultiply(joint.inverseAxes).multiply(joint.axes);
    joint.node.quaternion.copy(joint.rotation).premultiply(delta);
  }
  spring(object, key, velocityKey, target, stiffness, damping, dt) {
    const n = Math.max(1, Math.ceil(dt * 120)), h = dt / n;
    for (let i = 0; i < n; i++) {
      this.velocity[velocityKey] += (stiffness * (target - object[key]) - 2 * Math.sqrt(stiffness) * damping * this.velocity[velocityKey]) * h;
      object[key] += this.velocity[velocityKey] * h;
    }
  }

  actionPose() {
    const pose = { nod: 0, yaw: 0, roll: 0, body: 0, arm: 0, armL: 0, legs: 0, y: 0, x: 0, compress: 0, gazeY: 0 };
    this.moves = this.moves.filter(move => this.time - move.start < move.duration && (move.out == null || this.time - move.out < 0.22));
    for (const move of this.moves) {
      const t = this.time - move.start, u = t / move.duration;
      const e = envelope(t, move.duration) * (move.out == null ? 1 : 1 - smooth((this.time - move.out) / 0.22));
      if (move.name === 'waving') {
        const wave = smooth((t - 0.18) / 0.4);
        pose.arm += (-0.28 - 0.10 * Math.sin(Math.max(0, t - 0.45) * 13) * wave) * e;
        pose.roll += 0.045 * e; pose.body -= 0.018 * e;
      } else if (move.name === 'review') {
        pose.nod += (0.055 + 0.04 * Math.sin(t * 6)) * e;
        pose.gazeY -= 0.45 * e; pose.body += 0.014 * e;
      } else if (move.name === 'lookAround') {
        pose.yaw += 0.11 * Math.sin(u * Math.PI * 2) * e;
        pose.roll -= 0.025 * Math.sin(u * Math.PI * 2) * e;
      } else if (move.name === 'waiting') {
        pose.roll += 0.065 * e; pose.nod -= 0.02 * e;
      } else if (move.name === 'failed') {
        pose.nod += 0.085 * e; pose.roll -= 0.035 * e; pose.compress -= 0.25 * e;
      } else if (move.name === 'jumping') {
        const launch = clamp((t - 0.2) / 0.7, 0, 1);
        pose.y += t < 0.2 ? -0.025 * Math.sin(t / 0.2 * Math.PI) : 0.14 * Math.sin(launch * Math.PI);
        pose.compress -= 0.5 * Math.sin(Math.min(t / 0.24, 1) * Math.PI) * e;
        pose.arm -= 0.15 * e;
      } else if (move.name.startsWith('running')) {
        const run = Math.sin(t * 13) * e;
        pose.legs += 0.13 * run; pose.arm += 0.09 * run; pose.y += 0.012 * Math.abs(run);
        pose.x += (move.name === 'runningRight' ? 1 : move.name === 'runningLeft' ? -1 : 0) * 0.12 * e;
      } else if (move.name === 'hugHeart') {
        pose.arm -= 0.16 * e; pose.armL += 0.10 * e; pose.nod += 0.055 * e;
      } else if (move.name === 'restMoon') {
        pose.roll += 0.085 * e; pose.nod += 0.045 * e; pose.body += 0.025 * e;
      } else if (move.name === 'playBall') {
        pose.arm += 0.13 * Math.sin(t * 7) * e; pose.nod += 0.04 * Math.sin(t * 7) * e;
        pose.y += 0.012 * Math.abs(Math.sin(t * 7)) * e;
      } else if (move.name === 'paint' || move.name === 'fish') {
        pose.arm += (-0.22 + 0.08 * Math.sin(t * (move.name === 'paint' ? 8 : 2.5))) * e;
        pose.nod += 0.06 * e; pose.gazeY -= 0.4 * e;
      } else if (move.name === 'playMusic') {
        pose.arm += (-0.2 + 0.075 * Math.sin(t * 12)) * e;
        pose.armL += 0.05 * Math.sin(t * 12 + Math.PI) * e; pose.body += 0.018 * Math.sin(t * 6) * e;
      } else if (move.name === 'celebrateCrown') {
        pose.arm -= 0.2 * e; pose.nod += 0.075 * Math.sin(t * 5) * e;
      } else if (move.name === 'celebrate100') {
        pose.arm -= 0.3 * e; pose.armL += 0.25 * e; pose.y += 0.045 * Math.abs(Math.sin(t * 6)) * e;
        pose.roll += 0.04 * Math.sin(t * 4) * e;
      } else if (move.name === 'blowBubbles') {
        pose.arm -= 0.22 * e; pose.nod -= 0.035 * e; pose.gazeY += 0.25 * e;
      } else {
        pose.arm += (-0.28 + 0.075 * Math.sin(t * 6)) * e;
        pose.yaw += (move.name === 'castSpell' ? 0.04 : 0.02) * Math.sin(t * 4) * e;
        pose.roll += 0.025 * Math.sin(t * 4) * e;
      }
    }
    return pose;
  }

  update(dt, reduced = false) {
    this.resetPose();
    if (reduced) {
      this.deform(0, 0, 0); this.updateEyes(0, 0, 0);
      return;
    }
    dt = clamp(dt, 0, 0.1); this.time += dt;
    if (this.time >= this.nextGaze) {
      this.wantedGaze = { x: (this.random() - 0.5) * 0.9, y: (this.random() - 0.5) * 0.5 };
      this.nextGaze = this.time + 2 + this.random() * 3;
    }
    if (!this.moves.length && this.time >= this.nextGesture) {
      this.play(this.random() < 0.55 ? 'lookAround' : 'waiting');
      this.nextGesture = this.time + 10 + this.random() * 10;
    }
    const action = this.actionPose(), look = this.pointer || this.wantedGaze;
    const gazeEase = 1 - Math.exp(-dt * 15);
    this.gaze.x += (look.x - this.gaze.x) * gazeEase;
    this.gaze.y += (clamp(look.y + action.gazeY, -1, 1) - this.gaze.y) * gazeEase;
    const target = {
      x: -this.gaze.y * 0.045 + noise(this.time * 0.16, this.seed) * 0.012 + action.nod,
      y: this.gaze.x * 0.10 + noise(this.time * 0.12, this.seed + 1) * 0.025 + action.yaw,
      z: noise(this.time * 0.10, this.seed + 2) * 0.035 + action.roll,
    };
    for (const key of ['x', 'y', 'z']) this.spring(this.head, key, key, target[key], 72, 0.82, dt);
    this.follow += (this.head.z * 0.3 + action.body - this.follow) * (1 - Math.exp(-dt / 0.22));
    this.spring(this.body, 'z', 'body', this.follow, 30, 0.95, dt);
    this.spring(this, 'tail', 'tail', -this.body.z * 1.4 - this.velocity.body * 0.08 + noise(this.time * 0.25, this.seed + 4) * 0.025, 38, 0.6, dt);
    this.spring(this, 'ear', 'ear', -this.head.z * 0.5 - this.velocity.z * 0.045, 85, 0.55, dt);
    this.breathPhase += dt / this.breathPeriod;
    if (this.breathPhase >= 1) { this.breathPhase %= 1; this.breathPeriod = 3.4 + this.random() * 1.3; }
    this.breath = this.breathPhase < 0.4 ? smooth(this.breathPhase / 0.4)
      : this.breathPhase < 0.9 ? 1 - smooth((this.breathPhase - 0.4) / 0.5) : 0;
    if (this.blinkAt < 0 && this.time >= this.nextBlink) { this.blinkAt = this.time; this.blinks++; }
    if (this.blinkAt >= 0) {
      const t = this.time - this.blinkAt;
      this.blink = t < 0.065 ? smooth(t / 0.065) : t < 0.09 ? 1 : 1 - smooth((t - 0.09) / 0.13);
      if (t >= 0.22) {
        this.blinkAt = -1; this.blink = 0;
        this.nextBlink = this.time + (this.random() < 0.15 ? 0.14 : 2.2 + this.random() * 3.6);
      }
    }
    this.rotate('pet_head', this.head.x, this.head.y, this.head.z - this.body.z);
    this.rotate('pet_arm_r', 0, 0, action.arm);
    this.rotate('pet_arm_l', 0, 0, -action.arm * 0.18 + action.armL);
    this.rotate('pet_leg_l', 0, 0, action.legs); this.rotate('pet_leg_r', 0, 0, -action.legs);
    this.rotate('pet_tail', 0, 0, this.tail);
    this.rotate('pet_ear_l', 0, 0, this.ear); this.rotate('pet_ear_r', 0, 0, this.ear * 0.8);
    // Lean above the feet rather than rotating the entire drawing about its origin.
    const neckHeight = this.surfaces[0]?.neckY || 1;
    for (const [name, joint] of this.joints) if (name !== 'pet_root' && !name.startsWith('pet_ear_') && !name.startsWith('pet_leg_')) {
      const h = joint.point.y, influence = smooth(h / Math.max(0.01, neckHeight));
      const shift = new THREE.Vector3(-this.body.z * h * influence * influence, 0, 0).applyQuaternion(joint.inverseAxes);
      joint.node.position.add(shift);
    }
    const root = this.joints.get('pet_root');
    if (root) { root.node.position.y += action.y; root.node.position.x += action.x; }
    this.deform(this.breath, action.compress, this.body.z);
    this.updateEyes(this.blink, this.gaze.x, this.gaze.y);
  }

  deform(breath, compress, tilt) {
    for (const surface of this.surfaces) {
      const { attribute, original, field, height, center } = surface;
      for (let i = 0; i < attribute.count; i++) {
        const j = i * 3, w = field[i];
        attribute.array[j] = original[j] + ((original[j] - center) * 0.014 * breath - tilt * (original[j + 1] - surface.floor)) * w;
        attribute.array[j + 1] = original[j + 1] + height * (0.006 * breath + 0.018 * compress) * w;
        attribute.array[j + 2] = original[j + 2];
      }
      attribute.needsUpdate = true;
    }
  }
  updateEyes(blink, x, y) {
    for (const eye of this.eyes) {
      const dictionary = eye.morphTargetDictionary || {}, weights = eye.morphTargetInfluences;
      if (!weights) continue;
      if (dictionary.blink != null) weights[dictionary.blink] = eye.userData.couplemon_eye_role === 'lash' ? smooth((blink - 0.6) / 0.4) : blink;
      if (dictionary.lookX != null) weights[dictionary.lookX] = x * (1 - blink);
      if (dictionary.lookY != null) weights[dictionary.lookY] = y * (1 - blink);
    }
  }
  get state() { return { breath: this.breath, head: { ...this.head }, bodyTilt: this.body.z,
    gaze: { ...this.gaze }, blink: this.blink, blinks: this.blinks, eyeParts: this.eyes.length,
    tail: this.tail, ear: this.ear, footFloat: 0 }; }
}

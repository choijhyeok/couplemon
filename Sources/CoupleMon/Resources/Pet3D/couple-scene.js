import * as THREE from 'three';
import { GLTFLoader } from './vendor/GLTFLoader.js';
import { PetMotionPlayer } from './motion-player.js';

const smooth = x => { x = THREE.MathUtils.clamp(x, 0, 1); return x * x * (3 - 2 * x); };
function dispose(root) {
  root?.traverse(o => {
    o.geometry?.dispose();
    for (const m of [o.material].flat().filter(Boolean)) {
      for (const v of Object.values(m)) if (v?.isTexture) v.dispose();
      m.dispose();
    }
  });
}

export class CoupleScene {
  constructor(scene, pivot, model, player, onFinish) {
    Object.assign(this, { scene, pivot, model, player, onFinish });
    this.partner = null; this.url = null; this.pending = null; this.active = null;
    this.lastID = null; this.completed = 0; this.savedPose = [];
    const shape = new THREE.Shape();
    shape.moveTo(0, -0.18);
    shape.bezierCurveTo(-0.42, 0.08, -0.23, 0.38, 0, 0.17);
    shape.bezierCurveTo(0.23, 0.38, 0.42, 0.08, 0, -0.18);
    this.heart = new THREE.Mesh(new THREE.ExtrudeGeometry(shape, { depth: 0.07, bevelEnabled: true, bevelSize: 0.025, bevelThickness: 0.02, bevelSegments: 2, steps: 1 }),
      new THREE.MeshStandardMaterial({ color: 0xff79a8, roughness: 0.6 }));
    this.heart.visible = false;
    scene.add(this.heart);
  }
  async setPartner(url) {
    if (url === this.url) return;
    this.url = url;
    this.handA = null; this.handB = null;
    this.finish();
    if (this.partner) { this.scene.remove(this.partner.pivot); dispose(this.partner.pivot); this.partner = null; }
    if (!url) return;
    try {
      const gltf = await new GLTFLoader().loadAsync(url);
      if (this.url !== url) { dispose(gltf.scene); return; }
      const bounds = new THREE.Box3().setFromObject(gltf.scene);
      const size = bounds.getSize(new THREE.Vector3());
      const extent = Math.max(size.x, size.y, size.z);
      if (!Number.isFinite(extent) || extent <= 0) { dispose(gltf.scene); return; }
      const normalized = new THREE.Group();
      normalized.add(gltf.scene);
      normalized.scale.setScalar(1.9 / extent);
      normalized.position.copy(bounds.getCenter(new THREE.Vector3())).multiplyScalar(-1.9 / extent);
      const pivot = new THREE.Group(); pivot.add(normalized); this.scene.add(pivot);
      this.partner = { pivot, model: gltf.scene, player: new PetMotionPlayer(gltf.scene, gltf.animations) };
      this.faceA = this.face(this.model, this.pivot);
      this.faceB = this.face(this.partner.model, pivot);
      this.contactA = this.contact(this.model);
      this.contactB = this.contact(this.partner.model);
    } catch (e) { console.warn('Partner model unavailable', String(e)); }
  }
  face(model, pivot) {
    pivot.updateWorldMatrix(true, true);
    let anchor = null, head = null;
    model.traverse(o => { if (o.name === 'pet_anchor_face') anchor = o; if (o.name === 'pet_head') head = o; });
    if (anchor) return pivot.worldToLocal(anchor.getWorldPosition(new THREE.Vector3()));
    const box = new THREE.Box3().setFromObject(head || model);
    const point = box.getCenter(new THREE.Vector3()); point.z = box.max.z;
    if (!head) point.y = box.min.y + (box.max.y - box.min.y) * 0.72;
    return pivot.worldToLocal(point);
  }
  contact(model, hand = false) {
    const explicit = model.getObjectByName(hand ? 'pet_anchor_hand_r' : 'pet_anchor_face');
    if (explicit) return explicit;
    const parent = model.getObjectByName(hand ? 'pet_arm_r' : 'pet_head') || model;
    const matches = [];
    parent.traverse(o => { if (o.isMesh && (hand ? /paw|hand/i : /mouth|nose/i).test(o.name)) matches.push(o); });
    const box = new THREE.Box3();
    for (const o of matches) box.union(new THREE.Box3().setFromObject(o));
    if (box.isEmpty()) box.setFromObject(parent);
    const point = box.getCenter(new THREE.Vector3());
    if (!hand) point.z = box.max.z;
    const anchor = new THREE.Object3D();
    anchor.position.copy(parent.worldToLocal(point)); parent.add(anchor);
    return anchor;
  }
  perform(event) {
    if (!event || event.id === this.lastID || !['kiss', 'hug', 'highFive'].includes(event.action)) return;
    this.pending = event;
  }
  restorePose() {
    for (const [node, rotation] of this.savedPose) node.quaternion.copy(rotation);
    this.savedPose = [];
  }
  joint(model, name, x, z) {
    const node = model.getObjectByName(name);
    if (!node) return;
    this.savedPose.push([node, node.quaternion.clone()]);
    node.rotateX(x); node.rotateZ(z);
  }
  finish() {
    this.restorePose();
    if (this.active) { this.active = null; this.completed++; this.onFinish(); }
    this.heart.visible = false;
  }
  update(dt, now, reduced) {
    if (this.pending && this.partner && !this.active) {
      const event = this.pending; this.pending = null; this.lastID = event.id;
      const elapsed = Date.now() / 1000 - event.startsAt;
      if (elapsed < 6) {
        this.active = event;
        this.player.setRandomMode(false, this.player.randomInterval, now);
        this.player.play('idle', now);
        this.partner.player.play('idle', now);
      }
    }
    if (!this.partner) { this.pivot.scale.setScalar(1); this.pivot.position.x = 0; return; }
    const other = this.partner;
    other.player.setReducedMotion(reduced); other.player.update(dt, now);
    this.pivot.scale.setScalar(0.67); other.pivot.scale.setScalar(0.67);
    this.pivot.position.x = -0.72; other.pivot.position.set(0.72, this.pivot.position.y, 0);
    other.pivot.rotation.set(0, -0.12, 0);
    if (!this.active) return;
    const t = Math.max(0, Date.now() / 1000 - this.active.startsAt);
    if (t >= 6) { this.finish(); return; }
    const approach = smooth(t / 1.5) * (1 - smooth((t - 4.3) / 1.7));
    const touch = smooth((t - 1.5) / 0.5) * (1 - smooth((t - 3.7) / 0.6));
    const kind = this.active.action;
    this.heart.visible = t > 1.5 && t < 4.4;
    this.heart.material.color.set(kind === 'highFive' ? 0xffd76b : 0xff79a8);
    this.heart.position.set(0, 0.65 + (reduced ? 0 : 0.07 * Math.sin(t * 5)), 0.3);
    this.heart.scale.setScalar(reduced ? 0.7 : 0.7 + 0.1 * Math.sin(t * 7));
    if (reduced) return;
    const depthA = THREE.MathUtils.clamp(Math.abs(this.faceA.z) * 0.67, 0.12, 0.5);
    const depthB = THREE.MathUtils.clamp(Math.abs(this.faceB.z) * 0.67, 0.12, 0.5);
    const gap = kind === 'hug' ? 0.05 : kind === 'highFive' ? 0.18 : 0.015;
    this.pivot.position.x = THREE.MathUtils.lerp(-0.72, -depthA - gap, approach);
    other.pivot.position.x = THREE.MathUtils.lerp(0.72, depthB + gap, approach);
    const faceHeight = Math.max(this.faceA.y, this.faceB.y);
    this.pivot.position.y += (faceHeight - this.faceA.y) * 0.67 * touch;
    other.pivot.position.y += (faceHeight - this.faceB.y) * 0.67 * touch;
    this.pivot.rotation.set(0, Math.PI / 2 * approach, -0.06 * touch);
    other.pivot.rotation.set(0, -Math.PI / 2 * approach, 0.06 * touch);
    const step = Math.sin(t * 16) * 0.035 * approach * (1 - touch);
    this.pivot.position.y += Math.abs(step); other.pivot.position.y += Math.abs(step);
    for (const m of [this.model, other.model]) {
      this.joint(m, 'pet_head', 0.08 * touch, kind === 'kiss' ? 0.09 * touch : 0);
      this.joint(m, 'pet_arm_l', -(kind === 'hug' ? 1.1 : kind === 'highFive' ? 1.6 : 0.35) * touch, 0.3 * touch);
      this.joint(m, 'pet_arm_r', -(kind === 'hug' ? 1.1 : kind === 'highFive' ? 1.6 : 0.35) * touch, -0.3 * touch);
    }
    // Solve contact after animation and rotation, so different proportions and
    // head pivots still meet at the same point instead of relying on body height.
    if (kind === 'highFive' && !this.handA) {
      this.handA = this.contact(this.model, true); this.handB = this.contact(other.model, true);
    }
    const anchorA = kind === 'highFive' ? this.handA : this.contactA;
    const anchorB = kind === 'highFive' ? this.handB : this.contactB;
    this.scene.updateMatrixWorld(true);
    const pa = anchorA.getWorldPosition(new THREE.Vector3());
    const pb = anchorB.getWorldPosition(new THREE.Vector3());
    const correction = pb.clone().sub(pa).multiplyScalar(touch * 0.5);
    correction.x -= (kind === 'hug' ? 0.045 : 0.008) * touch;
    this.pivot.position.add(correction); other.pivot.position.sub(correction);
  }
  dispose() { this.url = null; dispose(this.partner?.pivot); dispose(this.heart); }
}

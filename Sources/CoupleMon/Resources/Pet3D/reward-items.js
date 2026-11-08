import * as THREE from 'three';

export const interactionActions = ['playStar', 'hugHeart', 'blowBubbles', 'restMoon', 'playBall', 'paint',
  'playMusic', 'fish', 'celebrateCrown', 'castSpell', 'celebrate100'];
const mat = color => new THREE.MeshStandardMaterial({ color, roughness: 0.45, metalness: 0.12 });
const mesh = (geometry, color) => new THREE.Mesh(geometry, mat(color));
function rod(group, color, height = 0.34) {
  const object = mesh(new THREE.CylinderGeometry(0.018, 0.025, height, 10), color);
  object.position.y = height / 2;
  group.add(object);
}
function star(color) {
  const shape = new THREE.Shape();
  for (let i = 0; i < 10; i++) {
    const angle = Math.PI / 2 + i * Math.PI / 5, r = i % 2 ? 0.055 : 0.12;
    if (i === 0) shape.moveTo(Math.cos(angle) * r, Math.sin(angle) * r);
    else shape.lineTo(Math.cos(angle) * r, Math.sin(angle) * r);
  }
  shape.closePath();
  return mesh(new THREE.ExtrudeGeometry(shape, { depth: 0.04, bevelEnabled: true, bevelSize: 0.01, bevelThickness: 0.01, bevelSegments: 2 }), color);
}
function line(points, color) {
  return new THREE.Line(new THREE.BufferGeometry().setFromPoints(points.map(point => new THREE.Vector3(...point))),
    new THREE.LineBasicMaterial({ color }));
}
function dispose(root) {
  root.traverse(object => { object.geometry?.dispose(); object.material?.dispose(); });
  root.clear();
}

export class RewardItem {
  constructor(scene, model) {
    this.root = new THREE.Group();
    this.effects = new THREE.Group();
    scene.add(this.root, this.effects);
    this.model = model;
    this.amount = 0;
    this.root.visible = false;
    this.anchor = model.getObjectByName('pet_arm_r');
    model.traverse(object => {
      if (/pet_hand_r|paw_holding_heart_?001/i.test(object.name)) this.anchor = object;
    });
    this.anchor = model.getObjectByName('pet_anchor_hand_r') || this.anchor;
  }
  setReward(reward) {
    if (this.reward?.level === reward?.level) return;
    dispose(this.root);
    dispose(this.effects);
    this.reward = reward;
    this.root.visible = !!reward;
    this.amount = 0;
    if (!reward) return;
    const color = new THREE.Color().setHSL(((reward.level * 37) % 360) / 360, 0.65, 0.63);
    this.color = color;
    const kind = reward.kind;
    if (kind === 'star' || kind === 'wand') {
      if (kind === 'wand') rod(this.root, 0x8c6bcb);
      const object = star(kind === 'star' ? color : 0xffdf76);
      object.position.y = kind === 'wand' ? 0.38 : 0.05;
      this.root.add(object);
    } else if (kind === 'heart') {
      const shape = new THREE.Shape();
      shape.moveTo(0, -0.1); shape.bezierCurveTo(-0.22, 0.02, -0.1, 0.23, 0, 0.1);
      shape.bezierCurveTo(0.1, 0.23, 0.22, 0.02, 0, -0.1);
      this.root.add(mesh(new THREE.ExtrudeGeometry(shape, { depth: 0.06, bevelEnabled: true, bevelSize: 0.015, bevelThickness: 0.015, bevelSegments: 2 }), color));
    } else if (kind === 'bubbles') {
      rod(this.root, color, 0.22);
      const ring = mesh(new THREE.TorusGeometry(0.07, 0.012, 8, 24), color);
      ring.position.y = 0.28;
      this.root.add(ring);
    } else if (kind === 'moon') {
      const moon = mesh(new THREE.TorusGeometry(0.16, 0.05, 8, 32, Math.PI * 1.55), color);
      moon.rotation.z = 0.6;
      this.root.add(moon);
    } else if (kind === 'ball' || kind === 'music') {
      this.root.add(mesh(new THREE.SphereGeometry(0.12, 20, 12), color));
      const stripe = mesh(new THREE.TorusGeometry(0.12, 0.015, 6, 24), 0xffedb0);
      this.root.add(stripe);
      if (kind === 'music') rod(this.root, 0xffedb0, 0.2);
    } else if (kind === 'brush') {
      rod(this.root, 0xa67a53, 0.3);
      const tip = mesh(new THREE.ConeGeometry(0.045, 0.13, 12), color);
      tip.position.y = 0.36;
      this.root.add(tip);
      this.effects.add(line(Array.from({ length: 24 }, (_, i) => [0.3 + i * 0.018, -0.25 + Math.sin(i * 0.35) * 0.07, 0.75]), color));
    } else if (kind === 'fishing') {
      rod(this.root, color, 0.46);
      this.root.add(line([[0, 0.46, 0], [0.17, 0.38, 0], [0.2, 0.08, 0]], 0xcfeaff));
      const fish = mesh(new THREE.SphereGeometry(0.055, 12, 8), 0xffbb72);
      fish.scale.set(1.6, 0.8, 0.6);
      fish.position.set(0.2, 0.07, 0);
      this.root.add(fish);
    } else if (kind === 'crown') {
      this.root.add(mesh(new THREE.TorusGeometry(0.13, 0.025, 8, 24), 0xffd05a));
      for (let i = 0; i < 5; i++) {
        const point = mesh(new THREE.ConeGeometry(0.04, 0.12, 4), 0xffd05a);
        point.position.set(Math.cos(i * Math.PI * 0.4) * 0.11, Math.sin(i * Math.PI * 0.4) * 0.11, 0.03);
        point.rotation.x = Math.PI / 2;
        this.root.add(point);
      }
    } else if (kind === 'trophy') {
      rod(this.root, 0xffcf54, 0.15);
      const cup = mesh(new THREE.CylinderGeometry(0.13, 0.05, 0.16, 20), 0xffd45e);
      cup.position.y = 0.23;
      this.root.add(cup, mesh(new THREE.BoxGeometry(0.2, 0.035, 0.12), 0x6f5cad));
    }
    // Every level carries a distinct palette and tier; higher tiers gain extra beads.
    for (let i = 0; i < Math.min(9, reward.variant - 1); i++) {
      const bead = mesh(new THREE.SphereGeometry(0.018, 8, 6), color);
      bead.position.set(Math.cos(i * 2.4) * 0.14, -0.05 + i * 0.014, Math.sin(i * 2.4) * 0.07);
      this.root.add(bead);
    }
    if (['star', 'wand', 'bubbles', 'music', 'trophy'].includes(kind)) {
      for (let i = 0; i < 6; i++) {
        const particle = kind === 'bubbles'
          ? new THREE.Mesh(new THREE.SphereGeometry(0.035 + i * 0.004, 12, 8), new THREE.MeshStandardMaterial({ color, transparent: true, opacity: 0.4, roughness: 0.1 }))
          : star(color);
        if (kind !== 'bubbles') particle.scale.setScalar(0.2);
        this.effects.add(particle);
      }
    }
  }
  update(now, dt, action, reduced) {
    if (!this.reward) return;
    const active = action === this.reward.action && !reduced;
    this.amount += ((active ? 1 : 0) - this.amount) * Math.min(1, dt * 8);
    if (reduced) this.amount = 0;
    const resting = new THREE.Vector3(0.83, -0.65, 0.3);
    const target = new THREE.Vector3(0.32, -0.05, 0.7);
    if (this.anchor) {
      this.model.updateMatrixWorld(true);
      this.anchor.getWorldPosition(target);
      target.z += 0.12;
    }
    const kind = this.reward.kind, speed = 1 + this.reward.variant * 0.08;
    if (kind === 'heart') target.set(0, -0.06, 0.72);
    if (kind === 'moon') target.set(-0.65, -0.25, 0.45);
    if (kind === 'ball') target.set(0.42 + Math.sin(now * 3) * 0.18, -0.85 + Math.abs(Math.sin(now * 5 * speed)) * 0.35, 0.55);
    if (kind === 'star') { target.x += Math.cos(now * 4 * speed) * 0.1; target.y += Math.sin(now * 4 * speed) * 0.1; }
    if (kind === 'crown') target.set(0, 1.0 + Math.sin(now * 3) * 0.04, 0.25);
    this.root.position.copy(resting).lerp(target, this.amount);
    this.root.rotation.set(0.1, reduced ? 0 : Math.sin(now * speed) * 0.2, active ? Math.sin(now * 4 * speed) * 0.18 : -0.1);
    if (this.anchor && this.amount > 0 && !['heart', 'moon', 'ball', 'crown'].includes(kind)) {
      const heldRotation = this.anchor.getWorldQuaternion(new THREE.Quaternion());
      this.root.quaternion.slerp(heldRotation, this.amount * 0.75);
    }
    this.root.scale.setScalar(active && kind === 'heart' ? 1 + Math.sin(now * 5) * 0.08 : 1);
    this.effects.visible = active;
    if (kind !== 'brush') this.effects.children.forEach((particle, i) => {
      const phase = (now * 0.5 * speed + i / 6) % 1;
      const radius = kind === 'trophy' ? phase * 0.85 : 0.12 + phase * 0.2;
      particle.position.set(target.x + Math.cos(i * 2.4) * radius, target.y + phase * 0.55, target.z + Math.sin(i * 2.4) * radius);
      particle.rotation.z = now + i;
    });
  }
  dispose() { dispose(this.root); dispose(this.effects); }
}

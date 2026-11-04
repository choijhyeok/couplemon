import * as THREE from 'three';
import { RewardItem } from './reward-items.js';

const material = color => new THREE.MeshStandardMaterial({ color, roughness: 0.45, metalness: 0.15 });
function extruded(shape, color) {
  return new THREE.Mesh(new THREE.ExtrudeGeometry(shape, {
    depth: 0.055, bevelEnabled: true, bevelSegments: 2, steps: 1, bevelSize: 0.015, bevelThickness: 0.015,
  }), material(color));
}
function star() {
  const shape = new THREE.Shape();
  for (let i = 0; i < 10; i++) {
    const angle = Math.PI / 2 + i * Math.PI / 5, radius = i % 2 ? 0.075 : 0.16;
    const x = Math.cos(angle) * radius, y = Math.sin(angle) * radius;
    if (i === 0) shape.moveTo(x, y); else shape.lineTo(x, y);
  }
  shape.closePath();
  return extruded(shape, 0xffd665);
}
function heart() {
  const shape = new THREE.Shape();
  shape.moveTo(0, -0.13);
  shape.bezierCurveTo(-0.3, 0.05, -0.13, 0.27, 0, 0.12);
  shape.bezierCurveTo(0.13, 0.27, 0.3, 0.05, 0, -0.13);
  return extruded(shape, 0xff8da8);
}
function crown() {
  const group = new THREE.Group();
  const band = new THREE.Mesh(new THREE.TorusGeometry(0.18, 0.035, 8, 32), material(0xffcc48));
  band.rotation.x = Math.PI / 2;
  group.add(band);
  for (let i = 0; i < 5; i++) {
    const angle = i / 5 * Math.PI * 2;
    const point = new THREE.Mesh(new THREE.ConeGeometry(0.06, 0.15, 4), material(0xffd96b));
    point.position.set(Math.cos(angle) * 0.14, 0.065, Math.sin(angle) * 0.14);
    group.add(point);
  }
  return group;
}

export class PetProps {
  constructor(scene, model) {
    this.rewardItem = new RewardItem(scene, model);
    const moon = new THREE.Mesh(new THREE.TorusGeometry(0.13, 0.045, 8, 32, Math.PI * 1.55), material(0xbcb2ff));
    moon.rotation.z = 0.65;
    this.items = [
      { name: 'star', level: 2, mesh: star(), position: [-0.94, 0.48, 0.1] },
      { name: 'heart', level: 3, mesh: heart(), position: [0.95, 0.32, 0.15] },
      { name: 'moon', level: 5, mesh: moon, position: [-0.92, -0.48, 0.1] },
      { name: 'crown', level: 10, mesh: crown(), position: [0, 1.09, 0] },
    ];
    for (const item of this.items) {
      item.mesh.name = 'level_' + item.name;
      item.mesh.position.set(...item.position);
      scene.add(item.mesh);
    }
    this.setLevel(1);
    this.letter = new THREE.Group();
    this.letter.add(new THREE.Mesh(new THREE.BoxGeometry(0.32, 0.22, 0.045), material(0xfff1d6)));
    const seam = new THREE.Line(new THREE.BufferGeometry().setFromPoints([
      new THREE.Vector3(-0.15, 0.1, 0.025), new THREE.Vector3(0, -0.02, 0.025), new THREE.Vector3(0.15, 0.1, 0.025),
    ]), new THREE.LineBasicMaterial({ color: 0xc19870 }));
    this.letter.add(seam);
    this.letter.visible = false;
    scene.add(this.letter);
    this.event = null;
  }
  setLevel(level) {
    this.level = Math.max(1, Math.min(100, Math.floor(Number(level) || 1)));
    for (const item of this.items) item.mesh.visible = this.level >= item.level;
    if (this.rewardItem.reward?.level > this.level) this.rewardItem.setReward(null);
  }
  setReward(reward) { this.rewardItem.setReward(reward && reward.level >= 2 && reward.level <= this.level ? reward : null); }
  startLetter(event, now) {
    this.event = ['sendingLetter', 'receivingLetter'].includes(event) ? event : null;
    this.started = now;
    this.letter.visible = false;
  }
  update(now, reduced, dt, action) {
    this.rewardItem.update(now, dt, action, reduced);
    for (let i = 0; i < this.items.length; i++) {
      const item = this.items[i];
      item.mesh.position.y = item.position[1] + (reduced ? 0 : Math.sin(now * 1.6 + i * 1.7) * 0.045);
      if (item.name !== 'moon') item.mesh.rotation.y = reduced ? 0 : Math.sin(now + i) * 0.25;
    }
    const t = (now - this.started) / 1.4;
    this.letter.visible = !reduced && this.event != null && t >= 0 && t < 1;
    if (this.letter.visible) {
      const travel = this.event === 'sendingLetter' ? t : 1 - t;
      this.letter.position.set(0.15 + travel * 0.65, -0.16 + travel * 0.6, 0.7);
      this.letter.rotation.set(0.1, travel * 0.5, -travel * 0.35);
      this.letter.scale.setScalar(0.9 - travel * 0.3);
    }
  }
  get unlocked() { return this.items.filter(item => item.mesh.visible).map(item => item.name); }
  dispose() {
    this.rewardItem.dispose();
    for (const root of [...this.items.map(item => item.mesh), this.letter]) {
      root.traverse(object => {
        object.geometry?.dispose();
        for (const mat of [object.material].flat().filter(Boolean)) mat.dispose();
      });
    }
  }
}

import * as THREE from 'three';
import { IllustratedMotion, isIllustrated } from './illustrated-motion.js';

export class PetMotionPlayer {
  constructor(model, clips) {
    this.mixer = new THREE.AnimationMixer(model);
    this.illustrated = isIllustrated(model) ? new IllustratedMotion(model) : null;
    this.clips = new Map(clips.map(clip => [clip.name.toLowerCase(), clip]));
    this.idle = this.clips.get('idle') || clips.find(clip => /idle|breath/i.test(clip.name)) || clips[0];
    this.name = 'idle';
    this.reduced = false;
    this.started = 0;
    this.deadline = Infinity;
    this.randomEnabled = false;
    this.randomInterval = 5;
    this.nextRandomAt = Infinity;
    this.lastRandomAction = null;
    this.randomActionCount = 0;
    this.mixer.addEventListener('finished', event => {
      if (event.action === this.active) this.play('idle', this.now);
    });
    this.play('idle', 0);
  }
  play(name, now = this.now || 0) {
    if (this.reduced) name = 'idle';
    this.name = name;
    this.started = now;
    this.nextRandomAt = this.randomEnabled && name === 'idle' ? now + this.randomInterval : Infinity;
    if (this.illustrated) {
      this.mixer.stopAllAction();
      this.hasClip = true;
      this.deadline = now + this.illustrated.duration(name);
      this.illustrated.play(name);
      return;
    }
    const clip = this.clips.get(name.toLowerCase()) || (name === 'idle' ? this.idle : null);
    this.hasClip = !!clip;
    this.deadline = clip || name === 'idle' ? Infinity : now + 1.8;
    const previous = this.active;
    if (!clip) {
      previous?.fadeOut(0.15);
      this.active = null;
      return;
    }
    const next = this.mixer.clipAction(clip);
    next.reset().setEffectiveTimeScale(1).setEffectiveWeight(1);
    next.setLoop(name === 'idle' ? THREE.LoopRepeat : THREE.LoopOnce, name === 'idle' ? Infinity : 1);
    next.clampWhenFinished = false;
    next.play();
    if (previous && previous !== next) next.crossFadeFrom(previous, 0.16, false);
    this.active = next;
  }
  setRandomMode(enabled, interval, now = this.now || 0) {
    interval = Math.max(3, Math.min(30, Number(interval) || 5));
    if (this.randomEnabled === enabled && this.randomInterval === interval) return;
    const wasEnabled = this.randomEnabled;
    this.randomEnabled = enabled;
    this.randomInterval = interval;
    if (!enabled) {
      this.nextRandomAt = Infinity;
      if (wasEnabled) this.play('idle', now);
    } else if (!wasEnabled && this.name === 'idle' && !this.reduced) {
      this.playRandom(now);
    } else {
      this.nextRandomAt = this.name === 'idle' ? now + interval : Infinity;
    }
  }
  playRandom(now) {
    const basic = ['runningRight', 'runningLeft', 'waving', 'jumping', 'failed', 'waiting', 'running', 'review', 'lookAround'];
    const candidates = this.illustrated ? ['waiting', 'lookAround', 'review', 'waving', 'failed'] : basic;
    let choices = candidates.filter(name => this.clips.has(name.toLowerCase()));
    if (!choices.length) choices = basic;
    if (this.interaction) choices.push(this.interaction);
    const different = choices.filter(name => name !== this.lastRandomAction);
    if (different.length) choices = different;
    const selected = choices[Math.floor(Math.random() * choices.length)];
    this.lastRandomAction = selected;
    this.randomActionCount += 1;
    this.play(selected, now);
  }
  setReducedMotion(value) {
    if (value === this.reduced) return;
    this.reduced = value;
    this.mixer.stopAllAction();
    this.active = null;
    this.play('idle', this.now);
    this.mixer.update(0);
    if (this.illustrated) this.illustrated.update(0, this.reduced);
  }
  update(dt, now) {
    this.now = now;
    if (this.illustrated) this.illustrated.update(dt, this.reduced);
    if (this.reduced) return;
    if (!this.illustrated) this.mixer.update(dt);
    if (now >= this.deadline) this.play('idle', now);
    if (this.randomEnabled && this.name === 'idle' && now >= this.nextRandomAt) this.playRandom(now);
  }
  fallback(now) {
    if (this.hasClip || this.reduced || this.name === 'idle') return { y: 0, z: 0 };
    const t = THREE.MathUtils.clamp((now - this.started) / 1.8, 0, 1);
    const envelope = Math.sin(t * Math.PI);
    return { y: (this.name === 'jumping' ? 0.16 : 0.04) * envelope,
      z: 0.07 * Math.sin(t * Math.PI * 4) * envelope };
  }
}

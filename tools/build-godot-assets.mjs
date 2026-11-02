// Asset pipeline for the PC (Godot) edition.
// Raw CC0 downloads -> one plain glTF binary per prefab (no meshopt, PNG/JPEG textures up to 2K)
// so that Godot can import them and generate LODs. Characters share one animation library.
// usage: node build-godot-assets.mjs [chars|anims|props|all]
import fs from 'node:fs';
import { NodeIO, Document, PropertyType } from '@gltf-transform/core';
import { ALL_EXTENSIONS } from '@gltf-transform/extensions';
import { dedup, prune, weld, flatten, join, mergeDocuments, textureCompress } from '@gltf-transform/functions';
import { MeshoptDecoder } from 'meshoptimizer';
import sharp from 'sharp';
import { CHARACTERS, ANIM_SOURCE, LIBS } from './assets-manifest.mjs';

const OUT = '../assets';
const what = process.argv[2] || 'all';
const want = k => what === 'all' || what === k;
await MeshoptDecoder.ready;
const io = new NodeIO().registerExtensions(ALL_EXTENSIONS).registerDependencies({ 'meshopt.decoder': MeshoptDecoder });
const kb = f => (fs.statSync(f).size / 1024).toFixed(0) + 'KB';

async function clean(doc, { joinMeshes = false } = {}) {
  const steps = [joinMeshes ? dedup({ propertyTypes: [PropertyType.ACCESSOR, PropertyType.MESH, PropertyType.TEXTURE] }) : dedup(), prune()];
  if (joinMeshes) steps.push(flatten(), join({ keepNamed: false }), prune());
  steps.push(weld(), textureCompress({ encoder: sharp, resize: [2048, 2048], pattern: /^T_/, targetFormat: 'jpeg', quality: 90 }), textureCompress({ encoder: sharp, resize: [2048, 2048] }));
  await doc.transform(...steps);
  // single buffer for GLB
  const buffers = doc.getRoot().listBuffers();
  for (const a of doc.getRoot().listAccessors()) a.setBuffer(buffers[0]);
  for (const b of buffers.slice(1)) b.dispose();
}

// ---------- characters (meshes + skeleton only) ----------
if (want('chars')) {
  fs.mkdirSync(`${OUT}/chars`, { recursive: true });
  for (const [name, src] of Object.entries(CHARACTERS)) {
    const doc = await io.read(src);
    for (const a of doc.getRoot().listAnimations()) a.dispose();
    await clean(doc);
    await io.write(`${OUT}/chars/${name}.glb`, doc);
    console.log('char', name, kb(`${OUT}/chars/${name}.glb`));
  }
}

// ---------- shared animation library ----------
// Native Quaternius clips + 25 clips retargeted from the Universal Animation Library
// (retargeted offline for the browser edition; stored as three.js clip JSON).
const IN_PLACE = ['roll_ual', 'sprint', 'jog', 'walk_ual', 'walk_formal', 'crouch_walk', 'land', 'land_soft', 'Roll', 'Run', 'Walk', 'Run_Shoot', 'Run_Left', 'Run_Right', 'Run_Back'];
if (want('anims')) {
  fs.mkdirSync(`${OUT}/anims`, { recursive: true });
  const doc = await io.read(ANIM_SOURCE);
  const root = doc.getRoot();
  const buffer = root.listBuffers()[0];
  // only the skeleton is needed
  for (const n of root.listNodes()) if (n.getMesh()) n.setMesh(null);
  for (const s of root.listSkins()) void s;
  const san = s => s.replace(/[\[\]\.:\/]/g, '').replace(/\s/g, '_');
  const byName = new Map(root.listNodes().map(n => [san(n.getName()), n]));
  for (const a of root.listAnimations()) a.setName(a.getName().replace(/^.*\|/, ''));
  const ual = JSON.parse(fs.readFileSync('../../mishmeret-layla/public/assets/anims/ual.json', 'utf8'));
  for (const [clipName, clip] of Object.entries(ual)) {
    const anim = doc.createAnimation(clipName);
    for (const t of clip.tracks) {
      const [nodeName, prop] = t.name.split('.');
      const node = byName.get(nodeName);
      if (!node) continue;
      const path = prop === 'quaternion' ? 'rotation' : 'translation';
      const input = doc.createAccessor().setType('SCALAR').setArray(new Float32Array(t.times)).setBuffer(buffer);
      const output = doc.createAccessor().setType(path === 'rotation' ? 'VEC4' : 'VEC3').setArray(new Float32Array(t.values)).setBuffer(buffer);
      const sampler = doc.createAnimationSampler().setInput(input).setOutput(output).setInterpolation('LINEAR');
      anim.addSampler(sampler).addChannel(doc.createAnimationChannel().setTargetNode(node).setTargetPath(path).setSampler(sampler));
    }
  }
  // strip horizontal root motion from locomotion clips (the AI moves the character)
  for (const a of root.listAnimations()) {
    if (!IN_PLACE.includes(a.getName())) continue;
    for (const ch of a.listChannels()) {
      if (ch.getTargetNode()?.getName() !== 'Body' || ch.getTargetPath() !== 'translation') continue;
      const out = ch.getSampler().getOutput(); const v = out.getArray().slice();
      const x0 = v[0], z0 = v[2];
      for (let i = 0; i < v.length; i += 3) { v[i] = x0; v[i + 2] = z0; }
      out.setArray(v);
    }
  }
  await doc.transform(prune({ propertyTypes: [PropertyType.MESH, PropertyType.MATERIAL, PropertyType.TEXTURE] }));
  await io.write(`${OUT}/anims/anims.glb`, doc);
  console.log('anims', root.listAnimations().length, 'clips', kb(`${OUT}/anims/anims.glb`));
}

// ---------- props: one glb per prefab ----------
if (want('props')) {
  fs.mkdirSync(`${OUT}/props`, { recursive: true });
  for (const entries of Object.values(LIBS)) {
    for (const [name, src] of Object.entries(entries)) {
      const doc = await io.read(src);
      for (const a of doc.getRoot().listAnimations()) a.dispose();
      if (src.includes('/dck/')) for (const m of doc.getRoot().listMeshes()) for (const p of m.listPrimitives()) p.setAttribute('COLOR_0', null);
      // keep only the first scene
      const scenes = doc.getRoot().listScenes();
      for (const s of scenes.slice(1)) s.dispose();
      await clean(doc, { joinMeshes: true });
      await io.write(`${OUT}/props/${name}.glb`, doc);
      console.log('prop', name, kb(`${OUT}/props/${name}.glb`));
    }
  }
}
void mergeDocuments; void Document;

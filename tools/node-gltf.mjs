// Helper: load a .glb in Node with three's GLTFLoader (no textures needed).
import fs from 'node:fs';
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js';
import { MeshoptDecoder } from 'three/examples/jsm/libs/meshopt_decoder.module.js';
globalThis.self ??= globalThis;
export function loadGLB(file) {
  const buf = fs.readFileSync(file);
  const ab = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
  const loader = new GLTFLoader().setMeshoptDecoder(MeshoptDecoder);
  // Replace texture loading with a no-op so Node does not need DOM images.
  loader.register(p => ({ name: 'noop', loadTexture: () => Promise.resolve(null) }));
  return new Promise((res, rej) => loader.parse(ab, '', res, rej));
}

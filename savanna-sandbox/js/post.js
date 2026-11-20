// One full-screen pass after the scene: depth-of-field for the miniature look,
// filmic tone mapping, a light grade and a vignette. `?post=0` turns it off.
import * as THREE from '../vendor/three/three.module.js';

const FRAG = /* glsl */`
precision highp float;
uniform sampler2D tColor;
uniform sampler2D tDepth;
uniform vec2 px;          // size of one pixel in uv
uniform float near, far, focus, maxBlur, exposure, vig;
varying vec2 vUv;

float linearDepth(vec2 uv) {
  float z = texture2D(tDepth, uv).x * 2.0 - 1.0;
  return 2.0 * near * far / (far + near - z * (far - near));
}
float coc(float d) {
  return clamp((abs(d - focus) - focus * 0.085) / (focus * 0.5), 0.0, 1.0);
}
// ACES filmic curve, the same fit three.js uses for ACESFilmicToneMapping.
vec3 rrtOdt(vec3 v) {
  vec3 a = v * (v + 0.0245786) - 0.000090537;
  vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
  return a / b;
}
vec3 aces(vec3 c) {
  const mat3 inM = mat3(0.59719, 0.07600, 0.02840, 0.35458, 0.90834, 0.13383, 0.04823, 0.01566, 0.83777);
  const mat3 outM = mat3(1.60475, -0.10208, -0.00327, -0.53108, 1.10813, -0.07276, -0.07367, -0.00605, 1.07602);
  c *= exposure / 0.6;
  return clamp(outM * rrtOdt(inM * c), 0.0, 1.0);
}
void main() {
  float d = linearDepth(vUv);
  float c = coc(d);
  vec4 base = texture2D(tColor, vUv);
  vec3 sum = base.rgb;
  float wsum = 1.0;
  if (c > 0.02) {
    float rad = c * maxBlur;
    // golden-angle spiral
    for (int i = 1; i <= 22; i++) {
      float fi = float(i);
      float r = sqrt(fi / 22.0) * rad;
      float a = fi * 2.39996;
      vec2 uv = vUv + vec2(cos(a), sin(a)) * r * px;
      float w = clamp(coc(linearDepth(uv)) * 5.0 + 0.12, 0.0, 1.0);
      sum += texture2D(tColor, uv).rgb * w;
      wsum += w;
    }
  }
  vec3 col = sum / wsum;
  col = aces(col);
  float lum = dot(col, vec3(0.299, 0.587, 0.114));
  col = mix(vec3(lum), col, 1.06);
  vec2 q = vUv - 0.5;
  col *= 1.0 - vig * smoothstep(0.35, 0.95, length(q) * 1.25);
  col = mix(col * 12.92, 1.055 * pow(col, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, col));
  gl_FragColor = vec4(col, 1.0);
}`;

const VERT = /* glsl */`
varying vec2 vUv;
void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`;

export function createPost(stage) {
  const { renderer, scene, camera } = stage;
  const size = new THREE.Vector2();
  renderer.getDrawingBufferSize(size);
  const target = new THREE.WebGLRenderTarget(size.x, size.y, { type: THREE.HalfFloatType, samples: 4, depthBuffer: true });
  target.depthTexture = new THREE.DepthTexture(size.x, size.y);
  target.depthTexture.type = THREE.UnsignedIntType;
  const mat = new THREE.ShaderMaterial({
    vertexShader: VERT, fragmentShader: FRAG, depthTest: false, depthWrite: false,
    uniforms: {
      tColor: { value: target.texture }, tDepth: { value: target.depthTexture }, px: { value: new THREE.Vector2() },
      near: { value: camera.near }, far: { value: camera.far }, focus: { value: 100 }, maxBlur: { value: 10 }, exposure: { value: 1.0 }, vig: { value: 0.3 },
    },
  });
  const quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), mat);
  const quadScene = new THREE.Scene();
  quadScene.add(quad);
  const quadCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
  const P = { blur: 1 };
  P.render = () => {
    renderer.getDrawingBufferSize(size);
    if (target.width !== size.x || target.height !== size.y) target.setSize(size.x, size.y);
    mat.uniforms.px.value.set(1 / size.x, 1 / size.y);
    mat.uniforms.focus.value = stage.cam.dist;
    mat.uniforms.maxBlur.value = size.y * 0.0095 * P.blur;
    renderer.setRenderTarget(target);
    renderer.render(scene, camera);
    renderer.setRenderTarget(null);
    renderer.render(quadScene, quadCam);
  };
  return P;
}

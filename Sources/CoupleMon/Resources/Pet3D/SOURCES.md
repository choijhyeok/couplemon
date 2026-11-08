# Local character generation references

Prompt is authored for CoupleMon, not copied from a third-party prompt pack.

- LivLiv Player: https://github.com/livliv-dev/player
  Reviewed `src/runtime/puppet.ts` (head paraboloid, anchor-based grid deformation,
  depth/parallax) and `FORMAT.md` (drawing coordinates and rig anchors).
  `image-rig.py` independently implements a curved original-image UV grid with
  continuous skin weights and glTF bone animation. It does not copy LivLiv code,
  its models, textures, brand assets, or its unpublished AI generation pipeline.
  Source artwork remains the user's. This mode preserves the front illustration;
  it does not reconstruct unseen geometry. `illustrated-motion.js` independently
  implements asynchronous gaze/head/body motion, damped follow-through and a
  continuous breathing field with fixed feet, inspired by `src/runtime/idle.ts`.
- Mesh Avatar Studio: https://github.com/shinshin86/mesh-avatar-studio/blob/main/docs/format.md
  Separate source-eye patches and a filled backing informed the generated eye rig.
  Our small backing uses neighboring skin/fur interpolation; closing lids and a
  curved closed-eye stroke are local geometry, not copied or AI-generated art.
- Live2D physics: https://docs.live2d.com/4.2/en/cubism-editor-manual/physics-operation/
  Input-driven secondary motion informed damped ear/tail follow-through. No Cubism
  SDK or Live2D model files are used.

- BlenderAlchemy authors' implementation: https://github.com/ianhuang0630/BlenderAlchemyOfficial
  Image-grounded procedural edits and execution-feedback iteration inspired the image inspection and one repair pass.
- BlenderLLM authors' implementation: https://github.com/FreedomIntelligence/BlenderLLM
  Runnable bpy scripts with execution feedback, rather than an image presented as a 3D asset.
- Three.js AnimationAction: https://threejs.org/docs/pages/AnimationAction.html
  Named one-shot actions, crossfades, completion events, and return to idle.
- Blender glTF manual: https://docs.blender.org/manual/en/latest/addons/import_export/scene_gltf2.html
  Export-compatible Principled BSDF materials, meshes, embedded GLB resources, and animation.
- Blender Python glTF exporter: https://docs.blender.org/api/current/bpy.ops.export_scene.html
- Codex CLI: https://learn.chatgpt.com/docs/developer-commands
  Image attachment, read-only exec, JSON schema, final-response file.
- Claude Code: https://code.claude.com/docs/en/headless
  Noninteractive stream JSON and structured output.

Renderer vendors three.js r180 (0.180.0), GLTFLoader and BufferGeometryUtils under MIT.
Upstream: https://github.com/mrdoob/three.js/tree/r180
GLTFLoader's BufferGeometryUtils import is changed to a sibling path; all other vendor code is unchanged.
No CDN requests at runtime. No external 3D generation API.

`pet-actions.py` bakes ten basic actions and eleven item interactions through shared NLA track names and validates all 21 clips in the GLB export.
Level ornaments are app-created Three.js meshes, independent of generated character geometry.

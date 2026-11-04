# Local character generation references

Prompt is authored for CoupleMon, not copied from a third-party prompt pack.

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

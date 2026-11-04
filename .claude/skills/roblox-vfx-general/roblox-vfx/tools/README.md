# VFX workflow tools

Command-line helpers for the `roblox-vfx` skill (this folder is `<skill>/tools/`). They run on
the dev machine, never in the game.

| Tool | Needs | Does |
|---|---|---|
| `clip.mjs read` | Node 18+, ffmpeg + ffprobe on PATH | Stores a reference video's frames, measures the effect's timing, size and colours, writes labelled overview and close-up sheets |
| `clip.mjs span` | same | A labelled sheet of up to 16 stored frames between two effect times |
| `clip.mjs compare` | same | Our captures beside the clip's frames at the same effect times (R, then S) |
| `clip.mjs tone` | same | Colour check on our captures: pale / vivid / deep / blown-out shares against studied artists' effects |
| `flipbook.mjs` | Node 18+ | Checks a 1024 x 1024 flipbook sheet: grid, empty cells, drawing cut off at cell edges, repeated or held frames, and the emitter settings to use |
| `vfxtex.py` | numpy (Blender's Python has it) | Draws textures and flipbooks: strokes, blobs, noise, warps, hard edges; writes PNG + preview + a note for `flipbook.mjs` |
| `examples.py` | numpy | Ten example drawings (claw slash, puff, dust, splinters, cracks, impact star, glint, star, fire burst, burn-out) |

Run `node <skill>/tools/clip.mjs help` for every option. How these fit into building an effect:
`references/review.md`, `references/setup.md` ("Matching a reference video") and
`references/drawing-textures.md` in the skill. Mesh shapes for effects (swirl, dome, any
surface) are MeshFactory generators in `runtime/VFX/MeshFactory.luau`.

Stored clips go to `.vfx-clips/` in the current folder (add it to `.gitignore`) unless `--out` says otherwise.

## License

These tools are ported from [Roqer](https://github.com/S4US/Roqer) (commit `4e29b9b`), an
open-source Roblox Studio agent by S4US and contributors, licensed under the GNU Affero
General Public License v3.0 or later. The files here are modified versions of Roqer's and
are under the same license (`LICENSE` in this folder). Each file names the Roqer source it
came from. If you distribute this folder, or a program built on it, the AGPL's terms apply.

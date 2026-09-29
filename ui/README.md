# ui: the contract

Not built yet. When it is, it obeys three rules, and CI will grep for
the first one.

1. **Nothing in `ui/` withs anything below `Forge.Session`.** The GUI
   sees `Forge.Session` (Execute, Mesh_Of, History_*) and `Forge`
   (Vec3, Name). It never sees `Forge.Mesh` operations, `Forge.CSG`,
   `Forge.Primitives`.
2. **Every button builds a line and calls `Execute`.** The line is
   shown in a command bar at the bottom of the window before it runs.
   A user who watches the bar for an hour can write `.forge` files.
3. **Rendering reads `Mesh_Of (S, name)` after every `Execute`** and
   uploads it to the GPU. It never mutates a mesh. Selection, camera,
   colours and highlighting are UI state, not session state, and are
   not saved in the document.

## Suggested stack

- Window and input: [adi2](https://github.com/ovenpasta/adi2), with
  the command bar as a text field and the solid list as a list widget.
- Viewport: OpenGLAda into adi2's texture-view widget. One VBO per
  solid, rebuilt when `Mesh_Of` changes (compare `NT` and a hash, or
  just rebuild; parts are small).
- Camera: orbit, pan, zoom on the mouse; nothing fancy.

## Milestone 5 acceptance

Open `examples/bracket.forge`, see three solids, type
`difference cut base hole` in the bar (milestone 2 done), see the cut
part, click Export, open the STL in another tool, it is watertight.
Then do the same by clicking, and read the bar: same four lines.

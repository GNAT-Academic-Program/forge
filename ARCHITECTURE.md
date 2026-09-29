# Architecture

## Layers

```
ui/  (adi2 + OpenGLAda)      cli/  (stdin)         an agent (pipe)      front ends: lines in, lines out
              \                 |                    /
               Forge.Session    Execute (S, Line, Response); Mesh_Of for renderers
                    |           owns memory (heap), history, undo, save/load
               Forge.Commands   Command <-> text, Parse and Image are inverses
                    |
   Forge.CSG   Forge.Primitives   Forge.Transform   Forge.STL      kernel operations
                    |
               Forge.Mesh        Tri_Mesh, Well_Formed, Is_Watertight, Volume    SPARK, proof target
                    |
               Forge             Scalar, Vec3, Name                              Pure
```

Dependencies point down only. Nothing above `Forge.Session` names a
kernel package. Nothing at or below `Forge.Mesh` allocates or does I/O.

## The edge, and why it holds

Every CAD program has a script layer bolted on after the fact, and the
GUI always ends up able to do things the script cannot. forge inverts
the order: the script layer is the only layer. `Forge.Session.Execute`
takes a `String` and returns a `Response`. There is no second API.

Consequences:

- A GUI button is a function that builds a line and calls `Execute`.
  The GUI's command bar shows that line. A user learns the language by
  watching the buttons.
- The document is the history. Save writes it; load replays it. There
  is no serializer to keep in sync with the model, because the model
  is a replay.
- Undo is pop-and-replay. O(n), and there is nothing to get wrong.
- An agent has the same power as a user: read the file, emit lines,
  read `info`. No screenshot parsing, no accessibility tree.

The cost: replay must be deterministic. The kernel is pure, so it is.

## Kernel

### Tri_Mesh

Indexed triangle mesh, bounded by two discriminants, no heap. `NV`,
`NT` live counts; `V (1 .. NV)`, `T (1 .. NT)`. `Well_Formed` says every
triangle refers to three distinct live vertices; it is the
precondition of everything and the postcondition of every builder.

### Solid

A mesh is a solid when it is closed and consistently oriented. One test
covers both: every directed edge `(a, b)` appears exactly once and its
reverse `(b, a)` appears exactly once. That is `Is_Watertight`. A hole
breaks "once"; a flipped triangle breaks "reverse". `Is_Solid` adds
`NT >= 4` (a tetrahedron is the smallest closed surface).

`Volume` is the signed sum over triangles of `dot (a, cross (b, c)) / 6`.
Positive for outward orientation. The tests use it as a second oracle.

### Numbers

`Scalar is new Long_Float`. CAD lives in millimetres with sub-micron
tolerances and metre-scale parts; that is 12 orders of magnitude, and
fixed point cannot do it. The proof story is topology, which is
integers.

### Operations

Primitives build a mesh from nothing and promise `Is_Solid`. Transforms
move vertices and leave topology alone, so they preserve `Is_Solid` by
construction (except a negative scale, which the spec forbids). CSG is
the placeholder. STL is a byte writer.

Every operation has the same shape: meshes in, mesh out, `Ok` out, and
in CSG a reason. No exceptions cross a kernel boundary.

## Session

`Solids`: a fixed table of 64 named `Mesh_Access`, allocated once per
slot at first use and reused. `History`: 4096 modeling commands.
`Execute` parses, dispatches, and for modeling commands appends to the
history only on success, so the history is always replayable.

`Ensure_Solid` after every primitive and CSG result: if the kernel hands
back something that fails `Is_Solid`, the session discards it and
reports an error. The kernel's promise is checked at the boundary,
which is what lets `ui/` trust `Mesh_Of` blindly.

## Commands

A `Command` is a discriminated record; `Parse` builds one from a line,
`Image` prints it. The grammar is in the spec header. Numbers print as
integers when integral and as `Long_Float'Image` otherwise, so files are
readable and still exact. `Round_Trip` in the tests is the contract.

Queries (`list`, `info`), side effects (`export`) and meta commands
(`undo`, `save`, `load`) are not recorded. Only `Modeling` commands
are the document.

## CSG: the project

`Forge.CSG.Apply (Op, A, B, Result, Ok, Reason, Last)`. The contract is
solid in, solid out, or `Ok = False` with a reason. The seed returns the
reason "not implemented".

Path:

1. **BSP CSG** (milestone 2). Build a BSP tree from each mesh's
   triangles (each node a plane, polygons split across it). Union:
   clip A by B, clip B by A, remove B's coplanar duplicates, merge.
   Difference: invert A, union with B, invert. Intersection: by De
   Morgan. Output is a polygon soup; triangulate, then merge coincident
   vertices so `Is_Watertight` can pass. Expect slivers and near-
   degenerate triangles; the `Ensure_Solid` gate will reject the first
   several attempts, which is the point.
2. **Robustness** (milestone 4). Floating-point plane classification
   is the source of every failure in step 1. Options: epsilon with
   careful vertex welding; exact rational predicates on the
   intersection curve (Shewchuk-style adaptive precision); or a
   fixed-point snap of the intersection points. The last is the one
   that leads to a proof.

What must never happen: `Apply` returning `Ok = True` with a mesh that
fails `Is_Solid`. The session catches it, but the kernel should not
rely on that.

## STL

Binary STL, 84 + 50 * NT bytes, little-endian, face normal unnormalized
(readers ignore it). `Size` is exact; `Write` fills exactly that. Export
is derived data; the `.forge` file is the source.

## What is deliberately not here

- Parametric constraints, sketches, fillets. Each is a command family
  on top of this; none changes the architecture.
- Any mesh import. STL in is a milestone once CSG can consume arbitrary
  solids.
- A GUI in the seed. `ui/README.md` is the contract; adi2 and OpenGLAda
  are the tools; milestone 5.

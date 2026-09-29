--  Boolean operations on solids. THE PROJECT.
--
--  Given two solids A and B, produce a solid that is their union,
--  difference (A minus B) or intersection. This is what makes a modeler
--  a modeler, and it is hard: the triangles of A and B must be split
--  along their mutual intersection curve, classified inside/outside the
--  other solid, and the kept pieces stitched into a closed mesh.
--
--  The seed body returns Ok = False with Reason = "not implemented".
--  Everything else (primitives, transforms, session, script, CLI, STL)
--  works around that hole, so the tool is usable from day one for
--  positioning primitives and exporting, and the hole is exactly the
--  size of the capstone.
--
--  Recommended path (ARCHITECTURE.md has the detail):
--    1. BSP-tree CSG (the classic "csg.js" algorithm): build a BSP from
--       each mesh, clip each against the other, invert as needed, merge.
--       Simple, robust enough for primitives, produces sliver triangles.
--       Milestone 2.
--    2. Exact arithmetic on the intersection curve (rational or
--       fixed-point predicates) so that Is_Solid holds on the output for
--       every input pair. Milestone 4; this is where "proven" gets teeth.
--
--  Contract every implementation must meet: solid in, solid out, or
--  Ok = False with a reason. Never a mesh that fails Is_Solid.

with Forge.Mesh; use Forge.Mesh;

package Forge.CSG with SPARK_Mode is

   type Operation is (Union, Difference, Intersection);

   Max_Reason : constant := 64;
   subtype Reason_String is String (1 .. Max_Reason);

   procedure Apply
     (Op     : Operation;
      A, B   : Tri_Mesh;
      Result : in out Tri_Mesh;
      Ok     : out Boolean;
      Reason : out Reason_String;
      Last   : out Natural)
     with Pre  => Well_Formed (A) and then Well_Formed (B),
          Post => Well_Formed (Result)
                  and then Last <= Max_Reason
                  and then (if not Ok then Result.NT = 0);
   --  On Ok, Result is a solid. Reason (1 .. Last) says why not otherwise.

end Forge.CSG;

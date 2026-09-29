with Ada.Numerics;
with Ada.Numerics.Generic_Elementary_Functions;

package body Forge.Transform with SPARK_Mode => Off is
   --  Off for sin/cos in Rotate only.

   package Elem is new Ada.Numerics.Generic_Elementary_Functions (Scalar);

   procedure Translate (M : in out Tri_Mesh; By : Vec3) is
   begin
      for I in 1 .. M.NV loop
         M.V (I) := M.V (I) + By;
      end loop;
   end Translate;

   procedure Scale (M : in out Tri_Mesh; F : Scalar) is
   begin
      for I in 1 .. M.NV loop
         M.V (I) := M.V (I) * F;
      end loop;
   end Scale;

   procedure Rotate (M : in out Tri_Mesh; About : Axis; Degrees : Scalar) is
      A : constant Scalar := Degrees * Ada.Numerics.Pi / 180.0;
      C : constant Scalar := Elem.Cos (A);
      S : constant Scalar := Elem.Sin (A);
   begin
      for I in 1 .. M.NV loop
         declare
            P : constant Vec3 := M.V (I);
         begin
            case About is
               when X => M.V (I) := (P.X, C * P.Y - S * P.Z, S * P.Y + C * P.Z);
               when Y => M.V (I) := (C * P.X + S * P.Z, P.Y, -S * P.X + C * P.Z);
               when Z => M.V (I) := (C * P.X - S * P.Y, S * P.X + C * P.Y, P.Z);
            end case;
         end;
      end loop;
   end Rotate;

end Forge.Transform;

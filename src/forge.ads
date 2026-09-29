--  forge: solid modeling with a proven topology kernel, driven by text.
--
--  Root package: scalars, vectors, names. Pure. No I/O anywhere below
--  Forge.Session; the kernel computes, the session owns memory, the
--  front ends (cli/, ui/) talk to the session in lines of text.

package Forge with SPARK_Mode, Pure is

   type Scalar is new Long_Float;
   --  CAD needs range and 15 digits; fixed point is the wrong tool here.
   --  What is proved is topology (integers), not floating-point geometry.

   type Vec3 is record
      X, Y, Z : Scalar := 0.0;
   end record;

   Origin : constant Vec3 := (0.0, 0.0, 0.0);

   function "+" (A, B : Vec3) return Vec3 is (A.X + B.X, A.Y + B.Y, A.Z + B.Z);
   function "-" (A, B : Vec3) return Vec3 is (A.X - B.X, A.Y - B.Y, A.Z - B.Z);
   function "*" (A : Vec3; S : Scalar) return Vec3 is (A.X * S, A.Y * S, A.Z * S);
   function Dot (A, B : Vec3) return Scalar is (A.X * B.X + A.Y * B.Y + A.Z * B.Z);
   function Cross (A, B : Vec3) return Vec3 is
     (A.Y * B.Z - A.Z * B.Y, A.Z * B.X - A.X * B.Z, A.X * B.Y - A.Y * B.X);

   type Axis is (X, Y, Z);

   ---------------------------------------------------------------------
   --  Names: identifiers for solids in a session. Bounded, ASCII.
   ---------------------------------------------------------------------

   Max_Name : constant := 32;

   type Name is record
      Length : Natural range 0 .. Max_Name := 0;
      Text   : String (1 .. Max_Name) := [others => ' '];
   end record;

   function To_Name (S : String) return Name
     with Pre => S'Length <= Max_Name;

   function Image (N : Name) return String is (N.Text (1 .. N.Length));

   function "=" (A, B : Name) return Boolean is
     (A.Length = B.Length and then A.Text (1 .. A.Length) = B.Text (1 .. B.Length));

end Forge;

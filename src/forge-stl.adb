with Ada.Unchecked_Conversion;
with Interfaces;

package body Forge.STL with SPARK_Mode => Off is
   --  Off for the float-to-bits conversion only.

   use type Interfaces.Unsigned_32;
   function To_Bits is new Ada.Unchecked_Conversion (Float, Interfaces.Unsigned_32);

   procedure Write (M : Tri_Mesh; Buffer : out Byte_Array; Last : out Natural) is
      P : Positive := Buffer'First;

      procedure U32 (V : Interfaces.Unsigned_32);
      procedure F32 (V : Scalar);
      procedure Vec (V : Vec3);

      procedure U32 (V : Interfaces.Unsigned_32) is
         X : Interfaces.Unsigned_32 := V;
      begin
         for I in 1 .. 4 loop
            Buffer (P) := Byte (X and 16#FF#);
            X := X / 256;
            P := P + 1;
         end loop;
      end U32;

      procedure F32 (V : Scalar) is
      begin
         U32 (To_Bits (Float (V)));
      end F32;

      procedure Vec (V : Vec3) is
      begin
         F32 (V.X); F32 (V.Y); F32 (V.Z);
      end Vec;

      Header : constant String := "forge binary STL";
   begin
      Buffer := [others => 0];
      for I in Header'Range loop
         Buffer (P + I - 1) := Byte (Character'Pos (Header (I)));
      end loop;
      P := Buffer'First + 80;
      U32 (Interfaces.Unsigned_32 (M.NT));
      for I in 1 .. M.NT loop
         Vec (Normal (M, I));
         Vec (M.V (M.T (I).A));
         Vec (M.V (M.T (I).B));
         Vec (M.V (M.T (I).C));
         Buffer (P) := 0; Buffer (P + 1) := 0;
         P := P + 2;
      end loop;
      Last := P - 1;
   end Write;

end Forge.STL;

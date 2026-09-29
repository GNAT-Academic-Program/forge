--  STL writer. Binary STL: 80-byte header, uint32 triangle count, then
--  per triangle 12 IEEE single floats (normal, a, b, c) and a uint16
--  attribute, little-endian. 84 + 50 * NT bytes. The kernel produces
--  bytes; whoever owns a file writes them.
--
--  Proof target: Size is exact and Write never indexes past it.

with Forge.Mesh; use Forge.Mesh;

package Forge.STL with SPARK_Mode is

   type Byte is mod 2 ** 8 with Size => 8;
   type Byte_Array is array (Positive range <>) of Byte with Pack;

   function Size (M : Tri_Mesh) return Positive is (84 + 50 * Positive (M.NT + 1) - 50)
     with Pre => Well_Formed (M);

   procedure Write (M : Tri_Mesh; Buffer : out Byte_Array; Last : out Natural)
     with Pre  => Well_Formed (M) and then Buffer'Length >= Size (M),
          Post => Last = Buffer'First + Size (M) - 1;

end Forge.STL;

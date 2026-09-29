package body Forge with SPARK_Mode is

   function To_Name (S : String) return Name is
      N : Name;
   begin
      N.Length := S'Length;
      N.Text (1 .. S'Length) := S;
      return N;
   end To_Name;

end Forge;

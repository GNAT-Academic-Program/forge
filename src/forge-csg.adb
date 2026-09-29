package body Forge.CSG with SPARK_Mode is

   --  PLACEHOLDER. See the spec.

   procedure Apply
     (Op     : Operation;
      A, B   : Tri_Mesh;
      Result : in out Tri_Mesh;
      Ok     : out Boolean;
      Reason : out Reason_String;
      Last   : out Natural)
   is
      pragma Unreferenced (Op, A, B);
      Msg : constant String := "boolean operations are not implemented yet";
   begin
      Clear (Result);
      Ok := False;
      Reason := [others => ' '];
      Reason (1 .. Msg'Length) := Msg;
      Last := Msg'Length;
   end Apply;

end Forge.CSG;

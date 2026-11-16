with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Ada.Assertions;
with Ada.Exceptions;
with Ada.Unchecked_Deallocation;
with Forge.Primitives;
with Forge.STL;
with Forge.Transform;

package body Forge.Session is

   procedure Free is new Ada.Unchecked_Deallocation (Tri_Mesh, Mesh_Access);
   pragma Unreferenced (Free);
   --  Meshes are allocated once per slot and reused; nothing frees them
   --  before the program ends. Kept for a future Session finalizer.

   procedure Set (R : out Response; Ok : Boolean; Msg : String) renames Responses.Set;
   procedure Append (R : in out Response; Msg : String) renames Responses.Append;
   function Find (S : Session; N : Name) return Natural;
   function Slot_For (S : in out Session; N : Name) return Natural;
   procedure Release (S : in out Session; I : Positive);
   procedure Clear_Solids (S : in out Session);
   procedure Apply (S : in out Session; C : Command; R : out Response);
   procedure Replay (S : in out Session);
   procedure Do_Info (S : Session; N : Name; R : out Response);
   procedure Do_List (S : Session; R : out Response);
   procedure Do_Export (S : Session; N : Name; Path : String; R : out Response);
   procedure Do_Save (S : Session; Path : String; R : out Response);
   procedure Do_Load (S : in out Session; Path : String; R : out Response);

   ---------------------------------------------------------------------
   --  Solid table
   ---------------------------------------------------------------------

   function Find (S : Session; N : Name) return Natural is
   begin
      for I in S.Meshes'Range loop
         if S.Tree (I).N.Length /= 0 and then S.Tree (I).N = N then
            return I;
         end if;
      end loop;
      return 0;
   end Find;

   --  Preserve the seed's named primitive replacement. Replacing a group
   --  would orphan its operands, so Boolean result names must be new.
   function Slot_For (S : in out Session; N : Name) return Natural is
      I : constant Natural := Find (S, N);
   begin
      if N = World or else N.Length = 0 then
         raise Invalid_Command with "world cannot be replaced";
      end if;
      if I /= 0 then
         if S.Tree (I).Kind in Union_Node .. Intersection_Node then
            raise Invalid_Command with "cannot replace a Boolean group";
         end if;
         S.Tree (I) := (N => N, Parent => S.Tree (I).Parent,
                       Order => S.Tree (I).Order, others => <>);
         Clear (S.Meshes (I).all);
         return I;
      end if;
      for J in S.Meshes'Range loop
         if S.Tree (J).N.Length = 0 then
            if S.Meshes (J) = null then
               S.Meshes (J) := new Tri_Mesh (Default_Cap_V, Default_Cap_T);
            end if;
            Clear (S.Meshes (J).all);
            S.Tree (J) := (N => N, Order => S.Count + 1, others => <>);
            return J;
         end if;
      end loop;
      raise Invalid_Command with "solid tree full";
   end Slot_For;

   procedure Release (S : in out Session; I : Positive) is
   begin
      S.Tree (I) := (others => <>);
      Clear (S.Meshes (I).all);
   end Release;

   procedure Clear_Solids (S : in out Session) is
   begin
      for I in S.Meshes'Range loop
         if S.Tree (I).N.Length /= 0 then
            Release (S, I);
         end if;
      end loop;
   end Clear_Solids;

   ---------------------------------------------------------------------
   --  Apply one modeling command to the solids. No history here.
   ---------------------------------------------------------------------

   procedure Apply (S : in out Session; C : Command; R : out Response) is
      Ok : Boolean;
      I : Natural;

      function Need (N : Name) return Positive;
      function Need (N : Name) return Positive is
         Index : constant Natural := Find (S, N);
      begin
         if Index = 0 then
            raise Invalid_Command with "no solid named " & Image (N);
         end if;
         return Index;
      end Need;

      procedure Remove (Index : Positive);
      procedure Remove (Index : Positive) is
      begin
         for J in S.Meshes'Range loop
            if S.Tree (J).N.Length /= 0 and then S.Tree (J).Parent = S.Tree (Index).N then
               Remove (J);
            end if;
         end loop;
         Release (S, Index);
      end Remove;

      procedure Change (M : in out Tri_Mesh; Offset, Pivot : Vec3; Factor : Scalar);
      procedure Change (M : in out Tri_Mesh; Offset, Pivot : Vec3; Factor : Scalar) is
      begin
         case C.K is
            when Translate | Move => Transform.Translate (M, Offset);
            when Scale | Resize =>
               Transform.Translate (M, -Pivot);
               Transform.Scale (M, Factor);
               Transform.Translate (M, Pivot);
            when Rotate => Transform.Rotate (M, C.About, C.Degrees);
            when others => null;
         end case;
      end Change;

   begin
      Set (R, True, "ok");
      case C.K is
         when Box | Cube | Sphere | Cylinder =>
            declare
               N : constant Name := (case C.K is when Box => C.Box_Name,
                 when Cylinder => C.Cyl_Name, when others => C.Shape_Name);
               Size : constant Vec3 := (case C.K is when Box => (C.W, C.H, C.D),
                 when Cylinder => (C.R, C.CH, 0.0), when others => (C.Size, C.Size, C.Size));
            begin
               if Size.X <= 0.0 or else Size.Y <= 0.0
                 or else (C.K = Box and then Size.Z <= 0.0)
                 or else (C.K in Cube | Sphere and then C.Initial_Scale <= 0.0)
               then
                  raise Invalid_Command with "dimensions and scale must be positive";
               end if;
               I := Slot_For (S, N);
               S.Tree (I).Size := Size;
               case C.K is
                  when Box | Cube =>
                     S.Tree (I).Kind := Box_Node;
                     Primitives.Box (S.Meshes (I).all, Size.X, Size.Y, Size.Z, Ok);
                  when Sphere =>
                     S.Tree (I).Kind := Sphere_Node;
                     S.Tree (I).Size := (C.Size, 0.0, 0.0);
                     Primitives.Sphere (S.Meshes (I).all, C.Size, Ok);
                  when Cylinder =>
                     S.Tree (I).Kind := Cylinder_Node;
                     Primitives.Cylinder (S.Meshes (I).all, C.R, C.CH, C.Segments, Ok);
                  when others => null;
               end case;
               if not Ok or else not Is_Solid (S.Meshes (I).all) then
                  raise Invalid_Command with "primitive did not produce a solid mesh";
               end if;
               if C.K in Cube | Sphere then
                  Transform.Scale (S.Meshes (I).all, C.Initial_Scale);
                  Transform.Translate (S.Meshes (I).all, C.Position);
                  S.Tree (I).Position := C.Position;
                  S.Tree (I).Scale := C.Initial_Scale;
               end if;
            end;

         when Translate | Move | Rotate | Scale | Resize =>
            I := Need ((case C.K is when Translate | Move => C.Tr_Name,
                        when Rotate => C.Rot_Name, when others => C.Sc_Name));
            declare
               Offset : Vec3 := Origin;
               Pivot : Vec3 := Origin;
               Factor : Scalar := 1.0;
               Point : Tri_Mesh (1, 0);
               V : Vertex_Index;
               Ancestor : Natural;
            begin
               if C.K in Translate | Move then
                  Offset := (if C.K = Move then C.By - S.Tree (I).Position else C.By);
               elsif C.K in Scale | Resize then
                  if C.Factor <= 0.0 then
                     raise Invalid_Command with "scale must be positive";
                  end if;
                  Factor := C.Factor;
                  if C.K = Resize then
                     Factor := C.Factor / S.Tree (I).Scale;
                     Pivot := S.Tree (I).Position;
                  end if;
               end if;
               for J in S.Meshes'Range loop
                  if S.Tree (J).N.Length /= 0 then
                     Ancestor := J;
                     while Ancestor /= I and then S.Tree (Ancestor).Parent /= World loop
                        Ancestor := Need (S.Tree (Ancestor).Parent);
                     end loop;
                     if Ancestor = I then
                        Change (S.Meshes (J).all, Offset, Pivot, Factor);
                        Clear (Point);
                        Add_Vertex (Point, S.Tree (J).Position, V, Ok);
                        Change (Point, Offset, Pivot, Factor);
                        S.Tree (J).Position := Point.V (V);
                        S.Tree (J).Scale := S.Tree (J).Scale * Factor;
                        if S.Tree (J).Scale <= 0.0 then
                           raise Invalid_Command with "scale underflow";
                        end if;
                     end if;
                  end if;
               end loop;
            end;

         when Union | Difference | Intersect =>
            declare
               Shapes : constant Name_Array := Name_Array'[C.A, C.B] & C.Extra (1 .. C.Extra_Count);
               First : constant Node := S.Tree (Need (C.A));
               Index : Positive;
            begin
               for J in Shapes'Range loop
                  Index := Need (Shapes (J));
                  if S.Tree (Index).Parent /= First.Parent then
                     raise Invalid_Command with "Boolean operands must be siblings";
                  end if;
                  for K in Shapes'First .. J - 1 loop
                     if Shapes (J) = Shapes (K) then
                        raise Invalid_Command with "duplicate Boolean operand";
                     end if;
                  end loop;
               end loop;
               if Find (S, C.Result) /= 0 then
                  raise Invalid_Command with "Boolean result must have a new name";
               end if;
               I := Slot_For (S, C.Result);
               S.Tree (I).Kind := (case C.K is when Union => Union_Node,
                 when Difference => Difference_Node, when others => Intersection_Node);
               S.Tree (I).Parent := First.Parent;
               S.Tree (I).Order := First.Order;
               for J in Shapes'Range loop
                  Index := Need (Shapes (J));
                  S.Tree (Index).Parent := C.Result;
                  S.Tree (Index).Order := J;
               end loop;
               Set (R, True, "ok Boolean group; geometry pending");
            end;

         when Copy =>
            declare
               Source : constant Positive := Need (C.From);
               Parent : Name;
               Order : Natural;
            begin
               if C.Cp_Name = C.From then
                  return;
               end if;
               if S.Tree (Source).Kind in Union_Node .. Intersection_Node then
                  raise Invalid_Command with "copy of Boolean groups is not implemented";
               end if;
               I := Slot_For (S, C.Cp_Name);
               Parent := S.Tree (I).Parent;
               Order := S.Tree (I).Order;
               Mesh.Copy (S.Meshes (Source).all, S.Meshes (I).all, Ok);
               if not Ok then
                  raise Invalid_Command with "mesh capacity";
               end if;
               S.Tree (I) := S.Tree (Source);
               S.Tree (I).N := C.Cp_Name;
               S.Tree (I).Parent := Parent;
               S.Tree (I).Order := Order;
            end;

         when Delete =>
            I := Need (C.Target);
            declare
               Parent : Name := S.Tree (I).Parent;
            begin
               Remove (I);
               while Parent /= World loop
                  exit when (for some N of S.Tree => N.N.Length /= 0 and then N.Parent = Parent);
                  I := Need (Parent);
                  Parent := S.Tree (I).Parent;
                  Release (S, I);
               end loop;
            end;

         when others => raise Invalid_Command with "not a modeling command";
      end case;
   exception
      when E : Invalid_Command => Set (R, False, "err " & Ada.Exceptions.Exception_Message (E));
      when Constraint_Error =>
         Set (R, False, "err outside fixed-point modeling range");
      when Ada.Assertions.Assertion_Error =>
         Set (R, False, "err invalid geometry or numerical range");
   end Apply;

   ---------------------------------------------------------------------
   --  Replay the history from empty
   ---------------------------------------------------------------------

   procedure Replay (S : in out Session) is
      R : Response;
      Count : constant Natural := S.Count;
   begin
      Clear_Solids (S);
      for I in 1 .. Count loop
         S.Count := I - 1;
         Apply (S, S.History (I), R);
         if not R.Ok then
            raise Program_Error with "recorded command failed during replay: " & Image (R);
         end if;
      end loop;
      S.Count := Count;
   end Replay;

   ---------------------------------------------------------------------
   --  Queries and side effects
   ---------------------------------------------------------------------

   procedure Do_Info (S : Session; N : Name; R : out Response) is
      I : constant Natural := Find (S, N);
   begin
      if I = 0 then
         Set (R, False, "err no solid named " & Image (N));
         return;
      end if;
      if S.Tree (I).Kind in Union_Node .. Intersection_Node then
         Set (R, True, "ok " & Image (N) & " Boolean group; geometry pending");
         return;
      end if;
      declare
         M : Tri_Mesh renames S.Meshes (I).all;
         Lo, Hi : Vec3;
      begin
         Bounds (M, Lo, Hi);
         Set (R, True, "ok " & Image (N));
         Append (R, " vertices" & M.NV'Image & " triangles" & M.NT'Image);
         Append (R, " solid " & (if Is_Solid (M) then "yes" else "NO"));
         Append (R, " volume" & Volume (M)'Image);
         Append (R, " min" & Lo.X'Image & Lo.Y'Image & Lo.Z'Image);
         Append (R, " max" & Hi.X'Image & Hi.Y'Image & Hi.Z'Image);
      end;
   end Do_Info;

   procedure Do_List (S : Session; R : out Response) is
   begin
      Set (R, True, "ok");
      for I in S.Meshes'Range loop
         if S.Tree (I).N.Length /= 0 then
            Append (R, " " & Image (S.Tree (I).N));
         end if;
      end loop;
   end Do_List;

   procedure Do_Export (S : Session; N : Name; Path : String; R : out Response) is
      use Ada.Streams.Stream_IO;
      I : constant Natural := Find (S, N);
      F : File_Type;
   begin
      if I = 0 then
         Set (R, False, "err no solid named " & Image (N));
         return;
      end if;
      if S.Tree (I).Kind in Union_Node .. Intersection_Node then
         Set (R, False, "err Boolean geometry is not implemented");
         return;
      end if;
      declare
         M    : Tri_Mesh renames S.Meshes (I).all;
         Buf  : STL.Byte_Array (1 .. STL.Size (M));
         Last : Natural;
         Elems : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Buf'Length))
           with Import, Address => Buf'Address;
      begin
         STL.Write (M, Buf, Last);
         Create (F, Out_File, Path);
         Write (F, Elems (1 .. Ada.Streams.Stream_Element_Offset (Last)));
         Close (F);
         Set (R, True, "ok wrote" & Last'Image & " bytes to " & Path);
      end;
   exception
      when others =>
         Set (R, False, "err cannot write " & Path);
   end Do_Export;

   procedure Do_Save (S : Session; Path : String; R : out Response) is
      use Ada.Text_IO;
      F : File_Type;
   begin
      Create (F, Out_File, Path);
      Put_Line (F, "# forge document, one command per line");
      for I in 1 .. S.Count loop
         Put_Line (F, Image (S.History (I)));
      end loop;
      Close (F);
      Set (R, True, "ok saved" & S.Count'Image & " commands to " & Path);
   exception
      when others =>
         Set (R, False, "err cannot write " & Path);
   end Do_Save;

   procedure Do_Load (S : in out Session; Path : String; R : out Response) is
      use Ada.Text_IO;
      F : File_Type;
      Line_No : Natural := 0;
   begin
      Open (F, In_File, Path);
      Clear_Solids (S);
      S.Count := 0;
      S.History.Clear;
      while not End_Of_File (F) loop
         declare
            Line : constant String := Get_Line (F);
            RL   : Response;
         begin
            Line_No := Line_No + 1;
            Execute (S, Line, RL);
            if not RL.Ok then
               Close (F);
               Set (R, False, "err line" & Line_No'Image & ": " & Image (RL));
               return;
            end if;
         end;
      end loop;
      Close (F);
      Set (R, True, "ok loaded" & S.Count'Image & " commands from " & Path);
   exception
      when others =>
         Set (R, False, "err cannot read " & Path);
   end Do_Load;

   ---------------------------------------------------------------------
   --  Execute
   ---------------------------------------------------------------------

   procedure Execute (S : in out Session; Line : String; R : out Response) is
      C   : Command;
      Ok  : Boolean;
      Err : Path_String;
   begin
      if Line'Length > Max_Line then
         Set (R, False, "err line too long");
         return;
      end if;
      Parse (Line, C, Ok, Err);
      if not Ok then
         Set (R, False, "err " & Image (Err));
         return;
      end if;

      Execute (S, C, R);
   end Execute;

   procedure Execute (S : in out Session; C : Command; R : out Response) is
      Checked : Command;
      Ok : Boolean;
      Error : Path_String;
   begin
      --  Reuse the grammar's argument validation for programmatic callers.
      Parse (Image (C), Checked, Ok, Error);
      if not Ok then
         Set (R, False, "err " & Image (Error));
         return;
      end if;
      case C.K is
         when Modeling =>
            if S.Count >= Max_History then
               Set (R, False, "err history full");
               return;
            end if;
            if Natural (S.History.Capacity) <= S.Count then
               S.History.Reserve_Capacity
                 (Ada.Containers.Count_Type (Natural'Min (Max_History, 2 * S.Count + 1)));
            end if;
            Apply (S, C, R);
            if R.Ok then
               S.Count := S.Count + 1;
               S.History.Set_Length (Ada.Containers.Count_Type (S.Count - 1));
               S.History.Append (C);
            else
               Replay (S); -- restore any meshes touched by a failed operation
            end if;
         when Undo =>
            if S.Count = 0 then
               Set (R, False, "err nothing to undo");
            else
               S.Count := S.Count - 1;
               Replay (S);
               Set (R, True, "ok undid; history" & S.Count'Image);
            end if;
         when Redo =>
            if S.Count = S.History.Last_Index then
               Set (R, False, "err nothing to redo");
            else
               Apply (S, S.History (S.Count + 1), R);
               if R.Ok then
                  S.Count := S.Count + 1;
               else
                  Replay (S);
               end if;
            end if;
         when Tree_View =>
            Set (R, True, "ok tree (name parent order kind)");
            for N of View_Tree (S) loop
               Append (R, ASCII.LF & Image (N.N) & " " & Image (N.Parent)
                       & N.Order'Image & " " & N.Kind'Image);
            end loop;
         when History_View =>
            Set (R, True, "ok history; applied" & S.Count'Image);
            for I in 1 .. S.History.Last_Index loop
               Append (R, ASCII.LF & (if I <= S.Count then "+ " else "- ")
                       & Image (S.History (I)));
            end loop;
         when List    => Do_List (S, R);
         when Info    => Do_Info (S, C.Target, R);
         when Commands.Export =>
            if C.Ex_Name.Length = 0 then
               Export (S, Image (C.Ex_Path));
               Set (R, True, "ok workspace export pending; no file written");
            else
               Do_Export (S, C.Ex_Name, Image (C.Ex_Path), R);
            end if;
         when Save    => Do_Save (S, Image (C.File), R);
         when Load    => Do_Load (S, Image (C.File), R);
         when Comment | Empty => Set (R, True, "ok");
      end case;
   end Execute;

   ---------------------------------------------------------------------
   --  Read-back
   ---------------------------------------------------------------------

   function Solid_Count (S : Session) return Natural is
      N : Natural := 0;
   begin
      for I in S.Meshes'Range loop
         if S.Tree (I).N.Length /= 0 then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Solid_Count;

   function Solid_Name (S : Session; I : Positive) return Name is
      N : Natural := 0;
   begin
      for J in S.Meshes'Range loop
         if S.Tree (J).N.Length /= 0 then
            N := N + 1;
            if N = I then
               return S.Tree (J).N;
            end if;
         end if;
      end loop;
      return To_Name ("");
   end Solid_Name;

   function Has_Solid (S : Session; N : Name) return Boolean is (Find (S, N) /= 0);

   function Mesh_Of (S : Session; N : Name) return Mesh_View is
     (if S.Tree (Find (S, N)).Kind in Union_Node .. Intersection_Node then null
      else Mesh_View (S.Meshes (Find (S, N))));

   function History_Length (S : Session) return Natural is (S.Count);

   function History_Line (S : Session; I : Positive) return String is
     (Image (S.History (I)));

   procedure Run (S : in out Session; C : Command);
   function Fresh_Name (S : in out Session) return Name;
   function Combine (S : in out Session; K : Boolean_Kind; Shapes : Name_Array) return Name;

   procedure Run (S : in out Session; C : Command) is
      R : Response;
   begin
      Execute (S, C, R);
      if not R.Ok then
         raise Invalid_Command with Image (R);
      end if;
   end Run;

   function Fresh_Name (S : in out Session) return Name is
   begin
      loop
         declare
            Text : constant String := S.Serial'Image;
            N : constant Name := To_Name ("solid_" & Text (2 .. Text'Last));
         begin
            S.Serial := S.Serial + 1;
            if not Has_Solid (S, N) then
               return N;
            end if;
         end;
      end loop;
   end Fresh_Name;

   function Make_Cube
     (S : in out Session; Length : Scalar;
      X, Y, Z : Scalar := 0.0; Scale : Scalar := 1.0) return Name
   is
      N : constant Name := Fresh_Name (S);
   begin
      Run (S, (Cube, N, Length, (X, Y, Z), Scale));
      return N;
   end Make_Cube;

   function Make_Sphere
     (S : in out Session; Radius : Scalar;
      X, Y, Z : Scalar := 0.0; Scale : Scalar := 1.0) return Name
   is
      N : constant Name := Fresh_Name (S);
   begin
      Run (S, (Sphere, N, Radius, (X, Y, Z), Scale));
      return N;
   end Make_Sphere;

   procedure Delete_Shape (S : in out Session; Shape : Name) is
   begin
      Run (S, (Delete, Shape));
   end Delete_Shape;

   procedure Move_Shape (S : in out Session; Shape : Name; X, Y, Z : Scalar) is
   begin
      Run (S, (Move, Shape, (X, Y, Z)));
   end Move_Shape;

   procedure Scale_Shape (S : in out Session; Shape : Name; Scale : Scalar) is
   begin
      Run (S, (Resize, Shape, Scale));
   end Scale_Shape;

   function Combine (S : in out Session; K : Boolean_Kind; Shapes : Name_Array) return Name is
      C : Command (K);
   begin
      if Shapes'Length not in 2 .. Max_Operands then
         raise Invalid_Command with "a Boolean needs 2 .. Max_Operands operands";
      end if;
      C.Result := Fresh_Name (S);
      C.A := Shapes (Shapes'First);
      C.B := Shapes (Shapes'First + 1);
      C.Extra_Count := Shapes'Length - 2;
      C.Extra (1 .. C.Extra_Count) := Shapes (Shapes'First + 2 .. Shapes'Last);
      Run (S, C);
      return C.Result;
   end Combine;

   function Union (S : in out Session; Shapes : Name_Array) return Name is
   begin
      return Combine (S, Commands.Union, Shapes);
   end Union;

   function Subtraction (S : in out Session; Shapes : Name_Array) return Name is
   begin
      return Combine (S, Difference, Shapes);
   end Subtraction;

   function Intersection (S : in out Session; Shapes : Name_Array) return Name is
   begin
      return Combine (S, Intersect, Shapes);
   end Intersection;

   procedure Undo (S : in out Session) is
   begin
      Run (S, (K => Commands.Undo));
   end Undo;

   procedure Redo (S : in out Session) is
   begin
      Run (S, (K => Commands.Redo));
   end Redo;

   procedure Export (S : Session; Filepath : String) is
      pragma Unreferenced (S, Filepath);
   begin
      null;
   end Export;

   function View_Tree (S : Session) return Node_Array is
      Result : Solid_Tree;
      Last : Natural := 0;
   begin
      Result (0) := S.Tree (0);
      for I in S.Meshes'Range loop
         if S.Tree (I).N.Length /= 0 then
            Last := Last + 1;
            Result (Last) := S.Tree (I);
         end if;
      end loop;
      return Result (0 .. Last);
   end View_Tree;

   function View_History
     (S : Session; Include_Redo : Boolean := False) return Command_Array
   is
   begin
      return Result : Command_Array
        (1 .. (if Include_Redo then S.History.Last_Index else S.Count))
      do
         for I in Result'Range loop
            Result (I) := S.History (I);
         end loop;
      end return;
   end View_History;

end Forge.Session;

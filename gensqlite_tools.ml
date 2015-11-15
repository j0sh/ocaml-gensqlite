(** Gensqlite_tools: utility functions for gensqlite *)

(** [close_db] is a helper to close the database handle [db]. Successful closes
 * return unit. If closing fails for whatever reason, the attempt is retried up
 * to 100 times. After the 101th time, a `Sqlite3.Error` is raised.
 *)
let close_db dbh =
  let rec f attempts =
    let res = Sqlite3.db_close dbh in
    if not res && attempts < 100 then f (attempts + 1)
    else if not res then
      raise (Sqlite3.Error "Failed attempt to close DB; missing finalization?")
    else () in
  f 0

(** [enforce_fks] is a helper to enable foreign key constraint enforcement on
 * the opened database handle [dbh]. Returns unit on success and raises
 * `Sqlite3.Error` if FK enforcement could not be set.
 *)
let enforce_fks dbh =
  let open Sqlite3 in
  let res = exec dbh "PRAGMA foreign_keys = ON" in
  if Rc.OK <> res then begin
    let str = Printf.sprintf "%s : Error setting FK pragma" (Rc.to_string res) in
    raise (Sqlite3.Error str)
  end


(* The rest of these functions should not be used; they are really meant for
 * gensqlite internal use. *)

let bind_idx stmt idx data = try
  let res = Sqlite3.bind stmt idx data in
  if Sqlite3.Rc.OK <> res then begin
    let str = Printf.sprintf "%s Unable to bind index %d for %s"
      (Sqlite3.Rc.to_string res)
      idx
      (Sqlite3.Data.to_string_debug data) in
    raise (Sqlite3.Error str)
  end
with Not_found ->
  let str = Printf.sprintf "Error! Index %d not found for statement" idx in
  raise (Sqlite3.Error str)

let bind_var stmt name data = try
  let idx = Sqlite3.bind_parameter_index stmt (":" ^ name) in
  bind_idx stmt idx data
with Not_found ->
  let str = Printf.sprintf "Error! Named index %s not found for statement" name in
  raise (Sqlite3.Error str)

let sqtext v = Sqlite3.Data.TEXT v
let sqint v = Sqlite3.Data.INT (Int64.of_int v)
let sqint32 v = Sqlite3.Data.INT (Int64.of_int32 v)
let sqint64 v = Sqlite3.Data.INT v

let query ?(cb = fun _ -> ()) s =
  let open Sqlite3 in
  let res = ref (step s) in
  while !res = Rc.ROW do
    cb s;
    res := step s;
  done;
  ignore(clear_bindings s);
  ignore(reset s);
  if Rc.OK <> !res && Rc.DONE <> !res then begin
    let str = Printf.sprintf "Query error %s" (Rc.to_string !res) in
    raise (Sqlite3.Error str)
  end

let data2int s i = try
  let open Sqlite3.Data in
  match Sqlite3.column s i with
  | INT d -> Int64.to_int d
  | FLOAT d -> int_of_float d
  | TEXT d | BLOB d -> int_of_string d
  | _ -> failwith ""
with Failure _ -> -1

let data2int32 s i = try
  let open Sqlite3.Data in
  match Sqlite3.column s i with
  | INT d -> Int64.to_int32 d
  | FLOAT d -> Int32.of_float d
  | TEXT d | BLOB d -> Int32.of_string d
  | _ -> failwith ""
with Failure _ -> -1l

let data2int64 s i = try
  let open Sqlite3.Data in
  match Sqlite3.column s i with
  | INT d -> d
  | FLOAT d -> Int64.of_float d
  | TEXT d | BLOB d -> Int64.of_string d
  | _ -> failwith ""
with Failure _ -> -1L

let data2str s i = try
  Sqlite3.(Data.to_string(column s i))
(* Failure can't really be raised here but it's here anyway... *)
with Failure _ -> ""

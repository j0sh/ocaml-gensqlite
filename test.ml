open OUnit

open T

let sample_query = [
  QueryString "INSERT INTO users(name, role) VALUES(";
  StringParam "name";
  QueryString ",";
  IntParam "role";
  QueryString ")";
]

let ae = assert_equal ~printer:(fun x -> x)
let pq q = parse_query q |> to_sql

let test _ =

  let s = to_sql sample_query in
  ae "INSERT INTO users(name, role) VALUES(:name,:role)" s;

  let s = pq "insert into values(>@device, >@agency)" in
  ae "insert into values(:device, :agency)" s;

  let s = pq ">@device is here" in
  ae ":device is here" s;

  let s = pq "device is >@here" in
  ae "device is :here" s;

  let s = pq "@device :is :@here" in
  ae "@device :is :@here" s;

  let s = pq ">@:device ::is >:@here" in
  ae "::device ::is :@here" s;

  let s = pq "excellent" in
  ae "excellent" s


let outputs _ =

  let s = pq "<:output device <@okay zug" in
  ae "output device okay zug" s;

  let s = pq "output <@really <@okay" in
  ae "output really okay" s


let test_ints _ =
  (* parse and remove spaces *)
  let g = parse_query ">?h <?h >$b <$b " in
  let g = List.filter (function QueryString _ -> false | _ -> true) g in
  let expected = [Int32Param "h"; Int32Output "h"; Int64Param "b"; Int64Output "b"] in
  let printer x = List.map T.to_raw x |> String.concat "" in
  assert_equal ~printer expected g

let test_gensqlite _ =
  let open Sqlite_tools in
  let open Sqlite3 in
  let dbx = db_open (Filename.temp_file "gensqlite" "gensqlite") in

  (* test invalid query. hard-coding the error message may be brittle? *)
  let run () = [%gensqlite dbx "invalid query"] in
  let msg = "Sqlite3.prepare: near \"invalid\": syntax error" in
  assert_raises (Error msg) run;

  (* test some actual queries; create the table *)
  (* if it compiles and runs without raising an exception, then probably OK *)
  let (drop_s, drop_table) = [%gensqlite dbx "drop table if exists users"] in
  let (create_s, create_table) = [%gensqlite dbx "create table if not exists
  users(id integer primary key asc, name text not null unique, created integer
  not null default current_timestamp, check(trim(name)<>''));"] in

  drop_table () |> create_table;

  let (insert_s, insert) = [%gensqlite dbx "insert into users(name) values(>@name)"] in
  let (select_s, select) = [%gensqlite dbx "select <:id, <@name, strftime('%s', <?created) from users where name = >@name"] in
  let (select2_s, select2) = [%gensqlite dbx "select <@id, strftime('%s', <$created) from users where name = >:name"] in

  (* get current timestamp to verify handling of boxed int32s and values that
   * would otherwise overflow a ocaml int (ticks since epoch)
   * It is possible that Unix.time () and sqlite could contain different values
   * but this is is Close Enough for testing. If it fails, re-run the test? *)
  let now = Unix.time () |> Int32.of_float in
  insert ~name:"asdf" () |> insert ~name:"1002" |> insert ~name:"qwerty";

  (* verify insertions *)
  assert_equal 3L (last_insert_rowid dbx);

  (* verify selections *)
  let res = select ~name:"asdf" () in
  let msg = "Selection compare failed; timestamp drift? Retry?" in
  assert_equal ~msg ((1, "asdf", now)::[]) res;

  (* empty selection *)
  let res = select ~name:"nothere" () in
  assert_equal [] res;

  (* verify some type conversion (for id) and int64 handling (for timestamp) *)
  let res = select2 ~name:1002 () in
  assert_equal ~msg (("2", Int64.of_int32 now)::[]) res;

  (* test single output and aggregates *)
  let (select3_s, select3) = [%gensqlite dbx "select count(*) as <:count from users"] in
  let res = select3 () in
  let printer x = List.map string_of_int x |> String.concat "," in
  assert_equal ~msg:"select3" ~printer (3::[]) res;

  (* an interesting case from the README. Returns the first column, 'id' *)
  let (select4_s, select4) = [%gensqlite dbx "select <:* from users"] in
  let res = select4 () in
  assert_equal ~msg:"select4" ~printer (3::2::1::[]) res;

  (* if this compiles and runs it's probably OK *)
  (* note that all prepared statements must be finalized prior to closing *)
  let stmts = drop_s :: create_s :: insert_s :: select_s :: select2_s :: [] in
  let stmts = select3_s :: select4_s :: stmts in
  List.iter (fun s -> ignore(Sqlite3.finalize s)) stmts;
  close_db dbx

let tests =
  "gensqlite_tests">::: [
    "test_input">::test;
    "test_output">::outputs;
    "test_ints">::test_ints;
    "test_gensqlite">::test_gensqlite
  ]

let _ = run_test_tt_main tests

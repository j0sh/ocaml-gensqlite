open OUnit

open Q

let ae = assert_equal ~printer:(fun x -> x)
let pq q = process q |> function (sql, _, _) -> sql

let test _ =

  let s = pq "insert into values(%s{device}, %s{agency})" in
  ae "insert into values(:device, :agency)" s;

  let s = pq "%d{device} is here" in
  ae ":device is here" s;

  let s = pq "device is %s{here}" in
  ae "device is :here" s;

  (* a bit irrelevant now but we should do something similar *)
  let s = pq "@device :is :@here" in
  ae "@device :is :@here" s;

  (* unnamed outputs should not match (return as-is). unlabelled inputs as ? *)
  let s = pq "@s@s %d@s{abc}%d@s%d@s%d{def}%d{ghi}@s" in
  ae "@s@s ?abc?@s?@s:def:ghi@s" s;

  (* label is not alphanumeric so interpret as unnamed *)
  let s = pq "%s{:device} ::is >:@here" in
  ae "?{:device} ::is >:@here" s;

  let s = pq "excellent" in
  ae "excellent" s


let outputs _ =

  let s = pq "@d{output} device @s{okay} zug" in
  ae "output device okay zug" s;

  let s = pq "output @s{really} @s{okay}" in
  ae "output really okay" s


let test_ints _ =
  (* parse and remove spaces *)
  let (_, inputs, outputs) = process "%n{h} @n{h} %L{b} @L{b}" in
  let g = List.map param2type inputs @ List.map param2type outputs in
  let expected = [Int32; Int64; Int32; Int64] in
  let printer x = List.map typ2ocamlstr x |> String.concat "," in
  assert_equal ~printer expected g

let test_gensqlite _ =
  let open Gensqlite_tools in
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

  let (insert_s, insert) = [%gensqlite dbx "insert into users(name) values(%s{name})"] in
  let (select_s, select) = [%gensqlite dbx "select @d{id}, @s{name}, strftime('%s',
  @n{created}) from users where name = %s{name}"] in
  let (select2_s, select2) = [%gensqlite dbx "select @s{id}, strftime('%s',
  @L{created}) from users where name = %d{name}"] in

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
  let (select3_s, select3) = [%gensqlite dbx "select count(*) as @d{count} from users"] in
  let res = select3 () in
  let printer x = List.map string_of_int x |> String.concat "," in
  assert_equal ~msg:"select3" ~printer (3::[]) res;

  (* if this compiles and runs it's probably OK *)
  (* note that all prepared statements must be finalized prior to closing *)
  let stmts = drop_s :: create_s :: insert_s :: select_s :: select2_s :: [] in
  let stmts = select3_s :: stmts in
  List.iter (fun s -> ignore(Sqlite3.finalize s)) stmts;
  close_db dbx

let test_quotes _ =
  let s = pq "strftime('%s-%d', %s-%d @s{abc}%d{def} '@s{abc}%d{def}')" in
  ae "strftime('%s-%d', ?-? abc:def '@s{abc}%d{def}')" s;
  ()

let tests =
  "gensqlite_tests">::: [
    "test_input">::test;
    "test_output">::outputs;
    "test_ints">::test_ints;
    "test_gensqlite">::test_gensqlite;
    "test_quotes">::test_quotes;
  ]

let _ = run_test_tt_main tests

open Gensqlite_tools

let dbx = Sqlite3.db_open "test.sqlite"

let (drop_s, drop_table) = [%gensqlite dbx "drop table if exists users"]

let (create_s, create_table) = [%gensqlite dbx "CREATE TABLE if not exists users(id integer primary key
asc, name text not null unique, created integer not null default
current_timestamp, check(trim(name)<>''));"]

let () = drop_table () |> create_table

let (insert_s, ins) = [%gensqlite dbx "insert into users(name) values(>@name)"]

let () = ()
  |> ins ~name:"beakybird"
  |> ins ~name:"diagonaldaffodil"
  |> ins ~name:"lateralligator"
  |> ins ~name:"1001"

let (select_s, q) = [%gensqlite dbx "select <:id, <@name, strftime('%s', <?created) from users where
name = >@name"]

let print_res = function
  | (id, name, created)::_ ->
      Printf.printf "id %d name: %s created: %ld\n" id name created
  | [] -> Printf.printf "empty result from query\n"

let () = q ~name:"lateralligator" () |> print_res

let () = q ~name:"squeamish ossifrage" () |> print_res

let (select2_s, q2) = [%gensqlite dbx "select <@id, <:name, strftime('%s', <$created)
from users where name = >:name"]

let print_res2 = function
  | (id, name, created)::_ ->
      Printf.printf "id %s name %d created %Ld\n" id name created
  | [] -> Printf.printf "empty result from query\n"

let () = q2 ~name:1001 () |> print_res2

let stmts = drop_s :: create_s :: insert_s :: select_s :: select2_s :: []
let () = List.iter (fun s -> ignore(Sqlite3.finalize s)) stmts

let () = close_db dbx

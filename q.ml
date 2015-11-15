type name = string
type typ = Int | Int32 | Int64 | Float | String | Blob | Bool
type modifier = Option | List
(* two names: a label and the actual argument name *)
type input = (name * name) * typ * modifier list
type output = name * typ * modifier list
type param = In of input | Out of output

let str2typ = function
  | "d" -> Int
  | "n" -> Int32
  | "L" -> Int64
  | "f" -> Float
  | "s" -> String
  | "S" -> Blob
  | "b" -> Bool
  | _ -> failwith "Invalid type"

let typ2ocamlstr = function
  | Int -> "int"
  | Int32 -> "int32"
  | Int64 -> "int64"
  | Float -> "float"
  | String | Blob -> "string"
  | Bool -> "bool"

let mod2ocamlstr = function
  | Option -> "option"
  | List -> "list"

let paramtype2str (_, typ, mods) =
  let typ = typ2ocamlstr typ in
  (*let mods = List.map mod2ocamlstr mods |> String.concat " " in*)
  (*Printf.sprintf "%s %s" typ mods*)
  typ (* ignore modifiers for now *)

let param2type (_, typ, _) = typ

let name ((name,_,_) : input) = name

let process str =
  (* grievous hack to escape everything within quotes *)
  let escrgx = Re_pcre.regexp {|('[^']*')|} in
  let esc_list = ref [] in
  let esc_str = "<GENSQLITE_PRESERVED>" in
  let esc_subst substrings =
    let mtch = Re.get substrings 0 in
    esc_list := mtch :: !esc_list;
    esc_str in

  let escaped = Re.replace ~f:esc_subst escrgx str in
  esc_list := List.rev !esc_list;

  (* logic to extract inputs and outputs *)
  let inrgx = Re_pcre.regexp {|%([dnLfsSb])(\?)?(\{(\w+)\})?|} in
  let outrgx = Re_pcre.regexp {|@([dnLfsSb])(\?)?\{(\w+)\}|} in
  let ctr = ref 0 in
  let getin (acc : input list) s =
    let groups = Re.get_all s in
    let typ = Array.get groups 1 |> str2typ in
    let optional = "?" = Array.get groups 2 in
    let mods = if optional then [Option] else [] in
    let name = Array.get groups 4 |> String.trim in
    let param = "p" ^ (string_of_int !ctr) in
    let name = if "" = name then ("", param) else (name, name) in
    let res = name, typ, mods in
    incr ctr;
    res::acc in
  let getout (acc : output list) s =
    let groups = Re.get_all s in
    let typ = Array.get groups 1 |> str2typ in
    let optional = "?" = Array.get groups 2 in
    let mods = if optional then [Option] else [] in
    let name = Array.get groups 3 |> String.trim in
    let res = name, typ, mods in
    res::acc in

  (* esecute extractions *)
  let ins = Re.all inrgx escaped |> List.fold_left getin [] |> List.rev in
  let outs = Re.all outrgx escaped |> List.fold_left getout [] |> List.rev in

  (* substitute inputs and outputs to regular SQL *)
  let rep_count_in = ref 0 in
  let in_subst substrs =
    let (name, _, _) = List.nth ins !rep_count_in in
    incr rep_count_in;
    match name with
    | ("", _) -> "?"
    | (n, _) -> ":" ^ n in
  let rep_count_out = ref 0 in
  let out_subst substrs =
    let (name, _,_) = List.nth outs !rep_count_out in
    incr rep_count_out;
    name in

  (* now restore the escaped strings *)
  let rep_esc_count = ref 0 in
  let unesc_subst substrs =
    let restore = List.nth !esc_list !rep_esc_count in
    incr rep_esc_count;
    restore in

  (* generate final sql *)
  let sql =
    Re.replace ~f:in_subst inrgx escaped
    |> Re.replace ~f:out_subst outrgx
    |> Re.replace ~f:unesc_subst (Re_pcre.regexp esc_str) in
  (sql, ins, outs)

(*let _ = process "@d{hallo} @n?{lolz}%f{float}"
let () = process "@d?{world}"
let () = process "%s{foo}"
let () = process "%L?"
let () = process "!{foo}"
let () =
  let (sql, _, _) = process "strftime('%s' @n{created} %d{many} 'saddfaces')" in
  let (sql2, _, _) = process "strftime('%s-%d' %s-%d')" in
  print_endline sql;
  print_endline sql2*)

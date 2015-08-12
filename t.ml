type literal
type param

type t =
  | QueryString of string
  | IntParam of string
  | Int32Param of string
  | Int64Param of string
  | StringParam of string
  | IntOutput of string
  | Int32Output of string
  | Int64Output of string
  | StringOutput of string

type query = t list

let to_sql (q:query) : string =
  let t2s = function
    | QueryString s | IntOutput s | Int32Output s | Int64Output s | StringOutput s -> s
    | IntParam s | Int32Param s | Int64Param s | StringParam s -> ":" ^ s in
  let strs = List.map t2s q in
  String.concat "" strs

let to_raw = function
  | QueryString s
  | IntParam s | Int32Param s | Int64Param s | StringParam s
  | IntOutput s | Int32Output s | Int64Output s | StringOutput s -> s

let filter_params =
  List.filter (function IntParam _ | Int32Param _ | Int64Param _
  | StringParam _ -> true | _ -> false)

let filter_outputs =
  List.filter (function IntOutput _ | Int32Output _ | Int64Output _
  | StringOutput _ -> true | _ -> false)

let parse_query (s:string) : query =
  let open Re in
  let inout = alt [ char '>'; char '<' ] in
  let sigil = alt [ char '@'; char ':'; char '?'; char '$'] in
  let rx = rep1 (seq [inout; sigil; rep alpha; ]) in
  let rc = compile rx in
  let m = all rc s in
  let trim s = String.sub s 2 ((String.length s) - 2) in
  (* TODO refactor to make this nicer ... *)
  let typ = function
    | s when String.length s < 2 -> QueryString "(EMPTY)"
    | s when String.sub s 0 2 = ">@" -> StringParam (trim s)
    | s when String.sub s 0 2 = ">:" -> IntParam (trim s)
    | s when String.sub s 0 2 = ">?" -> Int32Param (trim s)
    | s when String.sub s 0 2 = ">$" -> Int64Param (trim s)
    | s when String.sub s 0 2 = "<@" -> StringOutput (trim s)
    | s when String.sub s 0 2 = "<:" -> IntOutput (trim s)
    | s when String.sub s 0 2 = "<?" -> Int32Output (trim s)
    | s when String.sub s 0 2 = "<$" -> Int64Output (trim s)
    | s -> QueryString s in
  let query = List.fold_left(fun (list, off) group ->
    let (start, stop) = get_ofs group 0 in
    let lead = QueryString (String.sub s off (start - off)) in
    let actual = typ (String.sub s start (stop - start)) in
    (list @ [lead;actual], stop)) ([], 0) m in
  let (list, off) = query in
  list @ [QueryString (String.sub s off ((String.length s) - off))]

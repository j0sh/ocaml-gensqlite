open Ast_mapper
open Ast_helper
open Asttypes
open Parsetree
open Longident

let get_loc { pstr_loc = loc; } = loc

let gen_stuff dbh sql loc =
  let mklid s = {txt=Lident s; loc} in
  let mkident s = Exp.ident (mklid s) in
  let mkstr s = Exp.constant ~loc (Const_string (s, None)) in
  let mkint i = Exp.constant ~loc (Const_int i) in
  let qs = T.parse_query sql in (* tokenize input "sql" *)
  let sql = mkstr (T.to_sql qs) in (* generate the actual sql *)
  (* only keep the input variables for processing *)
  let outputs = T.filter_outputs qs in
  let qs = T.filter_params qs |> List.rev in
  (* misc helper functions *)
  let q2t = function T.IntParam _ -> "int" | T.Int32Param _ -> "int32"
    | T.Int64Param _ -> "int64" | _ -> "string" in
  let q2n = T.to_raw in
  let q2tp sadf =
    let constr = Typ.constr (mklid (q2t sadf)) [] in
    Pat.constraint_ (Pat.var {txt=(q2n sadf);loc}) constr in
  (* generate callback tuple *)
  let zogs = fun i -> function
    | T.IntOutput s -> [%expr data2int s [%e mkint i]]
    | T.Int32Output s -> [%expr data2int32 s [%e mkint i]]
    | T.Int64Output s -> [%expr data2int64 s [%e mkint i]]
    | s -> [%expr data2str s [%e mkint i]] in
  let zogt = Exp.tuple (List.mapi zogs outputs) in
  let query_call =
    if List.length outputs >= 2 then zogt
    else if List.length outputs = 1 then zogs 0 (List.hd outputs)
    else [%expr () ] in
  (* actual query and callback expression *)
  let base = if List.length outputs > 0 then [%expr
    let ret = ref [] in
    let cb s = ret := [%e query_call]::!ret in
    query ~cb stmt;
    !ret
  ] else [%expr query stmt ] in (* simple case for no outputs *)
  (* generate bindings for output variables *)
  let q2b acc qn =
    let s = q2n qn in
    let cf = (function T.IntParam _ -> "sqint" | T.Int32Param _ -> "sqint32"
      | T.Int64Param _ -> "sqint64" | _ -> "sqtext") qn in
    let val_ = [%expr ([%e mkident cf] [%e mkident s])] in
    let z = [%expr bind_var stmt [%e mkstr s] [%e val_]] in
    Exp.sequence z acc in
  let binds = List.fold_left q2b base qs in
  (* generate function params *)
  let initial = Exp.fun_ "" None (Pat.construct (mklid "()") None) binds in
  (*let initial = Exp.fun_ "" None (Pat.mk (Ppat_var {txt="()"; loc})) binds in*)
  let q2f acc qn = Exp.fun_ (q2n qn) None (q2tp qn) acc in
  let bind_f = List.fold_left q2f initial qs in
  (* generate record type based on outvars *)
  (* currently unused...
  let q2tc qn = Typ.constr (mklid (q2t qn)) [] in
  let labels = List.map (fun qn -> Type.field {txt=(q2n qn);loc} (q2tc qn)) outputs in
  let rcd = Type.mk ~kind:(Ptype_record labels) {txt="typename"; loc} in
  let rcdt = Str.type_ [rcd] in
  *)
  [%expr
    let stmt  = Sqlite3.prepare [%e dbh] [%e sql] in
    let bind_stmt = [%e bind_f] in
    (stmt, bind_stmt)
  ]


let gensqlite_mapper argv =
  (* our gensqlite_mapper only overrides the handling of expressions in the
   * default mapper. *)
  { default_mapper with
    expr = fun mapper expr ->
      match expr with
      (* is this an extension node? *)
      | {pexp_desc =
        (* should have name 'gensqlite' *)
        Pexp_extension ({txt = "gensqlite"; loc}, pstr)} ->
      begin match pstr with
      | (* should have a single structure item, which is the evaluation of a
          constant string. *)
        PStr [ {pstr_desc = Pstr_eval (
          {pexp_desc = Pexp_apply (dbh, [(_, {pexp_desc =
            Pexp_constant(Const_string(sym, None))})])}, _)} ] ->
          gen_stuff dbh sym loc
      | _ -> raise (Location.Error(
        Location.error ~loc "[%gensqlite accepts a db handle and a string]"))
      end
    (* Delegate to the default mapper *)
    | x -> default_mapper.expr mapper x;
  }

let () = register "gensqlite" gensqlite_mapper

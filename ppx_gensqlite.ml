open Ast_mapper
open Ast_helper
open Asttypes
open Parsetree
open Longident

let get_loc { pstr_loc = loc; } = loc

let gen_stuff dbh str loc =
  let mklid s = {txt=Lident s; loc} in
  let mkident s = Exp.ident (mklid s) in
  let mkstr s = Exp.constant ~loc (Const_string (s, None)) in
  let mkint i = Exp.constant ~loc (Const_int i) in
  let (sql, inputs, outputs) = Q.process str in
  let sql = mkstr sql in
  let q2t = Q.paramtype2str in
  let q2n = Q.name in
  let q2label qn =
    let (label, _) = q2n qn in
    label in
  let q2arg qn =
    let (_, arg) = q2n qn in
    arg in
  let q2tp sadf =
    let constr = Typ.constr (mklid (q2t sadf)) [] in
    let txt = q2arg sadf in
    Pat.constraint_ (Pat.var {txt;loc}) constr in
  (* generate callback tuple *)
  let zogs = fun i -> function
    | (s, Q.Int, _) -> [%expr data2int s [%e mkint i]]
    | (s, Q.Int32, _) -> [%expr data2int32 s [%e mkint i]]
    | (s, Q.Int64, _) -> [%expr data2int64 s [%e mkint i]]
    | (s, _, _) -> [%expr data2str s [%e mkint i]] in
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
  let ctr = ref 0 in
  let q2b acc qn =
    incr ctr;
    let (label, arg) = q2n qn in (* extract arg name *)
    (* todo: floats, bools and options *)
    let cf = (function Q.Int -> "sqint" | Q.Int32 -> "sqint32"
      | Q.Int64 -> "sqint64" | _ -> "sqtext") (Q.param2type qn) in
    let val_ = [%expr ([%e mkident cf] [%e mkident arg])] in
    let z =
      if "" = label
      then [%expr bind_idx stmt [%e mkint !ctr] [%e val_]]
      else [%expr bind_var stmt [%e mkstr arg] [%e val_]] in
    Exp.sequence z acc in
  let binds = List.fold_left q2b base inputs in
  (* generate function params *)
  let initial = Exp.fun_ "" None (Pat.construct (mklid "()") None) binds in
  (*let initial = Exp.fun_ "" None (Pat.mk (Ppat_var {txt="()"; loc})) binds in*)
  let q2f acc qn = Exp.fun_ (q2label qn) None (q2tp qn) acc in
  let bind_f = List.fold_left q2f initial inputs in
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

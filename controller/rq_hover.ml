(************************************************************************)
(* Coq Language Server Protocol -- Requests                             *)
(* Copyright 2019 MINES ParisTech -- Dual License LGPL 2.1 / GPL3+      *)
(* Copyright 2019-2023 Inria      -- Dual License LGPL 2.1 / GPL3+      *)
(* Written by: Emilio J. Gallego Arias                                  *)
(************************************************************************)

open Lsp.Core

(* Debug parameters *)
let show_loc_info = false

(* Taken from printmod.ml, funny stuff! *)
let build_ind_type mip = Inductive.type_of_inductive mip

let info_of_ind env sigma ((sp, i) : Names.Ind.t) =
  let mib = Environ.lookup_mind sp env in
  let u =
    Univ.make_abstract_instance (Declareops.inductive_polymorphic_context mib)
  in
  let mip = mib.Declarations.mind_packets.(i) in
  let paramdecls = Inductive.inductive_paramdecls (mib, u) in
  let env_params, params =
    Namegen.make_all_rel_context_name_different env (Evd.from_env env)
      (EConstr.of_rel_context paramdecls)
  in
  let nparamdecls = Context.Rel.length params in
  let args = Context.Rel.instance_list Constr.mkRel 0 params in
  let arity =
    Reduction.hnf_prod_applist_decls env nparamdecls
      (build_ind_type ((mib, mip), u))
      args
  in
  Printer.pr_lconstr_env env_params sigma arity

let type_of_constant cb = cb.Declarations.const_type

let info_of_const env cr =
  let cdef = Environ.lookup_constant cr env in
  (* This prints the definition *)
  (* let cb = Environ.lookup_constant cr env in *)
  (* Option.cata (fun (cb,_univs,_uctx) -> Some cb ) None *)
  (*   (Global.body_of_constant_body Library.indirect_accessor cb), *)
  type_of_constant cdef

let info_of_var env vr =
  let vdef = Environ.lookup_named vr env in
  (* This prints the value if some *)
  (* Option.cata (fun cb -> Some cb) None (Context.Named.Declaration.get_value
     vdef) *)
  Context.Named.Declaration.get_type vdef

(* XXX: Some work to do wrt Global.type_of_global_unsafe *)
let info_of_constructor env cr =
  (* let cdef = Global.lookup_pinductive (cn, cu) in *)
  let ctype, _uctx =
    Typeops.type_of_global_in_context env (Names.GlobRef.ConstructRef cr)
  in
  ctype

type id_info =
  | Notation of Pp.t
  | Def of Pp.t

let print_type env sigma x = Def (Printer.pr_ltype_env env sigma x)

let info_of_id env sigma id =
  let qid = Libnames.qualid_of_string id in
  try
    let id = Names.Id.of_string id in
    Some (info_of_var env id |> print_type env sigma)
  with _ -> (
    try
      (* try locate the kind of object the name refers to *)
      match Nametab.locate_extended qid with
      | TrueGlobal lid ->
        (* dispatch based on type *)
        let open Names.GlobRef in
        (match lid with
        | VarRef vr -> info_of_var env vr |> print_type env sigma
        | ConstRef cr -> info_of_const env cr |> print_type env sigma
        | IndRef ir -> Def (info_of_ind env sigma ir)
        | ConstructRef cr -> info_of_constructor env cr |> print_type env sigma)
        |> fun x -> Some x
      | Abbrev kn ->
        Some (Notation (Prettyp.default_object_pr.print_abbreviation env kn))
    with _ -> None)

let info_of_id ~st id =
  let st = Coq.State.to_coq st in
  let sigma, env =
    match st with
    | { Vernacstate.lemmas = Some pstate; _ } ->
      Vernacstate.LemmaStack.with_top pstate
        ~f:Declare.Proof.get_current_context
    | _ ->
      let env = Global.env () in
      (Evd.from_env env, env)
  in
  info_of_id env sigma id

let info_of_id_at_point ~node id =
  let st = node.Fleche.Doc.Node.state in
  Fleche.Info.LC.in_state ~st ~f:(info_of_id ~st) id

let pp_typ id = function
  | Def typ ->
    let typ = Pp.string_of_ppcmds typ in
    Format.(asprintf "```coq\n%s : %s\n```" id typ)
  | Notation nt ->
    let nt = Pp.string_of_ppcmds nt in
    Format.(asprintf "```coq\n%s\n```" nt)

let if_bool b l = if b then [ l ] else []
let to_list x = Option.cata (fun x -> [ x ]) [] x

let info_type ~contents ~node ~point : string option =
  Option.bind (Rq_common.get_id_at_point ~contents ~point) (fun id ->
      Option.map (pp_typ id) (info_of_id_at_point ~node id))

let extract_def ~point:_ (def : Vernacexpr.definition_expr) :
    Constrexpr.constr_expr list =
  match def with
  | Vernacexpr.ProveBody (_bl, et) -> [ et ]
  | Vernacexpr.DefineBody (_bl, _, et, eb) -> [ et ] @ to_list eb

let extract_pexpr ~point:_ (pexpr : Vernacexpr.proof_expr) :
    Constrexpr.constr_expr list =
  let _id, (_bl, et) = pexpr in
  [ et ]

let extract ~point ast =
  match (Coq.Ast.to_coq ast).v.expr with
  | Vernacexpr.VernacDefinition (_, _, expr) -> extract_def ~point expr
  | Vernacexpr.VernacStartTheoremProof (_, pexpr) ->
    List.concat_map (extract_pexpr ~point) pexpr
  | _ -> []

let ntn_key_info (_entry, key) = "notation: " ^ key

let info_notation ~point (ast : Fleche.Doc.Node.Ast.t) =
  (* XXX: Iterate over the results *)
  match extract ~point ast.v with
  | { CAst.v = Constrexpr.CNotation (_, key, _params); _ } :: _ ->
    Some (ntn_key_info key)
  | _ -> None

let info_notation ~node ~point : string option =
  Option.bind node.Fleche.Doc.Node.ast (info_notation ~point)

let hover ~doc ~node ~point =
  let open Fleche in
  let contents = doc.Fleche.Doc.contents in
  let range = Doc.Node.range node in
  let info = Doc.Node.info node in
  let range_string = Format.asprintf "%a" Lang.Range.pp range in
  let stats_string = Doc.Node.Info.print info in
  let type_string = info_type ~contents ~node ~point in
  let notation_string = info_notation ~node ~point in
  let hovers =
    if_bool show_loc_info range_string
    @ if_bool !Config.v.show_stats_on_hover stats_string
    @ to_list type_string @ to_list notation_string
  in
  match hovers with
  | [] -> `Null
  | hovers ->
    let range = Some range in
    let value = String.concat "\n___\n" hovers in
    let contents = { HoverContents.kind = "markdown"; value } in
    HoverInfo.(to_yojson { contents; range })

let hover ~doc ~point =
  let node = Fleche.Info.LC.node ~doc ~point Exact in
  (match node with
  | None ->
    if show_loc_info then
      let contents =
        { HoverContents.kind = "markdown"; value = "no node here" }
      in
      HoverInfo.(to_yojson { contents; range = None })
    else `Null
  | Some node -> hover ~doc ~node ~point)
  |> Result.ok

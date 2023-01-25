(************************************************************************)
(*         *   The Coq Proof Assistant / The Coq Development Team       *)
(*  v      *   INRIA, CNRS and contributors - Copyright 1999-2018       *)
(* <O___,, *       (see CREDITS file for the list of authors)           *)
(*   \VV/  **************************************************************)
(*    //   *    This file is distributed under the terms of the         *)
(*         *     GNU Lesser General Public License Version 2.1          *)
(*         *     (see LICENSE file for the text of the license)         *)
(************************************************************************)

(************************************************************************)
(* Coq serialization API/Plugin SERAPI                                  *)
(* Copyright 2016-2019 MINES ParisTech -- LGPL 2.1+                     *)
(* Copyright 2019-2022 Inria           -- LGPL 2.1+                     *)
(* Written by: Emilio J. Gallego Arias                                  *)
(************************************************************************)

type 'a hyp =
  { names : Names.Id.t list
  ; def : 'a option
  ; ty : 'a
  }

type info =
  { evar : Evar.t
  ; name : Names.Id.t option
  }

type 'a reified_goal =
  { info : info
  ; ty : 'a
  ; hyps : 'a hyp list
  }

type 'a goals =
  { goals : 'a list
  ; stack : ('a list * 'a list) list
  ; bullet : Pp.t option
  ; shelf : 'a list
  ; given_up : 'a list
  }

type reified_pp = Pp.t reified_goal goals

(** XXX: Do we need to perform evar normalization? *)

module CDC = Context.Compacted.Declaration

type cdcl = Constr.compacted_declaration

let to_tuple ppx : cdcl -> 'pc hyp =
  let open CDC in
  let ppx t = ppx (EConstr.of_constr t) in
  function
  | LocalAssum (idl, tm) ->
    { names = List.map Context.binder_name idl; def = None; ty = ppx tm }
  | LocalDef (idl, tdef, tm) ->
    { names = List.map Context.binder_name idl
    ; def = Some (ppx tdef)
    ; ty = ppx tm
    }

(** gets a hypothesis *)
let get_hyp (ppx : EConstr.t -> 'pc) (_sigma : Evd.evar_map) (hdecl : cdcl) :
    'pc hyp =
  to_tuple ppx hdecl

(** gets the constr associated to the type of the current goal *)
let get_goal_type (ppx : EConstr.t -> 'pc) (sigma : Evd.evar_map) (g : Evar.t) :
    _ =
  let (EvarInfo evi) = Evd.find sigma g in
  ppx Evd.(evar_concl evi)

let build_info sigma g = { evar = g; name = Evd.evar_ident g sigma }

(** Generic processor *)
let process_goal_gen ppx sigma g : 'a reified_goal =
  (* XXX This looks cumbersome *)
  let env = Global.env () in
  let (EvarInfo evi) = Evd.find sigma g in
  let env = Evd.evar_filtered_env env evi in
  (* why is compaction neccesary... ? [eg for better display] *)
  let ctx = Termops.compact_named_context (Environ.named_context env) in
  let ppx = ppx env sigma in
  let hyps = List.map (get_hyp ppx sigma) ctx |> List.rev in
  let info = build_info sigma g in
  { info; ty = get_goal_type ppx sigma g; hyps }

let if_not_empty (pp : Pp.t) =
  if Pp.(repr pp = Ppcmd_empty) then None else Some pp

let reify ~ppx lemmas =
  let lemmas = State.Proof.to_coq lemmas in
  let proof =
    Vernacstate.LemmaStack.with_top lemmas ~f:(fun pstate ->
        Declare.Proof.get pstate)
  in
  let { Proof.goals; stack; sigma; _ } = Proof.data proof in
  let ppx = List.map (process_goal_gen ppx sigma) in
  { goals = ppx goals
  ; stack = List.map (fun (g1, g2) -> (ppx g1, ppx g2)) stack
  ; bullet = if_not_empty @@ Proof_bullet.suggest proof
  ; shelf = Evd.shelf sigma |> ppx
  ; given_up = Evd.given_up sigma |> Evar.Set.elements |> ppx
  }

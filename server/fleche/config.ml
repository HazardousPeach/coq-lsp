type t =
  { mem_stats : bool [@default false]
        (** [mem_stats] Call [Obj.reachable_words] for every sentence. This is
            very slow and not very useful, so disabled by default *)
  ; gc_quick_stats : bool [@default true]
        (** [gc_quick_stats] Show the diff of [Gc.quick_stats] data for each
            sentence *)
  ; client_version : string [@default "any"]
  ; eager_diagnostics : bool [@default true]
        (** [eager_diagnostics] Send (full) diagnostics after processing each *)
  ; ok_diagnostics : bool [@default false]  (** Show diagnostic for OK lines *)
  ; goal_after_tactic : bool [@default false]
        (** When showing goals and the cursor is in a tactic, if false, show
            goals before executing the tactic, if true, show goals after *)
  ; show_coq_info_messages : bool [@default false]
        (** Show `msg_info` messages in diagnostics *)
  ; show_notices_as_diagnostics : bool [@default false]
        (** Show `msg_notice` messages in diagnostics *)
  ; admit_on_bad_qed : bool [@default true]
        (** [admit_on_bad_qed] There are two possible error recovery strategies
            when a [Qed] fails: one is not to add the constant to the state, the
            other one is admit it. We find the second behavior more useful, but
            YMMV. *)
  }

let default =
  { mem_stats = false
  ; gc_quick_stats = true
  ; client_version = "any"
  ; eager_diagnostics = true
  ; ok_diagnostics = false
  ; goal_after_tactic = false
  ; show_coq_info_messages = false
  ; show_notices_as_diagnostics = false
  ; admit_on_bad_qed = true
  }

let v = ref default

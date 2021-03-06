type 'a table = { ref: 'a ref; init: unit -> 'a }
type 'a immutable = { ref: 'a ref; mutable snapshot: 'a }

type ref_and_reset =
  | Table : 'a table -> ref_and_reset
  | Ref : 'a immutable -> ref_and_reset

type bindings = {
  mutable refs: ref_and_reset list;
  mutable frozen : bool;
  mutable is_bound: bool;
}

let global_bindings =
  { refs = []; is_bound = false; frozen = false }

let is_bound () = global_bindings.is_bound

let reset () =
  assert (is_bound ());
  List.iter (function
    | Table { ref; init } -> ref := init ()
    | Ref { ref; snapshot } -> ref := snapshot
  ) global_bindings.refs

let s_table create size =
  let init () = create size in
  let ref = ref (init ()) in
  assert (not global_bindings.frozen);
  global_bindings.refs <- (Table { ref; init }) :: global_bindings.refs;
  ref

let s_ref k =
  let ref = ref k in
  assert (not global_bindings.frozen);
  global_bindings.refs <-
    (Ref { ref; snapshot = k }) :: global_bindings.refs;
  ref

type 'a cell = { ref : 'a ref; mutable value : 'a }
type slot = Slot : 'a cell -> slot
type store = slot list

let fresh () =
  let slots =
    List.map (function
      | Table { ref; init } -> Slot {ref; value = init ()}
      | Ref r ->
          if not global_bindings.frozen then r.snapshot <- !(r.ref);
          Slot { ref = r.ref; value = r.snapshot }
    ) global_bindings.refs
  in
  global_bindings.frozen <- true;
  slots

let with_store slots f =
  assert (not global_bindings.is_bound);
  global_bindings.is_bound <- true;
  List.iter (fun (Slot {ref;value}) -> ref := value) slots;
  match f () with
  | res ->
    List.iter (fun (Slot s) -> s.value <- !(s.ref)) slots;
    global_bindings.is_bound <- false;
    res
  | exception exn ->
    List.iter (fun (Slot s) -> s.value <- !(s.ref)) slots;
    global_bindings.is_bound <- false;
    raise exn

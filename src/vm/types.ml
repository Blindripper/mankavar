open Das_helpers
open Vm_helpers

type value = Value.t
module VMap = Value.Map
type stack = Stack.t

type register = A | B | C | D
[@@deriving ez]
let register_pp ppf x =
  Format.fprintf ppf "r%s" @@ match x with
  | A -> "a"
  | B -> "b"
  | C -> "c"
  | D -> "d"
let register_encoding = Encoding.(
  union [
    case get_a_opt (fun () -> a) unit ;
    case get_b_opt (fun () -> b) unit ;
    case get_c_opt (fun () -> c) unit ;
    case get_d_opt (fun () -> d) unit ;
  ]
)

type op1 = Not
[@@deriving ez]
let op1_pp ppf x =
  let print x = Format.fprintf ppf "%s" x in
  print @@ op1_destruct_tpl ("Not") x
let op1_encoding = Encoding.(
  union [
    case get_not_opt not' unit ;
  ]
)

type op2 =
| Add
| Sub
| Mul
| Div
| And
| Or
[@@deriving ez]
let op2_pp ppf x =
  let print x = Format.fprintf ppf x in
  let print_s = print "%s" in
  print_s @@
  op2_destruct_tpl
    "+" "-" "*" "/"
    "&&" "||"
  x
let op2_encoding = Encoding.(
  union [
    case get_add_opt add' unit ;
    case get_sub_opt sub' unit ;
    case get_mul_opt mul' unit ;
    case get_div_opt div' unit ;
    case get_and__opt and_' unit ;
    case get_or__opt or_' unit ;
  ]
)
(*
  Instructions extended with a case for compile time stuff
*)
type 'ct instruction =
| Jump_value of value
| Jump of register
| JumpGez of register * register (* if greater x1, jump to x2 *)
| Stack_push of register (* Stack.push r *)
| Stack_get of int * register (* r <- stack[i] *)
| Stack_set of int * register (* stack[i] <- r *)
| Stack_drop of int
| Register_set_value of register * value (* r <- value *)
| Register_set of register * register (* r1 <- r2 *)
| Call_op1 of op1 * register * register (* r1 <- op r2 *)
| Call_op2 of op2 * register * register * register (* r1 <- op r2 r3 *)
| Custom of int (* external *)
| Compile_time of 'ct
| Halt
[@@deriving ez]

let instruction_pp ~compile_time ppf x =
  let print x = Format.dprintf x in
  let vpp = Value.pp in
  let rpp = register_pp in
  let o1pp = op1_pp in
  let o2pp = op2_pp in
  instruction_destruct
  ~jump_value:(print "jmp to %a" vpp)
  ~jump:(print "jmp to %a" rpp)
  ~jumpgez:(fun r1 r2 -> print "jmp>%a to %a" rpp r1 rpp r2)
  ~stack_push:(print "stack push %a" rpp)
  ~stack_get:(fun i r -> print "stack[%d] -> %a" i rpp r)
  ~stack_set:(fun i r -> print "stack[%d] <- %a" i rpp r)
  ~stack_drop:(print "stack[0:%d] drop")
  ~register_set_value:(fun r v -> print "%a <- %a" rpp r vpp v)
  ~register_set:(fun r1 r2 -> print "%a <- %a" rpp r1 rpp r2)
  ~call_op1:(fun op r1 r2 -> print "%a <- %a %a" rpp r1 o1pp op rpp r2)
  ~call_op2:(fun op r1 r2 r3 ->
    print "%a <- %a %a %a" rpp r1 rpp r2 o2pp op rpp r3
  )
  ~halt:(print "halt")
  ~custom:(fun i -> print "custom %d" i)
  ~compile_time
  x ppf

type empty = |

(*
  Runtime instructions don't have compile_time case
*)
type rt_instruction = empty instruction

let rt_instruction_pp : _ -> rt_instruction -> _ =
  let compile_time : empty -> _ = function _ -> . in
  instruction_pp ~compile_time

let rt_instruction_encoding : rt_instruction Encoding.t = Encoding.(
  let renc = register_encoding in
  let op1enc = op1_encoding in
  let op2enc = op2_encoding in
  union [
    case get_jump_value_opt jump_value int64 ;
    case get_jump_opt jump renc ;
    case get_jumpgez_opt jumpgez' @@ tuple_2 renc renc ;
    case get_stack_push_opt stack_push renc ;
    case get_stack_get_opt stack_get' @@ tuple_2 int renc ;
    case get_stack_set_opt stack_set' @@ tuple_2 int renc ;
    case get_stack_drop_opt stack_drop int ;
    case get_register_set_value_opt register_set_value' @@ tuple_2 renc int64 ;
    case get_register_set_opt register_set' @@ tuple_2 renc renc ;
    case get_call_op1_opt call_op1' @@ tuple_3 op1enc renc renc ;
    case get_call_op2_opt call_op2' @@ tuple_4 op2enc renc renc renc ;
    case get_custom_opt custom int ;
    case get_halt_opt halt' unit ;
  ]
)

type 'mem state = {
  instructions : rt_instruction array ;
  mutable instruction_pointer : value ;
  mutable a : value ;
  mutable b : value ;
  mutable c : value ;
  mutable d : value ;
  mutable memory : 'mem ;
  stack : stack ;
}
let state_pp f ppf s =
  let {
    instructions ; instruction_pointer = ip ;
    a ; b ; c ; d ;
    memory ; stack ;
  } = s in
  let print x = Format.fprintf ppf x in
  print "@[<v>" ;
  print "@[<v 2>  " ;
  instructions |> Array.iteri (fun i instr -> (
    print "%d:\t%a" i rt_instruction_pp instr ;
    if i = Int64.to_int ip then (
      print "\t<--- current" ;
    ) ;
    print "@;" ;
  )) ;
  print "@]" ;
  print "ra:%a\trb:%a\trc:%a\trd:%a@;"
    Value.pp a Value.pp b Value.pp c Value.pp d ;
  print "%a@;" Stack.pp stack ;
  print "%a@;" f memory ;
  print "@]" ;
  ()

let state_empty instructions ip memory = {
  instructions ;
  instruction_pointer = ip ;
  a = Value.zero ;
  b = Value.zero ;
  c = Value.zero ;
  d = Value.zero ;
  memory = memory ;
  stack = Stack.empty ;
}

type program = {
  code : rt_instruction list ;
  start_pointer : int ;
}
[@@deriving ez]

module C = Configurator.V1

let () =
  C.main ~name:"" @@ fun _ ->
  C.Flags.write_sexp "flags.sexp" @@ 
  match Sys.getenv_opt "SODIUM_LIB_DIR" with
  (* | Some path -> ["-cclib"; "-L" ^ path] *)
  | Some _path -> (
    (* Format.printf "Sodium lib dir: %s\n" _path ; *)
    ["-cclib"; "-lsodium"]
    (* ["-cclib"; "-llibsodium" ; "-L" ^ path] *)
    (* ["-cclib";
  "-L/usr/lib/x86_64-linux-gnu"] *)
  )
  | None -> []
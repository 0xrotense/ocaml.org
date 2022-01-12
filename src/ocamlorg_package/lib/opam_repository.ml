module Process = struct
  open Lwt.Infix

  let pp_args =
    let sep = Fmt.(const string) " " in
    Fmt.(array ~sep (quote string))

  let pp_cmd f = function
    | "", args ->
      pp_args f args
    | bin, args ->
      Fmt.pf f "(%S, %a)" bin pp_args args

  let pp_status f = function
    | Unix.WEXITED x ->
      Fmt.pf f "exited with status %d" x
    | Unix.WSIGNALED x ->
      Fmt.pf f "failed with signal %d" x
    | Unix.WSTOPPED x ->
      Fmt.pf f "stopped with signal %d" x

  let check_status cmd = function
    | Unix.WEXITED 0 ->
      ()
    | status ->
      Fmt.failwith "%a %a" pp_cmd cmd pp_status status

  let exec cmd =
    let proc = Lwt_process.open_process_none cmd in
    proc#status >|= check_status cmd

  let pread cmd =
    let proc = Lwt_process.open_process_in cmd in
    Lwt_io.read proc#stdout >>= fun output ->
    proc#status >|= check_status cmd >|= fun () -> output

  let pread_lines cmd =
    let open Lwt.Syntax in
    let proc = Lwt_process.open_process_in cmd in
    let* lines = Lwt_io.read_lines proc#stdout |> Lwt_stream.to_list in
    let* status = proc#status in
    check_status cmd status;
    Lwt.return lines
end

let clone_path = Config.opam_repository_path

let git_cmd args =
  "git", Array.of_list ("git" :: "-C" :: Fpath.to_string clone_path :: args)

let clone () =
  match Bos.OS.Path.exists clone_path with
  | Ok true ->
    Lwt.return_unit
  | Ok false ->
    Process.exec
      ( "git"
      , [| "git"
         ; "clone"
         ; "https://github.com/ocaml/opam-repository.git"
         ; Fpath.to_string clone_path
        |] )
  | _ ->
    Fmt.failwith "Error finding about this path: %a" Fpath.pp clone_path

let pull () = Process.exec (git_cmd [ "pull"; "--ff-only"; "origin" ])

let last_commit () =
  let open Lwt.Syntax in
  let+ output =
    Process.pread (git_cmd [ "rev-parse"; "HEAD" ]) |> Lwt.map String.trim
  in
  output

let ls_dir directory =
  Sys.readdir directory
  |> Array.to_list
  |> List.filter (fun x -> Sys.is_directory (Filename.concat directory x))

let list_packages () = ls_dir Fpath.(to_string (clone_path / "packages"))

let list_package_versions package =
  ls_dir Fpath.(to_string (clone_path / "packages" / package))

let process_opam_file f =
  let open Lwt.Syntax in
  Lwt_io.with_file ~mode:Input (Fpath.to_string f) (fun channel ->
      let+ content = Lwt_io.read channel in
      OpamFile.OPAM.read_from_string content)

let opam_file package_name package_version =
  let opam_file =
    Fpath.(clone_path / "packages" / package_name / package_version / "opam")
  in
  process_opam_file opam_file

let commit_at_date date =
  Process.pread (git_cmd [ "rev-list"; "-1"; "--before=" ^ date; "@" ])
  |> Lwt.map String.trim

let new_files_since ~a ~b =
  Process.pread_lines
    (git_cmd [ "diff"; "--diff-filter=A"; "--name-only"; a; b ])
  |> Lwt.map (List.map Fpath.v)
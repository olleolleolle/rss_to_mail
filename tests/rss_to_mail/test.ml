open Printf

(* Fetch feeds in the `feeds/` subdirectory
   Fetchs are blocking *)
module Local_fetch =
struct

  type error = int

  let fetch uri =
    let f = "feeds/" ^ Uri.to_string uri in
    eprintf "opening %s\n" f;
    Lwt.return @@
    match open_in f with
    | exception Sys_error _		-> Error 404
    | inp						->
      let len = in_channel_length inp in
      Ok (really_input_string inp len)

end

module Log =
struct

  let log_error url = function
    | `Fetch_error code					->
      printf "Log: %s: Fetch error %d\n" url code
    | `Parsing_error ((line, col), msg)	->
      printf "Log: %s: Parsing error (line %d, col %d)\n%s\n" url line col msg

  let log_updated url ~entries =
    printf "Log: %s: %d entries\n" url entries

end

module Feed_datas =
struct

  type t = Rss_to_mail.feed_data StringMap.t

  let get t url = StringMap.find_opt url t
  let set t url data = StringMap.add url data t

end

module Rss_to_mail = Rss_to_mail.Make (Local_fetch) (Log) (Feed_datas)

let now = 12345678L

let print_mail (m : Rss_to_mail.mail) =
  printf "FROM: %s\nSUBJECT: %s\nBODY html: %s\nBODY text: %s\n"
    m.sender m.subject m.body_html m.body_text

let print_options (opts : Feed_desc.options) =
  printf "Options:";
  (match opts.refresh with
   | `Every h		-> printf " (refresh %f)" h
   | `At (h, m)	-> printf " (refresh (at %d:%d))" h m
   | `At_weekly (d, h, m) -> printf " (refresh (at %d:%d %d)" h m (CalendarLib.Date.int_of_day d));
  Option.iter (printf " (title %s)") opts.title;
  Option.iter (printf " (label %s)") opts.label;
  (if opts.no_content then printf " (no_content true)");
  printf "\n"

let print_feed (feed, options) =
  begin match feed with
    | Feed_desc.Feed url	-> printf "\n# %s\n\n" url
    | Scraper (url, _)		-> printf "\n# scraper %s\n\n" url
    | Bundle url			-> printf "\n# bundle %s\n\n" url
  end;
  print_options options

let () =
  let { Persistent_data.feed_datas; _ } =
    match CCSexp.parse_file "feed_datas.sexp" with
    | Error _ -> failwith "Error parsing datas"
    | Ok sexp -> Persistent_data.load_feed_datas sexp
  in
  let { Persistent_data.feeds; _ } =
    match CCSexp.parse_file "feeds.sexp" with
    | Error _ -> failwith "Error parsing feeds"
    | Ok sexp -> Persistent_data.load_feeds sexp
  in
  List.iter print_feed feeds;
  printf "\n# Done parsing\n\n";
  let _, mails =
    Rss_to_mail.check_all ~now feed_datas feeds
    |> Lwt_main.run
  in
  List.iter print_mail (List.rev mails)

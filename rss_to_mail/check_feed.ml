module Make (Async : sig
		type 'a t
		val return : 'a -> 'a t
		val bind : 'a t -> ('a -> 'b t) -> 'b t
	end)
	(Fetch : sig
		type error
		val fetch : Uri.t -> (string, error) result Async.t
	end) =
struct

	(* Remove date for IDs that disapeared from the feed: 1 month *)
	let remove_date_from = Int64.(+) 2678400L

	let prepare_mail ~sender feed options entry =
		let subject =
			match entry.Feed.title with
			| Some title	-> title
			| None			-> "New entry from " ^ sender
		in
		let body = Mail_body.generate ~sender feed options entry in
		Utils.{ sender; subject; body }

	let prepare_bundle ~sender feed options entries =
		let len = List.length entries in
		if len = 0
		then []
		else
			let subject = string_of_int len ^ " entries from " ^ sender in
			let body =
				entries
				|> List.map (Mail_body.generate ~sender feed options)
				|> String.concat "\n"
			in
			[ Utils.{ sender; subject; body } ]

	let new_entries remove_date seen_ids entries =
		let ids, news = Array.fold_right (fun e (ids, news) ->
			match Feed.entry_id e with
			| Some id	->
				let news = if SeenSet.is_seen id seen_ids
						then news else e :: news in
				id :: ids, news
			| None		-> ids, news
		) entries ([], []) in
		SeenSet.new_ids remove_date ids seen_ids, news

	let filter_entries filters entries =
		let match_any_filter =
			function
			| Feed.{ title = Some title; _ } ->
				let match_ (regexp, expctd) =
					try
						ignore (Str.search_forward regexp title 0);
						expctd
					with Not_found ->
						not expctd
				in
				List.exists match_ filters
			| { title = None; _ }			-> true
		in
		if List.is_empty filters
		then entries
		else Array.filter match_any_filter entries

	let process ~first_update ~now feed_uri options seen_ids feed =
		let feed = Feed.resolve_urls feed_uri feed in
		let entries = filter_entries options.Feed_options.filter feed.entries in
		let seen_ids, entries =
			new_entries (remove_date_from now) seen_ids entries
		in
		let sender =
			let (|||) opt def =
				match opt with
				| Some ""
				| None		-> def ()
				| Some v	-> v
			in
			options.Feed_options.title ||| fun () ->
			feed.Feed.feed_title ||| fun () ->
			Uri.host feed_uri ||| fun () ->
			Uri.to_string feed_uri
		in
		let mails =
			if first_update then []
			else if options.bundle
			then prepare_bundle ~sender feed options entries
			else List.map (prepare_mail ~sender feed options) entries
		in
		Async.return (`Ok (seen_ids, mails))

	let update ~first_update ~now uri options seen_ids =
		let process_feed contents =
			match Feed_parser.parse (`String (0, contents)) with
			| exception Feed_parser.Error (pos, msg) ->
				Async.return (`Parsing_error (pos, msg))
			| feed ->
				process ~first_update ~now uri options seen_ids feed
		and process_scrap scraper contents =
			let feed = Scraper.scrap scraper contents in
			process ~first_update ~now uri options seen_ids feed
		in
		let f = Fetch.fetch uri in
		Async.bind f (function
		| Error e		-> Async.return (`Fetch_error e)
		| Ok contents	->
			match options.scraper with
			| Some sc		-> process_scrap sc contents
			| None			-> process_feed contents)

	let check ~now uri options data =
		let first_update, uptodate, seen_ids =
			match data with
			| Some (last_update, seen_ids) ->
				let uptodate = Utils.is_uptodate now last_update options in
				false, uptodate, seen_ids
			| None -> true, false, SeenSet.empty
		in
		if uptodate then Async.return `Uptodate
		else update ~first_update ~now uri options seen_ids

end
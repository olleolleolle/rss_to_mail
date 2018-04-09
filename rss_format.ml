open Xml_utils
open Feed

let parse rss_elem =
	let dc_ns = namespace "http://purl.org/dc/elements/1.1/" in
	let parse_item item =
		let date =
			Int64.of_float @@
			Js.date##parse (node (child "pubDate" item))##getText
		and categories =
			let parse_category cat =
				{ term = None; label = Some (text cat) } in
			List.map parse_category (children "category" item)
		and author =
			try Some (text (child ~ns:dc_ns "creator" item))
			with _ -> None
		in
		{	id = text (child "guid" item);
			title = text (child "title" item);
			content = text (child "description" item);
			link = text (child "link" item);
			author; date; categories }
	in
	let channel = child "channel" rss_elem in
	let entries =
		Array.of_list (children "item" channel)
		|> Array.map parse_item
	in
	{	feed_title = text (child "title" channel);
		feed_link = (try Some (text (child "link" channel)) with _ -> None);
		entries }
#!/bin/sh

# Dependencies:
# posix coreutils
# smu: https://github.com/Gottox/smu/

BLOG_DIR="blog"
DEST_DIR="./"
HOST_URL="https://ShaqeelAhmad.github.io"

add_file() {
	if [ $# -lt 1 ]; then
		echo "Not enough arguments" >&2;
		usage >&2
		exit 1;
	fi

	Date="$(date +"%Y/%m/%d")"

	mkdir -p  "$BLOG_DIR"/"$Date"
	Path=""$BLOG_DIR"/"$Date"/"$1""
	if [ -r "$Path" ] ;
	then
		printf "File: %s exists, do you want to overwrite it? [y/N] " "$Path"
		read Answer
		case "$Answer" in
			y|Y|yes) ;;
			*)
				printf "Ignoring File\n";
				return
				;;
		esac
	fi

	touch "$Path"
	printf "Created file %s\n" "$Path"
}

build_files() {
	RssFile="$DEST_DIR/rss.xml"
	Url="$HOST_URL"

	# We are building the blog posts and blog posts index and rss feed at
	# the same time.
	cat <<EOF > "$RssFile"
<?xml version="1.0" encoding="utf-8" standalone="yes" ?>
<rss version="2.0">
	<channel>
		<title>Shaqeel rss feed</title>
	<link>"$Url"</link>
		<description>My blog</description>
		<language>en</language>
EOF
	IndexFile=""$DEST_DIR"/"$BLOG_DIR"/index.html"
	HTMLHeader="$(cat ./src/header.html)"
	HTMLFooter="$(cat ./src/footer.html)"
	echo "$HTMLHeader" | sed 's/TITLE/blog/' > "$IndexFile"
	printf "<ul>" >> "$IndexFile"

	for File in $(find "$BLOG_DIR" -type f -iname '*.md')
	do
		Date=$(dirname ${File#*"$BLOG_DIR"/})
		Title="$(awk -F '# ' '/^# /{print $2;exit}' "$File")"

		[ -z "$Title" ] && printf "Error: file %s doesn't have a title\nAborting...\n" "$File" && exit 1

		# Blog
		mkdir -p "$DEST_DIR"/"$(dirname "$File")"
		(echo "$HTMLHeader" | sed 's/TITLE/'"$Title"'/' ; smu "$File"; echo "$HTMLFooter") > "$DEST_DIR"/"${File%.md}".html

		# Rss
		echo '<item>'                                                                        >> "$RssFile"
		printf '<title>%s</title>\n' "$Title"                                                >> "$RssFile"
		printf '<link>%s/%s</link>\n' "$Url" "$File"                                         >> "$RssFile"
		printf '<pubDate>%s %s</pubDate>\n' "$(date -d "$Date" '+%a, %d %b %Y %H:%M:%S %z')" >> "$RssFile"
		printf '<description>'                                                               >> "$RssFile"
		smu "$File" | smu -n                                                                 >> "$RssFile"
		echo '</description>'                                                                >> "$RssFile"
		echo '</item>'                                                                       >> "$RssFile"

		# Index file
		File="${File%.md}.html"
		printf "<li>%s: <a href=/%s>%s</a></li>\n" "$Date" "$File" "$Title" >> "$IndexFile"
	done
	printf "</ul>"     >> "$IndexFile"
	echo "$HTMLFooter" >> "$IndexFile"

	cat <<EOF >> "$RssFile"
	</channel>
</rss>
EOF
}

argv0="$0"

usage() {
	printf "usage:\n"
	printf "\t%s new <filename>\n" "$argv0"
	printf "\t%s [build]\n" "$argv0"
}

if [ $# -lt 1 ]; then
	build_files
	exit $?;
fi

case "$1" in
	"-h")
		usage
		;;
	"new")
		shift
		add_file "$@"
		;;
	"build")
		build_files
		;;
	*)
		printf "Unknown command %s\n" "$1" >&2;
		usage >&2
		exit 1;
esac

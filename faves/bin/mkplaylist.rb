#!/usr/bin/ruby

require 'optparse'
require 'net/http'
require 'uri'
require 'json'

##############################################################################
class Config
  PLAYLIST_LIMIT = 50       # Max playlist size allowed by YouTube

  attr_reader :sep, :hm_fields, :field_index, :s_url_video_regex, 
    :s_url_playlist_prefix, :num_lookups_before_sleep, :sleep_seconds,
    :s_match_audio_video, :max_playlist_size, :confirm_ids

  def initialize
    @sep         = "|"      # Markdown table: Column separator
    @hm_fields   = 4        # Markdown table: How many columns/fields
    @field_index = 3        # Markdown table: Index of the field containing the hyperlinks

    @s_url_video_regex      = "https://www.youtube.com/watch.*v="
    @s_url_playlist_prefix  = "https://www.youtube.com/watch_videos?video_ids="

    @num_lookups_before_sleep   = 4
    @sleep_seconds              = 1.0

    @s_match_audio_video    = nil
    @max_playlist_size      = nil
    @confirm_ids            = nil
    parse_command_line
  end

  def parse_command_line
    @s_match_audio_video  = "audio"         # Default value
    @max_playlist_size    = PLAYLIST_LIMIT  # Default value
    @confirm_ids          = false           # Default value

    op = OptionParser.new do |opts|
      opts.banner = <<~EOF

        Make a YouTube playlist from audio/video links in a markdown table.
        Usage: #{File.basename(__FILE__)}  [options]  MARKDOWN_FILENAME.md
      EOF

      opts.on("-h", "--help", "Prints this help") do
        puts opts
        exit
      end

      opts.on("-a", "--audio", "Extract links marked as audio [default]") do
        @s_match_audio_video = "audio"
      end

      opts.on("-v", "--video", "Extract links marked as video") do
        @s_match_audio_video = "video"
      end

      opts.on("-m", "--max-playlist-size NUM", "Maximum number of IDs per playlist [default 50]") do |s_num|
        @max_playlist_size = s_num.to_i

        unless @max_playlist_size.to_s == s_num and @max_playlist_size > 0 and @max_playlist_size <= PLAYLIST_LIMIT
          STDERR.puts "Error: Max playlist size '#{s_num}' must be an integer 1-#{PLAYLIST_LIMIT}"
          STDERR.puts op.help
          exit(1)
        end
      end

      opts.on("-c", "--confirm-ids", "Confirm IDs via network probe") do
        @confirm_ids = true
      end
    end
    begin
      op.parse!     # Now ARGV should only contain the filename
    rescue OptionParser::InvalidOption => e
      puts "Error: #{e}"
      STDERR.puts op.help
      exit(2)
    end

    unless ARGV.size == 1
      STDERR.puts "Error: No markdown filename supplied."
      STDERR.puts op.help
      exit(3)
    end

    unless File.readable?(ARGV[0])
      STDERR.puts "Error: Unable to find or read file '#{ARGV[0]}'"
      STDERR.puts op.help
      exit(4)
    end
  end
end

##############################################################################
def get_markdown_link(line, conf)
  s_match = conf.s_match_audio_video

  # Extract the column/field containing the links
  fields = line.chomp.split(conf.sep)
  return nil unless fields.length == conf.hm_fields

  # Ensure there is at least one valid link
  field = fields[conf.field_index]
  return nil unless field.match(conf.s_url_video_regex.downcase)

  # Put each markdown link into an array
  field.gsub!(/\), \[/, "),[")
  markdown_links = field.split(",")

  # Get the first matching link. We don't want links with a start-time (t=...)
  md_link = markdown_links.find{|link| link.match(/#{s_match}.*#{conf.s_url_video_regex}/i) and !link.match("t=")}
  # If we can't match against s_match, then just get the first valid URL
  md_link = markdown_links.find{|link| link.match(/#{conf.s_url_video_regex}/i) and !link.match("t=")} unless md_link
  return nil unless md_link
  md_link
end

##############################################################################
def get_youtube_playlists_from_markdown_table(conf)
  ids = []                # A playlist: which is an array of IDs
  playlists = []          # An array of playlists
  puts "\nTitle list:"
  id_count = 0

  ARGF.each_line{|line|
    md_link = get_markdown_link(line, conf)
    next unless md_link
    ids << md_link.gsub(/^.*=/, "").gsub!(/\).*$/, "")

    if ids.length == conf.max_playlist_size
      playlists << ids    # Push this playlist onto the array of playlists
      ids = []            # Initialise the next playlist
    end

    # Show details about this item/ID
    id_count += 1
    puts "[%3d] %s" % [id_count, line.sub(/(\|.[^\|]*){2}$/, "").gsub(/ +/, " ").sub(/<sup>.*<.sup>/, "")]
  }
  playlists << ids if ids.length > 0  # Push the last playlist onto the array of playlists
  playlists
end

##############################################################################
def verify_youtube_ids(ids, conf)
  # Use oEmbed (https://oembed.com/) to verify that the YouTube video exists
  print "Confirming IDs: "
  ids.each_with_index{|id, idx|
    print "."                         # Progress bar
    $stdout.flush
    url_oembed = "https://youtube.com/oembed?url=https://www.youtube.com/watch?v=#{id}&format=json"
    body = Net::HTTP.get(URI.parse(url_oembed))
    begin
      params = JSON.parse(body)
      puts "\nERROR with youtube ID '#{id}': #{body}" unless params["type"] # "type" is a required response param
    rescue JSON::ParserError => e
      puts "\nERROR with youtube ID '#{id}': #{body}"
    end
    count = idx + 1
    if count % conf.num_lookups_before_sleep == 0 and count < ids.length
      sleep conf.sleep_seconds
    end
  }
  puts
end

##############################################################################
# Main
##############################################################################
conf = Config.new
puts "### MAKE YOUTUBE PLAYLIST(S) ###"
get_youtube_playlists_from_markdown_table(conf).each_with_index{|ids, i|
  puts "\nYoutube #{conf.s_match_audio_video} playlist \##{i+1} (#{ids.length} items):"
  puts "#{conf.s_url_playlist_prefix}#{ids.join(',')}"

  verify_youtube_ids(ids, conf) if conf.confirm_ids
}

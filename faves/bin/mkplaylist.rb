#!/usr/bin/ruby

require 'optparse'

##############################################################################
class Config
  attr_reader :sep, :hm_fields, :field_index, :s_url_video_regex, :s_url_playlist_prefix, :s_match_audio_video

  def initialize
    @sep         = "|"      # Markdown table: Column separator
    @hm_fields   = 4        # Markdown table: How many columns/fields
    @field_index = 3        # Markdown table: Index of the field containing the hyperlinks

    @s_url_video_regex      = "https://www.youtube.com/watch.*v="
    @s_url_playlist_prefix  = "https://www.youtube.com/watch_videos?video_ids="

    @s_match_audio_video = nil
    parse_command_line
  end

  def parse_command_line
    @s_match_audio_video = "audio"     # Default value

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
    end
    begin
      op.parse!   # ARGV is left with filename
    rescue OptionParser::InvalidOption => e
      puts "Error: #{e}"
    end

    if ARGV.size != 1
      STDERR.puts "Error: No markdown filename supplied."
      STDERR.puts op.help
      exit(1)
    end

    unless File.readable?(ARGV[0])
      STDERR.puts "Error: Unable to find or read file '#{ARGV[0]}'"
      STDERR.puts op.help
      exit(2)
    end
  end
end

##############################################################################
def get_youtube_ids_from_markdown_table(conf)
  s_match = conf.s_match_audio_video
  ids = []
  id_num = 0
  puts "Title list:"
  ARGF.each_line{|line|
    # Extract the column/field containing the links
    fields = line.chomp.split(conf.sep)
    next unless fields.length == conf.hm_fields

    # Ensure there is at least one valid link
    field = fields[conf.field_index]
    next unless field.match(conf.s_url_video_regex.downcase)

    # Put each markdown link into an array
    field.gsub!(/\), \[/, "),[")
    markdown_links = field.split(",")

    # Get the first matching link. We don't want links with a start-time (t=...)
    md_link = markdown_links.find{|link| link.match(/#{s_match}.*#{conf.s_url_video_regex}/i) and !link.match("t=")}
    # If we can't match against s_match, then just get the first valid URL
    md_link = markdown_links.find{|link| link.match(/#{conf.s_url_video_regex}/i) and !link.match("t=")} unless md_link
    next unless md_link

    # Extract the id from the link.
    # Assumes the URL query string only contains parameter 'v', i.e.  v=...
    ids << md_link.gsub(/^.*=/, "").gsub!(/\).*$/, "")
    id_num += 1
    puts "[%3d] %s" % [id_num, line.sub(/(\|.[^\|]*){2}$/, "").gsub(/ +/, " ").sub(/<sup>.*<.sup>/, "")]
  }
  ids
end

##############################################################################
conf = Config.new
puts "### MAKE YOUTUBE PLAYLIST ###"

ids = get_youtube_ids_from_markdown_table(conf)
puts "Youtube ID list (#{ids.length}):"
ids.each{|id| puts "  #{id}"}

puts "Youtube playlist for links marked as '#{conf.s_match_audio_video}' (#{ids.length}):"
puts "#{conf.s_url_playlist_prefix}#{ids.join(',')}"

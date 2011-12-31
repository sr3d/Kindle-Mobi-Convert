#!/usr/bin/env ruby
# encoding: UTF-8

require 'ruby-debug'
require 'benchmark'
require 'mechanize'
require 'active_support/core_ext/string'
require 'trollop'

# url = "http://vnthuquan.net/truyen/truyen.aspx?tid=2qtqv3m3237n4n1n1ntn31n343tq83a3q3m3237nvn"
# url = "http://vnthuquan.net/truyen/truyen.aspx?tid=2qtqv3m3237nqntn1n31n343tq83a3q3m3237nvn" # Anh Hung Xa Dieu
url = ARGV[0]
raise "Invalid URL" unless url

opts = Trollop::options do
  version "VNThuQuan Scraper"
  banner <<-EOS
Scraping VNThuQuan.net Kung-Fu Novels and.

Usage:
       ./scraper [options] <url>
       
Example:
       ./scraper http://vnthuquan.net/truyen/truyen.aspx?tid=2qtqv3m3237n4n1n1ntn31n343tq83a3q3m3237nvn
       
       Output will be
      ./Đại Đường Song Long Truyện/
        1.html
        2.html
        ...
        761.html
        index.html
        Đại Đường Song Long Truyện.mobi
      
where [options] are:
EOS
  opt :output, "Output folder, default to the Novel's name"
end
# Trollop::die :volume, "must be non-negative" if opts[:volume] < 0



# Download
# write files
# cache
# combine
# output

class Scraper < Struct.new(:chapters, :title, :author, :out_folder)
  
  def initialize url
    @url = url
    @chapters = []
    
    @a = Mechanize.new { |agent|
      agent.user_agent_alias = 'Mac Safari'
    }
  end
  
  def run
    extract_meta
    prepare_folder
    generate_toc_file
    process_chapters
    convert_to_mobi
  end
  
  def extract_meta
    time = Benchmark.measure("Extracting Meta for #{@url}") do
      puts "Downloading #{@url}..."
      @a.get(@url) do |page|
        @author = page.search("p.style28")[0].text
        @title  = page.search(".viethead")[0].text

        page.search("acronym").collect do |chapter| 
          @chapters << { 
            :title => chapter[:title].titlecase,
            :url   => chapter.search("a")[0][:href].gsub(/truyen.aspx/i,'truyentext.aspx')
          }
        end
      end
    end
    
    @out_folder = "#{@title}"    
    @mobi_file = "#{@out_folder}/#{@title}.mobi"
    
    puts "Downloading Info for #{@author} - #{@title}: %.3fs" % time.real
    puts "Found #{@chapters.length} chapters"
  end
  
  def process_chapters
    total_time = Benchmark.measure do 
      @chapters.each_with_index do |chapter, index|
        chapter_index = index + 1
        if chapter_downloaded? chapter_index
          puts "Chapter #{chapter_index} downloaded.  Skipping."
          next 
        end
      
        time = Benchmark.measure("Download Chapter #{chapter_index} ") do
          @a.get(chapter[:url]) do |page|

            # chapter[:text] = page.search('div.truyen_text').collect{ |div| "<p>#{div.inner_html.split("\n", '<br/>')}</p>" }.join("\n")
            chapter[:text] = page.search('div.truyen_text').collect{ |div| "<p>#{div.inner_html.split("\n").join("<br/>")}</p>" }.join("")
          end
        end
        puts "Download Chapter #{chapter_index}: %.3f seconds" % time.real
        write_chapter chapter, chapter_index
        
        break
        
      end
    end
    
    puts "Total Time: %.3f" % total_time.real
  end
  
  def write_chapter chapter, chapter_index
    out_file = "#{@out_folder}/#{chapter_index}.html"
    File.open(out_file, "w") do |f|
      f.write <<-HEADER
        <html>
        <head>
        <title>Chapter #{chapter_index} - #{chapter[:title]}</title>
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
        <body>
          <h1 class="chapter">Chapter #{chapter_index} - #{chapter[:title]}</h1>
        HEADER
      f.write chapter[:text]
      f.write <<-FOOTER
        </body>
        </html>
        FOOTER
    end
    puts "-> #{out_file}"
  end

  
  def generate_toc_file
    @toc = "#{@out_folder}/index.html"
    File.open(@toc, "w") do |f|
      f.write <<-HEADER
        <html>
        <head>
        <title>#{@author} - #{@title}</title>
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8">
        </head>
        <body>
            <h1>Table of Contents</h1>
            <p style="text-indent:0pt">
      HEADER
      @chapters.each_with_index do |chapter, index|
        chapter_index = index + 1
        f.write <<-CHAPTER
          <p><a href="#{chapter_index}.html">#{chapter_index} - #{chapter[:title]}</a></p>
          CHAPTER
      end
      f.write <<-FOOTER
        </p>
        </body>
        </html>
        FOOTER
    end
    puts "TOC file generated"
  end
  
  def chapter_downloaded? chapter_index
    File.exists? chapter_filename(chapter_index)
  end

  def chapter_filename chapter_index
    out_file = "#{@out_folder}/#{chapter_index}.html"
  end

  def prepare_folder
    mkdir @out_folder unless File.directory? @out_folder
  end
  
  def prepare_folder
    Dir.mkdir @out_folder unless File.directory? @out_folder
  end
  
  def convert_to_mobi
    puts "Converting to .mobi..."
    cmd = %!
      ebook-convert "#{@toc}" "#{@mobi_file}" --input-profile=kindle --output-profile=kindle --authors="#{@author}" --title="#{@title}" --remove-paragraph-spacing --remove-paragraph-spacing-indent-size -vvv!.squish
    
    time = Benchmark.measure do
      system(cmd)
    end
    puts "Done generating mobi file:  %.3f" % time.real
  end
end


scraper = Scraper.new url
scraper.run

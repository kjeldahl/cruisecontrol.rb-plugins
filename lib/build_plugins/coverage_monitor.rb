# This plugin will monitor changes to code coverage
require 'hpricot'

class CoverageMonitor
  
  cattr_accessor :coverage_file, :output_file
  
  @@coverage_file = 'coverage/index.html'
  @@output_file = 'coverage_changes.html'
  
  def initialize(project)
    @project = project
  end

  def build_finished(build)
    if build.successful?
      successfull_build = last_successfull_build
      if successfull_build
        write_output(coverage_for_build(build), coverage_for_build(successfull_build), build)
      end
    end
  end
  
  def write_output(this_build_coverage, last_build_coverage, build)
    changes = []
    this_build_coverage.each_with_index do |value, index|
      changes[index] = this_build_coverage[index] - last_build_coverage[index]
    end
    
    File.open(build.artifact(CoverageMonitor.output_file), 'w') do |f| 
      
      f.write("<html>
      <head><title>Changes to code coverage</title>
      <style type='text/css'>
      body {font-size: 24em; font-family: helvetica;}
      tr.light {
       background-color: rgb(240, 240, 245);
      }
      tr.dark {
       background-color: rgb(230, 230, 235);
      }
      table {border: thin solid black:}
      </style>
      </head>
      <body>
      <table cellpadding=\"10\">
        <tr class='dark'><th>&nbsp;</th><th>This build</th><th>Last build</th><th>Change</th></tr>
        <tr class='light'><td>Total coverage</td><td>#{this_build_coverage[0]}%</td><td>#{last_build_coverage[0]}%</td><td>#{changes[0]}%</td></tr>
        <tr class='dark'><td>Code coverage</td><td>#{this_build_coverage[1]}%</td><td>#{last_build_coverage[1]}%</td><td>#{changes[1]}%</td></tr>
        <tr class='light'><td>Total lines</td><td>#{this_build_coverage[2].to_i}</td><td>#{last_build_coverage[2].to_i}</td><td>#{changes[2].to_i}</td></tr>
        <tr class='dark'><td>Code lines</td><td>#{this_build_coverage[3].to_i}</td><td>#{last_build_coverage[3].to_i}</td><td>#{changes[3].to_i}</td></tr>
      </table>
      </body>
      </html>")
    end
  end
  
  def last_successfull_build
    @project.builds.reverse.find{|b| b.successful?}
  end
  
  def coverage_for_build(build)
    classes = %w(coverage_total coverage_code lines_total lines_code)
    coverage_file = build.artifact(CoverageMonitor.coverage_file)
    if File.exists?(coverage_file)
      doc = open(coverage_file) { |f| Hpricot(f)}
      classes.collect {|c| doc.at(".#{c}").inner_text.gsub('%','').to_f}
    end
  end
end

Project.plugin :coverage_monitor
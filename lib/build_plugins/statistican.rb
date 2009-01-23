# This plugin will generate a progress chart based on rake stats
# From: http://www.oreillynet.com/ruby/blog/2008/03/cruisecontrol_charts.html
require 'fileutils'
require 'code_statistics'

class CodeStatistics;  attr_reader :statistics;  end

class StatisticianCollecter

  STATS_FOLDERS = [
    %w(Controllers        app/controllers),
    %w(Helpers            app/helpers), 
    %w(Models             app/models),
    %w(Libraries          lib/),
    %w(APIs               app/apis),
    %w(Components         components),
    %w(Integration\ tests test/integration),
    %w(Functional\ tests  test/functional),
    %w(Unit\ tests        test/unit)
  ].freeze

  # Uses code_statistics.rb to collect line counts for project
  def self.collect_stats
    #  code callously ripped from statistics.rake !
    folders = STATS_FOLDERS.select{|name, dir| File.directory?(dir) }
    cs      = CodeStatistics.new(*folders)
    statz   = cs.statistics
    tyme    = Time.now.to_i
    yaml    = { "build_#{ tyme }" => statz }.to_yaml
    return yaml.sub(/^---/, '')  #  abrogate that pesky document marker!
  end

  def self.append_stats(project)
    yaml = collect_stats
    plop = project.path + '/statistics.yaml'
    File.open(plop, 'a+') { |f| f.write(yaml) }
  end

end


class Statistician

  def initialize(project)
    @project = project
  end

  def build_finished(build)
    run_in_here = @project.path + '/work'
    FileUtils.cd(run_in_here) { StatisticianCollecter.append_stats(@project) }
  end

end

Project.plugin :statistician

# This plugin will generate a progress chart based on rake stats
# From: http://www.oreillynet.com/ruby/blog/2008/03/cruisecontrol_charts.html
require 'fileutils'
require 'code_statistics'

class CodeStatistics;  attr_reader :statistics;  end


module StatisticianCollecter

  STATS_FOLDERS = [
    %w(Controllers        app/controllers),
    %w(Helpers            app/helpers), 
    %w(Models             app/models),
    %w(Libraries          lib/),
    %w(APIs               app/apis),
    %w(Components         components),
    %w(Controller\ specs  spec/controllers),
    %w(Helper\ specs      spec/helpers),
    %w(Model\ specs       spec/models),
    %w(View\ specs        spec/views/*),
    %w(Library\ specs     spec/lib),
    %w(Integration\ tests test/integration),
    %w(Functional\ tests  test/functional),
    %w(Unit\ tests        test/unit)
  ].freeze

  # Uses code_statistics.rb to collect line counts for project
  def collect_stats
    #  code callously ripped from statistics.rake !
    folders = STATS_FOLDERS.select{|name, dir| File.directory?(dir) }
    cs      = CodeStatistics.new(*folders)
    statz   = cs.statistics
    tyme    = Time.now.to_i
    yaml    = { "build_#{ tyme }" => statz }.to_yaml
    return yaml.sub(/^---/, '')  #  abrogate that pesky document marker!
  end

  def append_stats(project)
    yaml = collect_stats
    plop = project.path + '/statistics.yaml'
    File.open(plop, 'a+') { |f| f.write(yaml) }
  end

end


require 'gnuplot'
module StatisticianGraph

  # Load statistics
  def get_stats(project)
    statistics = File.read(project.path + '/statistics.yaml')
    statistics = YAML::load(statistics)
    statistics = statistics.map { |k,v| [k.sub('build_', '').to_i, v] }
    return statistics.sort
  end

  def timefmt;  '%Y/%d/%m-%H:%M';  end

  def ftime(timestamp)
    Time.at(timestamp).strftime(timefmt)
  end

  def fetch_codelines(stat, fields)
    return stat.values_at(*fields).map { |values| values ? values['codelines'] : 0 }.sum
  end

  def fetch_field(stat, fields, field)
    return stat.values_at(*fields).map { |values| values ? values[field] : 0 }.sum
  end

  ALL_TESTS = %w(Controller\ specs Helper\ specs Model\ specs View\ specs Library\ specs Unit\ tests Functional\ tests)
  ALL_CODE = %w(Libraries Helpers Controllers Models)

  def gnu_plot_stats(build, project, name, title, signals, logscale = false)
    output_file = build.artifact("stats/#{name}.jpeg")
    #  drastically prevent false positives in manual tests
    File.unlink(output_file) if File.exist?(output_file)

    Gnuplot.open do |gp|
      Gnuplot::Plot.new( gp ) do |plot|
        #  decorate the chart
        plot.xdata 'time'
        plot.key 'outside title "   Code Lines   "'
        plot.grid 'ytics'
        plot.timefmt timefmt.inspect # for quote marks
        plot.term 'jpeg small size 800,300'
        plot.output output_file
        plot.title title
        plot.logscale 'y' if logscale
        stats = get_stats(project)
        #  set the time range
        timestamps = stats.map(&:first)
        statistics = stats.map(&:last)
        mini = timestamps.first - 60
        maxi = timestamps.last  + 60
        plot.xrange "['#{ ftime(mini) }':'#{ ftime(maxi) }']"
        times = timestamps.map { |v|  ftime(v.to_i) }
        maxi = 0

        #  collect each signal and add its plot line
        plot.data = signals.keys.sort.map do |legend|
          fields = signals[legend]

          values = statistics.map{|stat|
                      if fields.respond_to? :call
                        fields.call(stat)
                      else
                        fetch_codelines(stat, fields)
                      end
                    }
          maxi = [maxi, *values].max

          Gnuplot::DataSet.new( [times, values] ) { |ds|
            ds.with = "linespoints"
            ds.title = legend
            ds.using = '1:2'
            ds.linewidth = 4
          }
        end

        #  set the chart height
        if logscale
          next_order_of_magnitude = 10 ** (Math.log10(maxi) + 1.1).to_i
          plot.set 'yrange', "[0.01:#{next_order_of_magnitude}]"
        end
      end
    end  #  this 'end' writes the output file

    # Append graph to stats index file
    index_file = build.artifact("stats/index.html")
    FileUtils.mkdir(File.dirname(index_file)) unless File.directory?(File.dirname(index_file))
    File.open(index_file, 'a') do |f|
      f.puts "<div><img src='#{name}.jpeg' width='800' height='300' /></div>\n"
    end
  end
end


class Statistician
  include StatisticianCollecter
  include StatisticianGraph

  def initialize(project)
    @project = project
  end

  def build_finished(build)
    return unless build.successful?

    run_in_here = @project.path + '/work'
    FileUtils.cd(run_in_here) { append_stats(@project) }

    name = "loc_to_lot"
    title = "rake stats: lines of code to lines of test"
    gnu_plot_stats build, @project, name, title,
      {
        'Test:Code' => lambda { |stats|
          test = fetch_codelines(stats, ALL_TESTS)
          code = fetch_codelines(stats, ALL_CODE)
          return test.to_f / code.to_f
        },
        'Code' => ALL_CODE,
        'Test' => ALL_TESTS
      }, true

    name = "test_coverage"
    title = "rake stats: code to test ratio"
    gnu_plot_stats build, @project, name, title, {
      'Test:Code' => lambda { |stats|
        test = fetch_codelines(stats, ALL_TESTS)
        code = fetch_codelines(stats, ALL_CODE)
        return test.to_f / code.to_f
      }
    }

    name = "code_size"
    title = "rake stats: tracking code size"
    gnu_plot_stats build, @project, name, title, {
      '100-LOC' => lambda { |stats|
        code = fetch_codelines(stats, ALL_CODE)
        return code.to_f / 100.0
      },
      'Classes' => lambda { |stats|
        fetch_field(stats, ALL_CODE, 'classes')
      },
      'Methods' => lambda { |stats|
        fetch_field(stats, ALL_CODE, 'methods')
      }
    }

    name = "code_complexity"
    title = "rake stats: tracking code complexity"
    gnu_plot_stats build, @project, name, title, {
      'M/C' => lambda { |stats|
        fetch_field(stats, ALL_CODE, 'methods').to_f / fetch_field(stats, ALL_CODE, 'classes')
      },
      'LOC/M' => lambda { |stats|
        fetch_codelines(stats, ALL_CODE).to_f / fetch_field(stats, ALL_CODE, 'methods')
      }
    }
  end

end

Project.plugin :statistician
# encoding: utf-8

require 'guard'
require 'guard/guard'
require 'guard/watcher'
require 'haml'
require 'haml-rails'

module Guard
  class Haml < Guard
    autoload :Notifier, 'guard/haml/notifier'

    def initialize(watchers = [], options = {})
      @options = {
        :notifications => true,
        :layout => nil
      }.merge options
      super(watchers, @options)
    end

    def start
      run_all if @options[:run_at_start]
    end

    def stop
      true
    end

    def reload
      run_all
    end

    def run_all
      run_on_changes(Watcher.match_files(self, Dir.glob(File.join('**', '*.*'))))
    end

    def run_on_changes(paths)
      # if any of the HAML template change, recompile template.haml
      paths = paths.map{|p| File.dirname(p)}.uniq.map{|p| p << "/template.haml"}

      paths.each do |file|
        output_file = get_output(file)
        content_template = File.basename(File.dirname(file))
        layout_file = nil
        if @options[:layout]
          layout_file = File.dirname(file) << "/#{@options[:layout]}.haml"
          if !File.exists?(layout_file)
            raise StandardError, "#{content_template}: Layout file (#{layout_file}) does not exist!"
          end
        end
        FileUtils.mkdir_p File.dirname(output_file)
        File.open(output_file, 'w') { |f| f.write(compile_haml(file, layout_file)) }
        message = "#{content_template}: Successfully compiled HAML to HTML!\n"
        message += "# #{file} → #{output_file}".gsub("#{Bundler.root.to_s}/", '')
        ::Guard::UI.info message
        Notifier.notify( true, message ) if @options[:notifications]
      end
      notify paths
    end

    private

    def compile_haml(file, layout = nil)
      begin
        content = File.new(file).read
        if layout.nil?
          engine  = ::Haml::Engine.new(content, (@options[:haml_options] || {}))
          engine.render
        else
          ::Haml::Engine.new(File.new(layout).read, (@options[:haml_options] || {})).render do
            ::Haml::Engine.new(content, (@options[:haml_options] || {})).render
          end
        end
      rescue StandardError => error
        message = "HAML compilation failed!\nError: #{error.message}"
        ::Guard::UI.error message
        Notifier.notify( false, message ) if @options[:notifications]
        throw :task_has_failed
      end
    end

    # Get the file path to output the html based on the file being
    # built. The output path is relative to where guard is being run.
    #
    # @param file [String] path to file being built
    # @return [String] path to file where output should be written
    #
    def get_output(file)
      file_dir = File.dirname(file)
      file_name = File.basename(file).split('.')[0..-2].join('.')

      file_name = "#{file_name}.html" if file_name.match("\.html?").nil?

      file_dir = file_dir.gsub(Regexp.new("#{@options[:input]}(\/){0,1}"), '') if @options[:input]
      file_dir = File.join(@options[:output], file_dir) if @options[:output]

      if file_dir == ''
        file_name
      else
        File.join(file_dir, file_name)
      end
    end

    def notify(changed_files)
      ::Guard.guards.reject{ |guard| guard == self }.each do |guard|
        paths = Watcher.match_files(guard, changed_files)
        guard.run_on_changes paths unless paths.empty?
      end
    end
  end
end

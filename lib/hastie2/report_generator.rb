require 'fileutils'
require 'config_file'
require 'constants'
require 'id_server'
require 'server_reader'

module Hastie2
  class ReportGenerator < ServerReader
    def self.banner
      "hastie2 create -l [LAB] -r [RESERACHER] <OPTIONS>"
    end

    attr_accessor :report_id, :title, :researcher, :lab, :order

    desc "Creates framework for new report"
    class_option :id, :aliases => "-i", :type => :string, :desc => "Overrides using ID server. Provide custom ID."
    class_option :lab, :aliases => "-l", :required => true, :desc => "Lab the researcher is under"
    class_option :researcher, :aliases => "-r", :required => true, :desc => "Researcher the report is for"
    class_option :type, :aliases => "-t", :desc => "Type of report to generate"
    class_option :template, :desc => "Template to use for creating report", :default => "report"
    class_option :analyst, :aliases => "-a", :desc => "Analyst generating the report"
    class_option :order, :aliases => "-f", :desc => "Order ID for the report (eg: MOLNG-110)"
    class_option :date, :aliases => "-d", :desc => "Date to use in report filename. Ex: 2011-11-29", :default => "#{Time.now.strftime('%Y-%m-%d')}"
    class_option :output, :aliases => "-o", :desc => "Output Directory for report"

    class_option :id_server, :desc => "URL of ID server to use", :default => Hastie.id_server
    class_option :id_issuer, :desc => "ID domain to use", :default => Hastie.id_issuer

    class_option :only_report, :type => :boolean, :desc => "Only output report and not rest of directory structure", :default => false

    def setup_id
      if !options[:id]
        if options[:id_server] and options[:id_issuer]
          id_server = Hastie::IdServer.new(options[:id_server], options[:id_issuer])
          say_status "Note", "Acquiring id from server", :green
          server_response = id_server.request_id(options[:lab], options[:researcher], options)
          say_status "Note", "Server response", :green
          puts server_response.inspect

          if server_response["project"] and server_response["project"]["id"]
            self.report_id = server_response["project"]["id"]
            options[:id] = self.report_id
            options[:report_id] = self.report_id
          else
            say_status "error", "No ID provided by ID server", :red
            say_status "error", "Check your ID server and try again", :red
            puts server_response.inspect
            exit(1)
          end
        else
          say_status "error", "No ID server found", :red
          say_status "error", " Provide --id_server and --id_issuer", :red
          say_status "error", " Or use --id to specify the ID of your report", :red
          exit(1)
        end
      else
        self.report_id = options[:id]
      end

      options[:name] = options[:id]

      # apparently :report_id is used when publishing.
      # TODO: remove duplication between options[:id] and options[:report_id]
      self.report_id = options[:id]
      options[:report_id] = options[:id]

      say_status "note", "id: #{options[:id]}"
      say_status "note", "name: #{options[:name]}"
    end

    # output directory now means two different things depending on :only_report
    # :only_report = true then :output means name of the report directory
    # :only_report = false then :output means the starting location for the
    #   project directory structure
    def setup_destination
      if options[:only_report]
        if !options[:output]
          options[:output] = File.join(".", Hastie.default_report_dir)
        end
        self.destination_root = options[:output]
      else
        if !options[:output]
          options[:output] = "."
        end
        self.destination_root = File.join(options[:output], options[:id])
      end

      say_status "note", "root: #{self.destination_root}"
    end

    def create_directory_structure
      unless options[:only_report]
        directory(File.join("templates", "project"), self.destination_root)
        self.destination_root = File.join(self.destination_root, Hastie.default_report_dir)
      end
    end

    def setup_variables
      options[:lab] ||= "cbio"
      options[:researcher] ||= "cbio"
      options[:type] ||= "textile"
      options[:date] ||= "#{Time.now.strftime('%Y-%m-%d')}"
      self.title = options[:name].gsub("_", " ")
      options[:title] = self.title

      options[:analyst] ||= "cbio"
      options[:data_dir] ||= data_dir
      options[:permalink] ||= "/#{options[:id]}.html"
    end

    def check_name_availible
      if options[:published_reports] and options[:published_reports].include? report_id
        say_status "error", "Sorry, the #{report_id} is already a published report", :red
        say_status "error", "Please run again with a different name", :red
        exit(1)
      end
    end

    def check_destination
      if File.exists? self.destination_root
        say_status "error", "#{self.destination_root} already exists.", :red
        say_status "error", "please choose different output directory", :red
        exit(1)
      end
    end

    def create_report_file
      say_status "create", "report: #{options[:id]}"
      extension = determine_extension(options[:type])
      template_name = options[:template]
      options[:extension] = extension
      template_file = "templates/#{template_name}.#{extension}.tt"
      if !File.exists? File.join(File.dirname(__FILE__), template_file)
        say_status "error", "#{template_file} not present. Invalid Template.", :red
        exit(1)
      end
      report_filename = "#{options[:date]}-#{report_id}.#{extension}"
      say_status  "note", "report file: #{report_filename}"
      template template_file, report_filename
      options[:report_file] = report_filename
      options[:report_file_generated] = options[:permalink]
    end

    def create_index_file
      template_file = "templates/report_index.html.tt"
      template template_file, "index.html"
    end

    def create_data_dir
      create_file File.join(data_dir, ".gitignore"), :verbose => true
    end

    def fetch_static_files
      options[:server]["static"] ||= []
      options[:server]["static"].each do |static_file|
        static_path = File.join(options[:server_root], static_file)
        if File.exists? static_path
          say_status "copy", "#{static_path} to #{File.basename(destination_root)}"
          FileUtils.cp_r static_path, self.destination_root
        end
      end
    end

    def write_config_file
      output_config_file = File.join(self.destination_root, Hastie.report_config_name)
      say_status "write", "#{File.basename(output_config_file)}"
      ConfigFile.write(output_config_file, options)
    end

    no_tasks do
      def determine_extension report_type
        extension = case report_type.to_sym
                    when :markdown,:md
                      "markdown"
                    when :textile
                      "textile"
                    when :html,:htm
                      "html"
                    else
                      say "WARNING: #{report_type} not a valid type. Defaulting to textile"
                      "textile"
                    end
        extension
      end

      def data_dir
        File.join(DATA_ROOT, options[:id])
      end
    end

  end
end

$:.unshift(File.expand_path('../hastie2',__FILE__))

if RUBY_VERSION =~ /1.9/
  Encoding.default_external = Encoding::UTF_8
  Encoding.default_internal = Encoding::UTF_8
end

#puts $LOAD_PATH

# Most of Hastie functionality is derived from Thor groups.
# Each Thor group is maintained in a separate file.

require 'report_generator'
require 'report_publisher'
require 'report_updater'
require 'server_generator'
require 'config_generator'
require 'report_watcher'
require 'info'
require 'id_maker'
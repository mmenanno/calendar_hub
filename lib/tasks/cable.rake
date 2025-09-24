# frozen_string_literal: true

namespace :db do
  namespace :cable do
    desc "Prepare the cable database by loading db/cable_schema.rb"
    task prepare: :environment do
      path = Rails.root.join("db/cable_schema.rb")
      unless File.exist?(path)
        abort "Missing db/cable_schema.rb; ensure solid_cable is installed and schema present"
      end

      # Establish a temporary connection directly to the cable DB and load schema
      configs = ActiveRecord::Base.configurations
      cable_cfg = if configs.respond_to?(:configs_for)
        cfgs = configs.configs_for(env_name: Rails.env, name: "cable")
        cfgs.is_a?(Array) ? cfgs.first : cfgs
      end
      unless cable_cfg&.respond_to?(:configuration_hash)
        abort "No cable database configuration for #{Rails.env}."
      end

      puts "Loading #{path} into cable database..."
      previous = ActiveRecord::Base.remove_connection
      ActiveRecord::Base.establish_connection(cable_cfg.configuration_hash)
      begin
        load(path)
        puts "Cable DB prepared."
      ensure
        # Restore previous application connection
        if previous
          if previous.respond_to?(:configuration_hash)
            ActiveRecord::Base.establish_connection(previous.configuration_hash)
          else
            ActiveRecord::Base.establish_connection(previous)
          end
        end
      end
      puts "Cable DB prepared."
    end
  end
end

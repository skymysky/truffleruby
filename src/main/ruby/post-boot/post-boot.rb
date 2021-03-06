# Copyright (c) 2016, 2017 Oracle and/or its affiliates. All rights reserved. This
# code is released under a tri EPL/GPL/LGPL license. You can use it,
# redistribute it and/or modify it under the terms of the:
#
# Eclipse Public License version 1.0
# GNU General Public License version 2
# GNU Lesser General Public License version 2.1

Truffle::Boot.delay do
  wd = Truffle::Boot.get_option('working_directory')
  Dir.chdir(wd) unless wd.empty?
end

if Truffle::Boot.ruby_home
  # Always provided features: ruby --disable-gems -e 'puts $"'
  begin
    require 'enumerator'
    require 'thread'
    require 'rational'
    require 'complex'
    require 'unicode_normalize'
    if Truffle::Boot.get_option('patching')
      Truffle::Boot.print_time_metric :'before-patching'
      require 'truffle/patching'
      Truffle::Patching.insert_patching_dir 'stdlib', "#{Truffle::Boot.ruby_home}/lib/mri"
      Truffle::Boot.print_time_metric :'after-patching'
    end
  rescue LoadError => e
    Truffle::Debug.log_warning "#{File.basename(__FILE__)}:#{__LINE__} #{e.message}"
  end

  if Truffle::Boot.get_option 'rubygems'
    Truffle::Boot.delay do
      if Truffle::Boot.resilient_gem_home?
        ENV.delete 'GEM_HOME'
        ENV.delete 'GEM_PATH'
        ENV.delete 'GEM_ROOT'
      end
    end

    begin
      Truffle::Boot.print_time_metric :'before-rubygems'
      begin
        if Truffle::Boot.get_option('rubygems.lazy')
          require 'truffle/lazy-rubygems'
        else
          Truffle::Boot.delay do
            require 'rubygems'
          end
        end
      ensure
        Truffle::Boot.print_time_metric :'after-rubygems'
      end
    rescue LoadError => e
      Truffle::Debug.log_warning "#{File.basename(__FILE__)}:#{__LINE__} #{e.message}"
    else
      Truffle::Boot.delay do
        # TODO (pitr-ch 17-Feb-2017): remove the warning when we can integrate with ruby managers
        if gem_home = ENV['GEM_HOME']
          bad_gem_home = false

          # rbenv does not set GEM_HOME
          # rbenv-gemset has to be installed which does set GEM_HOME, it's in the subdir of Truffle::Boot.ruby_home
          # rbenv/versions/<ruby>/gemsets
          bad_gem_home ||= gem_home.include?('rbenv/versions') && !gem_home.include?('rbenv/versions/truffleruby')

          # rvm stores gems at .rvm/gems/<ruby>@<gemset-name>
          bad_gem_home ||= gem_home.include?('rvm/gems') && !gem_home.include?('rvm/gems/truffleruby')

          # chruby stores gem in ~/.gem/<ruby>/<version>
          bad_gem_home ||= gem_home.include?('.gem') && !gem_home.include?('.gem/truffleruby')

          warn "[ruby] WARN A nonstandard GEM_HOME is set #{gem_home}" if $VERBOSE || bad_gem_home
          if bad_gem_home
            warn "[ruby] WARN The bad GEM_HOME may come from a ruby manager, make sure you've called one of: " +
                     '`rvm use system`, `rbenv system`, or `chruby system` to clear the environment.'
          end
        end
      end

      if Truffle::Boot.get_option 'did_you_mean'
        Truffle::Boot.print_time_metric :'before-did-you-mean'
        begin
          $LOAD_PATH << "#{Truffle::Boot.ruby_home}/lib/ruby/gems/#{Truffle::RUBY_BASE_VERSION}/gems/did_you_mean-1.0.0/lib"
          require 'did_you_mean'
        rescue LoadError => e
          Truffle::Debug.log_warning "#{File.basename(__FILE__)}:#{__LINE__} #{e.message}"
        ensure
          Truffle::Boot.print_time_metric :'after-did-you-mean'
        end
      end
    end
  end
end

# Post-boot patching when using context pre-initialization
if Truffle::Boot.preinitializing?
  old_home = Truffle::Boot.ruby_home
  if old_home
    # We need to fix all paths which capture the image build-time home to point
    # to the runtime home.
    patching_paths = Truffle::Patching.paths_depending_on_home
    Truffle::Boot.delay do
      new_home = Truffle::Boot.ruby_home
      [$LOAD_PATH, $LOADED_FEATURES, patching_paths].each do |array|
        array.each do |path|
          if path.start_with?(old_home)
            path.replace(new_home + path[old_home.size..-1])
          end
        end
      end
    end
  end
end

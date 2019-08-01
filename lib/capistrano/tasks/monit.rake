namespace :load do
    task :defaults do
      set :rpush_monit_conf_dir, '/etc/monit/conf.d'
      set :rpush_monit_conf_file, -> { "#{rpush_service_name}.conf" }
      set :rpush_monit_use_sudo, true
      set :monit_bin, '/usr/bin/monit'
      set :rpush_monit_default_hooks, true
      set :rpush_monit_templates_path, 'config/deploy/templates'
      set :rpush_monit_group, nil
    end
  end

  namespace :deploy do
    before :starting, :check_rpush_monit_hooks do
      if fetch(:rpush_default_hooks) && fetch(:rpush_monit_default_hooks)
        invoke 'rpush:monit:add_default_hooks'
      end
    end
  end

  namespace :rpush do
    namespace :monit do

      task :add_default_hooks do
        before 'deploy:updating',  'rpush:monit:unmonitor'
        after  'deploy:published', 'rpush:monit:monitor'
      end

      desc 'Config Rpush monit-service'
      task :config do
        on roles(fetch(:rpush_roles)) do |role|
          @role = role
          upload_rpush_template 'rpush_monit', "#{fetch(:tmp_dir)}/monit.conf", @role

          mv_command = "mv #{fetch(:tmp_dir)}/monit.conf #{fetch(:rpush_monit_conf_dir)}/#{fetch(:rpush_monit_conf_file)}"
          sudo_if_needed mv_command

          sudo_if_needed "#{fetch(:monit_bin)} reload"
        end
      end

      desc 'Monitor Rpush monit-service'
      task :monitor do
        on roles(fetch(:rpush_roles)) do
          fetch(:rpush_processes).times do |idx|
            begin
              sudo_if_needed "#{fetch(:monit_bin)} monitor #{rpush_service_name(idx)}"
            rescue
              invoke 'rpush:monit:config'
              sudo_if_needed "#{fetch(:monit_bin)} monitor #{rpush_service_name(idx)}"
            end
          end
        end
      end

      desc 'Unmonitor Rpush monit-service'
      task :unmonitor do
        on roles(fetch(:rpush_roles)) do
          fetch(:rpush_processes).times do |idx|
            begin
              sudo_if_needed "#{fetch(:monit_bin)} unmonitor #{rpush_service_name(idx)}"
            rescue
              # no worries here
            end
          end
        end
      end

      desc 'Start Rpush monit-service'
      task :start do
        on roles(fetch(:rpush_roles)) do
          fetch(:rpush_processes).times do |idx|
            sudo_if_needed "#{fetch(:monit_bin)} start #{rpush_service_name(idx)}"
          end
        end
      end

      desc 'Stop Rpush monit-service'
      task :stop do
        on roles(fetch(:rpush_roles)) do
          fetch(:rpush_processes).times do |idx|
            sudo_if_needed "#{fetch(:monit_bin)} stop #{rpush_service_name(idx)}"
          end
        end
      end

      desc 'Restart Rpush monit-service'
      task :restart do
        on roles(fetch(:rpush_roles)) do
          fetch(:rpush_processes).times do |idx|
            sudo_if_needed"#{fetch(:monit_bin)} restart #{rpush_service_name(idx)}"
          end
        end
      end

      def rpush_service_name(index=nil)
        fetch(:rpush_service_name, "rpush_#{fetch(:application)}_#{fetch(:rpush_env)}") + (index ? "_#{index}" : '')
      end

      def rpush_config
        if fetch(:rpush_config)
          "--config #{fetch(:rpush_config)}"
        end
      end

      def rpush_concurrency
        if fetch(:rpush_concurrency)
          "--concurrency #{fetch(:rpush_concurrency)}"
        end
      end

      def rpush_queues
        Array(fetch(:rpush_queue)).map do |queue|
          "--queue #{queue}"
        end.join(' ')
      end

      def rpush_logfile
        if fetch(:rpush_log)
          "--logfile #{fetch(:rpush_log)}"
        end
      end

      def rpush_require
        if fetch(:rpush_require)
          "--require #{fetch(:rpush_require)}"
        end
      end

      def rpush_options_per_process
        fetch(:rpush_options_per_process) || []
      end

      def sudo_if_needed(command)
        send(use_sudo? ? :sudo : :execute, command)
      end

      def use_sudo?
        fetch(:rpush_monit_use_sudo)
      end

      def upload_rpush_template(from, to, role)
        template = rpush_template(from, role)
        upload!(StringIO.new(ERB.new(template).result(binding)), to)
      end

      def rpush_template(name, role)
        local_template_directory = fetch(:rpush_monit_templates_path)

        search_paths = [
          "#{name}-#{role.hostname}-#{fetch(:stage)}.erb",
          "#{name}-#{role.hostname}.erb",
          "#{name}-#{fetch(:stage)}.erb",
          "#{name}.erb"
        ].map { |filename| File.join(local_template_directory, filename) }

        global_search_path = File.expand_path(
          File.join(*%w[.. .. .. generators capistrano rpush monit templates], "#{name}.conf.erb"),
          __FILE__
        )

        search_paths << global_search_path

        template_path = search_paths.detect { |path| File.file?(path) }
        File.read(template_path)
      end
    end
  end
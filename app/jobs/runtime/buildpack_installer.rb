module VCAP::CloudController
  module Jobs
    module Runtime
      class BuildpackInstaller < VCAP::CloudController::Jobs::CCJob

        class InstallError < StandardError; end
        class DuplicateInstallError < StandardError; end
        class StacklessBuildpackIncompatibilityError < StandardError; end

        CREATE_BUILDPACK = 'create'.freeze
        UPGRADE_BUILDPACK = 'upgrade'.freeze

        attr_accessor :buildpack_name, :buildpack_stack, :buildpack_file, :opts, :action

        # private_class_method :new
        def initialize(options)
          @buildpack_name = options[:name]
          @buildpack_stack = stack
          @buildpack_file = file
          @buildpack_opts = opts
          @action = action
        end


        ## HEY NERDS!
        #
        - consider moving plan to an options factory so we can test all params before they go do BuildpackInstaller.new
        - existing_plan becomes an instance variable on the factory

        # plan is not threadsafe
        def self.plan(name, file, opts, existing_plan: []) # this should be a set of some kind?
          found_buildpacks = Buildpack.where(name: name).all
          if found_buildpacks.empty?
            return new(name, nil, file, opts, CREATE_BUILDPACK)
          end

          found_buildpack = found_buildpacks.first

          detected_stack = VCAP::CloudController::Buildpacks::StackNameExtractor.extract_from_file(file)

          # upgrading from nil, but we've already planned to upgrade the nil entry
          if found_buildpack.stack.nil? && detected_stack && existing_plan.include?(found_buildpack)
            return new(name, nil, file, opts, CREATE_BUILDPACK)
          end

          if existing_plan.include?(found_buildpack) && found_buildpack.stack == detected_stack
            raise DuplicateInstallError.new
          end

          if detected_stack.nil? && found_buildpack.stack
            raise StacklessBuildpackIncompatibilityError.new 'Existing buildpack must be upgraded with a buildpack that has a stack.'
          end

          return new(name, nil, file, opts, UPGRADE_BUILDPACK)
        end

        def perform #
          logger = Steno.logger('cc.background')
          logger.info "Installing buildpack #{name}"

          buildpacks = find_existing_buildpacks
          if buildpacks.count > 1
            logger.error "Update failed: Unable to determine buildpack to update as there are multiple buildpacks named #{name} for different stacks."
            return
          end

          buildpack = buildpacks.first
          if buildpack&.locked
            logger.info "Buildpack #{name} locked, not updated"
            return
          end

          created = false
          if buildpack.nil?
            buildpacks_lock = Locking[name: 'buildpacks']
            buildpacks_lock.db.transaction do
              buildpacks_lock.lock!
              buildpack = Buildpack.create(name: name)
            end
            created = true
          end

          begin
            buildpack_uploader.upload_buildpack(buildpack, file, File.basename(file))
          rescue => e
            if created
              buildpack.destroy
            end
            raise e
          end

          buildpack.update(opts)
          logger.info "Buildpack #{name} installed or updated"
        rescue => e
          logger.error("Buildpack #{name} failed to install or update. Error: #{e.inspect}")
          raise e
        end

        def max_attempts
          1
        end

        def job_name_in_configuration
          :buildpack_installer
        end

        def buildpack_uploader
          buildpack_blobstore = CloudController::DependencyLocator.instance.buildpack_blobstore
          UploadBuildpack.new(buildpack_blobstore)
        end

        private

        def find_existing_buildpacks
          stack = VCAP::CloudController::Buildpacks::StackNameExtractor.extract_from_file(file)
          if stack.present?
            buildpacks_by_stack = Buildpack.where(name: name, stack: stack)
            return buildpacks_by_stack if buildpacks_by_stack.any?
            return Buildpack.where(name: name, stack: nil)
            # XTEAM: We were reconsidering whether or not we should overwrite buildpacks of unknown stack during install
          end

          Buildpack.where(name: name)
        end
      end
    end
  end
end

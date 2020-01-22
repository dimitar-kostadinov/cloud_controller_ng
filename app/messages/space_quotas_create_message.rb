require 'messages/metadata_base_message'
require 'messages/validators'

module VCAP::CloudController
  class SpaceQuotasCreateMessage < BaseMessage
    MAX_SPACE_QUOTA_NAME_LENGTH = 250

    def self.key_requested?(key)
      proc { |a| a.requested?(key) }
    end

    register_allowed_keys [:name, :relationships, :apps, :services, :routes]
    validates_with NoAdditionalKeysValidator
    validates_with RelationshipValidator

    validates :name,
      string: true,
      presence: true,
      length: { maximum: MAX_SPACE_QUOTA_NAME_LENGTH }

    validate :apps_validator, if: key_requested?(:apps)
    validate :services_validator, if: key_requested?(:services)
    validate :routes_validator, if: key_requested?(:routes)

    delegate :total_memory_in_mb, :per_process_memory_in_mb, :total_instances, :per_app_tasks, to: :apps_limits_message
    delegate :paid_services_allowed, :total_service_instances, :total_service_keys, to: :services_limits_message
    delegate :total_routes, :total_reserved_ports, to: :routes_limits_message

    def validates_hash(key, sym)
      return true if key.is_a?(Hash)

      errors[sym].concat(['must be an object'])
      false
    end

    def apps_validator
      return unless validates_hash(apps, :apps)

      errors[:apps].concat(apps_limits_message.errors.full_messages) unless apps_limits_message.valid?
    end

    def apps_limits_message
      @apps_limits_message ||= QuotasAppsMessage.new(apps&.deep_symbolize_keys)
    end

    def services_validator
      return unless validates_hash(services, :services)

      errors[:services].concat(services_limits_message.errors.full_messages) unless services_limits_message.valid?
    end

    def services_limits_message
      @services_limits_message ||= QuotasServicesMessage.new(services&.deep_symbolize_keys)
    end

    def routes_validator
      return unless validates_hash(routes, :routes)

      errors[:routes].concat(routes_limits_message.errors.full_messages) unless routes_limits_message.valid?
    end

    def routes_limits_message
      @routes_limits_message ||= QuotasRoutesMessage.new(routes&.deep_symbolize_keys)
    end

    # Relationships validations
    delegate :organization_guid, to: :relationships_message
    delegate :space_guids, to: :relationships_message

    def relationships_message
      @relationships_message ||= Relationships.new(relationships&.deep_symbolize_keys)
    end

    class Relationships < BaseMessage
      register_allowed_keys [:organization, :spaces]

      validates :organization, allow_nil: false, to_one_relationship: true
      validates :spaces, allow_nil: true, to_many_relationship: true

      def initialize(params)
        super(params)
      end

      def organization_guid
        HashUtils.dig(organization, :data, :guid)
      end

      def space_guids
        space_data = HashUtils.dig(spaces, :data)
        space_data ? space_data.map { |space| space[:guid] } : []
      end
    end
  end
end

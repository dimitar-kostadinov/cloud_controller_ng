module VCAP::CloudController
  class ServiceOfferingListFetcher
    def fetch(message)
      dataset = Service.dataset.
                join(:service_brokers, id: Sequel[:services][:service_broker_id]).
                left_join(:service_plans, service_id: Sequel[:services][:id]).
                left_join(:spaces, id: Sequel[:service_brokers][:space_id]).
                left_join(:organizations, id: Sequel[:spaces][:organization_id]).
                group(Sequel[:services][:id]).
                select_all(:services)

      dataset = filter(message, dataset)

      return dataset unless message.requested?(:organization_guids)

      dataset_with_visibilities(dataset, message)
    end

    def fetch_public(message)
      dataset = Service.dataset.
                join(:service_plans, service_id: Sequel[:services][:id]).
                join(:service_brokers, id: Sequel[:services][:service_broker_id]).
                left_join(:spaces, id: Sequel[:service_brokers][:space_id]).
                left_join(:organizations, id: Sequel[:spaces][:organization_id]).
                where { Sequel[:service_plans][:public] =~ true }.
                group(Sequel[:services][:id]).
                select_all(:services)

      filter(message, dataset)
    end

    def fetch_visible(message, org_guids, space_guids)
      dataset = Service.dataset.
                left_join(:service_plans, service_id: Sequel[:services][:id]).
                join(:service_brokers, id: Sequel[:services][:service_broker_id]).
                left_join(:spaces, id: Sequel[:service_brokers][:space_id]).
                left_join(:service_plan_visibilities, service_plan_id: Sequel[:service_plans][:id]).
                left_join(:organizations, id: Sequel[:service_plan_visibilities][:organization_id]).
                where do
                  (Sequel[:organizations][:guid] =~ org_guids) |
                  (Sequel[:service_plans][:public] =~ true) |
                  (Sequel[:spaces][:guid] =~ space_guids)
                end.
                group(Sequel[:services][:id]).
                select_all(:services)

      filter(message, dataset)
    end

    private

    def dataset_with_visibilities(dataset, message)
      dataset_with_visibilities = Service.dataset.
                                  join(:service_brokers, id: Sequel[:services][:service_broker_id]).
                                  join(:service_plans, service_id: Sequel[:services][:id]).
                                  left_join(:spaces, id: Sequel[:service_brokers][:space_id]).
                                  join(:service_plan_visibilities, service_plan_id: Sequel[:service_plans][:id]).
                                  join(:organizations, id: Sequel[:service_plan_visibilities][:organization_id]).
                                  select_all(:services)

      dataset_with_visibilities = filter(message, dataset_with_visibilities)

      dataset.union(dataset_with_visibilities, alias: :services)
    end

    def filter(message, dataset)
      if message.requested?(:available)
        dataset = dataset.where(Sequel[:services][:active] =~ string_to_boolean(message.available))
      end

      if message.requested?(:service_broker_guids)
        dataset = dataset.where(Sequel[:service_brokers][:guid] =~ message.service_broker_guids)
      end

      if message.requested?(:service_broker_names)
        dataset = dataset.where(Sequel[:service_brokers][:name] =~ message.service_broker_names)
      end

      if message.requested?(:names)
        dataset = dataset.where(Sequel[:services][:label] =~ message.names)
      end

      if message.requested?(:space_guids)
        dataset = dataset.where((Sequel[:spaces][:guid] =~ message.space_guids) | (Sequel[:service_plans][:public] =~ true))
      end

      if message.requested?(:organization_guids)
        dataset = dataset.where((Sequel[:organizations][:guid] =~ message.organization_guids) | (Sequel[:service_plans][:public] =~ true))
      end

      if message.requested?(:label_selector)
        dataset = LabelSelectorQueryGenerator.add_selector_queries(
          label_klass: ServiceOfferingLabelModel,
          resource_dataset: dataset,
          requirements: message.requirements,
          resource_klass: Service,
        )
      end

      dataset
    end

    def string_to_boolean(value)
      value == 'true'
    end
  end
end

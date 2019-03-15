require 'spec_helper'
require 'fetchers/package_list_fetcher'

module VCAP::CloudController
  RSpec.describe PackageListFetcher do
    let(:space1) { FactoryBot.create(:space) }
    let(:space2) { FactoryBot.create(:space) }
    let(:space3) { FactoryBot.create(:space) }
    let(:org_1_guid) { space1.organization.guid }
    let(:org_2_guid) { space2.organization.guid }
    let(:org_3_guid) { space3.organization.guid }
    let(:app1_in_space1) { FactoryBot.create(:app, space: space1) }
    let(:app2_in_space1) { FactoryBot.create(:app, space: space1) }
    let(:app3_in_space2) { FactoryBot.create(:app, space: space2) }
    let(:app4_in_space3) { FactoryBot.create(:app, space: space3) }

    let!(:package_in_space1) { FactoryBot.create(:package, app_guid: app1_in_space1.guid, type: PackageModel::BITS_TYPE, state: PackageModel::FAILED_STATE) }
    let!(:package2_in_space1) { FactoryBot.create(:package, app_guid: app1_in_space1.guid, type: PackageModel::DOCKER_TYPE, state: PackageModel::READY_STATE) }
    let!(:package_in_space3) { FactoryBot.create(:package, app_guid: app4_in_space3.guid, type: PackageModel::DOCKER_TYPE, state: PackageModel::FAILED_STATE) }

    let!(:package_for_app2) { FactoryBot.create(:package, app_guid: app2_in_space1.guid, type: PackageModel::DOCKER_TYPE, state: PackageModel::CREATED_STATE) }
    let!(:package_for_app3) { FactoryBot.create(:package, app_guid: app3_in_space2.guid, type: PackageModel::BITS_TYPE) }

    subject(:fetcher) { PackageListFetcher.new }
    let(:message) { PackagesListMessage.from_params(filters) }

    let(:filters) { {} }

    results = nil

    describe '#fetch_all' do
      before do
        results = fetcher.fetch_all(message: message)
      end
      it 'returns a Sequel::Dataset' do
        expect(results).to be_a(Sequel::Dataset)
      end

      it 'returns all of the packages' do
        expect(results.all).to match_array([package_in_space1, package2_in_space1, package_for_app2, package_for_app3, package_in_space3])
      end

      describe 'filtering on messages' do
        context 'filtering types' do
          let(:filters) { { types: [PackageModel::BITS_TYPE] } }

          it 'returns all of the packages with the requested types' do
            expect(results.all).to match_array([package_in_space1, package_for_app3])
          end
        end

        context 'filtering states' do
          let(:filters) { { states: [PackageModel::READY_STATE, PackageModel::FAILED_STATE] } }

          it 'returns all of the packages with the requested states' do
            expect(results.all).to match_array([package_in_space1, package2_in_space1, package_in_space3])
          end
        end

        context 'filtering app guids' do
          let(:filters) { { app_guids: [app1_in_space1.guid, app3_in_space2.guid] } }

          it 'returns all the packages associated with the requested app guid' do
            expect(results.all).to match_array([package_in_space1, package2_in_space1, package_for_app3])
          end
        end

        context 'filtering package guids' do
          let(:filters) { { guids: [package_for_app2.guid, package_for_app3.guid] } }

          it 'returns all the packages associated with the requested app guid' do
            expect(results.all).to match_array([package_for_app2, package_for_app3])
          end
        end

        context 'filtering space_guids' do
          let(:filters) { { space_guids: [space1.guid, space2.guid] } }

          it 'returns all the packages associated with the requested app guid' do
            expect(results.all).to match_array([package_in_space1, package2_in_space1, package_for_app2, package_for_app3])
          end
        end

        context 'filtering org guids' do
          let(:filters) { { organization_guids: [org_2_guid, org_3_guid] } }

          it 'returns the correct set of packages' do
            expect(results.all).to match_array([package_in_space3, package_for_app3])
          end
        end

        context 'filtering label selectors' do
          let(:filters) { { 'label_selector' => 'key=value' } }
          let!(:label) { PackageLabelModel.make(resource_guid: package_for_app3.guid, key_name: 'key', value: 'value') }

          it 'returns the correct set of packages' do
            expect(results.all).to match_array([package_for_app3])
          end
        end
      end
    end

    describe '#fetch_for_spaces' do
      before do
        results = fetcher.fetch_for_spaces(message: message, space_guids: [space1.guid, space3.guid])
      end
      it 'returns a Sequel::Dataset' do
        expect(results).to be_a(Sequel::Dataset)
      end

      it 'returns only the packages in spaces requested' do
        expect(results.all).to match_array([package_in_space1, package2_in_space1, package_for_app2, package_in_space3])
      end

      describe 'filtering on messages' do
        context 'filtering types' do
          let(:filters) { { types: [PackageModel::BITS_TYPE] } }

          it 'returns all of the packages with the requested types' do
            expect(results.all).to match_array([package_in_space1])
          end
        end

        context 'filtering states' do
          let(:filters) { { states: [PackageModel::CREATED_STATE, PackageModel::READY_STATE] } }

          it 'returns all of the packages with the requested states' do
            expect(results.all).to match_array([package2_in_space1, package_for_app2])
          end
        end

        context 'filtering app guids' do
          let(:filters) { { app_guids: [app1_in_space1.guid] } }

          it 'returns all the packages associated with the requested app guid' do
            expect(results.all).to match_array([package_in_space1, package2_in_space1])
          end
        end

        context 'filtering package guids' do
          let(:filters) { { guids: [package_in_space1.guid, package2_in_space1.guid] } }

          it 'returns all the packages associated with the requested app guid' do
            expect(results.all).to match_array([package_in_space1, package2_in_space1])
          end
        end

        context 'filtering space guids' do
          let(:filters) { { space_guids: [space3.guid] } }

          it 'returns all the packages associated with the requested space guid' do
            expect(results.all).to match_array([package_in_space3])
          end
        end

        context 'filtering org guids' do
          let(:filters) { { organization_guids: [org_2_guid, org_3_guid] } }

          it 'returns the correct set of packages' do
            expect(results.all).to match_array([package_in_space3])
          end
        end
      end
    end

    describe '#fetch_for_app' do
      returned_app = nil

      before do
        returned_app, results = fetcher.fetch_for_app(message: message)
      end
      let(:filters) { { app_guid: app1_in_space1.guid } }

      it 'returns a Sequel::Dataset and the app' do
        expect(results).to be_a(Sequel::Dataset)
        expect(returned_app.guid).to eq(app1_in_space1.guid)
      end

      it 'returns only the packages for the app requested' do
        expect(results.all).to match_array([package_in_space1, package2_in_space1])
      end

      describe 'filtering on messages' do
        context 'filtering types' do
          let(:filters) { { types: [PackageModel::BITS_TYPE], app_guid: app1_in_space1.guid } }

          it 'returns all of the packages with the requested types' do
            expect(results.all).to match_array([package_in_space1])
          end
        end

        context 'filtering states' do
          let(:filters) { { states: [PackageModel::CREATED_STATE, PackageModel::READY_STATE], app_guid: app1_in_space1.guid } }

          it 'returns all of the packages with the requested states' do
            expect(results.all).to match_array([package2_in_space1])
          end
        end

        context 'filtering package guids' do
          let(:filters) { { guids: [package_in_space1.guid, package2_in_space1.guid], app_guid: app1_in_space1.guid } }

          it 'returns all the packages associated with the requested app guid' do
            expect(results.all).to match_array([package_in_space1, package2_in_space1])
          end
        end

        context 'when the app does not exist' do
          let(:filters) { { app_guid: 'not a real guid' } }
          it 'returns nil' do
            expect(results).to be_nil
            expect(returned_app).to be_nil
          end
        end
      end
    end
  end
end

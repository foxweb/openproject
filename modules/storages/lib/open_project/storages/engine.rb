# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) 2012-2024 the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

# See also: Getting started with Engines: https://guides.rubyonrails.org/engines.html
# This file got generated by the open_project:plugin generator.
# It is loaded by `modules/storages/lib/open_project/storages.rb` when the plugin
# gets loaded.
module OpenProject::Storages
  class Engine < ::Rails::Engine
    def self.permissions
      @permissions ||= Storages::NextcloudGroupFolderPropertiesSyncService::PERMISSIONS_KEYS
    end

    # engine name is used as a default prefix for module tables when generating
    # tables with the rails command.
    # It may also be used in other places, please investigate.
    engine_name :openproject_storages

    # please see comments inside ActsAsOpEngine class
    include OpenProject::Plugins::ActsAsOpEngine

    initializer "openproject_storages.feature_decisions" do
      OpenProject::FeatureDecisions.add :storage_file_picking_select_all
    end

    initializer "openproject_storages.event_subscriptions" do
      Rails.application.config.after_initialize do
        [
          OpenProject::Events::MEMBER_CREATED,
          OpenProject::Events::MEMBER_UPDATED,
          OpenProject::Events::MEMBER_DESTROYED,
          OpenProject::Events::PROJECT_UPDATED,
          OpenProject::Events::PROJECT_RENAMED,
          OpenProject::Events::PROJECT_ARCHIVED,
          OpenProject::Events::PROJECT_UNARCHIVED
        ].each do |event|
          OpenProject::Notifications.subscribe(event) do |_payload|
            ::Storages::ManageNextcloudIntegrationJob.debounce
          end
        end

        OpenProject::Notifications.subscribe(
          OpenProject::Events::OAUTH_CLIENT_TOKEN_CREATED
        ) do |payload|
          if payload[:integration_type] == "Storages::Storage"
            ::Storages::ManageNextcloudIntegrationJob.debounce
          end
        end

        OpenProject::Notifications.subscribe(
          OpenProject::Events::ROLE_UPDATED
        ) do |payload|
          if payload[:permissions_diff]&.intersect?(OpenProject::Storages::Engine.permissions)
            ::Storages::ManageNextcloudIntegrationJob.debounce
          end
        end

        OpenProject::Notifications.subscribe(
          OpenProject::Events::ROLE_DESTROYED
        ) do |payload|
          if payload[:permissions]&.intersect?(OpenProject::Storages::Engine.permissions)
            ::Storages::ManageNextcloudIntegrationJob.debounce
          end
        end

        [
          OpenProject::Events::PROJECT_STORAGE_CREATED,
          OpenProject::Events::PROJECT_STORAGE_UPDATED,
          OpenProject::Events::PROJECT_STORAGE_DESTROYED
        ].each do |event|
          OpenProject::Notifications.subscribe(event) do |payload|
            if payload[:project_folder_mode] == :automatic
              ::Storages::ManageNextcloudIntegrationJob.debounce
              ::Storages::ManageNextcloudIntegrationJob.disable_cron_job_if_needed
            end
          end
        end

        OpenProject::Notifications.subscribe(
          ::OpenProject::Events::STORAGE_TURNED_UNHEALTHY
        ) do |payload|
          Storages::HealthService.new(storage: payload[:storage]).unhealthy(reason: payload[:reason])
        end

        OpenProject::Notifications.subscribe(
          ::OpenProject::Events::STORAGE_TURNED_HEALTHY
        ) do |payload|
          Storages::HealthService.new(storage: payload[:storage]).healthy
        end
      end
    end

    # For documentation see the definition of register in "ActsAsOpEngine"
    # This corresponds to the openproject-storage.gemspec
    # Pass a block to the plugin (for defining permissions, menu items and the like)
    register "openproject-storages",
             author_url: "https://www.openproject.org",
             bundled: true,
             settings: {} do
      # Defines permission constraints used in the module (controller, etc.)
      # Permissions documentation: https://www.openproject.org/docs/development/concepts/permissions/#definition-of-permissions
      # Independent of storages module (Disabling storages module does not revoke enabled permissions).
      project_module nil, order: 100 do
        permission :manage_storages_in_project,
                   { "storages/admin/project_storages": %i[index members new
                                                           edit update create oauth_access_grant
                                                           destroy destroy_info set_permissions],
                     "storages/project_settings/project_storage_members": %i[index] },
                   permissible_on: :project,
                   dependencies: %i[]
      end

      # Dependent on work_package_tracking module
      project_module :work_package_tracking do
        permission :view_file_links,
                   {},
                   permissible_on: :project,
                   dependencies: %i[view_work_packages],
                   contract_actions: { file_links: %i[view] }
        permission :manage_file_links,
                   {},
                   permissible_on: :project,
                   dependencies: %i[view_file_links],
                   contract_actions: { file_links: %i[manage] }
      end

      # Dependent on storages module (Disabling storages module does revoke enabled permissions).
      project_module :storages,
                     dependencies: :work_package_tracking do
        OpenProject::Storages::Engine.permissions.each do |p|
          permission(p, {}, permissible_on: :project, dependencies: %i[])
        end
      end

      # Menu extensions
      # Add a "storages_admin_settings" to the admin_menu with the specified link,
      # condition ("if:"), caption and icon.
      menu :admin_menu,
           :files,
           { controller: "/storages/admin/storages", action: :index },
           if: Proc.new { User.current.admin? },
           caption: :project_module_storages,
           icon: "hosting"

      menu :admin_menu,
           :external_file_storages,
           { controller: "/storages/admin/storages", action: :index },
           if: Proc.new { User.current.admin? },
           caption: :external_file_storages,
           parent: :files

      menu :admin_menu,
           :attachments,
           { controller: "/admin/settings/attachments_settings", action: :show },
           if: Proc.new { User.current.admin? },
           caption: :"attributes.attachments",
           parent: :files

      menu :project_menu,
           :settings_project_storages,
           { controller: "/storages/admin/project_storages", action: "index" },
           if: lambda { |project| User.current.allowed_in_project?(:manage_storages_in_project, project) },
           caption: :project_module_storages,
           parent: :settings

      configure_menu :project_menu do |menu, prj|
        u = User.current
        if prj.present? && u.logged? && u.member_of?(prj) && u.allowed_in_project?(:view_file_links, prj)
          prj.project_storages.each do |prj_storage|
            storage = prj_storage.storage
            hide_from_menu = !storage.configured? ||
                             # the following check is required for ensure access modal final check being possible
                             # the modal waiting for read_files permission on the project folder
                             # otherwise polls backend until eternity
                             (prj_storage.project_folder_automatic? && !u.allowed_in_project?(:read_files, prj))
            next if hide_from_menu

            icon = storage.provider_type_nextcloud? ? "nextcloud-circle" : "hosting"
            menu.push(
              :"storage_#{storage.id}",
              prj_storage.open_with_connection_ensured,
              caption: storage.name,
              before: :members,
              icon:,
              icon_after: "external-link",
              skip_permissions_check: true
            )
          end
        end
      end
    end

    patch_with_namespace :Principals, :ReplaceReferencesService

    # This hook is executed when the module is loaded.
    config.to_prepare do
      # Allow the browser to connect to external servers for direct file uploads.
      AppendStoragesHostsToCspHook

      # We have a bunch of filters defined within the module. Here we register the filters.
      ::Queries::Register.register(::Query) do
        [
          ::Queries::Storages::WorkPackages::Filter::FileLinkOriginIdFilter,
          ::Queries::Storages::WorkPackages::Filter::StorageIdFilter,
          ::Queries::Storages::WorkPackages::Filter::StorageUrlFilter,
          ::Queries::Storages::WorkPackages::Filter::LinkableToStorageIdFilter,
          ::Queries::Storages::WorkPackages::Filter::LinkableToStorageUrlFilter
        ].each do |filter|
          filter filter
          exclude filter
        end

        ::Queries::Register.register(::Queries::Projects::ProjectQuery) do
          filter ::Queries::Storages::Projects::Filter::StorageIdFilter
          filter ::Queries::Storages::Projects::Filter::StorageUrlFilter
        end

        ::Queries::Register.register(::Queries::Storages::FileLinks::FileLinkQuery) do
          filter ::Queries::Storages::FileLinks::Filter::StorageFilter
        end

        ::Queries::Register.register(::Queries::Storages::ProjectStorages::ProjectStoragesQuery) do
          filter ::Queries::Storages::ProjectStorages::Filter::StorageIdFilter
          filter ::Queries::Storages::ProjectStorages::Filter::StorageUrlFilter
          filter ::Queries::Storages::ProjectStorages::Filter::ProjectIdFilter
        end
      end
    end

    # This helper methods adds a method on the `api_v3_paths` helper. It is created with one parameter (storage_id)
    # and the return value is a string.
    add_api_path :storages do
      "#{root}/storages"
    end

    add_api_path :project_storages do
      "#{root}/project_storages"
    end

    add_api_path :project_storage do |id|
      "#{project_storages}/#{id}"
    end

    add_api_path :project_storage_open do |id|
      "#{project_storage(id)}/open"
    end

    add_api_path :storage do |storage_id|
      "#{storages}/#{storage_id}"
    end

    add_api_path :storage_open do |storage_id|
      "#{storage(storage_id)}/open"
    end

    add_api_path :storage_files do |storage_id|
      "#{storage(storage_id)}/files"
    end

    add_api_path :storage_file do |storage_id, file_id|
      "#{storage_files(storage_id)}/#{file_id}"
    end

    add_api_path :prepare_upload do |storage_id|
      "#{storage(storage_id)}/files/prepare_upload"
    end

    add_api_path :storage_oauth_client_credentials do |storage_id|
      "#{storage(storage_id)}/oauth_client_credentials"
    end

    add_api_path :file_links do |work_package_id|
      "#{work_package(work_package_id)}/file_links"
    end

    add_api_path :file_link do |file_link_id|
      "#{root}/file_links/#{file_link_id}"
    end

    add_api_path :file_link_download do |file_link_id|
      "#{file_link(file_link_id)}/download"
    end

    add_api_path :file_link_open do |file_link_id, location = false|
      "#{file_link(file_link_id)}/open#{location ? '?location=true' : ''}"
    end

    # Add api endpoints specific to this module
    add_api_endpoint "API::V3::Root" do
      mount ::API::V3::Storages::StoragesAPI
      mount ::API::V3::ProjectStorages::ProjectStoragesAPI
      mount ::API::V3::FileLinks::FileLinksAPI
    end

    add_api_endpoint "API::V3::WorkPackages::WorkPackagesAPI", :id do
      mount ::API::V3::FileLinks::WorkPackagesFileLinksAPI
    end

    add_cron_jobs do
      {
        "Storages::CleanupUncontaineredFileLinksJob": {
          cron: "06 22 * * *",
          class: ::Storages::CleanupUncontaineredFileLinksJob.name
        },

        "Storages::ManageNextcloudIntegrationJob": {
          cron: "1 * * * *",
          class: ::Storages::ManageNextcloudIntegrationJob.name
        }
      }
    end
  end
end

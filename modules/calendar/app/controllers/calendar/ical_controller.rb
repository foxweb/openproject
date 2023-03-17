#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) 2012-2023 the OpenProject GmbH
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

module ::Calendar
  class IcalController < ApplicationController
    def ical
      begin
        call = ::Calendar::IcalResponseService.new.call(
          ical_token: params[:ical_token],
          query_id: params[:id]
        )
      rescue ActiveRecord::RecordNotFound
        render_404
        return
      end

      if call.present? && call.success?
        send_data call.result, filename: "openproject_calendar_#{DateTime.now.to_i}.ics"
        # render plain: call.result # TODO: remove this, it's just handy for development debugging
      else
        render_404
      end
    end
  end
end

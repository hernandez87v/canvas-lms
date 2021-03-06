# frozen_string_literal: true

#
# Copyright (C) 2016 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

module DataFixup::MoveSubAccountGradingPeriodsToCourses
  def self.run
    move_sub_account_periods_to_courses_without_grading_periods
    destroy_sub_account_grading_period_groups_and_grading_periods
  end

  def self.move_sub_account_periods_to_courses_without_grading_periods
    Account.root_accounts.active.non_shadow.find_each do |root_account|
      check_if_account_periods_need_copying(root_account)
    end
  end

  def self.check_if_account_periods_need_copying(account, current_grading_period_group = nil)
    unless account.root_account?
      groups = GradingPeriodGroup.active.where(account_id: account.id)
      if groups.exists?
        current_grading_period_group = groups.first
      end
    end

    if current_grading_period_group && current_grading_period_group.grading_periods.active.exists?
      copy_periods_to_courses_under_account(account, current_grading_period_group)
    end

    account.sub_accounts.find_each do |sub_account|
      check_if_account_periods_need_copying(sub_account, current_grading_period_group)
    end
  end

  def self.copy_periods_to_courses_under_account(account, current_grading_period_group)
    account.courses.find_each do |course|
      next if course.grading_periods.active.exists?

      copy_periods_to_course(course, current_grading_period_group)
    end
  end

  def self.copy_periods_to_course(course, current_grading_period_group)
    group = course.grading_period_groups.active.first_or_create!
    current_grading_period_group.grading_periods.active.each do |period|
      group.grading_periods << period.dup
    end
  end

  def self.destroy_sub_account_grading_period_groups_and_grading_periods
    account_subquery = Account.non_root_accounts
    groups = GradingPeriodGroup.active.where(account_id: account_subquery)
    groups.find_ids_in_batches do |group_ids_chunk|
      GradingPeriodGroup.where(id: group_ids_chunk).update_all(workflow_state: "deleted")
      GradingPeriod.where(grading_period_group_id: group_ids_chunk).update_all(workflow_state: "deleted")
    end
  end
end

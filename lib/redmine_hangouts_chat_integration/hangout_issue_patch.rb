require_dependency 'journal'

module RedmineHangoutsChatIntegration
  module IssuePatch
    include IssuesHelper
    def self.included(base) # :nodoc:
      base.extend(ClassMethods)
      base.send(:include, InstanceMethods)

      base.class_eval do
        after_create :hangout_issue_add
      end
    end

    module ClassMethods
    end
    module InstanceMethods
    end

    def hangout_before_save
    end

    def hangout_issue_add
      send_hangout_issue_add(self)
    end

    private

    def send_hangout_issue_add(issue)
      return if is_disabled(User.current)

      ## Is private issue
      journal = issue.current_journal
      return if issue.is_private
      # return if journal.private_notes

      ## Get issue URL
      issue_url = get_object_url(issue)

      ## Get Webhook URL
      webhook_url = get_webhook_url(issue.project)
      return if webhook_url.nil?

      ## Make Webhook Thread URL
      thread_key = Digest::MD5.hexdigest(issue_url)
      thread_url = webhook_url + "&thread_key=" + thread_key
      return unless thread_url =~ URI::regexp

      ## webhook data
      data = {}

      ## Add issue updated_on
      data['text'] = "*#{l(:field_updated_on)}:#{issue.updated_on}*"

      ## Add issue subject
      subject = issue.subject.gsub(/[　|\s|]+$/, "")
      data['text'] = data['text'] + "\n*#{l(:field_subject)}:<#{issue_url}|[#{issue.project.name} - #{issue.tracker.name} ##{issue.id}] #{subject}>*"

      ## Add issue URL
      data['text'] = data['text'] + "\n*URL:* #{issue_url}"

      ## Add issue author
      data['text'] = data['text'] + "\n```" + l(:text_issue_updated, :id => "##{issue.id}", :author => issue.author)

      ## Add issue details
      # details = details_to_strings(journal.visible_details, true).join("\n")
      # unless details.blank?
      #   data['text'] = data['text'] + "\n#{''.ljust(37, '-')}\n#{details}"
      # end
      data['text'] = data['text'] + "\n#{issue.description}\n"

      ## Add issue notes
      unless issue.notes.blank?
        data['text'] = data['text'] + "\n#{''.ljust(37, '-')}\n#{issue.notes}"
      end

      ## Add ```
      data['text'] = data['text'] + "\n```"

      ## Don't send empty data
      # return if details.blank? && issue.notes.blank?

      ## Send webhook data
      send_webhook_data(thread_url, data)
    end

################################################################################
## Get Redmine Object URL
################################################################################
    def get_object_url(obj)
      routes = Rails.application.routes.url_helpers
      if Setting.host_name.to_s =~ /\A(https?\:\/\/)?(.+?)(\:(\d+))?(\/.+)?\z/i
        host, port, prefix = $2, $4, $5
        routes.url_for(obj.event_url({
                                         :host => host,
                                         :protocol => Setting.protocol,
                                         :port => port,
                                         :script_name => prefix
                                     }))
      else
        routes.url_for(obj.event_url({
                                         :host => Setting.host_name,
                                         :protocol => Setting.protocol
                                     }))
      end
    end

################################################################################
## Is Hangouts Chat Disabled
################################################################################
    def is_disabled(user)
      ## check user
      return true if user.nil?

      ## check user custom field
      user_cf = UserCustomField.find_by_name("Hangouts Chat Disabled")
      return true if user_cf.nil?

      ## check user custom value
      user_cv = user.custom_value_for(user_cf)

      ## user_cv is null
      return false if user_cv.nil?

      return false if user_cv.value == '0'

      return true
    end

################################################################################
## Get Hangouts Chat Webhook URL
################################################################################
    def get_webhook_url(proj)
      ## used value from this plugin's setting
      if proj.nil?
        return Setting.plugin_redmine_hangouts_chat_integration['hangouts_chat_webhook']
      end

      ## used value from this project's custom field
      proj_cf = ProjectCustomField.find_by_name("Hangouts Chat Webhook")
      unless proj_cf.nil?
        proj_cv = proj.custom_value_for(proj_cf)
        unless proj_cv.nil?
          url = proj_cv.value
          return url if url =~ URI::regexp
        end
      end

      ## used value from parent project's custom field
      return get_webhook_url(proj.parent)
    end

################################################################################
## Send data to Hangouts Chat
################################################################################
    def send_webhook_data(url, data)
      Rails.logger.debug("Webhook URL: #{url}")
      Rails.logger.debug("Webhook Data: #{data.to_json}")

      ## Send data
      begin
        https_proxy = ENV['https_proxy'] || ENV['HTTPS_PROXY']
        client = HTTPClient.new(https_proxy)
        client.ssl_config.cert_store.set_default_paths
        client.ssl_config.ssl_version = :auto
        client.post_async url, {:body => data.to_json, :header => {'Content-Type' => 'application/json'}}
      rescue Exception => e
        Rails.logger.warn("cannot connect to #{url}")
        Rails.logger.warn(e)
      end
    end  end
end

Issue.send(:include, RedmineHangoutsChatIntegration::IssuePatch) unless Issue.included_modules.include? RedmineHangoutsChatIntegration::IssuePatch
#RedmineExtensions::PatchManager.register_model_patch 'Issue', 'RedmineHangoutsChatIntegration::IssuePatch'

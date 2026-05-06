# frozen_string_literal: true

# name: discord-link-admin
# about: Admin tool to manually link/unlink Discord accounts to existing Discourse users; also extends OmniAuth Discord HTTP timeouts to better tolerate transient upstream jitter.
# version: 0.2.0
# authors: Stay Home Airlines
# url: https://github.com/stayhomeairlines/discourse-discord-link-admin

enabled_site_setting :discord_link_admin_enabled

register_asset "stylesheets/admin-discord-link.scss"

after_initialize do
  module ::DiscordLinkAdmin
    PLUGIN_NAME = "discord-link-admin"

    class Engine < ::Rails::Engine
      engine_name "discord_link_admin"
      isolate_namespace DiscordLinkAdmin
    end
  end

  module ::DiscordLinkAdmin
    class AdminController < ::Admin::AdminController
      def index
        render json: { ok: true }
      end

      def link
        username = params[:username].to_s.strip
        discord_id = params[:discord_id].to_s.strip
        force = ActiveModel::Type::Boolean.new.cast(params[:force])
        delete_old_user = ActiveModel::Type::Boolean.new.cast(params[:delete_old_user])

        if username.blank?
          return render json: { error: I18n.t("discord_link_admin.username_required") }, status: 400
        end

        unless discord_id =~ /\A\d{15,25}\z/
          return render json: { error: I18n.t("discord_link_admin.invalid_discord_id") }, status: 400
        end

        user = User.find_by_username(username)
        unless user
          return render json: { error: I18n.t("discord_link_admin.user_not_found", username: username) }, status: 404
        end

        existing_uid = UserAssociatedAccount.find_by(provider_name: "discord", provider_uid: discord_id)
        action_taken = nil
        deleted_user_username = nil

        if existing_uid && existing_uid.user_id && existing_uid.user_id != user.id
          other = User.find_by(id: existing_uid.user_id)

          unless force
            return render json: {
                     conflict: true,
                     existing_user: serialize_user(other),
                     target_user: serialize_user(user, basic: true),
                     message: I18n.t("discord_link_admin.conflict_message", username: other&.username),
                   },
                   status: 409
          end

          existing_uid.update!(user_id: user.id)
          action_taken = "force_move"

          if delete_old_user && other && other.id != user.id && (other.user_stat.post_count == 0) && !other.staff?
            begin
              UserDestroyer.new(current_user).destroy(other, {
                context: "discord-link-admin: removed auto-created duplicate",
                delete_posts: true,
              })
              deleted_user_username = other.username
              action_taken = "force_move_and_delete_old"
            rescue => e
              # Linking succeeded; deletion failed — return success with warning
              StaffActionLogger.new(current_user).log_custom("discord_link_admin", {
                target_user_id: user.id, target_username: user.username,
                discord_id: discord_id, action: action_taken,
              })
              return render json: {
                       success: true,
                       message: I18n.t("discord_link_admin.linked_with_warning",
                         username: user.username, discord_id: discord_id, warning: e.message),
                       user_id: user.id, username: user.username, action: action_taken,
                     }
            end
          end
        elsif existing_uid
          existing_uid.update!(user_id: user.id)
          action_taken = "attach_pending"
        else
          UserAssociatedAccount.create!(user: user, provider_name: "discord", provider_uid: discord_id)
          action_taken = "create"
        end

        StaffActionLogger.new(current_user).log_custom("discord_link_admin", {
          target_user_id: user.id, target_username: user.username,
          discord_id: discord_id, action: action_taken, deleted_user: deleted_user_username,
        })

        render json: {
                 success: true,
                 message: I18n.t("discord_link_admin.linked",
                   username: user.username, discord_id: discord_id),
                 user_id: user.id, username: user.username,
                 action: action_taken, deleted_user: deleted_user_username,
               }
      end

      def unlink
        discord_id = params[:discord_id].to_s.strip
        confirm = ActiveModel::Type::Boolean.new.cast(params[:confirm])
        delete_user = ActiveModel::Type::Boolean.new.cast(params[:delete_user])

        unless discord_id =~ /\A\d{15,25}\z/
          return render json: { error: I18n.t("discord_link_admin.invalid_discord_id") }, status: 400
        end

        existing = UserAssociatedAccount.find_by(provider_name: "discord", provider_uid: discord_id)
        unless existing
          return render json: { error: I18n.t("discord_link_admin.no_link_found") }, status: 404
        end

        user = existing.user_id ? User.find_by(id: existing.user_id) : nil

        unless confirm
          return render json: {
                   preview: true,
                   existing_user: user ? serialize_user(user) : nil,
                   discord_info: existing.info,
                   message: user ?
                     I18n.t("discord_link_admin.preview_message", username: user.username) :
                     I18n.t("discord_link_admin.preview_orphan"),
                 }
        end

        # Confirmed — perform unlink
        existing.destroy!
        action_taken = "unlink"
        deleted_user_username = nil

        if delete_user && user && (user.user_stat.post_count == 0) && !user.staff?
          begin
            UserDestroyer.new(current_user).destroy(user, {
              context: "discord-link-admin: unlinked user (admin requested deletion)",
              delete_posts: true,
            })
            deleted_user_username = user.username
            action_taken = "unlink_and_delete"
          rescue => e
            StaffActionLogger.new(current_user).log_custom("discord_link_admin", {
              target_user_id: user&.id, target_username: user&.username,
              discord_id: discord_id, action: "unlink",
            })
            return render json: {
                     success: true,
                     message: I18n.t("discord_link_admin.unlinked_with_warning",
                       discord_id: discord_id, warning: e.message),
                     action: "unlink",
                   }
          end
        end

        StaffActionLogger.new(current_user).log_custom("discord_link_admin", {
          target_user_id: user&.id, target_username: user&.username,
          discord_id: discord_id, action: action_taken, deleted_user: deleted_user_username,
        })

        msg = if deleted_user_username
                I18n.t("discord_link_admin.unlinked_and_deleted",
                  discord_id: discord_id, username: deleted_user_username)
              elsif user
                I18n.t("discord_link_admin.unlinked",
                  discord_id: discord_id, username: user.username)
              else
                I18n.t("discord_link_admin.unlinked_orphan", discord_id: discord_id)
              end

        render json: {
                 success: true,
                 message: msg,
                 action: action_taken,
                 deleted_user: deleted_user_username,
               }
      end

      private

      def serialize_user(user, basic: false)
        return nil unless user
        h = {
          id: user.id,
          username: user.username,
          email: user.email,
        }
        return h if basic
        h.merge!(
          post_count: user.user_stat&.post_count || 0,
          topic_count: user.user_stat&.topic_count || 0,
          trust_level: user.trust_level,
          admin: user.admin?,
          moderator: user.moderator?,
          created_at: user.created_at,
          can_delete: (user.user_stat&.post_count.to_i == 0) && !user.staff?,
        )
        h
      end
    end
  end

  ::DiscordLinkAdmin::Engine.routes.draw do
    get "/" => "admin#index", constraints: AdminConstraint.new
    post "/link" => "admin#link", constraints: AdminConstraint.new
    post "/unlink" => "admin#unlink", constraints: AdminConstraint.new
  end

  Discourse::Application.routes.append do
    mount ::DiscordLinkAdmin::Engine, at: "/admin/plugins/discord-link"
  end

  add_admin_route "discord_link_admin.title", "discord-link"

  # Extend Discord OAuth strategy HTTP timeouts so brief upstream jitter on
  # the way to discord.com does not kill an OAuth dance. Faraday default is
  # ~5s, which is fragile on a residential link with occasional latency
  # spikes. Discourse uses a nested DiscordStrategy class (NOT
  # OmniAuth::Strategies::Discord — that gem is not bundled).
  if defined?(::Auth::DiscordAuthenticator::DiscordStrategy)
    strategy = ::Auth::DiscordAuthenticator::DiscordStrategy
    strategy.default_options[:client_options] ||= {}
    existing_conn_opts = strategy.default_options[:client_options][:connection_opts] || {}
    existing_request   = existing_conn_opts[:request] || {}
    strategy.default_options[:client_options][:connection_opts] = existing_conn_opts.merge(
      request: existing_request.merge(open_timeout: 15, read_timeout: 15, timeout: 20),
    )
  end
end

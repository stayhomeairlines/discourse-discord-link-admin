import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { on } from "@ember/modifier";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";
import DButton from "discourse/components/d-button";

export default class DiscordLinkAdminPage extends Component {
  @tracked tab = "link";

  // Link tab state
  @tracked linkUsername = "";
  @tracked linkDiscordId = "";
  @tracked linkLoading = false;
  @tracked linkConflict = null;
  @tracked linkConflictDeleteOld = false;

  // Unlink tab state
  @tracked unlinkDiscordId = "";
  @tracked unlinkLoading = false;
  @tracked unlinkPreview = null;
  @tracked unlinkDeleteUser = false;

  // Status banner
  @tracked status = null;

  get isLinkTab() {
    return this.tab === "link";
  }
  get isUnlinkTab() {
    return this.tab === "unlink";
  }
  get linkSubmitLabel() {
    return this.linkLoading
      ? "discord_link_admin.link.saving"
      : "discord_link_admin.link.submit";
  }

  @action
  showLinkTab() {
    this.tab = "link";
    this.status = null;
    this.linkConflict = null;
    this.unlinkPreview = null;
  }

  @action
  showUnlinkTab() {
    this.tab = "unlink";
    this.status = null;
    this.linkConflict = null;
    this.unlinkPreview = null;
  }

  // ---- Link flow ----
  @action
  updateLinkUsername(e) {
    this.linkUsername = e.target.value;
  }
  @action
  updateLinkDiscordId(e) {
    this.linkDiscordId = e.target.value;
  }
  @action
  toggleConflictDeleteOld(e) {
    this.linkConflictDeleteOld = e.target.checked;
  }

  @action
  async submitLink(event) {
    event?.preventDefault();
    await this.#performLink({ force: false });
  }

  @action
  async confirmLinkForce() {
    await this.#performLink({
      force: true,
      deleteOldUser: this.linkConflictDeleteOld,
    });
  }

  @action
  cancelLinkConflict() {
    this.linkConflict = null;
    this.linkConflictDeleteOld = false;
  }

  async #performLink({ force, deleteOldUser } = {}) {
    this.status = null;
    this.linkLoading = true;
    try {
      const data = {
        username: this.linkUsername,
        discord_id: this.linkDiscordId,
      };
      if (force) {
        data.force = true;
      }
      if (deleteOldUser) {
        data.delete_old_user = true;
      }

      const result = await ajax("/admin/plugins/discord-link/link", {
        type: "POST",
        data,
      });

      this.status = { type: "success", message: result.message };
      this.linkUsername = "";
      this.linkDiscordId = "";
      this.linkConflict = null;
      this.linkConflictDeleteOld = false;
    } catch (e) {
      const responseJSON = e?.jqXHR?.responseJSON;
      if (responseJSON?.conflict) {
        this.linkConflict = {
          existing_user: responseJSON.existing_user,
          target_user: responseJSON.target_user,
        };
      } else {
        const msg = responseJSON?.error || "送信に失敗しました";
        this.status = { type: "error", message: msg };
      }
    } finally {
      this.linkLoading = false;
    }
  }

  // ---- Unlink flow ----
  @action
  updateUnlinkDiscordId(e) {
    this.unlinkDiscordId = e.target.value;
  }
  @action
  toggleUnlinkDeleteUser(e) {
    this.unlinkDeleteUser = e.target.checked;
  }

  @action
  async checkUnlink(event) {
    event?.preventDefault();
    await this.#performUnlink({ confirm: false });
  }

  @action
  async confirmUnlink() {
    await this.#performUnlink({
      confirm: true,
      deleteUser: this.unlinkDeleteUser,
    });
  }

  @action
  cancelUnlink() {
    this.unlinkPreview = null;
    this.unlinkDeleteUser = false;
  }

  async #performUnlink({ confirm, deleteUser } = {}) {
    this.status = null;
    this.unlinkLoading = true;
    try {
      const data = { discord_id: this.unlinkDiscordId };
      if (confirm) {
        data.confirm = true;
      }
      if (deleteUser) {
        data.delete_user = true;
      }

      const result = await ajax("/admin/plugins/discord-link/unlink", {
        type: "POST",
        data,
      });

      if (result.preview) {
        this.unlinkPreview = result;
      } else if (result.success) {
        this.status = { type: "success", message: result.message };
        this.unlinkDiscordId = "";
        this.unlinkPreview = null;
        this.unlinkDeleteUser = false;
      }
    } catch (e) {
      const responseJSON = e?.jqXHR?.responseJSON;
      const msg = responseJSON?.error || "送信に失敗しました";
      this.status = { type: "error", message: msg };
    } finally {
      this.unlinkLoading = false;
    }
  }

  <template>
    <div class="discord-link-admin">
      <h2>{{i18n "discord_link_admin.title"}}</h2>
      <p class="description">{{i18n "discord_link_admin.description"}}</p>

      <ul class="dla-tabs">
        <li class={{if this.isLinkTab "active"}}>
          <button type="button" {{on "click" this.showLinkTab}}>
            {{i18n "discord_link_admin.tab_link"}}
          </button>
        </li>
        <li class={{if this.isUnlinkTab "active"}}>
          <button type="button" {{on "click" this.showUnlinkTab}}>
            {{i18n "discord_link_admin.tab_unlink"}}
          </button>
        </li>
      </ul>

      {{#if this.status}}
        <div class="dla-status alert alert-{{this.status.type}}">
          {{this.status.message}}
        </div>
      {{/if}}

      {{#if this.isLinkTab}}
        <section class="dla-section">
          <h3>{{i18n "discord_link_admin.link.section_title"}}</h3>
          <p class="dla-help">{{i18n "discord_link_admin.link.section_help"}}</p>

          {{#if this.linkConflict}}
            <div class="dla-conflict alert alert-warning">
              <h4>{{i18n "discord_link_admin.conflict.title"}}</h4>
              <p>{{i18n "discord_link_admin.conflict.intro"}}</p>

              <div class="dla-user-card">
                <div class="dla-user-row">
                  <span class="dla-user-username">@{{this.linkConflict.existing_user.username}}</span>
                  <span class="dla-user-meta">id={{this.linkConflict.existing_user.id}}</span>
                </div>
                <dl class="dla-user-fields">
                  <dt>{{i18n "discord_link_admin.user_card.email"}}</dt>
                  <dd>{{this.linkConflict.existing_user.email}}</dd>
                  <dt>{{i18n "discord_link_admin.user_card.post_count"}}</dt>
                  <dd>{{this.linkConflict.existing_user.post_count}}</dd>
                  <dt>{{i18n "discord_link_admin.user_card.topic_count"}}</dt>
                  <dd>{{this.linkConflict.existing_user.topic_count}}</dd>
                  <dt>{{i18n "discord_link_admin.user_card.trust_level"}}</dt>
                  <dd>{{this.linkConflict.existing_user.trust_level}}</dd>
                  <dt>{{i18n "discord_link_admin.user_card.created_at"}}</dt>
                  <dd>{{this.linkConflict.existing_user.created_at}}</dd>
                </dl>
              </div>

              <p>
                {{i18n
                  "discord_link_admin.conflict.proceed_intro"
                  target=this.linkConflict.target_user.username
                }}
              </p>

              {{#if this.linkConflict.existing_user.can_delete}}
                <label class="dla-check">
                  <input
                    type="checkbox"
                    checked={{this.linkConflictDeleteOld}}
                    {{on "change" this.toggleConflictDeleteOld}}
                  />
                  {{i18n
                    "discord_link_admin.conflict.delete_old_label"
                    username=this.linkConflict.existing_user.username
                  }}
                </label>
              {{else}}
                <p class="dla-help">
                  {{i18n "discord_link_admin.conflict.delete_old_only_if_no_posts"}}
                </p>
              {{/if}}

              <div class="dla-actions">
                <DButton
                  @action={{this.confirmLinkForce}}
                  @disabled={{this.linkLoading}}
                  @label="discord_link_admin.conflict.confirm_force"
                  class="btn-danger"
                />
                <DButton
                  @action={{this.cancelLinkConflict}}
                  @label="discord_link_admin.conflict.cancel"
                />
              </div>
            </div>
          {{else}}
            <form class="dla-form" {{on "submit" this.submitLink}}>
              <div class="control-group">
                <label for="dla-link-username">
                  {{i18n "discord_link_admin.link.username_label"}}
                </label>
                <input
                  id="dla-link-username"
                  type="text"
                  value={{this.linkUsername}}
                  {{on "input" this.updateLinkUsername}}
                  placeholder={{i18n "discord_link_admin.link.username_placeholder"}}
                  required
                />
              </div>
              <div class="control-group">
                <label for="dla-link-discord-id">
                  {{i18n "discord_link_admin.link.discord_id_label"}}
                </label>
                <input
                  id="dla-link-discord-id"
                  type="text"
                  inputmode="numeric"
                  pattern="^[0-9]{15,25}$"
                  value={{this.linkDiscordId}}
                  {{on "input" this.updateLinkDiscordId}}
                  placeholder={{i18n "discord_link_admin.link.discord_id_placeholder"}}
                  required
                />
                <p class="dla-help">{{i18n "discord_link_admin.link.discord_id_help"}}</p>
              </div>
              <DButton
                @action={{this.submitLink}}
                @disabled={{this.linkLoading}}
                @label={{this.linkSubmitLabel}}
                class="btn-primary"
              />
            </form>
          {{/if}}
        </section>
      {{/if}}

      {{#if this.isUnlinkTab}}
        <section class="dla-section">
          <h3>{{i18n "discord_link_admin.unlink.section_title"}}</h3>
          <p class="dla-help">{{i18n "discord_link_admin.unlink.section_help"}}</p>

          {{#if this.unlinkPreview}}
            <div class="dla-conflict alert alert-info">
              <p>{{this.unlinkPreview.message}}</p>

              {{#if this.unlinkPreview.existing_user}}
                <div class="dla-user-card">
                  <div class="dla-user-row">
                    <span class="dla-user-username">@{{this.unlinkPreview.existing_user.username}}</span>
                    <span class="dla-user-meta">id={{this.unlinkPreview.existing_user.id}}</span>
                  </div>
                  <dl class="dla-user-fields">
                    <dt>{{i18n "discord_link_admin.user_card.email"}}</dt>
                    <dd>{{this.unlinkPreview.existing_user.email}}</dd>
                    <dt>{{i18n "discord_link_admin.user_card.post_count"}}</dt>
                    <dd>{{this.unlinkPreview.existing_user.post_count}}</dd>
                    <dt>{{i18n "discord_link_admin.user_card.topic_count"}}</dt>
                    <dd>{{this.unlinkPreview.existing_user.topic_count}}</dd>
                    <dt>{{i18n "discord_link_admin.user_card.trust_level"}}</dt>
                    <dd>{{this.unlinkPreview.existing_user.trust_level}}</dd>
                    <dt>{{i18n "discord_link_admin.user_card.created_at"}}</dt>
                    <dd>{{this.unlinkPreview.existing_user.created_at}}</dd>
                  </dl>
                </div>

                {{#if this.unlinkPreview.existing_user.can_delete}}
                  <label class="dla-check">
                    <input
                      type="checkbox"
                      checked={{this.unlinkDeleteUser}}
                      {{on "change" this.toggleUnlinkDeleteUser}}
                    />
                    {{i18n
                      "discord_link_admin.unlink.delete_user_label"
                      username=this.unlinkPreview.existing_user.username
                    }}
                  </label>
                {{else}}
                  <p class="dla-help">
                    {{i18n "discord_link_admin.unlink.delete_user_only_if_no_posts"}}
                  </p>
                {{/if}}
              {{/if}}

              <div class="dla-actions">
                <DButton
                  @action={{this.confirmUnlink}}
                  @disabled={{this.unlinkLoading}}
                  @label="discord_link_admin.unlink.confirm"
                  class="btn-danger"
                />
                <DButton
                  @action={{this.cancelUnlink}}
                  @label="discord_link_admin.unlink.cancel"
                />
              </div>
            </div>
          {{else}}
            <form class="dla-form" {{on "submit" this.checkUnlink}}>
              <div class="control-group">
                <label for="dla-unlink-discord-id">
                  {{i18n "discord_link_admin.unlink.discord_id_label"}}
                </label>
                <input
                  id="dla-unlink-discord-id"
                  type="text"
                  inputmode="numeric"
                  pattern="^[0-9]{15,25}$"
                  value={{this.unlinkDiscordId}}
                  {{on "input" this.updateUnlinkDiscordId}}
                  required
                />
              </div>
              <DButton
                @action={{this.checkUnlink}}
                @disabled={{this.unlinkLoading}}
                @label="discord_link_admin.unlink.check"
                class="btn-primary"
              />
            </form>
          {{/if}}
        </section>
      {{/if}}
    </div>
  </template>
}

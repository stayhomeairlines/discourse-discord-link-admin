# discourse-discord-link-admin

Stay Home Airlines internal admin tool — manually link / unlink Discord OAuth associations on existing Discourse users.

## Why

When a member's Discord email differs from their Discourse email, the
built-in Discord OAuth flow can't auto-merge accounts. This plugin lets
admins:

- **Link** an existing Discourse user to a Discord User ID (snowflake).
- **Unlink** an existing Discord OAuth association from a user.
- When a Discord ID is already linked to a different (often
  auto-registered) user, prompt for confirmation before moving the link
  and optionally delete the previous user (only if they have no posts).
- All actions are logged via `StaffActionLogger.log_custom("discord_link_admin", …)`.

## Installation

Add to `containers/app.yml`:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/discourse/docker_manager.git
          - git clone https://github.com/stayhomeairlines/discourse-discord-link-admin.git
```

Then run `./launcher rebuild app`.

## Usage

After install, an "Discord Account Link" item appears under
**Admin → Plugins**. The page exposes two tabs:

- **Link** — enter a Discourse username and a Discord User ID.
- **Unlink** — enter a Discord User ID, see who's currently linked,
  optionally delete the user.

## Permissions

The plugin uses Discourse's `AdminConstraint`, so only admin users can
access the routes. Non-admins receive 404 on both the page and the API
endpoints.

## License

MIT

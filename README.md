# Profesjonell

**Profesjonell** is a World of Warcraft (1.12) addon designed for guilds to track and share profession recipes. It automatically gathers known recipes from guild members and synchronizes them, allowing anyone in the guild to easily find who can craft specific items.

## Features

- **Automatic Scanning**: Automatically scans your profession windows (Trade Skills and Crafts) when you open them.
- **Guild Sync**: Automatically synchronizes known recipes with other guild members who have the addon installed.
- **In-Game Search**: Search the guild database via slash commands or guild chat queries.
- **Officer Tools**: Manual management tools for guild officers to add/remove recipes or purge members who have left the guild.
- **Smart Replies**: When someone queries a recipe in guild chat, the addon can automatically reply (with built-in anti-spam to prevent multiple people from replying at once).

## Usage

### Commands

- `/prof [recipe name or link]` — Search the database for characters who know a specific recipe.
- `/prof sync` — Manually request a synchronization from other guild members.
- `?prof [recipe name or link]` — Type this in **Guild Chat** to trigger a search. If you know the recipe or have it in your database, the addon will reply to the guild.

### Officer Commands

- `/prof add [player] [recipe link]` — Manually add a recipe to a specific player.
- `/prof remove [player] [recipe link]` — Remove a specific recipe from a player.
- `/prof remove [player]` — Remove all data for a specific character.
- `/prof purge` — Remove all players from the database who are no longer in the guild.

### Debugging
- `/prof debug` — Toggles debug mode for troubleshooting.

## Data Export
Recipe data is stored in your `SavedVariables` (usually `WTF\Account\[ACCOUNT]\SavedVariables\Profesjonell.lua`). The `ProfesjonellDB` table contains the full list of tracked recipes in a format that can be extracted to CSV by external tools.

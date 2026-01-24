# Profesjonell

**Profesjonell** is a World of Warcraft (1.12) addon designed for guilds to track and share profession recipes. It automatically gathers known recipes from guild members and synchronizes them, allowing anyone in the guild to easily find who can craft specific items.

## Features

- **Automatic Scanning**: Automatically scans your profession windows (Trade Skills and Crafts) when you open them.
- **Guild Sync**: Efficiently synchronizes known recipes with other guild members. Features deterministic jitter and request suppression to minimize network traffic.
- **Tooltip Integration**: Shows "Known by" information directly on item and recipe tooltips.
- **In-Game Search**: Search the guild database via slash commands or guild chat queries.
- **Officer Tools**: Manual management tools for guild officers to add/remove recipes or manage character data.
- **Smart Replies**: Automatically responds to guild chat queries (e.g., `?prof [Link]`) with built-in anti-collision logic.
- **Database Safety**: Automatically wipes local data if you change guilds to prevent data leakage between different guilds.

## Usage

### Character Scanning
Simply open your profession windows (Alchemy, Blacksmithing, Enchanting, etc.). The addon will automatically scan your known recipes and share them with the guild.

### Tooltip Information
Hover over any item or recipe. If anyone in the guild (including your own characters) knows how to craft it, a "Known by" line will appear at the bottom of the tooltip.

### Commands
- `/prof [recipe name or link]` — Search the local database for characters who know a specific recipe. Supports partial name matching.
- `/prof sync` — Manually request a full synchronization from other guild members.
- `/prof debug` — Toggles debug mode for troubleshooting.

### Guild Chat Integration
- `?prof [recipe name or link]` — Type this in **Guild Chat** to trigger a search. If anyone in the guild has the data, the addon will automatically reply to the chat.

### Officer Commands
- `/prof add [player] [recipe link]` — Manually add a recipe to a specific player.
- `/prof remove [player] [recipe link]` — Remove a specific recipe from a player.
- `/prof remove [player]` — Remove all data for a specific character.
- `/prof purge` — Remove all players from the database who are no longer in the guild roster.

## Data & Syncing
Recipe data is stored in your `SavedVariables` (usually `WTF\Account\[ACCOUNT]\SavedVariables\Profesjonell.lua`). 
The synchronization is designed to be lightweight:
- **Jittered Responses**: Prevents multiple players from flooding the addon channel simultaneously.
- **Request Suppression**: If another player already responded to a query or sync request, your client will cancel its own pending response.
- **Hash-based Verification**: Efficiently checks if your database is up-to-date with peers before requesting full data.

## Development
To run the automated test suite, use a standalone Lua interpreter:
```bash
lua test_runner.lua
```

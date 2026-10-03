# open.mp Roleplay Server

A clean open.mp roleplay starter with persistent SQLite accounts, bcrypt password hashing, secure login and registration dialogs, resumable character creation, and `/stats`.

## Features

- Enforces `Firstname_Lastname` roleplay names.
- Stores every registered account in SQLite.
- Hashes passwords with `samp_bcrypt`.
- Saves character creation after every completed step.
- Resumes interrupted character creation after login.
- Uses validated lists for eye color, ethnicity, height, and weight.
- Prevents dialog spoofing and creation-step skipping.
- Shows completed character data through `/stats`.
- Provides an RCON-admin-only `/unregister Firstname_Lastname` account removal command.
- Spawns completed characters immediately after the updates dialog.

## Requirements

- open.mp server 1.5 or newer.
- `samp_bcrypt` plugin and its Pawn include.
- Pawn compiler compatible with open.mp includes.

## Setup

1. Install an open.mp server release.
2. Copy `gamemodes/roleplay.pwn` into the server's `gamemodes` folder.
3. Install `samp_bcrypt` and add its include to the compiler include directory.
4. Compile `roleplay.pwn` as `gamemodes/roleplay.amx`.
5. Copy `config.example.json` to `config.json` and replace `CHANGE_ME` before enabling RCON.
6. Start `omp-server.exe`. The server creates `scriptfiles/roleplay.db` automatically.

`schema.sql` documents the SQLite schema. The gamemode also creates and upgrades the table automatically at startup.

## Security

Runtime databases, logs, binaries, and local credentials are intentionally excluded from version control.

#include <open.mp>
#include <samp_bcrypt>

#define DEFAULT_SKIN            (0)
#define LOGIN_TIMEOUT_SECONDS   (30)
#define MAX_LOGIN_ATTEMPTS      (3)
#define MIN_PASSWORD_LENGTH     (6)
#define MAX_PASSWORD_LENGTH     (72)
#define MIN_HEIGHT_INCHES       (53)
#define MAX_HEIGHT_INCHES       (84)
#define MIN_WEIGHT_KG           (40)
#define MAX_WEIGHT_KG           (160)
#define WEIGHT_STEP_KG          (5)

static const Float:DEFAULT_X = 1958.3783;
static const Float:DEFAULT_Y = 1343.1572;
static const Float:DEFAULT_Z = 15.3746;
static const Float:DEFAULT_A = 270.0;

enum
{
    DIALOG_NONE,
    DIALOG_LOGIN,
    DIALOG_REGISTER,
    DIALOG_REGISTER_CONFIRM,
    DIALOG_CHARACTER_AGE,
    DIALOG_CHARACTER_EYES,
    DIALOG_CHARACTER_ETHNICITY,
    DIALOG_CHARACTER_HEIGHT,
    DIALOG_CHARACTER_WEIGHT,
    DIALOG_UPDATES,
    DIALOG_STATS
};

enum E_AUTH_STATE
{
    AUTH_CHECKING,
    AUTH_LOGIN,
    AUTH_REGISTER,
    AUTH_REGISTER_CONFIRM,
    AUTH_PROCESSING,
    AUTH_CHARACTER_CREATION,
    AUTH_UPDATES,
    AUTH_LOGGED_IN
};

enum E_CREATION_STEP
{
    STEP_NONE = 0,
    STEP_AGE,
    STEP_EYE_COLOR,
    STEP_ETHNICITY,
    STEP_HEIGHT,
    STEP_WEIGHT
};

static const gEyeColors[][] =
{
    "Amber", "Black", "Blue", "Brown", "Green", "Hazel", "Gray"
};

static const gEthnicities[][] =
{
    "Mexican", "Filipino", "Japanese", "Indian", "Indonesian", "Caucasian",
    "African American", "Hispanic/Latino", "Middle Eastern", "Chinese", "Mixed/Other"
};

enum E_PLAYER_INFO
{
    pID,
    pUsername[MAX_PLAYER_NAME + 1],
    pPassword[BCRYPT_HASH_LENGTH],
    pPendingPassword[MAX_PASSWORD_LENGTH + 1],
    pAge,
    pEyeColor[17],
    pEthnicity[33],
    pHeightFeet,
    pHeightInches,
    pWeightKg,
    pCharacterCompleted,
    E_CREATION_STEP:pCreationStep,
    pMoney,
    pScore,
    Float:pPosX,
    Float:pPosY,
    Float:pPosZ,
    Float:pAngle,
    pInterior,
    pVirtualWorld,
    bool:pLogged,
    E_AUTH_STATE:pAuthState,
    pExpectedDialog,
    pLoginAttempts,
    pLoginTimer,
    pSession
};

new PlayerInfo[MAX_PLAYERS][E_PLAYER_INFO];
new gConnectionSerial[MAX_PLAYERS];
new DB:gDatabase = DB:0;

forward OnPasswordHashed(playerid, session);
forward OnPasswordVerified(playerid, bool:success, session);
forward OnLoginTimeout(playerid, session);
forward bool:IsCurrentSession(playerid, session);
forward bool:IsRoleplayName(const name[]);
forward bool:IsNumeric(const string[]);
forward bool:ValidateCreationDialog(playerid, E_CREATION_STEP:expectedStep);

main()
{
}

public OnGameModeInit()
{
    SetGameModeText("OpenMP Roleplay");
    AddPlayerClass(DEFAULT_SKIN, DEFAULT_X, DEFAULT_Y, DEFAULT_Z, DEFAULT_A, WEAPON_FIST, 0, WEAPON_FIST, 0, WEAPON_FIST, 0);

    gDatabase = DB_Open("roleplay.db");
    if (gDatabase == DB:0)
    {
        print("[AUTH] Unable to open scriptfiles/roleplay.db.");
        SendRconCommand("exit");
        return 1;
    }

    new DBResult:result = DB_ExecuteQuery(gDatabase, "CREATE TABLE IF NOT EXISTS `users` (`id` INTEGER PRIMARY KEY AUTOINCREMENT,`username` VARCHAR(24) NOT NULL UNIQUE,`password` VARCHAR(60) NOT NULL,`money` INTEGER NOT NULL DEFAULT 500,`score` INTEGER NOT NULL DEFAULT 0,`pos_x` REAL NOT NULL DEFAULT 1958.3783,`pos_y` REAL NOT NULL DEFAULT 1343.1572,`pos_z` REAL NOT NULL DEFAULT 15.3746,`angle` REAL NOT NULL DEFAULT 270.0,`interior` INTEGER NOT NULL DEFAULT 0,`virtual_world` INTEGER NOT NULL DEFAULT 0,`age` INTEGER NOT NULL DEFAULT 0,`eye_color` VARCHAR(16) NOT NULL DEFAULT '',`ethnicity` VARCHAR(32) NOT NULL DEFAULT '',`height_feet` INTEGER NOT NULL DEFAULT 0,`height_inches` INTEGER NOT NULL DEFAULT 0,`weight_lbs` INTEGER NOT NULL DEFAULT 0,`weight_kg` INTEGER NOT NULL DEFAULT 0,`character_completed` INTEGER NOT NULL DEFAULT 0,`creation_step` INTEGER NOT NULL DEFAULT 1)");
    if (result != DBResult:0)
    {
        DB_FreeResultSet(result);
    }

    EnsureCharacterSchema();

    bcrypt_set_thread_limit(2);
    print("[AUTH] SQLite and bcrypt authentication initialized.");
    return 1;
}

public OnGameModeExit()
{
    if (gDatabase != DB:0)
    {
        DB_Close(gDatabase);
        gDatabase = DB:0;
    }
    return 1;
}

public OnPlayerConnect(playerid)
{
    static const emptyInfo[E_PLAYER_INFO];
    PlayerInfo[playerid] = emptyInfo;

    PlayerInfo[playerid][pSession] = ++gConnectionSerial[playerid];
    PlayerInfo[playerid][pAuthState] = AUTH_CHECKING;
    PlayerInfo[playerid][pExpectedDialog] = DIALOG_NONE;
    PlayerInfo[playerid][pPosX] = DEFAULT_X;
    PlayerInfo[playerid][pPosY] = DEFAULT_Y;
    PlayerInfo[playerid][pPosZ] = DEFAULT_Z;
    PlayerInfo[playerid][pAngle] = DEFAULT_A;
    PlayerInfo[playerid][pMoney] = 500;
    GetPlayerName(playerid, PlayerInfo[playerid][pUsername], MAX_PLAYER_NAME + 1);

    if (!IsRoleplayName(PlayerInfo[playerid][pUsername]))
    {
        SendClientMessage(playerid, 0xFF6347FF, "SERVER: Use the nickname format Firstname_Lastname (example: John_Doe).");
        Kick(playerid);
        return 1;
    }

    TogglePlayerSpectating(playerid, true);
    PlayerInfo[playerid][pLoginTimer] = SetTimerEx("OnLoginTimeout", LOGIN_TIMEOUT_SECONDS * 1000, false, "dd", playerid, PlayerInfo[playerid][pSession]);

    LookupAccount(playerid);
    return 1;
}

public OnPlayerDisconnect(playerid, reason)
{
    if (PlayerInfo[playerid][pLogged])
    {
        SavePlayer(playerid, reason);
    }

    StopLoginTimer(playerid);
    PlayerInfo[playerid][pLogged] = false;
    PlayerInfo[playerid][pExpectedDialog] = DIALOG_NONE;
    gConnectionSerial[playerid]++;
    return 1;
}

public OnDialogResponse(playerid, dialogid, response, listitem, inputtext[])
{
    if (PlayerInfo[playerid][pLogged])
    {
        return 0;
    }

    if (dialogid != PlayerInfo[playerid][pExpectedDialog] || dialogid == DIALOG_NONE)
    {
        RejectUnauthenticated(playerid, "SERVER: Invalid authentication response.");
        return 1;
    }

    if (!response)
    {
        if (PlayerInfo[playerid][pAuthState] == AUTH_CHARACTER_CREATION)
        {
            SendClientMessage(playerid, 0xFFD966FF, "SERVER: Character creation must be completed. Your progress has been saved.");
            StartOrResumeCharacterCreation(playerid);
            return 1;
        }

        RejectUnauthenticated(playerid, "SERVER: Authentication cancelled.");
        return 1;
    }

    switch (dialogid)
    {
        case DIALOG_LOGIN:
        {
            if (PlayerInfo[playerid][pAuthState] != AUTH_LOGIN)
            {
                RejectUnauthenticated(playerid, "SERVER: Invalid login state.");
                return 1;
            }

            if (strlen(inputtext) < 1 || strlen(inputtext) > MAX_PASSWORD_LENGTH)
            {
                HandleFailedLogin(playerid, "Invalid password.");
                return 1;
            }

            PlayerInfo[playerid][pExpectedDialog] = DIALOG_NONE;
            PlayerInfo[playerid][pAuthState] = AUTH_PROCESSING;
            bcrypt_verify(playerid, "OnPasswordVerified", inputtext, PlayerInfo[playerid][pPassword], "d", PlayerInfo[playerid][pSession]);
        }
        case DIALOG_REGISTER:
        {
            if (PlayerInfo[playerid][pAuthState] != AUTH_REGISTER)
            {
                RejectUnauthenticated(playerid, "SERVER: Invalid registration state.");
                return 1;
            }

            new passwordLength = strlen(inputtext);
            if (passwordLength < MIN_PASSWORD_LENGTH || passwordLength > MAX_PASSWORD_LENGTH)
            {
                ShowRegisterDialog(playerid, "Password must contain 6 to 72 characters.");
                return 1;
            }

            format(PlayerInfo[playerid][pPendingPassword], MAX_PASSWORD_LENGTH + 1, "%s", inputtext);
            ShowRegisterConfirmDialog(playerid, "Enter the same password again to confirm registration.");
        }
        case DIALOG_REGISTER_CONFIRM:
        {
            if (PlayerInfo[playerid][pAuthState] != AUTH_REGISTER_CONFIRM)
            {
                RejectUnauthenticated(playerid, "SERVER: Invalid registration confirmation state.");
                return 1;
            }

            if (strcmp(inputtext, PlayerInfo[playerid][pPendingPassword], false) != 0)
            {
                PlayerInfo[playerid][pPendingPassword][0] = EOS;
                ShowRegisterDialog(playerid, "Passwords did not match. Create your password again.");
                return 1;
            }

            PlayerInfo[playerid][pExpectedDialog] = DIALOG_NONE;
            PlayerInfo[playerid][pAuthState] = AUTH_PROCESSING;
            bcrypt_hash(playerid, "OnPasswordHashed", PlayerInfo[playerid][pPendingPassword], BCRYPT_COST, "d", PlayerInfo[playerid][pSession]);
        }
        case DIALOG_CHARACTER_AGE:
        {
            if (!ValidateCreationDialog(playerid, STEP_AGE)) return 1;
            if (!IsNumeric(inputtext) || strlen(inputtext) > 2)
            {
                ShowCharacterAgeDialog(playerid, "Invalid age. Enter numbers only, from 15 to 85.");
                return 1;
            }

            new age = strval(inputtext);
            if (age < 15 || age > 85)
            {
                ShowCharacterAgeDialog(playerid, "Age must be between 15 and 85 years old.");
                return 1;
            }

            PlayerInfo[playerid][pAge] = age;
            PlayerInfo[playerid][pCreationStep] = STEP_EYE_COLOR;
            SaveCreationProgress(playerid);
            ShowCharacterEyesDialog(playerid);
        }
        case DIALOG_CHARACTER_EYES:
        {
            if (!ValidateCreationDialog(playerid, STEP_EYE_COLOR)) return 1;
            if (listitem < 0 || listitem >= sizeof gEyeColors)
            {
                printf("[AUTH] Invalid eye-color list index %d from player %d.", listitem, playerid);
                ShowCharacterEyesDialog(playerid);
                return 1;
            }

            format(PlayerInfo[playerid][pEyeColor], 17, "%s", gEyeColors[listitem]);
            PlayerInfo[playerid][pCreationStep] = STEP_ETHNICITY;
            SaveCreationProgress(playerid);
            ShowCharacterEthnicityDialog(playerid);
        }
        case DIALOG_CHARACTER_ETHNICITY:
        {
            if (!ValidateCreationDialog(playerid, STEP_ETHNICITY)) return 1;
            if (listitem < 0 || listitem >= sizeof gEthnicities)
            {
                printf("[AUTH] Invalid ethnicity list index %d from player %d.", listitem, playerid);
                ShowCharacterEthnicityDialog(playerid);
                return 1;
            }

            format(PlayerInfo[playerid][pEthnicity], 33, "%s", gEthnicities[listitem]);
            PlayerInfo[playerid][pCreationStep] = STEP_HEIGHT;
            SaveCreationProgress(playerid);
            ShowCharacterHeightDialog(playerid);
        }
        case DIALOG_CHARACTER_HEIGHT:
        {
            if (!ValidateCreationDialog(playerid, STEP_HEIGHT)) return 1;
            if (listitem < 0 || listitem >= (MAX_HEIGHT_INCHES - MIN_HEIGHT_INCHES + 1))
            {
                printf("[AUTH] Invalid height list index %d from player %d.", listitem, playerid);
                ShowCharacterHeightDialog(playerid);
                return 1;
            }

            new totalInches = MIN_HEIGHT_INCHES + listitem;
            PlayerInfo[playerid][pHeightFeet] = totalInches / 12;
            PlayerInfo[playerid][pHeightInches] = totalInches % 12;
            PlayerInfo[playerid][pCreationStep] = STEP_WEIGHT;
            SaveCreationProgress(playerid);
            ShowCharacterWeightDialog(playerid);
        }
        case DIALOG_CHARACTER_WEIGHT:
        {
            if (!ValidateCreationDialog(playerid, STEP_WEIGHT)) return 1;
            if (listitem < 0 || listitem >= ((MAX_WEIGHT_KG - MIN_WEIGHT_KG) / WEIGHT_STEP_KG) + 1)
            {
                printf("[AUTH] Invalid weight list index %d from player %d.", listitem, playerid);
                ShowCharacterWeightDialog(playerid);
                return 1;
            }

            PlayerInfo[playerid][pWeightKg] = MIN_WEIGHT_KG + (listitem * WEIGHT_STEP_KG);
            PlayerInfo[playerid][pCharacterCompleted] = 1;
            PlayerInfo[playerid][pCreationStep] = STEP_NONE;
            SaveCreationProgress(playerid);
            ShowUpdatesDialog(playerid);
        }
        case DIALOG_UPDATES:
        {
            if (PlayerInfo[playerid][pAuthState] != AUTH_UPDATES)
            {
                RejectUnauthenticated(playerid, "SERVER: Invalid updates dialog state.");
                return 1;
            }

            FinishAuthentication(playerid);
        }
    }
    return 1;
}

public OnPasswordHashed(playerid, session)
{
    if (!IsCurrentSession(playerid, session) || PlayerInfo[playerid][pAuthState] != AUTH_PROCESSING)
    {
        return 1;
    }

    new hash[BCRYPT_HASH_LENGTH];
    bcrypt_get_hash(hash, sizeof hash);

    new query[384];
    format(query, sizeof query,
        "INSERT OR IGNORE INTO `users` (`username`,`password`,`money`,`score`,`pos_x`,`pos_y`,`pos_z`,`angle`,`interior`,`virtual_world`) VALUES ('%s','%s',500,0,%f,%f,%f,%f,0,0)",
        PlayerInfo[playerid][pUsername], hash, DEFAULT_X, DEFAULT_Y, DEFAULT_Z, DEFAULT_A);
    new DBResult:result = DB_ExecuteQuery(gDatabase, query);
    if (result != DBResult:0)
    {
        DB_FreeResultSet(result);
    }

    format(query, sizeof query, "SELECT `id` FROM `users` WHERE `username`='%s' LIMIT 1", PlayerInfo[playerid][pUsername]);
    result = DB_ExecuteQuery(gDatabase, query);
    if (result != DBResult:0 && DB_GetRowCount(result) > 0)
    {
        PlayerInfo[playerid][pID] = DB_GetFieldIntByName(result, "id");
    }
    if (result != DBResult:0)
    {
        DB_FreeResultSet(result);
    }

    if (PlayerInfo[playerid][pID] <= 0)
    {
        RejectUnauthenticated(playerid, "SERVER: Registration failed or the account already exists.");
        return 1;
    }

    format(PlayerInfo[playerid][pPassword], BCRYPT_HASH_LENGTH, "%s", hash);
    PlayerInfo[playerid][pPendingPassword][0] = EOS;
    PlayerInfo[playerid][pCharacterCompleted] = 0;
    PlayerInfo[playerid][pCreationStep] = STEP_AGE;
    ShowLoginDialog(playerid, "Registration complete. Enter your password to log in.");
    return 1;
}

public OnPasswordVerified(playerid, bool:success, session)
{
    if (!IsCurrentSession(playerid, session) || PlayerInfo[playerid][pAuthState] != AUTH_PROCESSING)
    {
        return 1;
    }

    if (!success)
    {
        HandleFailedLogin(playerid, "Incorrect password.");
        return 1;
    }

    // Authentication is complete.  Character creation is intentionally not timed.
    StopLoginTimer(playerid);

    if (!PlayerInfo[playerid][pCharacterCompleted])
    {
        StartOrResumeCharacterCreation(playerid);
    }
    else
    {
        ShowUpdatesDialog(playerid);
    }
    return 1;
}

public OnLoginTimeout(playerid, session)
{
    if (!IsCurrentSession(playerid, session) || PlayerInfo[playerid][pLogged])
    {
        return 1;
    }

    PlayerInfo[playerid][pLoginTimer] = 0;
    RejectUnauthenticated(playerid, "SERVER: Login timed out.");
    return 1;
}

public OnPlayerRequestClass(playerid, classid)
{
    #pragma unused classid
    return PlayerInfo[playerid][pLogged];
}

public OnPlayerRequestSpawn(playerid)
{
    return PlayerInfo[playerid][pLogged];
}

public OnPlayerSpawn(playerid)
{
    if (!CheckLoginState(playerid))
    {
        return 0;
    }

    SetPlayerInterior(playerid, PlayerInfo[playerid][pInterior]);
    SetPlayerVirtualWorld(playerid, PlayerInfo[playerid][pVirtualWorld]);
    SetPlayerPos(playerid, PlayerInfo[playerid][pPosX], PlayerInfo[playerid][pPosY], PlayerInfo[playerid][pPosZ]);
    SetPlayerFacingAngle(playerid, PlayerInfo[playerid][pAngle]);
    SetCameraBehindPlayer(playerid);
    return 1;
}

public OnPlayerCommandText(playerid, cmdtext[])
{
    if (!CheckLoginState(playerid))
    {
        return 1;
    }

    if (!strcmp(cmdtext, "/stats", true))
    {
        ShowCharacterStats(playerid);
        return 1;
    }
    return 0;
}

public OnPlayerText(playerid, text[])
{
    #pragma unused text
    return CheckLoginState(playerid);
}

public OnPlayerStateChange(playerid, PLAYER_STATE:newstate, PLAYER_STATE:oldstate)
{
    #pragma unused oldstate

    if (PlayerInfo[playerid][pLogged])
    {
        return 1;
    }

    if (newstate == PLAYER_STATE_NONE || newstate == PLAYER_STATE_SPECTATING)
    {
        return 1;
    }

    RejectUnauthenticated(playerid, "SERVER: Invalid player state before authentication.");
    return 0;
}

public OnPlayerStreamIn(playerid, forplayerid)
{
    #pragma unused forplayerid
    return CheckLoginState(playerid);
}

stock bool:IsCurrentSession(playerid, session)
{
    return IsPlayerConnected(playerid) && PlayerInfo[playerid][pSession] == session && gConnectionSerial[playerid] == session;
}

stock LookupAccount(playerid)
{
    new query[512];
    format(query, sizeof query,
        "SELECT `id`,`password`,`money`,`score`,`pos_x`,`pos_y`,`pos_z`,`angle`,`interior`,`virtual_world`,`age`,`eye_color`,`ethnicity`,`height_feet`,`height_inches`,`weight_kg`,`character_completed`,`creation_step` FROM `users` WHERE `username`='%s' LIMIT 1",
        PlayerInfo[playerid][pUsername]);

    new DBResult:result = DB_ExecuteQuery(gDatabase, query);
    if (result != DBResult:0 && DB_GetRowCount(result) > 0)
    {
        PlayerInfo[playerid][pID] = DB_GetFieldIntByName(result, "id");
        DB_GetFieldStringByName(result, "password", PlayerInfo[playerid][pPassword], BCRYPT_HASH_LENGTH);
        PlayerInfo[playerid][pMoney] = DB_GetFieldIntByName(result, "money");
        PlayerInfo[playerid][pScore] = DB_GetFieldIntByName(result, "score");
        PlayerInfo[playerid][pPosX] = DB_GetFieldFloatByName(result, "pos_x");
        PlayerInfo[playerid][pPosY] = DB_GetFieldFloatByName(result, "pos_y");
        PlayerInfo[playerid][pPosZ] = DB_GetFieldFloatByName(result, "pos_z");
        PlayerInfo[playerid][pAngle] = DB_GetFieldFloatByName(result, "angle");
        PlayerInfo[playerid][pInterior] = DB_GetFieldIntByName(result, "interior");
        PlayerInfo[playerid][pVirtualWorld] = DB_GetFieldIntByName(result, "virtual_world");
        PlayerInfo[playerid][pAge] = DB_GetFieldIntByName(result, "age");
        DB_GetFieldStringByName(result, "eye_color", PlayerInfo[playerid][pEyeColor], 17);
        DB_GetFieldStringByName(result, "ethnicity", PlayerInfo[playerid][pEthnicity], 33);
        PlayerInfo[playerid][pHeightFeet] = DB_GetFieldIntByName(result, "height_feet");
        PlayerInfo[playerid][pHeightInches] = DB_GetFieldIntByName(result, "height_inches");
        PlayerInfo[playerid][pWeightKg] = DB_GetFieldIntByName(result, "weight_kg");
        PlayerInfo[playerid][pCharacterCompleted] = DB_GetFieldIntByName(result, "character_completed");
        PlayerInfo[playerid][pCreationStep] = E_CREATION_STEP:DB_GetFieldIntByName(result, "creation_step");
        ValidateLoadedCharacter(playerid);
        DB_FreeResultSet(result);
        ShowLoginDialog(playerid, "Enter your password to continue.");
    }
    else
    {
        if (result != DBResult:0)
        {
            DB_FreeResultSet(result);
        }
        ShowRegisterDialog(playerid, "Create a password to register this account.");
    }
    return 1;
}

stock EnsureCharacterSchema()
{
    EnsureDatabaseColumn("age", "INTEGER NOT NULL DEFAULT 0");
    EnsureDatabaseColumn("eye_color", "VARCHAR(16) NOT NULL DEFAULT ''");
    EnsureDatabaseColumn("ethnicity", "VARCHAR(32) NOT NULL DEFAULT ''");
    EnsureDatabaseColumn("height_feet", "INTEGER NOT NULL DEFAULT 0");
    EnsureDatabaseColumn("height_inches", "INTEGER NOT NULL DEFAULT 0");
    EnsureDatabaseColumn("weight_lbs", "INTEGER NOT NULL DEFAULT 0");
    EnsureDatabaseColumn("weight_kg", "INTEGER NOT NULL DEFAULT 0");
    EnsureDatabaseColumn("character_completed", "INTEGER NOT NULL DEFAULT 0");
    EnsureDatabaseColumn("creation_step", "INTEGER NOT NULL DEFAULT 1");

    new DBResult:result = DB_ExecuteQuery(gDatabase, "UPDATE `users` SET `weight_kg`=ROUND(`weight_lbs` * 0.45359237) WHERE `weight_kg`=0 AND `weight_lbs`>0");
    if (result != DBResult:0)
    {
        DB_FreeResultSet(result);
    }
    return 1;
}

stock EnsureDatabaseColumn(const columnName[], const definition[])
{
    new bool:found = false;
    new fieldName[32];
    new DBResult:result = DB_ExecuteQuery(gDatabase, "PRAGMA table_info(`users`)");
    if (result != DBResult:0)
    {
        new rows = DB_GetRowCount(result);
        for (new row = 0; row < rows; row++)
        {
            DB_GetFieldStringByName(result, "name", fieldName, sizeof fieldName);
            if (!strcmp(fieldName, columnName, true))
            {
                found = true;
                break;
            }
            DB_SelectNextRow(result);
        }
        DB_FreeResultSet(result);
    }

    if (!found)
    {
        new query[160];
        format(query, sizeof query, "ALTER TABLE `users` ADD COLUMN `%s` %s", columnName, definition);
        result = DB_ExecuteQuery(gDatabase, query);
        if (result != DBResult:0)
        {
            DB_FreeResultSet(result);
        }
    }
    return 1;
}

stock bool:IsRoleplayName(const name[])
{
    new length = strlen(name);
    new underscore = -1;

    for (new i = 0; i < length; i++)
    {
        if (name[i] == '_')
        {
            if (underscore != -1) return false;
            underscore = i;
            continue;
        }

        if ((i == 0 || i == underscore + 1) && (name[i] < 'A' || name[i] > 'Z')) return false;
        if (i != 0 && i != underscore + 1 && (name[i] < 'a' || name[i] > 'z')) return false;
    }

    return underscore >= 2 && underscore <= length - 3;
}

stock bool:IsNumeric(const string[])
{
    new length = strlen(string);
    if (length == 0) return false;

    for (new i = 0; i < length; i++)
    {
        if (string[i] < '0' || string[i] > '9') return false;
    }
    return true;
}

stock bool:ValidateCreationDialog(playerid, E_CREATION_STEP:expectedStep)
{
    if (PlayerInfo[playerid][pAuthState] != AUTH_CHARACTER_CREATION || PlayerInfo[playerid][pCreationStep] != expectedStep)
    {
        RejectUnauthenticated(playerid, "SERVER: Invalid character creation step.");
        return false;
    }
    return true;
}

stock StartOrResumeCharacterCreation(playerid)
{
    switch (PlayerInfo[playerid][pCreationStep])
    {
        case STEP_EYE_COLOR: ShowCharacterEyesDialog(playerid);
        case STEP_ETHNICITY: ShowCharacterEthnicityDialog(playerid);
        case STEP_HEIGHT: ShowCharacterHeightDialog(playerid);
        case STEP_WEIGHT: ShowCharacterWeightDialog(playerid);
        default:
        {
            PlayerInfo[playerid][pCreationStep] = STEP_AGE;
            SaveCreationProgress(playerid);
            ShowCharacterAgeDialog(playerid, "Please enter your character's age (15 to 85 years old).");
        }
    }
    return 1;
}

stock ShowCharacterAgeDialog(playerid, const message[])
{
    PlayerInfo[playerid][pAuthState] = AUTH_CHARACTER_CREATION;
    PlayerInfo[playerid][pExpectedDialog] = DIALOG_CHARACTER_AGE;
    ShowPlayerDialog(playerid, DIALOG_CHARACTER_AGE, DIALOG_STYLE_INPUT, "Character Creation - Age", message, "Next", "Quit");
    return 1;
}

stock ShowCharacterEyesDialog(playerid)
{
    PlayerInfo[playerid][pAuthState] = AUTH_CHARACTER_CREATION;
    PlayerInfo[playerid][pExpectedDialog] = DIALOG_CHARACTER_EYES;
    ShowPlayerDialog(playerid, DIALOG_CHARACTER_EYES, DIALOG_STYLE_LIST, "Character Creation - Eye Color", "Amber\nBlack\nBlue\nBrown\nGreen\nHazel\nGray", "Next", "Quit");
    return 1;
}

stock ShowCharacterEthnicityDialog(playerid)
{
    PlayerInfo[playerid][pAuthState] = AUTH_CHARACTER_CREATION;
    PlayerInfo[playerid][pExpectedDialog] = DIALOG_CHARACTER_ETHNICITY;
    ShowPlayerDialog(playerid, DIALOG_CHARACTER_ETHNICITY, DIALOG_STYLE_LIST, "Character Creation - Ethnicity / Origin", "Mexican\nFilipino\nJapanese\nIndian\nIndonesian\nCaucasian\nAfrican American\nHispanic/Latino\nMiddle Eastern\nChinese\nMixed/Other", "Next", "Quit");
    return 1;
}

stock ShowCharacterHeightDialog(playerid)
{
    PlayerInfo[playerid][pAuthState] = AUTH_CHARACTER_CREATION;
    PlayerInfo[playerid][pExpectedDialog] = DIALOG_CHARACTER_HEIGHT;

    new options[768];
    new row[32];
    for (new totalInches = MIN_HEIGHT_INCHES; totalInches <= MAX_HEIGHT_INCHES; totalInches++)
    {
        format(row, sizeof row, "%d'%d\" / %d inches%s", totalInches / 12, totalInches % 12, totalInches, totalInches == MAX_HEIGHT_INCHES ? ("") : ("\n"));
        strcat(options, row, sizeof options);
    }
    ShowPlayerDialog(playerid, DIALOG_CHARACTER_HEIGHT, DIALOG_STYLE_LIST, "Character Creation - Height", options, "Next", "Quit");
    return 1;
}

stock ShowCharacterWeightDialog(playerid)
{
    PlayerInfo[playerid][pAuthState] = AUTH_CHARACTER_CREATION;
    PlayerInfo[playerid][pExpectedDialog] = DIALOG_CHARACTER_WEIGHT;

    new options[512];
    new row[32];
    for (new kilograms = MIN_WEIGHT_KG; kilograms <= MAX_WEIGHT_KG; kilograms += WEIGHT_STEP_KG)
    {
        new pounds = floatround(float(kilograms) * 2.20462262);
        format(row, sizeof row, "%d kg / %d lbs%s", kilograms, pounds, kilograms == MAX_WEIGHT_KG ? ("") : ("\n"));
        strcat(options, row, sizeof options);
    }
    ShowPlayerDialog(playerid, DIALOG_CHARACTER_WEIGHT, DIALOG_STYLE_LIST, "Character Creation - Weight", options, "Finish", "Quit");
    return 1;
}

stock SaveCreationProgress(playerid)
{
    new query[512];
    format(query, sizeof query,
        "UPDATE `users` SET `age`=%d,`eye_color`='%s',`ethnicity`='%s',`height_feet`=%d,`height_inches`=%d,`weight_kg`=%d,`character_completed`=%d,`creation_step`=%d WHERE `id`=%d LIMIT 1",
        PlayerInfo[playerid][pAge], PlayerInfo[playerid][pEyeColor], PlayerInfo[playerid][pEthnicity],
        PlayerInfo[playerid][pHeightFeet], PlayerInfo[playerid][pHeightInches], PlayerInfo[playerid][pWeightKg],
        PlayerInfo[playerid][pCharacterCompleted], _:PlayerInfo[playerid][pCreationStep], PlayerInfo[playerid][pID]);

    new DBResult:result = DB_ExecuteQuery(gDatabase, query);
    if (result != DBResult:0)
    {
        DB_FreeResultSet(result);
    }
    return 1;
}

stock bool:IsValidEyeColor(const value[])
{
    for (new i = 0; i < sizeof gEyeColors; i++)
    {
        if (!strcmp(value, gEyeColors[i], true)) return true;
    }
    return false;
}

stock bool:IsValidEthnicity(const value[])
{
    for (new i = 0; i < sizeof gEthnicities; i++)
    {
        if (!strcmp(value, gEthnicities[i], true)) return true;
    }
    return false;
}

stock ValidateLoadedCharacter(playerid)
{
    new E_CREATION_STEP:invalidStep = STEP_NONE;
    new totalInches = (PlayerInfo[playerid][pHeightFeet] * 12) + PlayerInfo[playerid][pHeightInches];

    if (PlayerInfo[playerid][pAge] < 15 || PlayerInfo[playerid][pAge] > 85) invalidStep = STEP_AGE;
    else if (!IsValidEyeColor(PlayerInfo[playerid][pEyeColor])) invalidStep = STEP_EYE_COLOR;
    else if (!IsValidEthnicity(PlayerInfo[playerid][pEthnicity])) invalidStep = STEP_ETHNICITY;
    else if (totalInches < MIN_HEIGHT_INCHES || totalInches > MAX_HEIGHT_INCHES) invalidStep = STEP_HEIGHT;
    else if (PlayerInfo[playerid][pWeightKg] < MIN_WEIGHT_KG || PlayerInfo[playerid][pWeightKg] > MAX_WEIGHT_KG || ((PlayerInfo[playerid][pWeightKg] - MIN_WEIGHT_KG) % WEIGHT_STEP_KG) != 0) invalidStep = STEP_WEIGHT;

    if (invalidStep != STEP_NONE)
    {
        PlayerInfo[playerid][pCharacterCompleted] = 0;
        PlayerInfo[playerid][pCreationStep] = invalidStep;
        SaveCreationProgress(playerid);
    }
    else
    {
        // All persisted fields are valid, so repair stale completion metadata.
        if (!PlayerInfo[playerid][pCharacterCompleted] || PlayerInfo[playerid][pCreationStep] != STEP_NONE)
        {
            PlayerInfo[playerid][pCharacterCompleted] = 1;
            PlayerInfo[playerid][pCreationStep] = STEP_NONE;
            SaveCreationProgress(playerid);
        }
    }
    return 1;
}

stock ShowCharacterStats(playerid)
{
    if (!PlayerInfo[playerid][pCharacterCompleted])
    {
        SendClientMessage(playerid, 0xFF6347FF, "SERVER: Complete character creation before using /stats.");
        return 1;
    }

    new kilograms = PlayerInfo[playerid][pWeightKg];
    new pounds = floatround(float(kilograms) * 2.20462262);
    new content[512];
    format(content, sizeof content,
        "Name: %s\nAge: %d\nEthnicity / Origin: %s\nEye Color: %s\nHeight: %d'%d\"\nWeight: %d kg / %d lbs\n\nMoney: $%d\nScore: %d",
        PlayerInfo[playerid][pUsername], PlayerInfo[playerid][pAge], PlayerInfo[playerid][pEthnicity],
        PlayerInfo[playerid][pEyeColor], PlayerInfo[playerid][pHeightFeet], PlayerInfo[playerid][pHeightInches],
        kilograms, pounds, GetPlayerMoney(playerid), GetPlayerScore(playerid));
    ShowPlayerDialog(playerid, DIALOG_STATS, DIALOG_STYLE_MSGBOX, "Character Statistics", content, "Close", "");
    return 1;
}

stock ShowLoginDialog(playerid, const message[])
{
    PlayerInfo[playerid][pAuthState] = AUTH_LOGIN;
    PlayerInfo[playerid][pExpectedDialog] = DIALOG_LOGIN;
    ShowPlayerDialog(playerid, DIALOG_LOGIN, DIALOG_STYLE_PASSWORD, "Account Login", message, "Login", "Quit");
    return 1;
}

stock ShowRegisterDialog(playerid, const message[])
{
    PlayerInfo[playerid][pAuthState] = AUTH_REGISTER;
    PlayerInfo[playerid][pExpectedDialog] = DIALOG_REGISTER;
    ShowPlayerDialog(playerid, DIALOG_REGISTER, DIALOG_STYLE_PASSWORD, "Account Registration", message, "Register", "Quit");
    return 1;
}

stock ShowRegisterConfirmDialog(playerid, const message[])
{
    PlayerInfo[playerid][pAuthState] = AUTH_REGISTER_CONFIRM;
    PlayerInfo[playerid][pExpectedDialog] = DIALOG_REGISTER_CONFIRM;
    ShowPlayerDialog(playerid, DIALOG_REGISTER_CONFIRM, DIALOG_STYLE_PASSWORD, "Confirm Registration Password", message, "Confirm", "Quit");
    return 1;
}

stock ShowUpdatesDialog(playerid)
{
    PlayerInfo[playerid][pAuthState] = AUTH_UPDATES;
    PlayerInfo[playerid][pExpectedDialog] = DIALOG_UPDATES;
    ShowPlayerDialog(playerid, DIALOG_UPDATES, DIALOG_STYLE_MSGBOX,
        "Server Update - Character Identity",
        "Latest server updates:\n\n- Every registered account is stored in SQLite\n- Character choices save after every completed step\n- Interrupted creation resumes safely after login\n- Eye color, ethnicity, height, and weight use validated lists\n- ESC during creation safely re-opens the current step\n- Completed characters skip the creation wizard permanently\n- /stats displays saved character information\n\nPress Continue to enter the server.",
        "Continue", "");
    return 1;
}

stock HandleFailedLogin(playerid, const message[])
{
    PlayerInfo[playerid][pLoginAttempts]++;
    if (PlayerInfo[playerid][pLoginAttempts] >= MAX_LOGIN_ATTEMPTS)
    {
        RejectUnauthenticated(playerid, "SERVER: Too many failed login attempts.");
        return 1;
    }

    ShowLoginDialog(playerid, message);
    return 1;
}

stock FinishAuthentication(playerid)
{
    StopLoginTimer(playerid);
    PlayerInfo[playerid][pExpectedDialog] = DIALOG_NONE;
    PlayerInfo[playerid][pAuthState] = AUTH_LOGGED_IN;
    PlayerInfo[playerid][pLogged] = true;

    ResetPlayerMoney(playerid);
    GivePlayerMoney(playerid, PlayerInfo[playerid][pMoney]);
    SetPlayerScore(playerid, PlayerInfo[playerid][pScore]);
    SetSpawnInfo(playerid, NO_TEAM, DEFAULT_SKIN,
        PlayerInfo[playerid][pPosX], PlayerInfo[playerid][pPosY], PlayerInfo[playerid][pPosZ], PlayerInfo[playerid][pAngle],
        WEAPON_FIST, 0, WEAPON_FIST, 0, WEAPON_FIST, 0);
    TogglePlayerSpectating(playerid, false);
    SpawnPlayer(playerid);
    return 1;
}

stock StopLoginTimer(playerid)
{
    if (PlayerInfo[playerid][pLoginTimer] != 0)
    {
        KillTimer(PlayerInfo[playerid][pLoginTimer]);
        PlayerInfo[playerid][pLoginTimer] = 0;
    }
    return 1;
}

stock CheckLoginState(playerid)
{
    if (!PlayerInfo[playerid][pLogged])
    {
        RejectUnauthenticated(playerid, "SERVER: You must authenticate before playing.");
        return 0;
    }
    return 1;
}

stock RejectUnauthenticated(playerid, const message[])
{
    if (IsPlayerConnected(playerid))
    {
        SendClientMessage(playerid, 0xFFFFFFFF, message);
        PlayerInfo[playerid][pExpectedDialog] = DIALOG_NONE;
        Kick(playerid);
    }
    return 1;
}

stock SavePlayer(playerid, reason)
{
    if (reason == 1)
    {
        GetPlayerPos(playerid, PlayerInfo[playerid][pPosX], PlayerInfo[playerid][pPosY], PlayerInfo[playerid][pPosZ]);
        GetPlayerFacingAngle(playerid, PlayerInfo[playerid][pAngle]);
    }

    PlayerInfo[playerid][pMoney] = GetPlayerMoney(playerid);
    PlayerInfo[playerid][pScore] = GetPlayerScore(playerid);
    PlayerInfo[playerid][pInterior] = GetPlayerInterior(playerid);
    PlayerInfo[playerid][pVirtualWorld] = GetPlayerVirtualWorld(playerid);

    new query[384];
    format(query, sizeof query,
        "UPDATE `users` SET `money`=%d,`score`=%d,`pos_x`=%f,`pos_y`=%f,`pos_z`=%f,`angle`=%f,`interior`=%d,`virtual_world`=%d WHERE `id`=%d LIMIT 1",
        PlayerInfo[playerid][pMoney], PlayerInfo[playerid][pScore],
        PlayerInfo[playerid][pPosX], PlayerInfo[playerid][pPosY], PlayerInfo[playerid][pPosZ], PlayerInfo[playerid][pAngle],
        PlayerInfo[playerid][pInterior], PlayerInfo[playerid][pVirtualWorld], PlayerInfo[playerid][pID]);
    new DBResult:result = DB_ExecuteQuery(gDatabase, query);
    if (result != DBResult:0)
    {
        DB_FreeResultSet(result);
    }
    return 1;
}

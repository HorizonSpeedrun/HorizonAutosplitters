// Created by Driver
// Updates:
// Gworld (state{} action), Gengine (state{} action), FNamePool (vars.Funcs.setGameVersion()) and executable hashes (vars.Funcs.setGameVersion())

state("LegoHorizonAdventures-Win64-Shipping", "v1.4.0.0-Steam"){
    // GWorld, levelFname
    ulong levelFName : 0x890E738, 0x18;
    // GWorld, Levels, Levels[1], WorldContainer, sceneFName
    ulong sceneFName : 0x890E738, 0x170, 0x8, 0x20, 0x18;

    // GEngine, GameInstance, 0x108, 0x1D0, goldBricks
    int goldBricks : 0x890B8A8, 0x1088, 0x108, 0x1D0, 0x2A4;
    // Gold bricks for the coop player:
    int goldBricksRemote : 0x890B8A8, 0xA58, 0xE8, 0xD00, 0x2B8, 0x8;

    // Loading flags:
    // GEngine, GameInstance, 0x108, GlowMusicSubsystem, GlowMusicGameplayHandler, Flag
    bool isPaused : 0x890B8A8, 0x1088, 0x108, 0x368, 0x288, 0x1EE;
    bool isCinematic : 0x890B8A8, 0x1088, 0x108, 0x368, 0x288, 0x1EF;
    bool isConversation : 0x890B8A8, 0x1088, 0x108, 0x368, 0x288, 0x1F1;
    bool isLoading : 0x890B8A8, 0x1088, 0x108, 0x368, 0x288, 0x208;
    bool isFadeToBlack : 0x890B8A8, 0x1088, 0x108, 0x368, 0x288, 0x209;
    bool isBetweenWorlds : 0x890B8A8, 0x1088, 0x108, 0x368, 0x288, 0x20A;
    bool isWorldTransition : 0x890B8A8, 0x1088, 0x108, 0x368, 0x288, 0x20B;
}

// EpicGames version's memory addresses are the same as the Steam version, as for patch
// 1.3, but an independant state is included here in case this changes in the future:
state("LegoHorizonAdventures-Win64-Shipping", "v1.4.0.0-EpicGames"){
    // GWorld, levelFname
    ulong levelFName : 0x890E738, 0x18;
    // GWorld, Levels, Levels[1], WorldContainer, sceneFName
    ulong sceneFName : 0x890E738, 0x170, 0x8, 0x20, 0x18;

    // GEngine, GameInstance, 0x108, 0x1D0, goldBricks
    int goldBricks : 0x890B8A8, 0x1088, 0x108, 0x1D0, 0x2A4;
    // Gold bricks for the coop player:
    int goldBricksRemote : 0x890B8A8, 0xA58, 0xE8, 0xD00, 0x2B8, 0x8;

    // Loading flags:
    // GEngine, GameInstance, 0x108, GlowMusicSubsystem, GlowMusicGameplayHandler, Flag
    bool isPaused : 0x890B8A8, 0x1088, 0x108, 0x368, 0x288, 0x1EE;
    bool isCinematic : 0x890B8A8, 0x1088, 0x108, 0x368, 0x288, 0x1EF;
    bool isConversation : 0x890B8A8, 0x1088, 0x108, 0x368, 0x288, 0x1F1;
    bool isLoading : 0x890B8A8, 0x1088, 0x108, 0x368, 0x288, 0x208;
    bool isFadeToBlack : 0x890B8A8, 0x1088, 0x108, 0x368, 0x288, 0x209;
    bool isBetweenWorlds : 0x890B8A8, 0x1088, 0x108, 0x368, 0x288, 0x20A;
    bool isWorldTransition : 0x890B8A8, 0x1088, 0x108, 0x368, 0x288, 0x20B;
}

// Script is executed
startup{
    // Object containing useful functions:
    vars.Funcs = new ExpandoObject();
    // Contains a list of checkpoints and coorelates with the split list:
    vars.checkpoints =  new Dictionary<string, ExpandoObject>();

    // Contains de autosplitter settings:
    dynamic[,] _settings = {
        // ID prefixes:
        // SSS: Start on scene start (currently not used)
        // SSE: Start on scene ending
        // WS: Split on world start (currently not used)
        // WE: Split on world ending
        // SS: Split on scene start (currently not used)
        // SE: Split on scene ending
        // GB: Split on gold brick
        // RB: Split on red brick (currently not used)
        // ID, Label, Tool tip, Parent ID, Default setting?
        {"SSE_StarterFrontendMap", "Start", "Starts the autosplitter automatically after starting a playthrough", null, true},
        {"m_quests", "Any%", null, null, true},
            {"WE_Prologue_P", "Prologue", "After completing the prologue", "m_quests", true},
            {"ch1", "Ch. 1- Rescuing the Nora", null, "m_quests", true},
                {"GB_B1_Room_003_Lighting_Day", "Into the woods", "", "ch1", true},
                {"GB_SR_B1_Tallneck_Exit_Lighting_Morning_Tallneck_Exit", "Head in the clouds", "", "ch1", true},
                {"GB_B1_Room_010_Lighting_Day_Forest", "Cult following", "", "ch1", true},
                {"GB_B1_Room_006_Lighting_Evening_Forest", "Face to the sun", "", "ch1", true},
                {"GB_TreasureRoom_01_Lighting_Evening", "A strange detour", "", "ch1", true},
                {"GB_B1_Room_004_Lighting_Night", "A girl and her destiny", "", "ch1", true},
            {"ch2", "Ch. 2 - Thunder in the Mountains", null, "m_quests", true},
                {"GB_B2_Room_001_Lighting_Day_Mountain", "The cold calling", "", "ch2", true},
                {"thaa", "The hills are alive", "None of the following interfiere with one another, so you can leave all of them checked", "ch2", true},
                    {"GB_B2_TreasureRoom_001_Lighting_Night_Mountain", "The hills are alive", "", "thaa", true},
                    {"GB_B2_TreasureRoom_001", "The hills are alive [Coop]", "Activate this one for coop playthroughs, but leave the oringinal one activated as well", "thaa", true},
                    {"GB_B2_TreasureRoom_001_Terrain", "The hills are alive [Coop]", "Activate this one for coop playthroughs, but leave the oringinal one activated as well", "thaa", true},
                {"GB_B2_Room_003_Lighting_Day_Mountain", "Frosted peaks", "", "ch2", true},
                {"GB_B2_TreasureRoom_001_Lighting_Day_Mountain", "The shivering summit", "", "ch2", true},
                {"GB_B2_Room_007_Lighting_Evening_Mountain", "A tower achievement", "", "ch2", true},
                {"GB_Cau_Boss_Lighting", "The belly of the beast", "", "ch2", true},
            {"ch3", "Ch. 3 - Desperately Seeking Sawtooths", null, "m_quests", true},
                {"GB_B3_Room_001_Lighting_Morning_Jungle", "Lair of the tree haters", "", "ch3", true},
                {"dus", "Digging up secrets", "", "ch3", true},
                    {"GB_SR_B3_Tallneck_01_Exit_Lighting_Day_Jungle", "Tallneck route", "", "dus", true},
                    {"GB_B3_TreasureRoom_001_Lighting_Day_Jungle", "Battle route", "", "dus", true},
                {"GB_B3_Room_006_Lighting_Evening_Jungle", "Home cooking", "", "ch3", true},
                {"GB_B3_Room_009_Lighting_Night_Jungle", "Legend of the mithyc tale", "", "ch3", true},
                {"inr", "Instructions not required", "None of the following interfiere with one another, so you can leave all of them checked", "ch3", true},
                    {"GB_B3_Boss_Room_BiomassFacility_Lighting", "Instructions not required", "On gold brick, single player", "inr", true},
                    {"GB_B3_Boss_Room_BiomassFacility", "Instructions not required [Coop]", "Activate this one for coop playthroughs, but leave the oringinal one activated as well", "inr", true},
                    {"GB_B3_Boss_Room_BiomassFacility_Terrain", "Instructions not required [Coop]", "Activate this one for coop playthroughs, but leave the oringinal one activated as well", "inr", true},
            {"ch4", "Ch. 4 - Drawing Out Helis", null, "m_quests", true},
                {"GB_B4_Room_002_Lighting_Day_Desert", "The desert flower", "", "ch4", true},
                {"GB_B4_Room_004_Lighting_Day_Desert", "Flavors of a lost world", "", "ch4", true},
                {"mato", "Midday at the oasis", "", "ch4", true},
                    {"GB_SR_B4_Tallneck_01_Exit_Lighting_Day_Desert", "Tallneck route", "", "mato", true},
                    {"GB_B4_TreasureRoom_001_Lighting_Day_Desert", "Battle route", "", "mato", true},
                {"GB_B4_Room_007_Lighting_Night_Desert", "We can be heroes", "", "ch4", true},
                {"GB_B4_Room_005_Lighting_Evening_Desert", "Sundown showdown", "", "ch4", true},
                {"SE_B5_Room_003_Lighting_Destruction_Jungle", "Pre-Hades", "Right before entering the final battle, before the loading screen.", "ch4", false},
                {"GB_B5_Boss_Room_001_Lighting_Destruction_Jungle_Hell", "The final battle", "", "ch4", true}
    };

    // Calculates the hash of a given module.
    // Taken from ISO2768mK's Horizon Forbidden West load remover:
    vars.Funcs.hashModule = (Func<ProcessModuleWow64Safe, string>)((module) => {
        byte[]  hashBytes = new byte[0];
        using (var sha256Object = System.Security.Cryptography.SHA256.Create())
        {
            using (var binary = File.Open(module.FileName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                hashBytes = sha256Object.ComputeHash(binary);
            }
        }
        var hexHashString = hashBytes.Select(x => x.ToString("X2")).Aggregate((a, b) => a + b);
        return hexHashString;
    });

    // Default variables (Patch 1.4.0.0 Steam version):
    version = "v1.4.0.0-Steam";
    vars.FNamePoolOffset = 0x86EBDC0;
    // Determines the running game version and initialize variables acordingly:
    // Patch 1.4.0.0 EpicGames:
    vars.Funcs.setGameVersion = (Action<string>)((hash) => {
        if(hash == "5EF34C4A1D75419D344F1C6B24C5354E02CB8E633776C95FEC608151410A2C1F"){
            version = "v1.3.0.0-EpicGames";
            vars.FNamePoolOffset = 0x86EBDC0;
            print("Detected game version: " + version);
        // Patch 1.4.0.0 Steam:
        }else if(hash == "7344F667E834475C75A0A03FA238E6FC5FE979780FFE755340B46E80F2E4BCCA"){
            // Don't do anything, the default variables are the Steam ones...
            print("Detected game version: " + version);
        }
        else{
            // If no version was identified, show a warning message:
            MessageBox.Show(
                "The Autosplitter could not identify the game version, the default version was set to " + version + ".\nIf this is not the version of your game, the Autosplitter might not work properly.",
                "LHA Autosplitter",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning
            );
        }
    });

    // Initialize the autosplitter settings
    dynamic tmp = null;
    for (int i = 0; i < _settings.GetLength(0); i++){
        tmp = new ExpandoObject();
        tmp.reachedBefore = false;
        // Autosplitter settings entry:
        // settings.Add(id, default_value = true, description = null, parent = null)
        settings.Add(_settings[i, 0], _settings[i, 4], _settings[i, 1], _settings[i, 3]);
        // Tool tip message (if available)
        if(_settings[i, 2] != null){
            settings.SetToolTip(_settings[i, 0], _settings[i, 2]);
        }
        vars.checkpoints.Add(_settings[i, 0], tmp);
    }
} // startup ends

init{
    // Gets the running game module hash:
    var moduleHash = vars.Funcs.hashModule(modules.First());
    print(moduleHash);

    // Initialize variables acording to the running version:
    vars.Funcs.setGameVersion(moduleHash);

    // Determines if the game is currently loading:
    vars.Funcs.isLoading = (Func<bool>)(() => {
        // Comment out unwanted flags:
        return
            // current.isPaused || // Pause menu (the one when you press ESC)
            // current.isCinematic || // Cinematics
            // current.isConversation || // Conversations
            current.isLoading || // General game loading
            // current.isFadeToBlack || // That brief moment when the screen fades in or out
            current.isBetweenWorlds || // Scene and world transitions
            current.isWorldTransition; // World transitions
            // Title screen:
            // vars.Funcs.FNameToString(current.levelFName) == "StarterFrontendMap";
    });

    // Determines if it is time to split:
    vars.Funcs.isSplit = (Func<string, bool>)((splitName) => {
        if(
            // Splits only if the user has enabled this split in the autosplitter settings:
            settings[splitName] &&
            // Splits only once per checkpoint:
            !vars.checkpoints[splitName].reachedBefore
        ){ 
            vars.checkpoints[splitName].reachedBefore = true;
            print("SPLIT: " + splitName);
            return true;
        }
        else{
            return false;
        }
    });

    // Unreal Engine's structures ********************************************
    IntPtr FNamePool = modules.First().BaseAddress + vars.FNamePoolOffset;
    // ***********************************************************************

    // Takes an FName object and returns the asociated string.
    // Based on TheDementedSalad's Silent Hill 2 remake autosplitter:
    vars.Funcs.FNameToString = (Func<ulong, string>)(fName => {
        var nameIdx  = (fName & 0x000000000000FFFF) >> 0x00;
        var chunkIdx = (fName & 0x00000000FFFF0000) >> 0x10;

        IntPtr chunk = memory.ReadValue<IntPtr>(FNamePool + 0x10 + (int)chunkIdx * 0x8);
        IntPtr entry = chunk + (int)nameIdx * sizeof(short);

        int length = memory.ReadValue<short>(entry) >> 6;
        string name = memory.ReadString(entry + sizeof(short), length);

        return name;
	});
} // init ends

update{
    // print(vars.Funcs.FNameToString(current.levelFName));
    // print(vars.Funcs.FNameToString(current.sceneFName));
    // print(current.goldBricksRemote.ToString());
}

isLoading{
    return vars.Funcs.isLoading();
}

start{
    if(old.levelFName != current.levelFName){
        var currentWorldName = vars.Funcs.FNameToString(current.levelFName);
        var oldWorldName = vars.Funcs.FNameToString(old.levelFName);
        print("\n\nWorld changed: " + currentWorldName);
        // World ending starting points:
        if(vars.Funcs.isSplit("SSE_" + oldWorldName)){
            return true;
        }
    }
}

split{
    // Checks if the timer is actually running:
    if (timer.CurrentPhase == TimerPhase.Running){
        var currentSceneName = vars.Funcs.FNameToString(current.sceneFName);
        // Gold brick splits:
        if(current.goldBricks > old.goldBricks || current.goldBricksRemote != old.goldBricksRemote){
            print("\n\nGold brick collected.");
            print("Local gold bricks: " + current.goldBricks.ToString() + " | " + "Remote gold bricks: " + current.goldBricksRemote.ToString());
            if(vars.Funcs.isSplit("GB_" + currentSceneName)){
                return true;
            }
        }
        // World splits:
        if(old.levelFName != current.levelFName){
            var currentWorldName = vars.Funcs.FNameToString(current.levelFName);
            var oldWorldName = vars.Funcs.FNameToString(old.levelFName);
            print("\n\nWorld changed: " + currentWorldName);
            // World ending splits:
            if(vars.Funcs.isSplit("WE_" + oldWorldName)){
                return true;
            }
            // World start splits:
            if(vars.Funcs.isSplit("WS_" + currentWorldName)){
                return true;
            }
        }
        // Scene splits:
        if(old.sceneFName != current.sceneFName){
            var oldSceneName = vars.Funcs.FNameToString(old.sceneFName);
            print("\n\nScene changed: " + currentSceneName);
            // Scene ending splits:
            if(vars.Funcs.isSplit("SE_" + oldSceneName)){
                return true;
            }
            // Scene start splits:
            if(vars.Funcs.isSplit("SS_" + currentSceneName)){
                return true;
            }
        }
    }
}

onReset{
    foreach (var checkpoint in vars.checkpoints){
        checkpoint.Value.reachedBefore = false;
    }
}

// Clean up to pre-init state when game process is closed
exit {
    foreach (var checkpoint in vars.checkpoints){
        checkpoint.Value.reachedBefore = false;
    }
}
// exit END

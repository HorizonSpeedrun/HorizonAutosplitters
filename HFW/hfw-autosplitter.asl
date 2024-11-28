// Created by Driver and ISO2768mK
// Version detection from the Death Stranding and Alan Wake ASL

state("HorizonForbiddenWest", "v1.5.80.0-Steam")
{
    uint loading : 0x08983150, 0x4B4;
    // Player => HorizonForbiddenWest.exe+8982DA0
    // Humanoid entity:
    // 0x8982DA0, 0x1C10, 0x0, 0x10
    // Aloy's position:
    double WestEast : 0x8982DA0, 0x1C10, 0x0, 0x10, 0xD8; // X [West-East]
    double SouthNorth : 0x8982DA0, 0x1C10, 0x0, 0x10, 0xE0; // Y [South-North]
    double DownUp : 0x8982DA0, 0x1C10, 0x0, 0x10, 0xE8; // Z [Down-Up]
    // Destructibility:
    // 0x8982DA0, 0x1C10, 0x0, 0x10, 0xD0
    // Aloy's invulnerable flag:
    // byte isGod :  0x8982DA0, 0x1C10, 0x0, 0x10, 0xD0, 0x70;    
}
state("HorizonForbiddenWest", "v1.5.80.0-Epic")
{
    uint loading : 0x0895EF50, 0x4B4;
    // Player => HorizonForbiddenWest.exe+895EBC8
    // Humanoid entity:
    // 0x895EBC8, 0x1C10, 0x0, 0x10
    // Aloy's position:
    double WestEast : 0x895EBC8, 0x1C10, 0x0, 0x10, 0xD8; // X [West-East]
    double SouthNorth : 0x895EBC8, 0x1C10, 0x0, 0x10, 0xE0; // Y [South-North]
    double DownUp : 0x895EBC8, 0x1C10, 0x0, 0x10, 0xE8; // Z [Down-Up]
    // Destructibility:
    // 0x895EBC8, 0x1C10, 0x0, 0x10, 0xD0
    // Aloy's invulnerable flag:
    // byte isGod :  0x895EBC8, 0x1C10, 0x0, 0x10, 0xD0, 0x70;
}

/*
Getting address for new game version:

Value (HEX)
48 8B 05 ?? ?? ?? ?? 48 85 C0 74 15 83 B8 B4 04 00 00 00 75 0C 83 B8 74 06 00 00 02 74 03 B0 01 C3 32 C0

Alternatively, giving multiple results:
83 B8 B4 04 00 00 00 (hard coded for RAX register)
83 ?? B4 04 00 00 00 (matches any register)

Options:
In static memory (HFW in the process dropdown)
Clear Writable, Check Executable flags
Clear Fast Scan (we probably don't have alignment)

Perform Scan

Right Click -> Disassemble this memory region

Get the value after "HorizonForbiddenWest+" -> this is the offset we need
*/

startup
{
    Action<string> DebugOutput = (text) => {
        if (false)
        {
            print("[HFW Load Remover Debug] " + text);
        }
    };
    vars.DebugOutput = DebugOutput;

    Action<string> InfoOutput = (text) => {
        print("[HFW Load Remover] " + text);
    };
    vars.InfoOutput = InfoOutput;

    Func<ProcessModuleWow64Safe, string> CalcModuleHash = (module) => {
        byte[] exeHashBytes = new byte[0];
        using (var sha = System.Security.Cryptography.SHA256.Create())
        {
            using (var s = File.Open(module.FileName, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            {
                exeHashBytes = sha.ComputeHash(s);
            }
        }
        var hash = exeHashBytes.Select(x => x.ToString("X2")).Aggregate((a, b) => a + b);
        return hash;
    };
    vars.CalcModuleHash = CalcModuleHash;

    // Object containing useful functions:
    vars.Funcs = new ExpandoObject();
    // Contains a list of checkpoints and coorelates with the split list:
    vars.checkpoints =  new Dictionary<string, ExpandoObject>();
    vars.legacyCheckpoints = new Dictionary<string, ExpandoObject>();
    // Checkpoints with known pointers:
    vars.memWatchers = new MemoryWatcherList();
    // Required to split outside the split action:
    vars.timerController = new TimerModel { CurrentState = timer };
    // Mirror variables:
    vars.isLoading = 0;
    vars.WestEast = 0;
    vars.SouthNorth = 0;
    vars.DownUp = 0;

    // Determines if Aloy is over a given checkpoint zone:
    vars.Funcs.isLegacySplit = (Func<double, double, double, dynamic>)((
            playerPosX, playerPosY, playerPosZ
    ) => {
        dynamic result = new ExpandoObject();
        result.isLegacySplit = false;
        result.splitName = null;
        result.splitType = null;
        foreach(var checkpoint in vars.legacyCheckpoints){
            if(
                // Checks if Aloy is in checkpoint zone West-East:
                (checkpoint.Value.geolocation[0] - checkpoint.Value.geolocation[3]) < playerPosX &&
                (checkpoint.Value.geolocation[0] + checkpoint.Value.geolocation[3]) > playerPosX &&
                // Checks if Aloy is in checkpoint zone South-North:
                (checkpoint.Value.geolocation[1] - checkpoint.Value.geolocation[3]) < playerPosY &&
                (checkpoint.Value.geolocation[1] + checkpoint.Value.geolocation[3]) > playerPosY &&
                // Checks if Aloy is in checkpoint zone vertically:
                (checkpoint.Value.geolocation[2] - checkpoint.Value.geolocation[3]) < playerPosZ &&
                (checkpoint.Value.geolocation[2] + checkpoint.Value.geolocation[3]) > playerPosZ
            ){
                result.isLegacySplit = true;
                result.splitName = checkpoint.Key;
                result.splitType = checkpoint.Value.Type;
                break;
            }
        }
        return result;
    });

    // Splits:
    vars.Funcs.Split = (Action<dynamic>)((splitObject) => {
        if(splitObject.Type == "start"){
            vars.timerController.Start();
        }
        if(splitObject.Type == "stop"){
            vars.timerController.Stop();
        }
        if(
            splitObject.Type == "split" ||
            splitObject.Type == "cutscene"
        ){
            // Checks if timer is actually running:
            if (timer.CurrentPhase == TimerPhase.Running){
                vars.timerController.Split();
                splitObject.reachedBefore = true;
                print("SPLIT: " + splitObject.Name);
            }
        }
    });

    // Contains de autosplitter settings:
    dynamic[,] _settings = {
        // Main game
        // ID, Label, Tool tip, Parent ID, Default setting?
        {"main_game", "Main game", "Main game splits", null, true},
            // STARTING POINTS
            {"mg_starting_points", "Starting points", "Select when livesplit will start the timer", "main_game", true},
                // NEW GAME+
                {"NGP_start", "NG+", "When the last cutscene before the cable car ride into the Daunt is skipped.", "mg_starting_points", true},
            // MAIN QUESTS:
            {"mg_quests", "Quests", null, "main_game", true},
                // TO THE BRINK
                {"to_the_brink", "To the brink", null, "mg_quests", true},
                    {"chainscrape_entrance", "Go to Chainscrape", "After talking to the guards", "to_the_brink", true},
                    {"find_erend", "Find Erend", "When the cutscene where Aloy finds Erend starts platying", "to_the_brink", true},
                    {"scroungers", "Scroungers", "After killing the scroungers and talking to Thurlis", "to_the_brink", true},
                    {"ttb_talk_to_erend", "Talk to Erend", "After killing the machines and talk to Erend", "to_the_brink", true},
                    {"clear_the_daunt", "Clear the Daunt", "After killing the Bristlebacks and talk with the Oseram worker", "to_the_brink", true},
                    {"chainscrape_campfire", "Chainscrape campfire", "When fast traveling to the campfire", "to_the_brink", true},
                    {"talk_to_ulvund", "Talk to Ulvund", "After Ulvund declares the work stoppage over", "to_the_brink", true},
                    {"to_the_brink_end", "To the brink completion", "After talking to Vuadis", "to_the_brink", true},
                // THE EMBASSY
                {"the_embassy", "The Embassy", null, "mg_quests", true},
                    {"ft_barren_light_campfire", "Go to Barren Light (campfire)", "After fast traveling to Barren Light's campfire", "the_embassy", true},
                    {"ft_barren_light_entrance", "Go to Barren Light (setlement)", "After fast traveling directly to Barren Light", "the_embassy", true},
                    {"barren_light_guards", "Talk to the Guards", "When talking to Lawan", "the_embassy", true},
                    {"commander_ozar", "Talk to Commander Nozar", "After talking to Commander Nozar", "the_embassy", true},
                    {"after_ambush", "After the ambush", "After killing Grudda and while talking to Lawan", "the_embassy", true},
                // DEATH'S DOOR
                {"deaths_door", "Death's Door", null, "mg_quests", true},
                    {"ft_tallneck_cinnabar_sands", "Tallneck: Cinnabar Sands", "When fast travelling to the tallneck", "deaths_door", true},
                    {"workshop_console", "Examine the Device", "After interacting with the console at Silence's workshop", "deaths_door", true},
                    {"latopolis_orb", "Follow the Orb's Trail", "After interacting with the orb", "deaths_door", true},
                    {"latopolis_firegleam1", "Ignite the Firegleam 1", "After interacting with the firegleam", "deaths_door", true},
                    {"latopolis_hatch", "Gene-Locked Hatch", "After interacting with the Gene-Locked Hatch", "deaths_door", true},
                    // {"latopolis_fight_ending", "Erik fight finishes", "After Erik fight", "deaths_door", true},
                    {"latopolis_firegleam2", "Ignite the Firegleam 2", "After interacting with the firegleam", "deaths_door", true},
                    {"deaths_door_end", "Death's Door quest completion", "After all the cutscenes", "deaths_door", true},
                // THE DYING LANDS
                {"dying_lands", "The Dying Lands", null, "mg_quests", true},
                    {"ft_campfire_cinnabar_sands", "Cinnabar Sands campfire Fast travel", "After fast traveling to the campfire", "dying_lands", true},
                    {"tdl_varl_and_zo2", "Meet Varl and Zo outside the Chorus", "After second talk with Varl and Zo", "dying_lands", true},
                    {"tau_door", "Override Tau Door", "When overriding the cauldron door", "dying_lands", true},
                    {"tau_core_bay", "Go to the Repair Bay Core", "After overriding the core door", "dying_lands", true},
                    {"tau_core", "Override the Repair Bay Core", "When overriding the Repair Bay Core", "dying_lands", true},
                    { "tdl_end", "The Dying Lands completion", "After the scripted animation of the new machine overrides", "dying_lands", true},
                // THE EYE OF THE EARTH
                {"eye_of_the_earth", "The Eye of the Earth", null, "mg_quests", true},
                    {"eote_minerva_console", "Examine the Console", "When playing the cutscene", "eye_of_the_earth", true},
                    {"eote__end", "The Eye of the Earth completion", "After leaving the base", "eye_of_the_earth", true},
                // THE SEA OF SANDS
                {"sea_of_sands", "The Sea of Sands", null, "mg_quests", true},
                    {"compressed_air_capsule", "Recover the Compressed Air Capsule", "When recovering the compressed air capsule", "sea_of_sands", true},
                    {"diving_mask", "Craft the Diving Mask", "After crafting the diving mask", "sea_of_sands", true},
                    {"main_pump", "Drain the City", "After interacting with the console at the main station", "sea_of_sands", true},
                    {"recover_poseidon", "Recover Poseidon", "When recovering Poseidon from the kernel console", "sea_of_sands", true},
                    {"las_vegas_exit", "Exit the Ruin", "After skiping the last cutscene", "sea_of_sands", true},
                    {"tsos_end", "The Sea of Sands completion", "After delivering Poseidon to Gaia", "sea_of_sands", true},
                // THE BROKEN SKY
                {"broken_sky", "The Broken Sky", null, "mg_quests", true},
                    {"throne_room", "Go to the Throne Room", "When reaching the Throne Room", "broken_sky", true},
                    {"tbs_talk_to_kotallo1", "Meet Kotallo at Stone Crest", "When talking to Kotallo at Stone Crest", "broken_sky", true},
                    {"tbs_kotallo_skip", "After Kotallo skip", "After skipping the cutscene", "broken_sky", true},
                    {"bulwark_guards", "Talk to the Guard", "When meeting Tekotteh for the first time", "broken_sky", true},
                    {"tbs_talk_to_kotallo2", "Talk to Kotallo", "When talking to Kotallo, after scanning the ancient debris", "broken_sky", true},
                    {"loot_the_tremortusk", "Loot the Tremortusk", "When looting the Tremortusk", "broken_sky", true},
                    {"broken_sky_end", "The Broken Sky completion", "After skipping the wall cutscene", "broken_sky", true},
                // SEEDS OF THE PAST
                {"seeds_of_the_past", "Seeds of the past", null, "mg_quests", true},
                    {"green_house", "Go to DEMETER's Coordinates", "When the first cutscene plays (the one of the Quen)", "seeds_of_the_past", true},
                    {"console1_active", "Examine the Console", "After interacting with the 1st console", "seeds_of_the_past", true},
                    {"console2_room", "Enter the Facility", "After meeting Alva for the first time", "seeds_of_the_past", true},
                    {"console2_active", "Examine the Paired Console", "After interacting with the paired console", "seeds_of_the_past", true},
                    {"tunnel1_exit", "Search the Tunnels for an Exit", "After exiting the first tunnel", "seeds_of_the_past", true},
                    {"station_elm_console", "Examine the Paired Console", "After activating the paired console", "seeds_of_the_past", true},
                    {"test_station_ivy", "Test Station Ivy", "When entering Test Station Ivy", "seeds_of_the_past", true},
                    {"recover_demeter", "Recover DEMETER", "When recovering Demeter from the kernel console", "seeds_of_the_past", true},
                    {"sotp_end", "Seeds of the past completion", "After delivering Demeter to Gaia", "seeds_of_the_past", true},
                // CRADLE OF ECHOES
                {"cradle_of_echoes", "Cradle of echoes", null, "mg_quests", true},
                    {"coe_console2", "Examine the main Console", "Before entering the ectogenic chambers code", "cradle_of_echoes", true},
                    {"coe_specter2", "Kill the Specter 2", "After killing the second Specter", "cradle_of_echoes", true},
                // THE KULRUT
                {"kulrut", "The Kulrut", null, "mg_quests", true},
                    {"ft_memorial_grove", "Go the the Memorial Grove", "When fast traveling to The Memorial Grove", "kulrut", true},
                    {"k_talk_to_hekarro", "Talk to Hekarro", "When talkint to Hekarro and Kotallo", "kulrut", true},
                    {"k_machines", "Kill the Machines", "After killing the machines", "kulrut", true},
                    {"k_Slitherfang", "Kill the Slitherfang", "After killing the Slitherfang and skipping the cutscene", "kulrut", true},
                    {"recover_aether", "Recover Aether", "While recovering Aether from the kernel console", "kulrut", true},
                    {"kulrut_end", "The Kulrut completion", "After delivering Aether to Gaia", "kulrut", true},
                // FARO'S TOMB
                {"faros_tomb", "Faro's Tomb", null, "mg_quests", true},
                    {"fst_boat", "Boat", "When interacting with the boat", "faros_tomb", true},
                    {"fst_legacys_landfall", "Legacy's Landfall", "When talking to the guards", "faros_tomb", true},
                    {"fst_talk_to_alva", "Talk to Alva", "When talking to Alva at Thebes", "faros_tomb", true},
                    {"fst_entrance_skip", "Thebes entrance skip", "After the first skip, when openning the first door", "faros_tomb", true},
                    {"fst_Corruptors", "Corruptors hall exit", "When openning the exit door from the Corruptors hall", "faros_tomb", true},
                    {"fst_omega_clearance", "Recover Ted Faro's Omega Clearance", "When intrecting with the console", "faros_tomb", true},
                    {"faros_tomb_end", "Faro's Tomb completion", "After skipping the escape cutscene", "faros_tomb", true},
                // GEMINI
                {"gemini", "Gemini", null, "mg_quests", true},
                    {"g_gemini", "Go to Gemini", "After skipping the ride cutscene", "gemini", true},
                    {"g_node1", "Override the Network Uplink 1", "After overriding the 1st chamber node", "gemini", true},
                    {"g_talk_to_beta", "Return to Beta and Varl", "Before the tragedy at Gemini", "gemini", true},
                // THE WINGS OF THE TEN
                {"wings_of_the_ten", "The wings of the ten", null, "mg_quests", true},
                    {"wott_sunwing_override", "Mount a Sunwing", "When the cutscene starts playing", "wings_of_the_ten", true},
                    {"wott_memorial_grove", "Fly to the Memorial Grove", "When the battle cutscene starts playing", "wings_of_the_ten", true},
                    // {"wott_regalla1", "Regalla fight phase 1 passed", "After the 1st phase of Regalla fight", "wings_of_the_ten", true},
                    // {"wott_regalla2", "Regalla fight phase 2 passed", "After the 2nd phase of Regalla fight", "wings_of_the_ten", true},
                    // {"wott_regalla3", "Regalla fight phase 3 passed", "After the 3d phase of Regalla fight", "wings_of_the_ten", true},
                    {"wings_of_the_ten_end", "The wings of the ten completion", "After skipping Silence cutscene", "wings_of_the_ten", true},
                // SINGULARITY
                {"singularity", "Singularity", null, "mg_quests", true},
                    {"s_shield_skip", "Shield skip", "Meassures the infamous Far Zenith base skip", "singularity", true},
                    {"kill_erik", "Kill Erik", "After sending that mf directly to his private suite in hell", "singularity", true},
                    {"s_tower_top", "Go to the Top of the Tower", "After activating the console at the top of the tower", "singularity", true},
                    {"s_defeat_tilda", "Defeat Tilda", "When the cutscene, after you get the objective 'Return to the Control Center', starts", "singularity", true}
    };

    // Initialize autosplit settings
    for (int i = 0; i < _settings.GetLength(0); i++){
        // Autosplitter settings entry:
        // settings.Add(id, default_value = true, description = null, parent = null)
        settings.Add(_settings[i, 0], _settings[i, 4], _settings[i, 1], _settings[i, 3]);

        // Tool tip message (if available)
        if(_settings[i, 2] != null){
            settings.SetToolTip(_settings[i, 0], _settings[i, 2]);
        }
    }
}

init
{
    var module = modules.Single(x => String.Equals(x.ModuleName, "HorizonForbiddenWest.exe", StringComparison.OrdinalIgnoreCase));
    // No need to catch anything here because LiveSplit wouldn't have attached itself to the process if the name wasn't present

    var moduleSize = module.ModuleMemorySize;
    var hash = vars.CalcModuleHash(module);
    vars.DebugOutput(module.ModuleName + ": Module Size " + moduleSize + ", SHA256 Hash " + hash);

    int GameModule = 0x08983150;
    int SceneManagerGame = 0x08982DD0;
    int Player = 0x08982DA0;

    version = "";
    if (hash == "9CEC6626AB60059D186EDBACCA4CE667573E8B28C916FCA1E07072002055429E")
    {
        version = "v1.5.80.0-Steam";
        // Don't do anything, the default variables are the Steam ones...
    }
    else if (hash == "8274587FA89612ADF904BDB2554DEA84D718B84CF691CCA9D2FB7D8D5D5D659B")
    {
        version = "v1.5.80.0-Epic";
        GameModule = 0x895EF50;
        SceneManagerGame = 0x895EBB8;
        Player = 0x895EBC8;
    }
    
    if (version != "")
    {
        vars.InfoOutput("Recognized version: " + version);
    }
    else
    {
        version = "v1.5.80.0-Steam";
        vars.InfoOutput("Unrecognized version of the game.");
        // If no version was identified, show a warning message:
        MessageBox.Show(
            "The Autosplitter could not identify the game version, the default version was set to " + version + ".\nIf this is not the version of your game, the Autosplitter will not work properly.",
            "HFW Autosplitter",
            MessageBoxButtons.OK,
            MessageBoxIcon.Warning
        );
    }

    // Contains the autosplitter checkpoints:
    // settings_ID, game progression pointer, location-based information, splitType
    dynamic[,] _checkpoints = {
        // Main game
            // NEW GAME+ starting point
            {"NGP_start", new DeepPointer("HorizonForbiddenWest.exe", SceneManagerGame, 0xE8, 0x1770, 0x1140, 0x16E1), null, "start"},
            // TO THE BRINK
                {"chainscrape_entrance", new DeepPointer("HorizonForbiddenWest.exe", SceneManagerGame, 0xE0, 0x1E0, 0x321), null, null},
                {"find_erend", null, new double[]{3441.31976318359, 152.444046020508, 497.432891845703, 3}, "cutscene"},
                {"scroungers", new DeepPointer("HorizonForbiddenWest.exe", SceneManagerGame, 0xE0, 0xDB8, 0xE61), null, null},
                {"ttb_talk_to_erend", null, new double[]{3477.35439284111, 132.332308891053, 495.012863606143, 2}, null},
                {"clear_the_daunt", new DeepPointer("HorizonForbiddenWest.exe", SceneManagerGame, 0xF8, 0x9B0, 0x888, 0xBA1), null, null},
                {"chainscrape_campfire", null, new double[]{3503.09459523606, 634.741075281604, 496.060607537627, 0.5}, null},
                {"talk_to_ulvund", new DeepPointer("HorizonForbiddenWest.exe", SceneManagerGame, 0xE0, 0x2A8, 0x518, 0x4A1), null, null},
                {"to_the_brink_end", new DeepPointer("HorizonForbiddenWest.exe", SceneManagerGame, 0x180, 0x930, 0x8D0, 0x239), null, null},
            // THE EMBASSY
                {"ft_barren_light_campfire", null, new double[]{3040.32467007056, 17.4176695265878, 465.806756163831, 0.5}, null},
                {"ft_barren_light_entrance", null, new double[]{3067.86202363374, 29.2769007543735, 465.452685935666, 0.5}, null},
                {"barren_light_guards", null, new double[]{3002.35785949576, -41.6765262664212, 460.219214364889, 1}, null},
                {"commander_ozar", null, new double[]{2991.17514877998, -52.8676416632364, 478.43438106914, 3}, null},
                {"after_ambush", new DeepPointer("HorizonForbiddenWest.exe", SceneManagerGame, 0xF8, 0x708, 0xDD8, 0xC41), null, null},
            // DEATH'S DOOR
                {"ft_tallneck_cinnabar_sands", null, new double[]{2104.00830694698, -263.949649523822, 450.753540039062, 0.5}, null},
                {"workshop_console", null, new double[]{1882.06305419515, -886.340802022707, 398.268561203955, 20}, "cutscene"},
                {"latopolis_orb", null, new double[]{1419.53016905987, -1067.06460825383, 419.140068532041, 1}, null},
                {"latopolis_firegleam1", null, new double[]{1407.47410455747, -1055.19197075368, 419.233367919912, 1}, null},
                {"latopolis_hatch", null, new double[]{1317.90443750157, -957.90438052909, 427.137498855591, 1}, null},
                // {"latopolis_fight_ending", null, new double[]{1279.18542480469, -912.010620117188, 428.282501220703, 3}, null},
                {"latopolis_firegleam2", null, new double[]{1167.81559193197, -1016.70593891713, 382.643293593338, 3}, null},
                {"deaths_door_end", new DeepPointer("HorizonForbiddenWest.exe", SceneManagerGame, 0xF8, 0xE38, 0x9D0, 0x951), null, null},
            // THE DYING LANDS
                {"ft_campfire_cinnabar_sands", null, new double[]{2087.25383485531, -253.908564715671, 450.657012939452, 1}, null},
                {"tdl_varl_and_zo2", null, new double[]{1826.52198698616, 97.3018469927963, 474.47509765625, 1}, null},
                {"tau_door", null, new double[]{1316.74923604789, -63.4205509014469, 506.636282503605, 1}, null},
                {"tau_core_bay", null, new double[]{1205.16775083477, -136.799048344064, 511.843992233614, 3}, null},
                {"tau_core", null, new double[]{1204.66921516848, -182.61169032363, 499.119144171476, 3}, null},
                {"tdl_end", new DeepPointer("HorizonForbiddenWest.exe", SceneManagerGame, 0x180, 0x738, 0x688, 0x239), null, null},
            // THE EYE OF THE EARTH
                {"eote_minerva_console", new DeepPointer("HorizonForbiddenWest.exe", SceneManagerGame, 0xE0, 0xCB0, 0x811), null, null},
                {"eote__end", new DeepPointer("HorizonForbiddenWest.exe", SceneManagerGame, 0xE0, 0xE48, 0x158, 0x3B1), null, null},
            // THE SEA OF SANDS
                {"compressed_air_capsule", null, new double[]{168.197416841984, -1755.24666068276, 361.263234436512, 3}, null},
                {"diving_mask", null, new double[]{178.927001953126, -1750.46426391601, 379.8254109025, 0.5}, null},
                {"main_pump", null, new double[]{330.186260598925, -1928.74938051968, 321.2208007395, 3}, "cutscene"},
                {"recover_poseidon", null, new double[]{375.885487531169, -1607.85799177243, 290.981842041016, 3}, "cutscene"},
                {"las_vegas_exit", new DeepPointer("HorizonForbiddenWest.exe", SceneManagerGame, 0xE8, 0xDC0, 0x5A8, 0xD99), null, null},
                {"tsos_end", new DeepPointer("HorizonForbiddenWest.exe", SceneManagerGame, 0xE0, 0x4F0, 0x1D0, 0x3F1), null, null},
            // THE BROKEN SKY
                {"throne_room", null, new double[]{-633.393053667102, -718.194006942366, 421.632792890072, 3}, null},
                {"tbs_talk_to_kotallo1", null, new double[]{-1319.54060840607, 552.306657314301, 505.025085449219, 3}, null},
                {"tbs_kotallo_skip", null, new double[]{-1722.13291072914, 391.312653769435, 404.777789474833, 1.5}, null},
                {"bulwark_guards", null, new double[]{-1713.9067993164, 299.763214111328, 445.635046988725, 3}, null},
                {"tbs_talk_to_kotallo2", null, new double[]{-1729.97919063644, 457.684209887134, 370.633636476527, 1.5}, null},
                {"loot_the_tremortusk", null, new double[]{-1572.0311859101, 652.102480441332, 383.739666610956, 3}, "cutscene"},
                {"broken_sky_end", new DeepPointer("HorizonForbiddenWest.exe", GameModule,  0x178, 0x10, 0xE0, 0xF68, 0x321), null, null},
            // SEEDS OF THE PAST
                {"green_house", null, new double[]{-2296.29821777344, -324.549560546875, 264.058563187719, 5}, null},
                {"console1_active", null, new double[]{-2431.87329865314, -180.895613586446, 274.75841699494, 2.5}, null},
                {"console2_room", null, new double[]{-2432.61199035513, -299.38409430339, 262.721442762085, 2.5}, null},
                {"console2_active", null, new double[]{-2436.56268157932, -309.137984056258, 262.734527587883, 2.5}, null},
                {"tunnel1_exit", null, new double[]{-2327.60716285157, -209.519637505797, 261.275722026825, 2.5}, null},
                {"station_elm_console", null, new double[]{-2374.6553970255, -70.9116399555847, 268.349670410156, 2.5}, null},
                {"test_station_ivy", null, new double[]{-2448.1122551441, -101.469541747108, 259.844213518525, 2.5}, null},
                {"recover_demeter", null, new double[]{-2434.22285265303, -152.158308535442, 267.041717529297, 2.5}, null},
                {"sotp_end", new DeepPointer("HorizonForbiddenWest.exe", SceneManagerGame,  0xE0, 0xF40, 0xB00, 0x411), null, null},
            // CRADLE OF ECHOES
                {"coe_console2", null, new double[]{543.435203280978, 1292.08648603277, 587.041625976563, 2.5}, null},
                {"coe_specter2", null, new double[]{484.638608932776, 1024.18652343813, 611.554178953421, 2.5}, null},
            // THE KULRUT
                {"ft_memorial_grove", null, new double[]{-536.684509277344, -689.538696289062, 417.407958984376, 3}, null},
                {"k_talk_to_hekarro", null, new double[]{-709.586461823186, -669.095686835261, 421.782592773438, 3}, null},
                {"k_machines", null, new double[]{-698.937885912758, -501.705726107, 435.614677124375, 0.5}, null},
                {"k_Slitherfang", null, new double[]{-707.209045410156, -640.884094238281, 402.438415676355, 0.5}, null},
                {"recover_aether", null, new double[]{-645.642142567462, -724.19342025944, 410.129646779969, 3}, null},
                {"kulrut_end", new DeepPointer("HorizonForbiddenWest.exe", SceneManagerGame, 0xE0, 0x10D0, 0x178, 0x651), null, null},
            // FARO'S TOMB
                {"fst_boat", null, new double[]{-2991.05639648438, -1676.1176147461, 256.294574439526, 3}, null},
                {"fst_legacys_landfall", null, new double[]{-3952.04347568689, -926.8164166615, 260.915409140938, 3}, null},
                {"fst_talk_to_alva", null, new double[]{-4124.05110842, -756.899763504, 257.224526367, 3}, null},
                {"fst_entrance_skip", null, new double[]{-4261.75767201338, -806.785997355906, 211.430053710936, 3}, null},
                {"fst_Corruptors", null, new double[]{-4320.63626606234, -752.726599781282, 195.796744658954, 3}, null},
                {"fst_omega_clearance", null, new double[]{-4347.25270207781, -701.263439108375, 171.529212629922, 3}, null},
                {"faros_tomb_end", new DeepPointer("HorizonForbiddenWest.exe", SceneManagerGame, 0xE0, 0x560, 0x321), null, null},
            // GEMINI
                {"g_gemini", new DeepPointer("HorizonForbiddenWest.exe", SceneManagerGame, 0xE8, 0x4B0, 0xFD8, 0x580, 0x321), null, null},
                {"g_node1", new DeepPointer("HorizonForbiddenWest.exe", SceneManagerGame, 0xE8, 0xFC8, 0xB48, 0xEF1), null, null},
                {"g_talk_to_beta", null, new double[]{-374.452293072273, -417.939213925904, 327.954232309294, 3}, null},
            // THE WINGS OF THE TEN
                {"wott_sunwing_override", null, new double[]{1094.35817246086, -198.300083576356, 633.342505225047, 3}, null},
                {"wott_memorial_grove", null, new double[]{-413.217704414023, -640.549513548812, 449.7227159445, 5}, null},
                // {"wott_regalla1", null, new double[]{-737.683959960938, -673.44642496109, 425.838824272156, 3}, "cutscene"},
                // {"wott_regalla2", null, new double[]{-753.797096789197, -646.943957527048, 418.178100141256, 3}, "cutscene"},
                // {"wott_regalla3", null, new double[]{-725.179475660616, -637.337163086555, 402.654195853353, 3}, "cutscene"},
                {"wings_of_the_ten_end", new DeepPointer("HorizonForbiddenWest.exe", SceneManagerGame, 0xF8, 0xED8, 0x4F0, 0xA61), null, null},
            // SINGULARITY
                {"s_shield_skip", new DeepPointer("HorizonForbiddenWest.exe", SceneManagerGame, 0xE0, 0x1E8, 0xE18, 0x791), null, null},
                {"kill_erik", null, new double[]{-1749.25894069672, -2938.75882327557, 275.52651977539, 3}, null},
                {"s_tower_top", null, new double[]{-1756.16803004627, -2949.95112186803, 385.631804418408, 3}, null},
                {"s_defeat_tilda", null, new double[]{-1771.61556974602, -2921.03838795219, 380.99396117125, 3}, null}
    };

    // Handles the event risen by a checkpoint memory flag when it changes
    // and evaluates if it's time to split or not:
    MemoryWatcherList.MemoryWatcherDataChangedEventHandler splitOrPass = (MemoryWatcher watcher) => {
        // Checks if the flag was set to 1, otherwise we don't care:
        if(Convert.ToByte(watcher.Current) > 0){
            // Legacy checkpoint logic, if a cutscene or a loading screen is on:
            if(watcher.Name == "isGodWatcher" || watcher.Name == "isLoadingWatcher"){
                // If Aloy is within a valid checkpoint zone:
                var checkpointQuery = vars.Funcs.isLegacySplit(vars.WestEast, vars.SouthNorth, vars.DownUp);
                if(checkpointQuery.isLegacySplit){
                    if(
                        // If this segment hasn't been splitted before in the current run:
                        !vars.legacyCheckpoints[checkpointQuery.splitName].reachedBefore &&
                        // Splits only if the user has enabled this split
                        // in the autosplitter settings:
                        settings[checkpointQuery.splitName] &&
                        (
                            // If isGod memory watcher was triggered, we shouldn't be on a loading screen:
                            (watcher.Name == "isGodWatcher" && checkpointQuery.splitType != "load") ||
                            // If isLoading memory watcher was triggered, we shouldn't be on a cutscene:
                            (watcher.Name == "isLoadingWatcher" && checkpointQuery.splitType != "cutscene")
                        )
                    ){
                        vars.Funcs.Split(vars.legacyCheckpoints[checkpointQuery.splitName]);
                    }
                }
            }
            else if(
                // Splits only if this segment hasn't been splitted before:
                !vars.checkpoints[watcher.Name].reachedBefore &&
                // We check if we are on a loading screen to avoid fake splits when
                // memory flags are reseted to 1 under some circumstances (Ex. restart from save):
                vars.isLoading == 0 &&
                // Splits only if the user has enabled this split
                // in the autosplitter settings:
                settings[watcher.Name]
            ){
                vars.Funcs.Split(vars.checkpoints[watcher.Name]);
            }
        }
    };
    // Add it to the the event handlers of the memory wathcher list:
    vars.memWatchers.OnWatcherDataChanged += splitOrPass;

    // Add a special memory watcher for cutscene detection.
    // We use it for cutscene checkpoint splits:
    vars.memWatchers.Add(
        new MemoryWatcher<byte>(
            new DeepPointer("HorizonForbiddenWest.exe", Player, 0x1C10, 0x0, 0x10, 0xD0, 0x70)
        ){Name = "isGodWatcher"}
    );
    // Add a special memory watcher for loading screen detection.
    // We use it for fast travel checkpoint splits:
    vars.memWatchers.Add(
        new MemoryWatcher<byte>(
            new DeepPointer("HorizonForbiddenWest.exe", GameModule, 0x4B4)
        ){Name = "isLoadingWatcher"}
    );

    dynamic tmp = null;
    // Initialize checkpoint coordinates and pointers
    for (int i = 0; i < _checkpoints.GetLength(0); i++){
        tmp = new ExpandoObject();
        tmp.Name = _checkpoints[i, 0];
        tmp.Type = _checkpoints[i, 3] != null ? _checkpoints[i, 3] : "split";
        // Has the checkpoint already been reached before?
        tmp.reachedBefore = false;

        // Memory flagged checkpoint:
        if (_checkpoints[i, 1] != null){
            // Add a memory watcher to detect checkpoit activation:
            vars.memWatchers.Add(
                new MemoryWatcher<byte>(_checkpoints[i, 1]){Name = _checkpoints[i, 0]}
            );
            vars.checkpoints.Add(_checkpoints[i, 0], tmp);
        }
        // Legacy checkpoint (position based):
        else if(_checkpoints[i, 2] != null){
            tmp.geolocation = _checkpoints[i, 2];
            vars.legacyCheckpoints.Add(_checkpoints[i, 0], tmp);
        }
    }
}


update{
    vars.WestEast = current.WestEast;
    vars.SouthNorth = current.SouthNorth;
    vars.DownUp = current.DownUp;
    vars.isLoading = current.loading;
    vars.memWatchers.UpdateAll(game);
}

start{
   // We use a custom implementation for this
}

split{
    // We use a custom implementation for this
}

onReset{
    foreach (var checkpoint in vars.checkpoints){
        checkpoint.Value.reachedBefore = false;
    }
    foreach (var checkpoint in vars.legacyCheckpoints){
        checkpoint.Value.reachedBefore = false;
    }
}

isLoading
{
    return (current.loading > 0);
}

exit
{
    timer.IsGameTimePaused = false;
    /****************************************************/
    /* exit: Clean up to pre-init state when game process is closed
    /****************************************************/
    vars.checkpoints =  new Dictionary<string, ExpandoObject>();
    vars.legacyCheckpoints = new Dictionary<string, ExpandoObject>();
    vars.memWatchers = new MemoryWatcherList();
}

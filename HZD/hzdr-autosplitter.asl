// Created by ISO2768mK and DorianSnowball
// Version detection from the Death Stranding and Alan Wake ASL

state("HorizonZeroDawnRemastered", "v1.3.51.0-Steam")
{
    byte24 aobPosition : 0x099A86F8, 0xA0, 0x00, 0x28, 0x150; // 3 doubles
    byte invulnerable : 0x099A86F8, 0xA0, 0x00, 0x28, 0x208, 0x60;

    uint pause : 0x099A9520, 0x20;
    byte frameTimeIGT : 0x099A9520, 0x158;
    double totalTimePlayed: 0x099A9520, 0x160; // time shown in statistics; for ridge delayed split
    uint loading : 0x099A9520, 0x4DC;
    // byte windowActiveInd : 0x099A9520, 0x172; // 0 -> tabbed in, 1 -> tabbed out => not needed

    ulong worldPtr : 0x099A9520;
}
/*
Placeholder for Epic Games version
state("HorizonZeroDawnRemastered", "v???-Epic")
{
    uint loading : ????, 0x4DC;
}
*/

/*
Getting address for new game version, giving multiple results:
83 B8 DC 04 00 00 00 (hard coded for RAX register)
83 ?? DC 04 00 00 00 (matches any register)

Options:
In static memory (HZDR in the process dropdown)
Clear Writable, Check Executable flags
Clear Fast Scan (we probably don't have alignment)

Perform Scan

Right Click -> Disassemble this memory region

check for je, test and mov opcode preceding in order that op -> we need the address from the mov

Get the value after "HorizonZeroDawnRemastered+" -> this is the offset we need

The other player base address should be derivable by subtracting 0x0E28 from that offset
*/

startup
{
    vars.WriteDebug = false;
    Action<string> DebugOutput = (text) => {
        if (vars.WriteDebug)
        {
            print("[HZDR Autosplitter Debug] " + text);
        }
    };
    vars.DebugOutput = DebugOutput;
    Action<string, double[]> DebugOutputPos = (text, posVec) => {
        if (vars.WriteDebug)
        {
            print("[HZDR Autosplitter Debug] " + text + " | Position:" + posVec[0].ToString() + "," + posVec[1].ToString() + "," + posVec[2].ToString());
        }
    };
    vars.DebugOutputPos = DebugOutputPos;
    Action<string, List<string>> DebugOutputList = (name, list) => {
        if (vars.WriteDebug)
        {
            string text = "";
            for(int i = list.Count - 1; i >= 0; --i)
            {
                text += " | " + list[i];
            }
            text += " |";
            print("[HZDR Autosplitter Debug] List: " + name + " (Size:" + list.Count() + "):" + text);
        }
    };
    vars.DebugOutputList = DebugOutputList;

    Action<string> InfoOutput = (text) => {
        print("[HZDR Autosplitter] " + text);
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

    Func<double[], double[], double[], bool> BoundsCheckAABB = (pos, p_min, p_max) => {
        bool chkX = (pos[0] >= p_min[0]) && (pos[0] <= p_max[0]);
        bool chkY = (pos[1] >= p_min[1]) && (pos[1] <= p_max[1]);
        bool chkZ = (pos[2] >= p_min[2]) && (pos[2] <= p_max[2]);
        return chkX && chkY && chkZ;
    };
    vars.BoundsCheckAABB = BoundsCheckAABB;

/*
    Helper Function to get trafoData (MATLAB / Octave):
    function homData = calcHomData(pLeft, pRight, UEnlarge, VMin, VMax)
        vecLR = pRight - pLeft;
        lenLR = norm(vecLR, 2);
        vecU = vecLR/lenLR;
        phiU = atan2d(vecLR(2),vecLR(1));
        phiV = phiU + 90;
        vecV = [cosd(phiV) sind(phiV)];

        orgUV = pLeft + VMin * vecV - UEnlarge * vecU;

        trafo1 = eye(3);
        trafo1(1,1:2) = vecU;
        trafo1(2,1:2) = vecV;
        trafo1(1:2,3) = -trafo1(1:2,1:2)*orgUV';

        homData = diag([1/(2*UEnlarge + lenLR) 1/(VMax-VMin) 1]) * trafo1;
        homData(3,:) = [];
    end
*/
    Func<double[], double[], double[], bool> BoundsCheckXYRBB = (pos, trafoData, boundZ) => {
        if (pos[2] < boundZ[0] || pos[2] > boundZ[1])
        {
            return false;
        }
        double posV = trafoData[3] * pos[0] + trafoData[4] * pos[1] + trafoData[5];
        if (posV < 0 || posV > 1) { return false; }
        double posU = trafoData[0] * pos[0] + trafoData[1] * pos[1] + trafoData[2];
        return (posU >= 0 && posU <= 1);
    }; // Bounding Box check allowing for rotation in XY, trafoData is expected to be 6 element vector for normalized transformation in XY
    vars.BoundsCheckXYRBB = BoundsCheckXYRBB;

    Func<double[], double[], double, bool> BoundsCheckCircLat = (pos, posCirc, radius) => {
        double deltaX = pos[0] - posCirc[0];
        double deltaY = pos[1] - posCirc[1];
        return (deltaX * deltaX + deltaY * deltaY <= radius * radius);
    };
    vars.BoundsCheckCircLat = BoundsCheckCircLat;

    Func<double[], double[], double, double[], bool> BoundsCheckCyl = (pos, posCyl, radius, boundZ) => {
        if (pos[2] < boundZ[0] || pos[2] > boundZ[1])
        {
            return false;
        }
        return vars.BoundsCheckCircLat(pos, posCyl, radius);
    };
    vars.BoundsCheckCyl = BoundsCheckCyl;

    refreshRate = 60;

    vars.effectiveIGTRunning = false;
    vars.positionVec = new double[3];
    vars.positionVec[0] = -5000; // initialize somewhere outside
    vars.positionVec[1] = 0;
    vars.positionVec[2] = 0;

	Action<string, string, string, string> AddSplitSetting = (key, name, description, parent) => {
		settings.Add(key, true, name, parent);
        if(description != "") { settings.SetToolTip(key, description); }
	};
	Action<string, string, string, string> AddSplitSettingF = (key, name, description, parent) => {
		settings.Add(key, false, name, parent);
        if(description != "") { settings.SetToolTip(key, description); }
	};

    AddSplitSettingF("res_main_menu", "Reset on Main Menu", "Reset run when quitting to main menu", null);

    settings.Add("ngp_overall",true, "NG+ Run");
    AddSplitSetting("01_ngp_start", "NG+ Start", "Note:\nDue to the information available, we cannot differentiate between resuming the cutscene and actually skipping it without starting the timer too late.\nOnce you are given the prompt to skip the cutscene, both Back and Skip will start the timer.\nPause via the Pause button or tabbing should be covered.", "ngp_overall");
    AddSplitSettingF("02_sawtooth_cs", "Sawtooth Looting", "On looting the Sawtooth", "ngp_overall");
    AddSplitSetting("02a_sawtooth_ft", "Sawtooth FT", "FT to Mother's Heart", "ngp_overall");
    AddSplitSettingF("03_mothers_heart", "Mother's Heart", "Start of Proving", "ngp_overall");
    AddSplitSetting("04_proving", "Proving", "End of Proving", "ngp_overall");
    AddSplitSetting("05_corrupter", "Corrupter", "FT to Main or North Gate", "ngp_overall");
    AddSplitSetting("06_daytower", "Daytower", "End of yapping", "ngp_overall");
    AddSplitSetting("07_meridian", "Meridian", "FT from Olin's", "ngp_overall");
    AddSplitSettingF("08a_excavation_yap", "Excavation Site Dialogue", "Completion of talking to Olin", "ngp_overall");
    AddSplitSetting("08_excavation_ft", "Excavation Site FT", "FT from Olin himself", "ngp_overall");
    AddSplitSetting("09_ambush", "Ambush", "FT post Ersa investigation", "ngp_overall");
    AddSplitSetting("10_makers_low", "Maker's End", "Cutscene entering the Tower", "ngp_overall");
    AddSplitSetting("11_fas_tower", "FAS Tower", "FT post Sylens", "ngp_overall");
    AddSplitSetting("12_war_chief", "War Chief", "FT after the pit fight", "ngp_overall");
    AddSplitSetting("13_camps", "Eclipse Camps", "End of talking to Sona at ROM tall building", "ngp_overall");
    AddSplitSetting("14_rom", "Ring of Metal", "Any FT post Ring of Metal", "ngp_overall");
    AddSplitSetting("15_grave_hoard", "Grave Hoard", "Any FT post Grave Hoard", "ngp_overall");
    AddSplitSetting("16_avad", "Avad", "Any FT after talking to Avad the first time", "ngp_overall");
    AddSplitSetting("17_eclipse_base", "Eclipse Base", "Any FT after the grapple point", "ngp_overall");
    AddSplitSetting("18_zero_dawn", "Zero Dawn", "Alpha Registry Cutscene", "ngp_overall"); // rising inv; -1316.22, 689.29, 237.11 | vaulting over desk: -1314.07, 691.64, 237.96
    AddSplitSetting("19_sun_ring", "Sun Ring", "Any FT after the rescue", "ngp_overall");
    AddSplitSetting("20_all_mother", "All-Mother", "Any FT after GAIA's plea", "ngp_overall"); // rising load outside mountain
    AddSplitSetting("21_borderlands", "Borderlands", "Any FT from Ersa", "ngp_overall"); // rising load 698.0, 937.57, 260.92
    AddSplitSettingF("22a_gaia_prime_entering", "GAIA Prime (Entering)", "Starting the dialogue in Sylens' workshop", "ngp_overall");
    AddSplitSetting("22_gaia_prime", "GAIA Prime", "Any FT after getting the spear", "ngp_overall");
    AddSplitSettingF("23a_blaze_skip", "Blaze Skip", "On skipping the cutscene pushing the Blaze out", "ngp_overall");
    AddSplitSetting("23_dervahl", "Dervahl", "Any FT after talking to Avad post-Dervahl", "ngp_overall"); // FT
    AddSplitSetting("24_helis", "Helis", "Arriving at Ridge (bottom of zipline or Jump-RFS)", "ngp_overall"); // Arriving down
    AddSplitSettingF("25a_ridge", "Ridge Defense (beginning of cutscene)", "Beginning of the post-ridge cutscene", "ngp_overall"); // Blackscreen in CS?
    AddSplitSetting("25_ridge", "Ridge Defense", "1st black screen in the post-ridge cutscene (18.21s IGT after the beginning of the cutscene)", "ngp_overall"); // Blackscreen in CS?
    AddSplitSetting("26_hades", "Hades", "stabbity stab stab (end of all runs that include the main game)", "ngp_overall");

    settings.Add("any_additional", false, "Any% additional");
    AddSplitSetting("00_ng_start", "NG Start", "Note:\nDue to the information available, we cannot differentiate between resuming the cutscene and actually skipping it without starting the timer too late.\nOnce you are given the prompt to skip the cutscene, both Back and Skip will start the timer.\nPause via the Pause button or tabbing should be covered.", "any_additional");
    AddSplitSetting("01_childhood", "Childhood", "Same as NG+ starting point", "any_additional");
    AddSplitSetting("01a_karst", "Karst", "Moving or fast-travelling away from Karst after talking to him", "any_additional");
    AddSplitSettingF("06a_striker_bow", "Striker Bow (UH)", "For Any% UH:\nSplits on Fast Travel from the Frozen Wilds Area", "any_additional");

    settings.Add("ngp_tfw", false, "NG+ Frozen Wilds");
    AddSplitSetting("tfw00_start", "NG+ TFW Start", "Grabbing the first handhold next to the campfire north of Grave-Hoard starts the run", "ngp_tfw");
    AddSplitSetting("tfw01_songs_edge", "Song's Edge", "FT to Song's Edge or passing by the CF", "ngp_tfw");
    AddSplitSetting("tfw02_tallneck", "TFW Tallneck", "Any loads after the TN cutscene, designed to be the RFS after the Tallneck", "ngp_tfw");
    AddSplitSetting("tfw03_naltuk", "Naltuk", "End of Yapping to Naltuk the first time (i.e. kill the machines and tower first)", "ngp_tfw");
    AddSplitSetting("tfw04a_shamans_path", "Shaman's Path Facility Entrance", "Opening the first facility door.", "ngp_tfw");
    AddSplitSetting("tfw04b_ourea", "Shaman's Path / Ourea", "Opening the facility door after talking to Ourea.", "ngp_tfw");
    AddSplitSetting("tfw05_tfw_hg", "TFW Hunting Ground", "FT away from the HG", "ngp_tfw");
    AddSplitSetting("tfw06_werak_challenge", "Werak Challenge", "FT after fighting the bears", "ngp_tfw");
    AddSplitSetting("tfw07_longnotch", "Longnotch", "Skipping the cutscene entering the facility", "ngp_tfw");
    AddSplitSetting("tfw08_firebreak", "Firebreak", "Skipping the cutscene after the TJ fight", "ngp_tfw");
    AddSplitSettingF("tfw09a_epsilon_n1", "Cauldron Epsilon - Cyan Node 1", "After moving past the first vine barricade", "ngp_tfw");
    AddSplitSettingF("tfw09b_epsilon_n2", "Cauldron Epsilon - Cyan Node 2", "After moving past the vine barricade with the Scorcher", "ngp_tfw");
    AddSplitSetting("tfw09c_epsilon_tb", "Cauldron Epsilon - Post TB Jump", "After moving past the vine barricade after TB skip", "ngp_tfw");
    AddSplitSettingF("tfw09d_epsilon_cyan", "Cauldron Epsilon - CYAN", "Skipping the CYAN cutscene after the puzzle", "ngp_tfw");
    AddSplitSetting("tfw10_fireclaw", "Fireclaw", "At escaping the Cauldron", "ngp_tfw");
    AddSplitSetting("tfw11_aratak", "Aratak", "Talking to Aratak outside of the CYAN facility (end of the run)", "ngp_tfw");

    vars.completedSplits = new List<string>();
    vars.completedSplits.Capacity = 100;
    vars.completedFacts = new List<string>();
    vars.completedFacts.Capacity = 100;
    vars.timeHelperCamps = 0;
    vars.timeHelperRidge = 0;

    vars.DbgSizeSplits = -1;
    vars.DbgSizeFacts = -1;

/*
    // for debugging specific spots
    vars.completedFacts.Add("fact_corrupter");
    vars.completedFacts.Add("fact_meridian");
    vars.completedFacts.Add("fact_fas");
    vars.completedFacts.Add("fact_zero_dawn");
    vars.completedFacts.Add("fact_gaia_prime");
*/
}

onReset
{
    vars.completedSplits.Clear();
    vars.completedFacts.Clear();
    vars.timeHelperCamps = 0;
    vars.timeHelperRidge = 0;
}

init
{
    var module = modules.Single(x => String.Equals(x.ModuleName, "HorizonZeroDawnRemastered.exe", StringComparison.OrdinalIgnoreCase));
    // No need to catch anything here because LiveSplit wouldn't have attached itself to the process if the name wasn't present

    var hash = vars.CalcModuleHash(module);

    version = "";
    if (hash == "416560393850E7C50F323975DC909C4F1367266DC235753AE3AF5BF197B98B04")
    {
        version = "v1.3.51.0-Steam";
    }
    /*
    else if (hash == "????")
    {
        version = "v???-Epic";
    }
    */

    if (version != "")
    {
        vars.InfoOutput("Recognized version: " + version);
    }
    else
    {
        vars.InfoOutput("Unrecognized version of the game.");
    }

    // Print debug info again
    vars.DbgSizeSplits = -1;
    vars.DbgSizeFacts = -1;
}

update
{
    if (current.aobPosition != null) // positions retain their old value on RFS to not trigger out of bounds checks for some splits
    {
        Buffer.BlockCopy(current.aobPosition, 0, vars.positionVec, 0, 24);
    }
    vars.effectiveIGTRunning = old.frameTimeIGT > 0;

    // ZD MQ Line
    if(!vars.completedFacts.Contains("fact_karst")) // NG only
    {
        if(current.invulnerable > 0)
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{2836.9, -1955.3}, 0.5))
            { vars.completedFacts.Add("fact_karst"); }
        }
    }
    if(!vars.completedFacts.Contains("fact_corrupter"))
    {
        if(current.loading > 0) // Prerendered loading cutscene
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{2385.8, -1896.5}, 5.0))
            { vars.completedFacts.Add("fact_corrupter"); }
        }
    }
    else if(!vars.completedFacts.Contains("fact_meridian"))
    {
        if(current.invulnerable > 0) // Dialogue in Olin's basement
        {
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{-271.7, -1046.8}, 2.0, new double[]{183, 188}))
            { vars.completedFacts.Add("fact_meridian"); }
        }
    }
    else if(!vars.completedFacts.Contains("fact_olin"))
    {
        if(current.invulnerable > 0) // Dialogue at excavation site
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{58.4, -73.5}, 3.0)) // Z 185.7
            { vars.completedFacts.Add("fact_olin"); }
        }
    }
    else if(!vars.completedFacts.Contains("fact_fas"))
    {
        if(current.invulnerable > 0) // Dialogue with Sylens
        {
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{-664.5, 1383.2}, 3.0, new double[]{319, 322}))
            { vars.completedFacts.Add("fact_fas"); }
        }
    }
    else if(!vars.completedFacts.Contains("fact_grave_hoard"))
    {
        if(current.invulnerable > 0) // Dialogue with Sylens on top of GH
        {
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{3024.8, 1082.7}, 3.0, new double[]{354, 361}))
            { vars.completedFacts.Add("fact_grave_hoard"); }
        }
    }
    else if(!vars.completedFacts.Contains("fact_eclipse_base"))
    {
        if(current.invulnerable > 0) // Eclipse base rappel point
        {
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{-1391, -1198}, 3.0, new double[]{270, 285}))
            { vars.completedFacts.Add("fact_eclipse_base"); }
        }
    }
    else if(!vars.completedFacts.Contains("fact_zero_dawn"))
    {
        if(current.invulnerable > 0) // Getting the alpha registry
        {
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{-1316.3, 689.3}, 2.0, new double[]{236, 239}))
            { vars.completedFacts.Add("fact_zero_dawn"); }
        }
    }
    else if(!vars.completedFacts.Contains("fact_sun_ring"))
    {
        if(current.invulnerable > 0) // Sylens dialogue
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{-841.7, 563.3}, 5.0)) // Z 264.7
            { vars.completedFacts.Add("fact_sun_ring"); }
        }
    }
    else if(!vars.completedFacts.Contains("fact_all_mother"))
    {
        if(current.invulnerable > 0) // GAIA's dying plea
        {
            if(vars.BoundsCheckAABB(vars.positionVec, new double[]{2330,-2230,226.5}, new double[]{2352,-2200,229}))
            { vars.completedFacts.Add("fact_all_mother"); }
        }
    }
    else if(!vars.completedFacts.Contains("fact_gaia_prime"))
    {
        if(current.invulnerable > 0) // Crafting the spear
        {
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{1657.8, 1434.5}, 1.0, new double[]{495, 498}))
            { vars.completedFacts.Add("fact_gaia_prime"); }
        }
    }
    else if(!vars.completedFacts.Contains("fact_helis"))
    {
        if(current.invulnerable > 0) // Invuln at Helis selection
        {
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{-297.7, -1184.2}, 2.0, new double[]{153, 156}))
            { vars.completedFacts.Add("fact_helis"); }
        }
    }

    // Nora MQ Line
    if(!vars.completedFacts.Contains("fact_war_chief"))
    {
        if(current.invulnerable > 0) // one of the two cutscenes inside
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{3297.2, -934.9}, 5.0)) // Z 195.9
            { vars.completedFacts.Add("fact_war_chief"); }
        }
    }
    else if(!vars.completedFacts.Contains("fact_rom"))
    {
        if(current.invulnerable > 0) // one of the two cutscenes inside
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{3772.2, 119}, 15.0)) // Z 123.2
            { vars.completedFacts.Add("fact_rom"); }
        }
    }

    // Dervahl MQ Line
    if(!vars.completedFacts.Contains("fact_ambush"))
    {
        if(current.invulnerable > 0) // Erend dialogue by ambush
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{-277.9, -25.2}, 5.0)) // Z 269
            { vars.completedFacts.Add("fact_ambush"); }
        }
    }
    else if(!vars.completedFacts.Contains("fact_avad"))
    {
        if(current.invulnerable > 0) // Avad dialogue at the throne
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{-295.7, -912.4}, 4.0)) // Z 201
            { vars.completedFacts.Add("fact_avad"); }
        }
    }
    else if(!vars.completedFacts.Contains("fact_ersa"))
    {
        if(current.invulnerable > 0) // ending the Erend dialogue by Ersa
        {
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{200.0, 1523}, 6.0, new double[]{342, 346.5}))
            { vars.completedFacts.Add("fact_ersa"); }
        }
    }
    else if(!vars.completedFacts.Contains("fact_blaze_bracket"))
    {
        if(current.invulnerable > 0) // at position of bracket
        {
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{-327.55, -1146.59}, 0.5, new double[]{196.8, 199.5}))
            { vars.completedFacts.Add("fact_blaze_bracket"); }
        }
    }
    else if(!vars.completedFacts.Contains("fact_dervahl"))
    {
        if(current.invulnerable > 0) // Dervahl captured CS
        {
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{-300, -896}, 5.0, new double[]{199, 205}))
            { vars.completedFacts.Add("fact_dervahl"); }
        }
    }

    // TFW area
    if(!vars.completedFacts.Contains("fact_tfw_area"))
    {
        if(vars.BoundsCheckCyl(vars.positionVec, new double[]{2951.37, 1048.84}, 3.0, new double[]{287, 289})) // TODO: check alternative TFW
        { vars.completedFacts.Add("fact_tfw_area"); }
    }
    else // fact_tfw_area
    {
    if(!vars.completedFacts.Contains("fact_tfw_tn"))
    {
        if(current.invulnerable > 0) // Tallneck reactivation CS
        {
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{2588.1, 1700.5}, 3.0, new double[]{455, 465}))
            { vars.completedFacts.Add("fact_tfw_tn"); }
        }
    }
    if(!vars.completedFacts.Contains("fact_tfw_shamans_path"))
    {
        if(current.invulnerable > 0) // Alternative End of Shaman's Path
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{2241.29, 2699.6}, 3.0))
            { vars.completedFacts.Add("fact_tfw_shamans_path"); }
        }
    }
    if(!vars.completedFacts.Contains("fact_tfw_ourea"))
    {
        if(current.invulnerable > 0) // End of Shaman's Path
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{2196.6, 2806.7}, 2.0)) // Z 751.8
            { vars.completedFacts.Add("fact_tfw_ourea"); }
        }
    }
    if(!vars.completedFacts.Contains("fact_tfw_hg"))
    {
        if(current.invulnerable > 0) // Talking to the keeper
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{2844.1, 2804.5}, 5.0))
            { vars.completedFacts.Add("fact_tfw_hg"); }
        }
    }
    if(!vars.completedFacts.Contains("fact_tfw_werak_challenge"))
    {
        if(current.invulnerable > 0) // Post teddy bear cutscene
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{2828.2, 1941.1}, 3.0))
            { vars.completedFacts.Add("fact_tfw_werak_challenge"); }
        }
    }
    if(!vars.completedFacts.Contains("fact_tfw_longnotch"))
    {
        if(current.invulnerable > 0) // Talking at the emergency door
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{3615.8, 1946.4}, 2.0))
            { vars.completedFacts.Add("fact_tfw_longnotch"); }
        }
    }
    if(!vars.completedFacts.Contains("fact_tfw_firebreak"))
    {
        if(current.invulnerable > 0) // Post TJ cutscene
        {
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{3775.6, 2289.7}, 2.0, new double[]{445, 450}))
            { vars.completedFacts.Add("fact_tfw_firebreak"); }
        }
    }
    if(!vars.completedFacts.Contains("fact_tfw_epsilon"))
    {
        if(current.invulnerable > 0) // Overriding the core
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{3317.6, 2771.8}, 3.0))
            { vars.completedFacts.Add("fact_tfw_epsilon"); }
        }
    }
    } // fact_tfw_area

    if(vars.WriteDebug)
    {
        if(vars.completedFacts.Count != vars.DbgSizeFacts)
        {
            vars.DebugOutputList("Facts", vars.completedFacts);
            vars.DbgSizeFacts = vars.completedFacts.Count;
        }
        if(vars.completedSplits.Count != vars.DbgSizeSplits)
        {
            vars.DebugOutputList("Splits", vars.completedSplits);
            vars.DbgSizeSplits = vars.completedSplits.Count;
        }
    }
}

reset
{
    if(settings["res_main_menu"] && (old.worldPtr > 0 && current.worldPtr == 0))
    {
        return true;
    }
    return false;
}

start
{
    //NG
    if(settings["00_ng_start"]) // Setting enabled?
    {
        if(old.pause == 1 && current.pause == 0 && old.invulnerable == 1 && vars.effectiveIGTRunning) // Falling edge on pause location during invulnerability
        {
            vars.DebugOutputPos("NG: Falling edge detected", vars.positionVec);
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{2453, -1857}, 68.5, new double[]{179, 195}))
            { return true; }
        }
    }
    //NG+
    if(settings["01_ngp_start"]) // Setting enabled?
    {
        if(old.pause == 1 && current.pause == 0 && old.invulnerable == 1 && vars.effectiveIGTRunning) // Falling edge on pause location during invulnerability
        {
            vars.DebugOutputPos("NG+: Falling edge detected", vars.positionVec);
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{2136.4, -1518.0}, 4, new double[]{293, 296.5}))
            { vars.completedSplits.Add("01_childhood"); return true; }
        }
    }
    //TFW NG+ Start
    if(settings["tfw00_start"]) // Setting enabled?
    {
        // No trigger :(
        if(vars.BoundsCheckCyl(vars.positionVec, new double[]{2951.37, 1048.84}, 0.35, new double[]{285.2, 285.6}))
        {
            vars.DebugOutputPos("TFW NG+: In Cyl-Bounds", vars.positionVec);
            return true;
        }
    }
    return false;
}

split
{
    if(settings["01_childhood"] && !vars.completedSplits.Contains("01_childhood"))
    {
        if(current.loading > 0) // Prerendered loading cutscene ports Aloy to NG+ Start position
        {
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{2136.4, -1518.0}, 4, new double[]{293, 296.5}))
            { vars.completedSplits.Add("01_childhood"); return true; }
        }
    }
    if(settings["01a_karst"] && !vars.completedSplits.Contains("01a_karst") && vars.completedFacts.Contains("fact_karst"))
    {
        if(!vars.BoundsCheckCircLat(vars.positionVec, new double[]{2836.9, -1955.3}, 1.0))
        { vars.completedSplits.Add("01a_karst"); return true; }
    }
    if(settings["02_sawtooth_cs"] && !vars.completedSplits.Contains("02_sawtooth_cs"))
    {
        if(vars.effectiveIGTRunning && old.pause == 1 && current.pause == 0 && current.invulnerable == 1)
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{2855.6, -1372.2}, 1.0)) // Z 186.6
            { vars.completedSplits.Add("02_sawtooth_cs"); return true; }
        }
    }
    if(settings["02a_sawtooth_ft"] && !vars.completedSplits.Contains("02a_sawtooth_ft"))
    {
        if(old.loading == 0 && current.loading > 0)
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{2450.6, -1363.9}, 1.0)) // Z 210.7
            { vars.completedSplits.Add("02a_sawtooth_ft"); return true; }
        }
    }
    if(settings["03_mothers_heart"] && !vars.completedSplits.Contains("03_mothers_heart"))
    {
        if(current.loading > 0) // Prerendered loading cutscene
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{2700.9, -2321.8}, 1.0)) // Z 299.7
            { vars.completedSplits.Add("03_mothers_heart"); return true; }
        }
    }
    if(settings["04_proving"] && !vars.completedSplits.Contains("04_proving"))
    {
        if(current.loading > 0) // Prerendered loading cutscene
        {
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{2287.1, -2155.8}, 1.0, new double[]{234, 237}))
            { vars.completedSplits.Add("04_proving"); return true; }
        }
    }
    if(vars.completedFacts.Contains("fact_corrupter")) {
    if(settings["05_corrupter"] && !vars.completedSplits.Contains("05_corrupter"))
    {
        if(current.loading > 0)
        {
            if(!vars.BoundsCheckCircLat(vars.positionVec, new double[]{2385.8, -1896.5}, 100.0)) // Z 175.12
            { vars.completedSplits.Add("05_corrupter"); return true; }
        }
    }
    if(settings["06a_striker_bow"] && !vars.completedSplits.Contains("06a_striker_bow") && vars.completedFacts.Contains("fact_tfw_area"))
    {
        if(current.loading > 0)
        {
            // xmin: 1700 (GP Entrance is 1600), xmax: 4300 (Battery entrance is at 3610)
            // ymin: 1000 (just S of Grave-Hoard-symbol), ymax: 3200 (N of Ban-Ur Gate)
            if(!vars.BoundsCheckAABB(vars.positionVec, new double[]{1700, 1000, 0}, new double[]{4300, 3200, 2000}))
            { vars.completedSplits.Add("06a_striker_bow"); return true; }
        }
    }
    if(settings["06_daytower"] && !vars.completedSplits.Contains("06_daytower"))
    {
        if(old.invulnerable > 0 && current.invulnerable == 0)
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{1542.8, -509.1}, 3.0)) // Z 301.7
            { vars.completedSplits.Add("06_daytower"); return true; }
        }
    }
    if(vars.completedFacts.Contains("fact_meridian")) {
    if(settings["07_meridian"] && !vars.completedSplits.Contains("07_meridian"))
    {
        if(current.loading > 0) // First FT post-fact
        {
            // FT Target: 151, -682.4, 147.5
            { vars.completedSplits.Add("07_meridian"); return true; }
        }
    }
    if(settings["08a_excavation_yap"] && !vars.completedSplits.Contains("08a_excavation_yap"))
    {
        if(current.invulnerable == 0 && vars.completedFacts.Contains("fact_olin"))
        {
            // Bounding check at Olin fact check
            // if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{58.4, -73.5}, 3.0)) // Z 185.7
            { vars.completedSplits.Add("08a_excavation_yap"); return true; }
        }
    }
    if(settings["08_excavation_ft"] && !vars.completedSplits.Contains("08_excavation_ft"))
    {
        if(current.loading > 0 && vars.completedFacts.Contains("fact_olin"))
        {
            if(!vars.BoundsCheckCircLat(vars.positionVec, new double[]{58.4, -73.5}, 70.0))
            { vars.completedSplits.Add("08_excavation_ft"); return true; }
        }
    }
    if(settings["09_ambush"] && !vars.completedSplits.Contains("09_ambush"))
    {
        if(current.loading > 0 && vars.completedFacts.Contains("fact_ambush"))
        {
            if(!vars.BoundsCheckCircLat(vars.positionVec, new double[]{-277.9, -25.3}, 50))
            { vars.completedSplits.Add("09_ambush"); return true; }
        }
    }
    if(settings["10_makers_low"] && !vars.completedSplits.Contains("10_makers_low"))
    {
        if(vars.effectiveIGTRunning && old.pause == 1 && current.pause == 0 && current.invulnerable == 1)
        {   // exclude looting the guy | new double[]{-558.6, 1366.6}, 3.5, new double[]{202.5, 206}
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{-558.0, 1368.1}, 23.5, new double[]{121, 131}) || // cutscene part
                vars.BoundsCheckCyl(vars.positionVec, new double[]{-599.4, 1371.9}, 1.5, new double[]{200, 203}) || // beginning -599.402,1371.879,201.054
                vars.BoundsCheckCyl(vars.positionVec, new double[]{-609, 1378}, 1.0, new double[]{202, 205}) // end -608.975,1378.002,203.088
                )
            { vars.completedSplits.Add("10_makers_low"); return true; }
        }
    }
    if(vars.completedFacts.Contains("fact_fas")) {
    if(settings["11_fas_tower"] && !vars.completedSplits.Contains("11_fas_tower"))
    {
        if(current.loading > 0) // First FT post-fact
        {
            // FT Target: 2867.7, -1416.7, 174.0
            { vars.completedSplits.Add("11_fas_tower"); return true; }
        }
    }
    if(settings["12_war_chief"] && !vars.completedSplits.Contains("12_war_chief"))
    {
        if(current.loading > 0 && vars.completedFacts.Contains("fact_war_chief"))
        {
            // FT out of the pit is the trigger here
            if(!vars.BoundsCheckCircLat(vars.positionVec, new double[]{3299, -933}, 75.0))
            { vars.completedSplits.Add("12_war_chief"); return true; }
        }
    }
    if(settings["13_camps"] && !vars.completedSplits.Contains("13_camps"))
    {
        if(vars.timeHelperCamps == 0)
        {
            if(current.invulnerable > 0 && vars.BoundsCheckCircLat(vars.positionVec, new double[]{3871.4, -20.0}, 3.0)) // Z 124.3
            {
                vars.timeHelperCamps = current.totalTimePlayed;
            }
        }
        else if(current.totalTimePlayed > vars.timeHelperCamps + 13.0 && current.invulnerable == 0) // Scar's RTA seconds: 25.81 -> 28.5 -> 43.0
        {
            vars.timeHelperCamps = 0;
            vars.completedSplits.Add("13_camps");
            return true;
        }
        else if(current.loading > 0) // RFS during yapping resets the timer
        {
            vars.timeHelperCamps = 0;
        }
    }
    if(settings["14_rom"] && !vars.completedSplits.Contains("14_rom"))
    {
        if(current.loading > 0 && vars.completedFacts.Contains("fact_rom"))
        {
            // FT out of the ring is the trigger here
            if(!vars.BoundsCheckCircLat(vars.positionVec, new double[]{3810, 125}, 75.0))
            { vars.completedSplits.Add("14_rom"); return true; }
        }
    }
    if(settings["15_grave_hoard"] && !vars.completedSplits.Contains("15_grave_hoard"))
    {
        if(current.loading > 0 && vars.completedFacts.Contains("fact_grave_hoard"))
        {
            // First FT post-fact
            // FT Target: Meridian at -219.9, -980.7, 188.9 | 2966/959 -> 3035/1085
            if(!vars.BoundsCheckCircLat(vars.positionVec, new double[]{3000, 1020}, 150.0)) // TODO
            { vars.completedSplits.Add("15_grave_hoard"); return true; }
        }
    }
    if(settings["16_avad"] && !vars.completedSplits.Contains("16_avad"))
    {
        if(current.loading > 0 && vars.completedFacts.Contains("fact_avad"))
        {
            // First FT post-fact
            // FT Target: Meridian northern CF at -144.2, -746.4, 182.7
            if(!vars.BoundsCheckCircLat(vars.positionVec, new double[]{-295.7, -912.4}, 70.0)) // Z 201
            { vars.completedSplits.Add("16_avad"); return true; }
        }
    }
    if(settings["17_eclipse_base"] && !vars.completedSplits.Contains("17_eclipse_base"))
    {
        if(current.loading > 0 && vars.completedFacts.Contains("fact_eclipse_base"))
        {
            // First FT post-fact
            // FT Target: CF SE of Sunfall at -767.9, -274.5, 258.7 | 1391.99/-1197.7 -> -1347.5/-1212.3
            if(!vars.BoundsCheckCircLat(vars.positionVec, new double[]{-1360, -1200}, 100.0))
            { vars.completedSplits.Add("17_eclipse_base"); return true; }
        }
    }
    if(settings["18_zero_dawn"] && !vars.completedSplits.Contains("18_zero_dawn"))
    { // should be post fact, but they are very close together
        if(old.loading == 0 && current.loading > 0)
        {
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{-1104.7, 520.8}, 3.0, new double[]{270, 275}))
            { vars.completedSplits.Add("18_zero_dawn"); return true; }
        }
    }
    if(vars.completedFacts.Contains("fact_zero_dawn")) {
    if(settings["19_sun_ring"] && !vars.completedSplits.Contains("19_sun_ring"))
    {
        if(current.loading > 0 && vars.completedFacts.Contains("fact_sun_ring"))
        {
            // First FT post-fact
            // FT Target: Mother's Watch CF at 2386.2, -1878.5, 190.9 (ideally)
            if(!vars.BoundsCheckCircLat(vars.positionVec, new double[]{3773.1, 112.8}, 100.0)) // TODO
            { vars.completedSplits.Add("19_sun_ring"); return true; }
        }
    }
    if(settings["20_all_mother"] && !vars.completedSplits.Contains("20_all_mother"))
    {
        if(current.loading > 0 && vars.completedFacts.Contains("fact_all_mother"))
        {
            // First FT post-fact
            // FT Target: CF near Dimmed Bones at -109.3, 220.1, 222.7 | -> 2342.5/-2060
            if(!vars.BoundsCheckCircLat(vars.positionVec, new double[]{2340, -2130}, 150.0))
            { vars.completedSplits.Add("20_all_mother"); return true; }
        }
    }
    if(settings["21_borderlands"] && !vars.completedSplits.Contains("21_borderlands"))
    {
        if(current.loading > 0 && vars.completedFacts.Contains("fact_ersa"))
        {
            // First FT post-fact
            // FT Target: CF towards GP at 698.0, 937.6, 260.9
            if(!vars.BoundsCheckCircLat(vars.positionVec, new double[]{200.0, 1521.6}, 100.0))
            { vars.completedSplits.Add("21_borderlands"); return true; }
        }
    }
    if(settings["22a_gaia_prime_entering"] && !vars.completedSplits.Contains("22a_gaia_prime_entering"))
    {
        if(current.invulnerable > 0)
        {
            // Virtual Sylens Yapping in GP
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{1664.6, 1432.6}, 1.0, new double[]{495, 498}))
            { vars.completedSplits.Add("22a_gaia_prime_entering"); return true; }
        }
    }
    if(vars.completedFacts.Contains("fact_gaia_prime")) {
    if(settings["22_gaia_prime"] && !vars.completedSplits.Contains("22_gaia_prime"))
    {
        if(current.loading > 0) // First FT post-fact
        {
            // FT Target: Meridian at -219.9, -980.7, 188.9
            { vars.completedSplits.Add("22_gaia_prime"); return true; }
        }
    }
    if(settings["23a_blaze_skip"] && !vars.completedSplits.Contains("23a_blaze_skip"))
    {
        if(vars.effectiveIGTRunning && old.pause == 1 && current.pause == 0 && current.invulnerable == 1 && vars.completedFacts.Contains("fact_blaze_bracket"))
        {   // Cutscene goes from -329.0,-1146.2,197.2 to -315.6,-1131.2,192.9
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{-322.0, -1138.6}, 11, new double[]{191, 199})) // Z 186.6
            { vars.completedSplits.Add("23a_blaze_skip"); return true; }
        }
    }
    if(settings["23_dervahl"] && !vars.completedSplits.Contains("23_dervahl"))
    {
        if(current.loading > 0 && vars.completedFacts.Contains("fact_dervahl"))
        {
            // First FT post-fact
            // FT Target: Meridian CF at -193.4, -1112.4, 191.2
            if(!vars.BoundsCheckCircLat(vars.positionVec, new double[]{-300, -890}, 60.0))
            { vars.completedSplits.Add("23_dervahl"); return true; }
        }
    }
    if(settings["24_helis"] && !vars.completedSplits.Contains("24_helis"))
    {
        if(vars.completedFacts.Contains("fact_helis"))
        {
            // Bottom of Zipline: -252.1, -1271.3, 121.55
            // With RFS: -243.33, -1284.29, 119.01
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{-257, -1264}, 15.0, new double[]{110, 123}) ||
                vars.BoundsCheckCircLat(vars.positionVec, new double[]{-243.3, -1284.3}, 2.0)
            )
            { vars.completedSplits.Add("24_helis"); return true; }
        }
    }
    if(settings["25a_ridge"] && !vars.completedSplits.Contains("25a_ridge") && vars.completedFacts.Contains("fact_helis"))
    {
        if(current.invulnerable > 0) // unsure if the position is already set on the rising edge
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{-241.1, -1285.3}, 3.0)) // Z 119.7
            { vars.completedSplits.Add("25a_ridge"); return true; }
        }
    }
    if(settings["25_ridge"] && !vars.completedSplits.Contains("25_ridge") && vars.completedFacts.Contains("fact_helis"))
    {
        if(vars.timeHelperRidge == 0)
        {
            if(current.invulnerable > 0) // unsure if the position is already set on the rising edge
            {
                if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{-241.1, -1285.3}, 3.0)) // Z 119.7
                {
                    vars.timeHelperRidge = current.totalTimePlayed + 18.21;
                    vars.DebugOutput("Ridge cutscene trigger detected. Time Helper set.");
                }
            }
        }
        else if(current.totalTimePlayed >= vars.timeHelperRidge)
        {
            vars.completedSplits.Add("25_ridge");
            vars.timeHelperRidge = 0;
            return true;
        }
        else if(current.loading > 0) // RFS for some reason after starting the cutscene
        {
            vars.timeHelperRidge = 0;
        }
    }
    } // fact_gaia_prime
    } // fact_zero_dawn
    } // fact_fas
    } // fact_meridian
    } // fact_corrupter
    //Stab Hades
    if(settings["26_hades"] && !vars.completedSplits.Contains("26_hades")) // Setting enabled?
    {
        if(old.invulnerable == 0 && current.invulnerable == 1)
        {
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{5.5, -1415}, 7, new double[]{175, 179}))
            { vars.completedSplits.Add("26_hades"); return true; }
        }
    }

    //TFW
    if(vars.completedFacts.Contains("fact_tfw_area"))
    {
    if(settings["tfw01_songs_edge"] && !vars.completedSplits.Contains("tfw01_songs_edge"))
    {
        if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{2617.9, 1314.2}, 20.0)) // Z 448.5
        { vars.completedSplits.Add("tfw01_songs_edge"); return true; }
    }
    if(settings["tfw02_tallneck"] && !vars.completedSplits.Contains("tfw02_tallneck"))
    {
        if(current.loading > 0 && vars.completedFacts.Contains("fact_tfw_tn"))
        {
            // First load post-fact -> RFS
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{2605.0, 1692.5}, 1.0))
            { vars.completedSplits.Add("tfw02_tallneck"); return true; }
        }
    }
    if(settings["tfw03_naltuk"] && !vars.completedSplits.Contains("tfw03_naltuk"))
    {
        if(old.invulnerable == 1 && current.invulnerable == 0)
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{2464.7, 1650.2}, 2.0))
            { vars.completedSplits.Add("tfw03_naltuk"); return true; }

        }
    }
    if(settings["tfw04a_shamans_path"] && !vars.completedSplits.Contains("tfw04a_shamans_path"))
    {
        if(current.invulnerable == 1 && vars.completedFacts.Contains("fact_tfw_shamans_path"))
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{2196.6, 2806.7}, 4.0))
            { vars.completedSplits.Add("tfw04a_shamans_path"); return true; }
        }
    }
    if(settings["tfw04b_ourea"] && !vars.completedSplits.Contains("tfw04b_ourea"))
    {
        if(current.invulnerable == 1 && vars.completedFacts.Contains("fact_tfw_ourea"))
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{2211.9, 2806.4}, 4.0))
            { vars.completedSplits.Add("tfw04b_ourea"); return true; }
        }
    }
    if(settings["tfw05_tfw_hg"] && !vars.completedSplits.Contains("tfw05_tfw_hg"))
    {
        if(current.loading > 0 && vars.completedFacts.Contains("fact_tfw_hg"))
        {
            if(!vars.BoundsCheckCircLat(vars.positionVec, new double[]{2840.0, 2820.0}, 150.0))
            { vars.completedSplits.Add("tfw05_tfw_hg"); return true; }
        }
    }
    if(settings["tfw06_werak_challenge"] && !vars.completedSplits.Contains("tfw06_werak_challenge"))
    {
        if(current.loading > 0 && vars.completedFacts.Contains("fact_tfw_werak_challenge"))
        {
            if(!vars.BoundsCheckCircLat(vars.positionVec, new double[]{2828.2, 1941.1}, 50.0))
            { vars.completedSplits.Add("tfw06_werak_challenge"); return true; }
        }
    }
    if(settings["tfw07_longnotch"] && !vars.completedSplits.Contains("tfw07_longnotch"))
    {
        if(old.pause == 1 && current.pause == 0 && old.invulnerable == 1 && vars.effectiveIGTRunning && vars.completedFacts.Contains("fact_tfw_longnotch"))
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{3615.8, 1946.4}, 2.0))
            { vars.completedSplits.Add("tfw07_longnotch"); return true; }
        }
    }
    if(settings["tfw08_firebreak"] && !vars.completedSplits.Contains("tfw08_firebreak"))
    {
        if(old.pause == 1 && current.pause == 0 && old.invulnerable == 1 && vars.effectiveIGTRunning && vars.completedFacts.Contains("fact_tfw_firebreak"))
        { // Cutscene skip post-TJ
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{3775.6, 2289.7}, 2.0, new double[]{445, 450}))
            { vars.completedSplits.Add("tfw08_firebreak"); return true; }
        }
    }
    if(settings["tfw09a_epsilon_n1"] && !vars.completedSplits.Contains("tfw09a_epsilon_n1"))
    {
        if(vars.completedFacts.Contains("fact_tfw_firebreak") &&
            vars.BoundsCheckXYRBB(vars.positionVec,
                new double[]{-0.112116, 0.230411, -159.99, -0.321142, -0.156265, 1546.84}, // homDataAratak1=calcHomData([3621.34 2457.04], [3620.07 2459.65], 0.5, 0.2, 3);
                new double[]{436, 440}
                ))
        { vars.completedSplits.Add("tfw09a_epsilon_n1"); return true; }
    }
    if(settings["tfw09b_epsilon_n2"] && !vars.completedSplits.Contains("tfw09b_epsilon_n2"))
    {
        if(vars.completedFacts.Contains("fact_tfw_firebreak") &&
            vars.BoundsCheckXYRBB(vars.positionVec,
                new double[]{-0.027595, 0.267076, -572.70, -0.355252, -0.036705, 1323.35}, // homDataAratak2=calcHomData([3466.69 2503.01], [3466.41 2505.72], 0.5, 0.2, 3);
                new double[]{429, 433}
                ))
        { vars.completedSplits.Add("tfw09b_epsilon_n2"); return true; }
    }
    if(settings["tfw09c_epsilon_tb"] && !vars.completedSplits.Contains("tfw09c_epsilon_tb"))
    {
        if(vars.completedFacts.Contains("fact_tfw_firebreak") &&
            vars.BoundsCheckXYRBB(vars.positionVec,
                new double[]{0.121478, 0.210250, -942.08, -0.309238, 0.178671, 563.51}, // homDataAratak3=calcHomData([3307.55 2570.3], [3309.11 2573.0], 0.5, 0.2, 3);
                new double[]{409, 413}
                ))
        { vars.completedSplits.Add("tfw09c_epsilon_tb"); return true; }
   }
    if(settings["tfw09d_epsilon_cyan"] && !vars.completedSplits.Contains("tfw09d_epsilon_cyan"))
    {
        if(old.pause == 1 && current.pause == 0 && old.invulnerable == 1 && vars.effectiveIGTRunning && vars.completedFacts.Contains("fact_tfw_firebreak"))
        { // Cutscene skip at CYAN
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{3331.6, 2670.5}, 2.0, new double[]{396, 399}))
            { vars.completedSplits.Add("tfw09d_epsilon_cyan"); return true; }
        }
    }
    if(settings["tfw10_fireclaw"] && !vars.completedSplits.Contains("tfw10_fireclaw"))
    {
        if(current.loading > 0 && vars.completedFacts.Contains("fact_tfw_epsilon"))
        {
            if(vars.BoundsCheckCircLat(vars.positionVec, new double[]{3222.5, 3029.2}, 2.0))
            { vars.completedSplits.Add("tfw10_fireclaw"); return true; }
        }
    }
    if(settings["tfw11_aratak"] && !vars.completedSplits.Contains("tfw11_aratak"))
    {
        if(old.invulnerable == 0 && current.invulnerable == 1)
        {
            if(vars.BoundsCheckCyl(vars.positionVec, new double[]{2192.5, 2672.1}, 3, new double[]{745, 749}))
            { vars.completedSplits.Add("tfw11_aratak"); return true; }
        }
    }
    } // fact_tfw_area
    return false;
}

isLoading
{
    return (current.loading >= 1);
}

exit
{
    timer.IsGameTimePaused = false;
    // Game crashes do not pause the timer to keep the rules as close as possible to the console LR
}

// Created by Driver and ISO2768mK
// Version detection from the Death Stranding and Alan Wake ASL

state("HorizonForbiddenWest", "v1.5.80.0-Steam")
{
    ulong worldPtr : 0x08983150;
    uint loading : 0x08983150, 0x4B4;
    // toggles between 0 and 1 on every save (quick or auto)
    byte saveToggle : 0x08983150, 0x3F8;
    // Aloy's position:
    byte24 aobPosition : 0x08982DA0, 0x1C10, 0x0, 0x10, 0xD8;
    // Aloy's invulnerable flag:
    byte invulnerable : 0x08982DA0, 0x1C10, 0x0, 0x10, 0xD0, 0x70; // 1 in dialogue, cutscenes and when flying
    /*
      Behavior:
      Aloy not on mount -> ControlledEntity is nullpointer
      Aloy on any mount in cutscene -> ControlledEntity is nullpointer
      Aloy on mount on ground (landed / land-mount) -> Aloy invul is 0
      Aloy flying -> Aloy invul is 1 and ControlledEntity points to flying mount,
        Destructability is not nullpointer, 0x70 is 0 (mount is vulnerable)
      Aloy on skiff (either Seyka (scripted) or Aloy) -> ControlledEntity is not nullpointer, Destructability is nullpointer
      End of flight paths (watching through the holo in mid-air) is probably the only instance where the mount is marked invulnerable
    */
    // ControlledEntity -> Destructability
    ulong mountDestructabilityResPtr : 0x08982DA0, 0x1C10, 0x0, 0x10, 0x80, 0xD0;
}
state("HorizonForbiddenWest", "v1.5.80.0-Epic")
{
    ulong worldPtr : 0x0895EF50;
    uint loading : 0x0895EF50, 0x4B4;
    byte saveToggle : 0x0895EF50, 0x3F8;
    byte24 aobPosition : 0x0895EBC8, 0x1C10, 0x0, 0x10, 0xD8;
    byte invulnerable :  0x0895EBC8, 0x1C10, 0x0, 0x10, 0xD0, 0x70;
    ulong mountDestructabilityResPtr : 0x0895EBC8, 0x1C10, 0x0, 0x10, 0x80, 0xD0;
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
        if (true)
        {
            print("[HFW Autosplitter Debug] " + text);
        }
    };
    vars.DebugOutput = DebugOutput;

    Action<string> InfoOutput = (text) => {
        print("[HFW Autosplitter] " + text);
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

    Func<double[], double[], int, bool, bool> BoundsCheckAABB = (pos, dataVec, index0, chkForInside) => {
        // dataVec: [p_min_x .. p_min_z p_max_x .. p_max_z]
        bool chkX = (pos[0] >= dataVec[index0 + 0]) && (pos[0] <= dataVec[index0 + 3 + 0]);
        bool chkY = (pos[1] >= dataVec[index0 + 1]) && (pos[1] <= dataVec[index0 + 3 + 1]);
        bool chkZ = (pos[2] >= dataVec[index0 + 2]) && (pos[2] <= dataVec[index0 + 3 + 2]);
        return (chkX && chkY && chkZ) ^ !chkForInside;
    };
    vars.BoundsCheckAABB = BoundsCheckAABB;

    Func<double[], double[], int, bool, bool> BoundsCheckCircLat = (pos, dataVec, index0, chkForInside) => {
        // dataVec: [r p_x p_y]
        double radius = dataVec[index0 + 0];
        double deltaX = pos[0] - dataVec[index0 + 1];
        double deltaY = pos[1] - dataVec[index0 + 2];
        return (deltaX * deltaX + deltaY * deltaY <= radius * radius) ^ !chkForInside;
    };
    vars.BoundsCheckCircLat = BoundsCheckCircLat;

    Func<double[], double[], int, bool, bool> BoundsCheckSphere = (pos, dataVec, index0, chkForInside) => {
        // dataVec: [r p_x p_y p_z]
        double radius = dataVec[index0 + 0];
        double deltaX = pos[0] - dataVec[index0 + 1];
        double deltaY = pos[1] - dataVec[index0 + 2];
        double deltaZ = pos[2] - dataVec[index0 + 3];
        return (deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ <= radius * radius) ^ !chkForInside;
    };
    vars.BoundsCheckSphere = BoundsCheckSphere;

    Func<double[], double[], int, bool, bool> BoundsCheckCyl = (pos, dataVec, index0, chkForInside) => {
        // dataVec: [r p_x p_y z_min z_max]
        if (pos[2] < dataVec[index0 + 3] || pos[2] > dataVec[index0 + 4])
        {
            // always outside
            return !chkForInside;
        }
        return vars.BoundsCheckCircLat(pos, dataVec, index0, chkForInside);
    };
    vars.BoundsCheckCyl = BoundsCheckCyl;

    const uint IGT_DELAY = (1<<16);

    const uint MEMORYCHECK = (1<<15);
    const uint MEMORY_RISING = (1<<14);
    const uint MEMORY_FALLING = (0<<14);

    const uint BOUNDSTYPE_MASK = (7<<11);
    const uint BOUNDSTYPE_AABB = (1<<11);
    const uint BOUNDSTYPE_CIRC = (2<<11);
    const uint BOUNDSTYPE_CYL = (3<<11);
    const uint BOUNDSTYPE_SPHERE = (4<<11);
    const uint BOUNDS_IO_MASK = (1<<10);
    const uint BOUNDS_INSIDE = (1<<10);
    const uint BOUNDS_OUTSIDE = (0<<10);

    const uint SKIP_FLAGS = (1<<9);
    const uint SAVETGL = (1<<8);
    const uint LOAD_FLANK_RISING = (1<<7);
    const uint LOAD_FLANK_FALLING = (1<<6);
    const uint LOAD_HIGH = (1<<5);
    const uint LOAD_LOW = (1<<4);
    const uint LOAD_MASK = 0x00F0;
    const uint INVUL_FLANK_RISING = (1<<3);
    const uint INVUL_FLANK_FALLING = (1<<2);
    const uint INVUL_HIGH = (1<<1);
    const uint INVUL_LOW = (1<<0);
    const uint INVUL_MASK = 0x000F;

    Func<uint, uint, bool> CheckFlags = (flagFunctionSetting, flagsCurrent) => {
        if((flagFunctionSetting & (SKIP_FLAGS | MEMORYCHECK)) > 0) { return true; }
        return ((flagFunctionSetting & flagsCurrent) > 0);
    };
    vars.CheckFlags = CheckFlags;

    Func<dynamic, dynamic, uint> CalcFlags = (paraOld, paraCurrent) => {
        uint ret = 0;
        if (paraCurrent.loading > 0) { ret |= LOAD_HIGH; }
        else { ret |= LOAD_LOW; }
        if ((paraCurrent.loading > 0) != (paraOld.loading > 0)) {
            // one of the flanks is active
            if (paraCurrent.loading > 0) { ret |= LOAD_FLANK_RISING; }
            else { ret |= LOAD_FLANK_FALLING; }
        }
        
        bool curInvuln = ((paraCurrent.invulnerable > 0) && (paraCurrent.mountDestructabilityResPtr == 0));
        bool oldInvuln = ((paraOld.invulnerable > 0) && (paraOld.mountDestructabilityResPtr == 0));

        if (curInvuln > 0) { ret |= INVUL_HIGH; }
        else { ret |= INVUL_LOW; }
        if ((curInvuln > 0) != (oldInvuln > 0)) {
            // one of the flanks is active
            if (curInvuln > 0) { ret |= INVUL_FLANK_RISING; }
            else { ret |= INVUL_FLANK_FALLING; }
        }

        if ((paraCurrent.saveToggle > 0) != (paraOld.saveToggle > 0)) {
            ret |= SAVETGL;
        }
        return ret;
    };
    vars.CalcFlags = CalcFlags;
    vars.gameProcess = (Process)null;

    Func<double[], int, bool> CheckSingleGameCondition = (dataVec, idxData) => {
        uint type = (uint)(dataVec[0]);
        if (!vars.CheckFlags(type, vars.currentFlags)) { return false; }
        bool passedMem = true;
        if ((type & MEMORYCHECK) > 0)
        {
            int idxMemList = (int)(dataVec[1]);
            passedMem = false;
            if (idxMemList >= 0 && idxMemList < vars.memoryDB.Count)
            {
                if(vars.memoryDB[idxMemList].Update(vars.gameProcess))
                {
                    vars.DebugOutput("Mem DB Index " + idxMemList.ToString() + "changed");
                    passedMem = (vars.memoryDB[idxMemList].Current > 0) ^ ((type & MEMORY_RISING) == 0);
                }
            }
        }
        if (!passedMem) { return false; }
        if ((type & BOUNDSTYPE_MASK) > 0)
        {
            bool chkForInside = ((type & BOUNDS_IO_MASK) == BOUNDS_INSIDE);
            switch (type & BOUNDSTYPE_MASK)
            {
                case BOUNDSTYPE_AABB:
                    return vars.BoundsCheckAABB(vars.positionVec, dataVec, 1, chkForInside);
                case BOUNDSTYPE_CIRC:
                    return vars.BoundsCheckCircLat(vars.positionVec, dataVec, 1, chkForInside);
                case BOUNDSTYPE_CYL:
                    return vars.BoundsCheckCyl(vars.positionVec, dataVec, 1, chkForInside);
                case BOUNDSTYPE_SPHERE:
                    return vars.BoundsCheckSphere(vars.positionVec, dataVec, 1, chkForInside);
                default:
                    return false;
            }
        }
        else if((type & IGT_DELAY) > 0)
        {
            if (idxData < 0) { /* invalid */ return true; }
            if (vars.splittingData[idxData].Item3 == 0)
            {
                vars.splittingData[idxData] = new Tuple<int,int,double>(
                    vars.splittingData[idxData].Item1,
                    vars.splittingData[idxData].Item1,
                    vars.inGameTime
                );
                return false;
            }
            else
            {
                return ((vars.inGameTime - vars.splittingData[idxData].Item3) > dataVec[1]);
            }
        }
        else
        {
            // no other condition apart from flags
            return true;
        }
    };
    vars.CheckSingleGameCondition = CheckSingleGameCondition;

    vars.positionVec = new double[3];
    Action resetVarsVals = () => {
        vars.positionVec[0] = -8000; // initialize somewhere outside
        vars.positionVec[1] = 0;
        vars.positionVec[2] = 0;

        vars.currentFlags = (uint)0;
        vars.inGameTime = (double)0; // currently unused
    };
    vars.resetVarsVals = resetVarsVals;
    vars.resetVarsVals();

    Action<string, string, string, string> AddSplitSetting = (key, name, description, parent) => {
		settings.Add(key, true, name, parent);
        if(description != "") { settings.SetToolTip(key, description); }
	};
	Action<string, string, string, string> AddSplitSettingF = (key, name, description, parent) => {
		settings.Add(key, false, name, parent);
        if(description != "") { settings.SetToolTip(key, description); }
	};

    // ------------------------------------------------------------------
    // Data definition begin
    // ------------------------------------------------------------------

    AddSplitSettingF("res_main_menu", "Reset on Main Menu", "Reset run when quitting to main menu (shouldn't trigger on game crash)", null);
    AddSplitSetting("ngp_overall", "NG+ Run", "Main game splits used for NG+, also works for NG", null);
        AddSplitSetting("ngp_start", "NG+ Start", "Trigger run start on top of the cable car ride", "ngp_overall");
        AddSplitSetting("ngp_a1_barren_light", "Barren Light (FT)", "Fast travelling after completing To The Brink", "ngp_overall");
        AddSplitSetting("ngp_a1_embassy", "Embassy", "Cutscene skip after defeating Grudda", "ngp_overall");
        AddSplitSettingF("ngp_a1_tallneck", "Tallneck (FT)", "Fast travelling to the Tallneck after Embassy", "ngp_overall");
        AddSplitSetting("ngp_a1_igniter", "Igniter", "Exploding the Latopolis firegleam at entry", "ngp_overall");
        AddSplitSetting("ngp_a1_latopolis", "Latopolis", "Exploding the Latopolis firegleam at exit", "ngp_overall");
        AddSplitSetting("ngp_a1_tau", "Tau", "Overriding the Tau Core after the Grimhorn fight", "ngp_overall");
        AddSplitSetting("ngp_a1_base", "Base", "Skipping the cutscene exiting the Base to the west", "ngp_overall");
        AddSplitSetting("ngp_a2_capsule", "Capsule", "Fast travelling to the Hive campfire after starting Poseidon", "ngp_overall");
        AddSplitSettingF("ngp_a2_memorial_grove", "Memorial Grove", "Talking to Dekka when entering the Grove", "ngp_overall");
        AddSplitSetting("ngp_a2_kotallo", "Kotallo Skip", "Skipping the custscene when entering the Bulwark", "ngp_overall");
        AddSplitSetting("ngp_a2_bulwark", "Bulwark", "Skipping the cutscene destroying the Bulwark", "ngp_overall");
        AddSplitSetting("ngp_a2_alva", "Alva", "Skipping the cutscene when meeting Alva after the Quen fight", "ngp_overall");
        AddSplitSetting("ngp_a2_demeter_ft", "Demeter (FT)", "Fast travelling after retrieving Demeter", "ngp_overall");
        AddSplitSettingF("ngp_a2_demeter_gaia", "Demeter Merge", "When merging GAIA with Demeter", "ngp_overall");
        AddSplitSetting("ngp_a2_beta", "Beta", "Fast travelling away from the Base after retrieving Beta", "ngp_overall");
        AddSplitSetting("ngp_a2_aether_ft", "Aether (FT)", "Fast travelling after retrieving Aether", "ngp_overall");
        AddSplitSettingF("ngp_a2_aether_gaia", "Aether Merge", "When merging GAIA with Aether", "ngp_overall");
        AddSplitSetting("ngp_a2_poseidon_ft", "Poseidon (FT)", "Fast travelling after retrieving Poseidon", "ngp_overall");
        AddSplitSettingF("ngp_a2_poseidon_gaia", "Poseidon Merge", "When merging GAIA with Poseidon", "ngp_overall");
        AddSplitSetting("ngp_a3_thunderjaw", "Thunderjaw (San Fran)", "Skipping the cutscene speaking to Alva in SF", "ngp_overall");
        AddSplitSetting("ngp_a3_thebes", "Thebes", "Fast travelling away from Thebes", "ngp_overall");
        AddSplitSetting("ngp_a3_gemini", "Gemini", "Skipping the cutscene after completing Gemini (flashbang)", "ngp_overall");
        AddSplitSetting("ngp_a3_regalla", "Regalla", "Fast travelling away from the Grove after dealing with Regalla", "ngp_overall");
        AddSplitSetting("ngp_a3_singularity","Singularity", null, "ngp_overall");
            AddSplitSettingF("ngp_a3_sing_start", "Point of no return", "Skipping the cutscene starting the Sinularity mission", "ngp_a3_singularity");
            AddSplitSetting("ngp_a3_fz_skip", "FZ Skip", "On RFS to skip half of the final mission", "ngp_a3_singularity");
            AddSplitSettingF("ngp_a3_eric", "Eric", "On skipping the cutscene after defeating Eric", "ngp_a3_singularity");
        AddSplitSetting("ngp_a3_tilda", "Tilda", "On triggering the cutscene ending the main game runs (NOT on defeating Specter Prime)", "ngp_overall");
    AddSplitSettingF("ng_additional", "NG / Any% additional", "Prologue splits for Any% / NG runs. Also enable the NG+ splits", null);
        AddSplitSetting("ng_start", "NG / Any% Start", "Trigger run start at the beginning of the prologue", "ng_additional");
        AddSplitSetting("ng_frost_sling", "Frost Sling", "Skipping the projector hologram before getting the Frost Sling", "ng_additional");
        AddSplitSetting("ng_fake_gaia", "Fake GAIA", "When entering the GAIA room in the FZ datacenter", "ng_additional");
        AddSplitSetting("ng_cable_car", "Cable Car", "On the top of cable car (same as NG+ start, but as split)", "ng_additional");

    AddSplitSettingF("bs_mq", "NG+ Burning Shores", "Main game splits used for NG+ Burning Shores, also works for NG", null);
        AddSplitSetting("bs_start", "NG+ Burning Shores Start", "Trigger run start on the way to the Burning Shores", "bs_mq");
        AddSplitSettingF("bs_start_split", "NG+ Burning Shores Start (as split)", "Trigger a split on the way to the Burning Shores (e.g. for combined main game and BS runs)", "bs_mq");
        AddSplitSetting("bs_skiff1", "Skiff", "Different options for the split after the first fight", "bs_mq");
            AddSplitSettingF("bs_skiff1_fight", "Post-fight cutscene", "Skipping the cutscene after defeating the machines", "bs_skiff1");
            AddSplitSetting("bs_skiff1_skiff", "Sitting down on the skiff", null, "bs_skiff1");
            AddSplitSettingF("bs_skiff1_skiff_move", "Skiff starts moving", null, "bs_skiff1");
            AddSplitSettingF("bs_skiff1_fleets_end", "Arriving in Fleet's End", "Skipping the first cutscene after the skiff ride", "bs_skiff1");
        AddSplitSettingF("bs_bilegut", "Bilegut", "Passing the vines at the Tower entrance", "bs_mq");
        AddSplitSetting("bs_tower", "Tower", "Different options for the Tower split", "bs_mq");
            AddSplitSettingF("bs_tower_seyka", "Talking to Seyka", "Start talking to Seyka after completing the tower", "bs_tower");
            AddSplitSetting("bs_tower_ft", "Fleet's End FT", "Fast travelling after the tower", "bs_tower");
        AddSplitSetting("bs_observatory", "Observatory", "Triggering the console in Londra's living quarters", "bs_mq");
        AddSplitSetting("bs_transmitter_ft", "Transmitter (FT)", "Fast-travelling from the Transmitter (100% splits have another option here)", "bs_mq");
        AddSplitSetting("bs_control_nodes", "Heaven's Rest - Control Nodes", "Fast travelling out of the control node area", "bs_mq");
        AddSplitSettingF("bs_acension_hall", "Heaven's Rest - Acension Hall", "Talking to Seyka after scanning the ship (or completing the dry wiggle)", "bs_mq");
        AddSplitSetting("bs_heavens_rest", "Heaven's Rest - Zeth", "Fast travelling away after defeating Zeth", "bs_mq");
        AddSplitSetting("bs_beach", "Beach", "Skipping the cutscene talking to Seyka at the beach", "bs_mq");
        AddSplitSetting("bs_ww_override", "Waterwing Override", "Crafting the Waterwing override", "bs_mq");
        AddSplitSetting("bs_pangea_crossing", "Pangea's Park - Crossing", "Skipping the cutscene ", "bs_mq");
        AddSplitSettingF("bs_pangea_nova", "Pangea's Park - Nova", "Interacting with the Nova's console", "bs_mq");
        AddSplitSetting("bs_pangea_slaugtherspine_ft", "Pangea's Park - Slaugtherspine (FT)", "Fast travelling away from the Apex Spiny (100% splits have another option here)", "bs_mq");
        AddSplitSetting("bs_horus_cooling", "Horus - Cooling", "Skipping the cutscene after destroying the cooling pipe", "bs_mq");
        AddSplitSettingF("bs_horus_sink1", "Horus - Underbelly sink", "On RFS after the destroying the underbelly heat sink", "bs_mq");
        AddSplitSetting("bs_horus_sink2", "Horus - Side sink", "On RFS after the destroying the side heat sink", "bs_mq");
        AddSplitSetting("bs_horus_arms", "Horus - Arms", "Skipping the cutscene after destroying the main heat sink", "bs_mq");
        AddSplitSetting("bs_londra", "Londra", "Skipping the cutscene after defeating Londra", "bs_mq");
        AddSplitSetting("bs_seyka", "Seyka", "End of the BS main quest runs", "bs_mq");

    AddSplitSettingF("bs_100", "100% Burning Shores additional", "Additional 100% splits for Burning Shores (does not check actual progress)", null);
        AddSplitSettingF("bs_aerial_ne", "Aerial NE", "Aerial NE ends at the observatory", "bs_100");
            AddSplitSetting("bs_aerial_ne_save", "On Aerial completion" , "On checkpoint after closing the aerial", "bs_aerial_ne");
            AddSplitSettingF("bs_aerial_ne_load", "RFS / FT after Aerial completion" , "Any loads after closing the aerial", "bs_aerial_ne");
        AddSplitSetting("bs_trinket_pot", "Trinket: Old Pot", "Old Pot is at the northern Slitherfang site", "bs_100");
            AddSplitSettingF("bs_trinket_pot_save", "On Trinket collection" , "On checkpoint collecting the trinket", "bs_trinket_pot");
            AddSplitSetting("bs_trinket_pot_load", "RFS / FT after Trinket collection" , "Any loads after collecting the trinket", "bs_trinket_pot");
        AddSplitSetting("bs_transmitter_cs", "Transmitter (CS)", "Skipping the cutscene talking to Seyka (remember to deselect the BS main quest split)", "bs_100");
        AddSplitSettingF("bs_aerial_n", "Aerial North", "Aerial North ends at Capitol Records", "bs_100");
            AddSplitSettingF("bs_aerial_n_save", "On Aerial completion" , "On checkpoint after closing the aerial", "bs_aerial_n");
            AddSplitSetting("bs_aerial_n_load", "RFS / FT after Aerial completion" , "Any loads after closing the aerial", "bs_aerial_n");
        AddSplitSetting("bs_trinket_music_box", "Trinket: Music Box", "Music Box is in the Scorcher cave", "bs_100");
            AddSplitSettingF("bs_trinket_music_box_save", "On Trinket collection" , "On checkpoint collecting the trinket", "bs_trinket_music_box");
            AddSplitSetting("bs_trinket_music_box_load", "RFS / FT after Trinket collection" , "Any loads after collecting the trinket", "bs_trinket_music_box");
        AddSplitSetting("bs_theta", "Cauldron Theta", null, "bs_100");
            AddSplitSettingF("bs_theta_entry", "Entry", "When going down the corridor entering the cauldron", "bs_theta");
            AddSplitSettingF("bs_theta_override", "Node Override", "Overriding the node lowering the shield", "bs_theta");
            AddSplitSetting("bs_theta_completion", "Completion", "Fast travelling away after completion", "bs_theta");
        AddSplitSetting("bs_beach_collectibles", "Beach Collectibles", null, "bs_100");
            AddSplitSettingF("bs_figure_parking_lot", "Pangea Figure: Parking Lot (load)", "RFS / FT after picking up figurine", "bs_beach_collectibles");
            AddSplitSettingF("bs_trinket_flask", "Trinket: Cherished Flask (load)", "RFS / FT after picking up Cherished Flask", "bs_beach_collectibles");
        AddSplitSettingF("bs_trinket_bellowback", "Trinket by Bellowback (load)", "RFS / FT after picking up Delver's Cap", "bs_100");
        AddSplitSetting("bs_trinket_clamberjaws", "Trinket by Clamberjaws (load)", "RFS / FT after picking up Lucky Porter", "bs_100");
        AddSplitSetting("bs_mh", "Murmuring Hollow", null, "bs_100");
            AddSplitSettingF("bs_mh_door", "Gildun Door", "Interacting with the door (Gildun)", "bs_mh");
            AddSplitSettingF("bs_mh_friend_completion", "Friend% completion", "Final split of the Friend% CE", "bs_mh");
            AddSplitSetting("bs_mh_gildun", "Gildun (load)", "FT(!) after completing Gildun's quest", "bs_mh");
        AddSplitSetting("bs_pangea_slaugtherspine_cs", "Pangea's Park - Slaugtherspine (CS)", "Skipping the cutscene after defeating Apex Spiny (remember to deselect the BS main quest split)", "bs_100");
        AddSplitSetting("bs_aerial_e", "Aerial East", "Aerial East ends above Pangea Park", "bs_100");
            AddSplitSettingF("bs_aerial_e_save", "On Aerial completion" , "On checkpoint after closing the aerial", "bs_aerial_e");
            AddSplitSetting("bs_aerial_e_load", "RFS / FT after Aerial completion" , "Any loads after closing the aerial", "bs_aerial_e");
        AddSplitSettingF("bs_seyka_ft", "Seyka (FT)", "FT(!) after talking to Seyka, credits and RFS (remember to deselect the BS main quest split)", "bs_100");
        AddSplitSetting("bs_pier", "Santa Monica Pier", null, "bs_100");
            AddSplitSettingF("bs_sb_air", "Stormbird (getting kicked off)", "On getting kicked off by the Apex Stormbird", "bs_pier");
            AddSplitSetting("bs_sb_kill", "Strombird (on kill)", "On killing the Stormbird", "bs_pier");
            AddSplitSettingF("bs_sb_aerial_door", "Aerial Door (post SB)", "On interacting with the door for the Aerial (after killing SB)", "bs_pier");
        AddSplitSetting("bs_aerial_w", "Aerial West", "Aerial West ends looking towards Santa Monica Pier", "bs_100");
            AddSplitSetting("bs_aerial_w_save", "On Aerial completion" , "On checkpoint after closing the aerial", "bs_aerial_w");
            AddSplitSettingF("bs_aerial_w_load", "RFS / FT after Aerial completion" , "Any loads after closing the aerial", "bs_aerial_w");
        AddSplitSettingF("bs_trinket_hammer", "Trinket by Tideripper (pickup)", "On picking up the Hammer in the cave by the Tideripper", "bs_100");
        AddSplitSetting("bs_sq_splinter", "SQ: The Splinter Within", null, "bs_100");
            AddSplitSettingF("bs_splinter_tower", "LAIA Tower Island", "FT away from the Airport Tower Island", "bs_sq_splinter");
            AddSplitSettingF("bs_splinter_rokomo", "Rokomo", "On skipping the Rokomo cutscene", "bs_sq_splinter");
            AddSplitSetting("bs_splinter_focus_ft", "Enki's Focus (FT)", "FT after picking up the focus", "bs_sq_splinter");
        AddSplitSetting("bs_sq_wake", "SQ: In His Wake", null, "bs_100");
            AddSplitSettingF("bs_wake_outside", "Outside", "Skipping the cutscene after completing the outside part", "bs_sq_wake");
            AddSplitSettingF("bs_wake_dig", "Dig site", "Inserting the Key in the Dig", "bs_sq_wake");
            AddSplitSettingF("bs_wake_pirik_cs", "Lan (CS)", "On opening Lan's cell", "bs_sq_wake");
            AddSplitSetting("bs_wake_pirik_ft", "Lan (FT)", "On FT after opening Lan's cell", "bs_sq_wake");
        AddSplitSettingF("bs_aerial_s", "Aerial South", "Aerial South is the one unlocked after completing all the other ones", "bs_100");
            AddSplitSetting("bs_aerial_s_save", "On Aerial completion" , "On checkpoint after closing the aerial", "bs_aerial_s");
            AddSplitSettingF("bs_aerial_s_load", "RFS / FT after Aerial completion" , "Any loads after closing the aerial", "bs_aerial_s");
        AddSplitSetting("bs_sidequests", "Handing in the sidequests", "FT after handing in both sidequests", "bs_100");
        AddSplitSetting("bs_arena", "Arena", "FT away from the Arena (no check)", "bs_100");
        AddSplitSetting("bs_epilogue", "Epilogue", "Triggering the Epilogue cutscene in the base", "bs_100");

    vars.startingDB = new Tuple<string, double[]>[]{
        new Tuple<string, double[]>(
            "identifier", new double[]{}
        ),
    };

    vars.splittingDB = new Tuple<string, uint, double[][]>[]{
        new Tuple<string, uint, double[][]>(
            "identifier", 1, new double[][]{ 
                new double[]{}
            }
        ),
    };

    vars.memoryDB = new List<MemoryWatcher>();
    Action<int, int> FillMemoryDB = (offsetSceneManagerGame, offsetGameModule) => {
        // 0
        //vars.memoryDB.Add()

        vars.DebugOutput("FillMemoryDB: " + vars.memoryDB.Count.ToString() + " memory watchers entered.");
    };
    vars.FillMemoryDB = FillMemoryDB;

    // ------------------------------------------------------------------
    // Data definition end
    // ------------------------------------------------------------------

    vars.splittingData = new List<Tuple<int,int,double>>();
    vars.splittingData.Capacity = vars.splittingDB.Length;
}

init
{
    var module = modules.Single(x => String.Equals(x.ModuleName, "HorizonForbiddenWest.exe", StringComparison.OrdinalIgnoreCase));
    // No need to catch anything here because LiveSplit wouldn't have attached itself to the process if the name wasn't present

    var moduleSize = module.ModuleMemorySize;
    var hash = vars.CalcModuleHash(module);
    vars.DebugOutput(module.ModuleName + ": Module Size " + moduleSize + ", SHA256 Hash " + hash);

    int offsetGameModule = 0x08983150;
    int offsetSceneManagerGame = 0x08982DD0;

    version = "";
    if (hash == "9CEC6626AB60059D186EDBACCA4CE667573E8B28C916FCA1E07072002055429E")
    {
        version = "v1.5.80.0-Steam";
        // Don't do anything, the default variables are the Steam ones...
    }
    else if (hash == "8274587FA89612ADF904BDB2554DEA84D718B84CF691CCA9D2FB7D8D5D5D659B")
    {
        version = "v1.5.80.0-Epic";
        offsetGameModule = 0x0895EF50;
        offsetSceneManagerGame = 0x0895EBB8;
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

    vars.FillMemoryDB(offsetSceneManagerGame, offsetGameModule);
    vars.gameProcess = game;
}


update{
    if (current.aobPosition != null) // positions retain their old value on RFS to not trigger out of bounds checks for some splits
    {
        Buffer.BlockCopy(current.aobPosition, 0, vars.positionVec, 0, 24);
    }
    vars.currentFlags = vars.CalcFlags(old, current);
    // vars.inGameTime = current.xxx;
}

reset
{
    if(settings["res_main_menu"] && (old.worldPtr > 0 && current.worldPtr == 0))
    {
        vars.InfoOutput("RESET: Main Menu");
        return true;
    }
    return false;
}

start{
    for (int i = 0 ; i < vars.startingDB.Length ; ++i)
    {
        if (settings[vars.startingDB[i].Item1])
        {
            if (vars.CheckSingleGameCondition(vars.startingDB[i].Item2, -1))
            {
                vars.InfoOutput("START: " + vars.startingDB[i].Item1);
                return true;
            }
        }
    }
    return false;
}

split{
    bool retVal = false;
    int j;
    int idxDB;
    for (int i = 0 ; i < vars.splittingData.Count ; ++i)
    {
        if (vars.splittingData[i].Item2 < 0) { continue; } // already split
        idxDB = vars.splittingData[i].Item1;
        for (j = vars.splittingData[i].Item2; j < vars.splittingDB[idxDB].Item2 ; ++j)
        {
            if (j > vars.splittingData[i].Item2) { break; }
            if (vars.CheckSingleGameCondition(vars.splittingDB[idxDB].Item3[j], i))
            {
                vars.DebugOutput("Subsplit: " + vars.splittingDB[idxDB].Item1 + " , condition " + j.ToString());
                vars.splittingData[i] = new Tuple<int,int,double>(idxDB, vars.splittingData[i].Item2 + 1, vars.splittingData[i].Item3);
            }
        }
        if (vars.splittingData[i].Item2 == vars.splittingDB[idxDB].Item2)
        {
            vars.splittingData[i] = new Tuple<int,int,double>(idxDB, -1, vars.splittingData[i].Item3);
            vars.InfoOutput("SPLIT: " + vars.splittingDB[idxDB].Item1);
            retVal = true;
        }
    }
    return retVal;
}

onStart{
    if (game == null) { return; }
    vars.DebugOutput("Arming Splitting Data");
    vars.splittingData.Clear();
    for ( int i = 0 ; i < vars.splittingDB.Length ; ++i )
    {
        if (!settings[vars.splittingDB[i].Item1]) { continue; }
        vars.splittingData.Add(
            new Tuple<int,int,double>(i, 0, 0)
        );
    }
    vars.DebugOutput("Armed Splitting Data: " + vars.splittingData.Count.ToString() + " splits active");
}

onReset{
    vars.splittingData.Clear();
    vars.resetVarsVals();
}

isLoading
{
    return (current.loading > 0);
}

exit
{
    timer.IsGameTimePaused = false;
    vars.memoryDB.Clear();
    vars.gameProcess = (Process)null;
}

// Created by Driver and ISO2768mK
// Version detection from the Death Stranding and Alan Wake ASL

state("HorizonForbiddenWest", "v1.5.80.0-Steam")
{
    ulong worldPtr : 0x08983150;
    uint paused : 0x08983150, 0x20;
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
    uint paused : 0x0895EF50, 0x20;
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

    Func<double[], double[], int, bool, bool> BoundsCheckXYRBB = (pos, dataVec, index0, chkForInside) => {
        // dataVec: [ 2x3-row-major-hom-trafo z_min z_max]
        if (pos[2] < dataVec[index0 + 6] || pos[2] > dataVec[index0 + 7])
        {
            return !chkForInside;
        }
        double posV = dataVec[index0 + 3] * pos[0] + dataVec[index0 + 4] * pos[1] + dataVec[index0 + 5];
        if (posV < 0 || posV > 1) { return !chkForInside; }
        double posU = dataVec[index0 + 0] * pos[0] + dataVec[index0 + 1] * pos[1] + dataVec[index0 + 2];
        return (posU >= 0 && posU <= 1) ^ !chkForInside;
    }; // Bounding Box check allowing for rotation in XY, trafoData is expected to be 6 element vector for normalized transformation in XY
    vars.BoundsCheckXYRBB = BoundsCheckXYRBB;

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

    const uint IGT_DELAY = (1<<22);
    
    const uint MEMORYCHECK = (1<<21);
    const uint MEMORY_RISING = (1<<20);
    const uint MEMORY_FALLING = (0<<20);

    const uint BOUNDSTYPE_MASK = (7<<17);
    const uint BOUNDSTYPE_AABB = (1<<17);
    const uint BOUNDSTYPE_CIRC = (2<<17);
    const uint BOUNDSTYPE_CYL = (3<<17);
    const uint BOUNDSTYPE_SPHERE = (4<<17);
    const uint BOUNDSTYPE_XYRBB = (5<<17);
    const uint BOUNDS_IO_MASK = (1<<16);
    const uint BOUNDS_INSIDE = (1<<16);
    const uint BOUNDS_OUTSIDE = (0<<16);

    const uint SKIP_FLAGS = (1<<11);
    const uint SAVETGL = (1<<10);
    const uint PAUSE_HIGH = (1<<9);
    const uint PAUSE_LOW = (1<<8);
    const uint PAUSE_MASK = (3<<8);
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

        if ((paraCurrent.paused > 0) && (paraCurrent.loading == 0)) { ret |= PAUSE_HIGH; }
        else { ret |= PAUSE_LOW; }

        if (paraCurrent.loading > 0) { ret |= LOAD_HIGH; }
        else { ret |= LOAD_LOW; }
        if ((paraCurrent.loading > 0) != (paraOld.loading > 0)) {
            // one of the flanks is active
            if (paraCurrent.loading > 0) { ret |= LOAD_FLANK_RISING; }
            else { ret |= LOAD_FLANK_FALLING; }
        }
        
        bool curInvuln = ((paraCurrent.invulnerable > 0) && (paraCurrent.mountDestructabilityResPtr == 0));
        bool oldInvuln = ((paraOld.invulnerable > 0) && (paraOld.mountDestructabilityResPtr == 0));

        if (curInvuln) { ret |= INVUL_HIGH; }
        else { ret |= INVUL_LOW; }
        if (curInvuln != oldInvuln) {
            // one of the flanks is active
            if (curInvuln) { ret |= INVUL_FLANK_RISING; }
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
                case BOUNDSTYPE_XYRBB:
                    return vars.BoundsCheckXYRBB(vars.positionVec, dataVec, 1, chkForInside);
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
        AddSplitSetting("ngp_a1_daunt", "Daunt", null, "ngp_overall");
            AddSplitSetting("ngp_a1_barren_light", "Barren Light (FT)", "Fast travelling after completing To The Brink", "ngp_a1_daunt");
            AddSplitSetting("ngp_a1_embassy", "Embassy", "Cutscene start after defeating Grudda", "ngp_a1_daunt");
            AddSplitSettingF("ngp_a1_tallneck", "Tallneck (FT)", "Fast travelling to the Tallneck after Embassy", "ngp_a1_daunt");
        AddSplitSetting("ngp_a1_igniter", "Igniter", "Exploding the Latopolis firegleam at entry", "ngp_overall");
        AddSplitSetting("ngp_a1_latopolis", "Latopolis", "Exploding the Latopolis firegleam at exit", "ngp_overall");
        AddSplitSetting("ngp_a1_tau", "Tau", null, "ngp_overall");
            AddSplitSettingF("ngp_a1_tau_door", "Tau (Entry)", "Skipping the cutscene that gives Zo her Focus.", "ngp_a1_tau");
            AddSplitSettingF("ngp_a1_tau_skips", "Tau Skips", "Skipping the cutscene opening the door to the Grimhorn", "ngp_a1_tau");
            AddSplitSetting("ngp_a1_tau_core", "Tau (Core)", "Overriding the Tau Core after the Grimhorn fight", "ngp_a1_tau");
        AddSplitSetting("ngp_a1_base", "Base", "Skipping the cutscene exiting the Base to the west", "ngp_overall");
        AddSplitSetting("ngp_a2_aether_1", "Aether Part 1", null, "ngp_overall");
            AddSplitSetting("ngp_a2_memorial_grove_enter", "Memorial Grove (Entering)", "Talking to Dekka when entering the Grove", "ngp_a2_aether_1");
            AddSplitSettingF("ngp_a2_memorial_grove_leave", "Memorial Grove (Exiting)", "Talking to Dekka when leaving the Grove", "ngp_a2_aether_1");
            AddSplitSetting("ngp_a2_kotallo", "Kotallo Skip", "Skipping the cutscene when entering the Bulwark", "ngp_a2_aether_1");
            AddSplitSetting("ngp_a2_bulwark", "Bulwark", "Skipping the cutscene destroying the Bulwark", "ngp_a2_aether_1");
        AddSplitSetting("ngp_a2_demeter", "Demeter", null, "ngp_overall");
            AddSplitSetting("ngp_a2_alva", "Alva", "Skipping the cutscene when meeting Alva after the Quen fight", "ngp_a2_demeter");
            AddSplitSetting("ngp_a2_demeter_ft", "Demeter (FT)", "Fast travelling after retrieving Demeter", "ngp_a2_demeter");
            AddSplitSettingF("ngp_a2_demeter_gaia", "Demeter Merge", "When merging GAIA with Demeter", "ngp_a2_demeter");
        AddSplitSetting("ngp_a2_beta", "Beta", "Fast travelling away from the Base after retrieving Beta", "ngp_overall");
        AddSplitSetting("ngp_a2_aether_2", "Aether Part 2 (Kulrut)", null, "ngp_overall");
            AddSplitSetting("ngp_a2_aether_ft", "Aether (FT)", "Fast travelling after retrieving Aether", "ngp_a2_aether_2");
            AddSplitSettingF("ngp_a2_aether_gaia", "Aether Merge", "When merging GAIA with Aether", "ngp_a2_aether_2");
        AddSplitSetting("ngp_a2_poseidon", "Poseidon", null, "ngp_overall");
            AddSplitSetting("ngp_a2_capsule", "Capsule (FT)", "Fast travelling after starting Poseidon (usually directly after Base)", "ngp_a2_poseidon");
            AddSplitSetting("ngp_a2_poseidon_ft", "Poseidon (FT)", "Fast travelling after retrieving Poseidon", "ngp_a2_poseidon");
            AddSplitSettingF("ngp_a2_poseidon_gaia", "Poseidon Merge", "When merging GAIA with Poseidon", "ngp_a2_poseidon");
        AddSplitSetting("ngp_a3_thunderjaw", "Thunderjaw (San Fran)", "Speaking to Alva in SF", "ngp_overall");
        AddSplitSetting("ngp_a3_thebes", "Thebes", "Fast travelling away from Thebes", "ngp_overall");
        AddSplitSetting("ngp_a3_gemini", "Gemini", "Skipping the cutscene after completing Gemini (flashbang)", "ngp_overall");
        AddSplitSetting("ngp_a3_regalla", "Regalla", "Fast travelling away from the Grove after dealing with Regalla", "ngp_overall");
        AddSplitSetting("ngp_a3_singularity","Singularity", null, "ngp_overall");
            AddSplitSettingF("ngp_a3_sing_start", "Point of no return", "Skipping the cutscene starting the Singularity mission (triggers after loads)", "ngp_a3_singularity");
            AddSplitSetting("ngp_a3_fz_skip", "FZ Skip", "On RFS to skip half of the final mission", "ngp_a3_singularity");
            AddSplitSettingF("ngp_a3_erik", "Erik", "On skipping the cutscene after defeating Erik", "ngp_a3_singularity");
        AddSplitSetting("ngp_a3_tilda", "Tilda", "On triggering the cutscene ending the main game runs (NOT on defeating Specter Prime)", "ngp_overall");
    AddSplitSettingF("ng_additional", "NG / Any% additional", "Prologue splits for Any% / NG runs. Also enable the NG+ splits", null);
        AddSplitSetting("ng_start", "NG / Any% Start", "Trigger run start at the beginning of the prologue\rNote that this can trigger under some circumstances when loading from title screen. Only enable if you are doing NG runs.", "ng_additional");
        AddSplitSetting("ng_frost_sling", "Frost Sling Holo", "Skipping the projector hologram before getting the Frost Sling", "ng_additional");
        AddSplitSetting("ng_fake_gaia", "Fake GAIA", "When entering the GAIA room in the FZ datacenter", "ng_additional");
        AddSplitSetting("ng_cable_car", "Cable Car", "On the top of cable car (same as NG+ start, but as split)", "ng_additional");

    AddSplitSettingF("bs_mq", "NG+ Burning Shores", "Main game splits used for NG+ Burning Shores, also works for NG", null);
        AddSplitSetting("bs_start", "NG+ Burning Shores Start", "Trigger run start on the way to the Burning Shores", "bs_mq");
        AddSplitSettingF("bs_start_split", "NG+ Burning Shores Start (as split)", "Trigger a split on the way to the Burning Shores (e.g. for combined main game and BS runs)", "bs_mq");
        AddSplitSetting("bs_skiff1", "Skiff", "Different options for the split after the first fight", "bs_mq");
            AddSplitSettingF("bs_skiff1_fight", "Post-fight cutscene", "Skipping the cutscene after defeating the machines", "bs_skiff1");
            AddSplitSetting("bs_skiff1_skiff", "Sitting down on the skiff", "Note: This splits slightly after sitting down", "bs_skiff1");
            AddSplitSettingF("bs_skiff1_skiff_move", "Skiff starts moving", null, "bs_skiff1");
            AddSplitSettingF("bs_skiff1_fleets_end", "Arriving in Fleet's End", "Skipping the first cutscene after the skiff ride", "bs_skiff1");
        AddSplitSettingF("bs_bilegut", "Bilegut", "Passing the vines at the Tower entrance", "bs_mq");
        AddSplitSetting("bs_tower", "Tower", "Different options for the Tower split", "bs_mq");
            AddSplitSettingF("bs_tower_seyka", "Talking to Seyka", "Start talking to Seyka after completing the tower", "bs_tower");
            AddSplitSetting("bs_tower_ft", "Fleet's End FT", "Fast travelling after the tower", "bs_tower");
        AddSplitSetting("bs_observatory", "Observatory", "Triggering the console in Londra's living quarters", "bs_mq");
        AddSplitSetting("bs_transmitter_ft", "Transmitter (FT)", "Fast-travelling from the Transmitter (100% splits have another option here)", "bs_mq");
        AddSplitSetting("bs_control_nodes", "Control Nodes", "Fast travelling out of the control node area", "bs_mq");
        AddSplitSettingF("bs_acension_hall", "Heaven's Rest - Acension Hall", "Talking to Seyka after scanning the ship (or completing the dry wiggle)", "bs_mq");
        AddSplitSetting("bs_heavens_rest", "Heaven's Rest - Zeth (FT)", "Fast travelling away after defeating Zeth", "bs_mq");
        AddSplitSetting("bs_beach", "Beach", "Skipping the cutscene talking to Seyka at the beach", "bs_mq");
        AddSplitSetting("bs_ww_override", "Waterwing Override", "Crafting the Waterwing override", "bs_mq");
        AddSplitSetting("bs_pangea", "Pangea Park", null, "bs_mq");
            AddSplitSetting("bs_pangea_crossing", "Crossing", "Skipping the cutscene ", "bs_pangea");
            AddSplitSettingF("bs_pangea_nova", "Nova", "Interacting with the Nova's console", "bs_pangea");
            AddSplitSetting("bs_pangea_slaugtherspine_ft", "Slaugtherspine (FT)", "Fast travelling away from the Apex Spiny (100% splits have another option here)", "bs_pangea");
        AddSplitSetting("bs_horus", "Horus", null, "bs_mq");
            AddSplitSetting("bs_horus_cooling", "Cooling", "Skipping the cutscene after destroying the cooling pipe", "bs_horus");
            AddSplitSettingF("bs_horus_sink1", "Underbelly sink", "On RFS after the destroying the underbelly heat sink", "bs_horus");
            AddSplitSetting("bs_horus_sink2", "Side sink", "On RFS after the destroying the side heat sink", "bs_horus");
            AddSplitSetting("bs_horus_arms", "Arms", "Skipping the cutscene after destroying the main heat sink", "bs_horus");
            AddSplitSetting("bs_londra", "Londra", "Skipping the cutscene after defeating Londra", "bs_horus");
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
        AddSplitSetting("bs_aerial_nw", "Aerial NW", "Aerial NW ends at the Hollywood sign", "bs_100");
            AddSplitSetting("bs_aerial_nw_save", "On Aerial completion" , "On checkpoint after closing the aerial", "bs_aerial_nw");
            AddSplitSettingF("bs_aerial_nw_load", "RFS / FT after Aerial completion" , "Any loads after closing the aerial", "bs_aerial_nw");
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
            AddSplitSettingF("bs_wake_lan_cs", "Lan (CS)", "On opening Lan's cell", "bs_sq_wake");
            AddSplitSetting("bs_wake_lan_ft", "Lan (FT)", "On FT after opening Lan's cell", "bs_sq_wake");
        AddSplitSettingF("bs_aerial_s", "Aerial South", "Aerial South is the one unlocked after completing all the other ones", "bs_100");
            AddSplitSetting("bs_aerial_s_save", "On Aerial completion" , "On checkpoint after closing the aerial", "bs_aerial_s");
            AddSplitSettingF("bs_aerial_s_load", "RFS / FT after Aerial completion" , "Any loads after closing the aerial", "bs_aerial_s");
        AddSplitSetting("bs_leaving", "Leaving the Burning Shores", "FT leaving the Burning Shores after the main quest. Usually this is after handing in the sidequests, but at the moment this cannot be relibly detected.", "bs_100");
        AddSplitSetting("bs_arena", "Arena", "FT away from the Arena (no check of completion)", "bs_100");
        AddSplitSetting("bs_epilogue", "Epilogue", "Triggering the Epilogue cutscene in the base (no check of achieving 100%)", "bs_100");

    vars.startingDB = new Tuple<string, double[]>[]{
        new Tuple<string, double[]>(
            "ngp_start", new double[]{
                BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_LOW,
                5,
                4051.11, 948.64,
                623, 627
            }
        ),
        new Tuple<string, double[]>(
            "ng_start", new double[]{
                BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_FLANK_FALLING,
                5,
                5649.10, -2878.05
            }
        ),
        new Tuple<string, double[]>(
            "bs_start", new double[]{
                BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_LOW,
                5,
                579.40, -4744.63,
                270, 275
            }
        )
    };
    const uint NUM_OF_STEPS = 0;
    vars.splittingDB = new Tuple<string, uint, double[][]>[]{
        // NG+
        new Tuple<string, uint, double[][]>(
            "ngp_a1_barren_light", 3, new double[][]{ 
                new double[]{ // Ulvund
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | SAVETGL,
                    2,
                    3514.57, 631.94
                },
                new double[]{ // Vuadis
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | SAVETGL,
                    2,
                    3478.15, 693.58
                },
                new double[]{ // FT away from CS
                    BOUNDSTYPE_CIRC | BOUNDS_OUTSIDE | LOAD_HIGH,
                    50,
                    3478.15, 693.58
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a1_embassy", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    1,
                    2861.84, -94.74
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a1_tallneck", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | LOAD_HIGH,
                    1,
                    2104.01, -263.95
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a1_igniter", 1, new double[][]{ 
                new double[]{ // Position erroring door: 1409.98, -1056.98
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    1,
                    1407.43, -1055.16,
                    418, 423
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a1_latopolis", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_FLANK_RISING,
                    2,
                    1167.75, -1016.77,
                    380, 384
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a1_tau_door", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_FLANK_FALLING,
                    1,
                    1316.54, -63.61,
                    505, 509
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a1_tau_skips", 1, new double[][]{ 
                new double[]{ // 1204.34,-135.38 -> CS -> 1204.4,-148.3
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_FLANK_FALLING,
                    8,
                    1204.35, -141.8,
                    510, 514
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a1_tau_core", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_FLANK_RISING,
                    1,
                    1204.68, -182.48,
                    498, 501
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a1_base", 1, new double[][]{ 
                new double[]{ // 1080.9,-128.4 -> CS -> 1065.7,-134.0 ; Save (2x) is def outside though
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | SAVETGL,
                    2,
                    1065.7, -134.0,
                    594, 597
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a2_capsule", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    168.20, -1755.25,
                    358, 365
                },
                new double[]{ // post RFS: 193.0, -1755.7
                    BOUNDSTYPE_CIRC | BOUNDS_OUTSIDE | LOAD_HIGH,
                    60,
                    168.20, -1755.25
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a2_memorial_grove_enter", 1, new double[][]{ 
                new double[]{ // -552.1,-695.8 -> Dia skipping -> -561.3,-701.2
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_FLANK_RISING,
                    3,
                    -552.1, -695.8
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a2_memorial_grove_leave", 2, new double[][]{ 
                new double[]{ // Hekarro
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    5,
                    -652.3, -726.3,
                    423, 427
                },
                new double[]{ // -560.06,-702.16 -> CS -> -560.24,-701.8
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_FLANK_FALLING,
                    2,
                    -560.24, -701.8
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a2_kotallo", 2, new double[][]{ 
                new double[]{ // -1723.13, 498.74 -> CS -> -1722.13, 391.31
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_FLANK_RISING,
                    2,
                    -1723.13, 498.74
                },
                new double[]{
                    INVUL_FLANK_FALLING
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a2_bulwark", 2, new double[][]{ 
                new double[]{ // Shooting: -1730.46,462.68, -1732.14,455.49 -> CS -> 1723.03, 479.15
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    -1732.14, 455.49
                },
                new double[]{
                    INVUL_FLANK_FALLING
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a2_alva", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_FLANK_RISING,
                    2,
                    -2432.61, -299.38
                },
                new double[]{
                    INVUL_FLANK_FALLING
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a2_demeter_ft", 2, new double[][]{ 
                new double[]{ // Demeter Core
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_FLANK_RISING,
                    2,
                    -2434.22, -152.16,
                    266, 269
                },
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_OUTSIDE | LOAD_HIGH,
                    100,
                    -2434.22, -152.16
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a2_demeter_gaia", 2, new double[][]{ 
                new double[]{ // Demeter Core
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_FLANK_RISING,
                    2,
                    -2434.22, -152.16,
                    266, 269
                },
                new double[]{ // GAIA
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_FLANK_RISING,
                    4,
                    1126.70, -172.77,
                    602, 607
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a2_beta", 3, new double[][]{ 
                new double[]{ // Ninmah console
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    543.45, 1292.2,
                    585, 589
                },
                new double[]{ // Varl in Base basement
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    3,
                    1126.43, -161.77,
                    585, 588
                },
                new double[]{ // FT from Base
                    BOUNDSTYPE_CIRC | BOUNDS_OUTSIDE | LOAD_HIGH,
                    150,
                    1126, -160
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a2_aether_ft", 2, new double[][]{ 
                new double[]{ // Aether core
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_FLANK_RISING,
                    2,
                    -645.64, -724.19,
                    409, 412
                },
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_OUTSIDE | LOAD_HIGH,
                    100,
                    -645.64, -724.19,
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a2_aether_gaia", 2, new double[][]{ 
                new double[]{ // Aether core
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_FLANK_RISING,
                    2,
                    -645.64, -724.19,
                    409, 412
                },
                new double[]{ // GAIA
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_FLANK_RISING,
                    4,
                    1126.70, -172.77,
                    602, 607
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a2_poseidon_ft", 3, new double[][]{ 
                new double[]{ // Poseidon core
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_FLANK_RISING,
                    2,
                    375.89, -1607.86,
                    289, 293
                },
                new double[]{ // outside
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    4,
                    189.87, -1755.63,
                    377, 381
                },
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_OUTSIDE | LOAD_HIGH,
                    50,
                    189.87, -1755.63
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a2_poseidon_gaia", 2, new double[][]{ 
                new double[]{ // Poseidon core
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_FLANK_RISING,
                    2,
                    375.89, -1607.86,
                    289, 293
                },
                new double[]{ // GAIA
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_FLANK_RISING,
                    4,
                    1126.70, -172.77,
                    602, 607
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a3_thunderjaw", 1, new double[][]{ 
                new double[]{ 
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_FLANK_RISING,
                    2,
                    -4124.05, -756.87
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a3_thebes", 4, new double[][]{ 
                new double[]{ // Omega console
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    -4347.25, -701.26,
                    170, 174
                },
                new double[]{ // start of CS
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    5,
                    -4202.13, -751.30
                },
                new double[]{ // end of CS
                    INVUL_LOW
                },
                new double[]{ // FT
                    BOUNDSTYPE_CIRC | BOUNDS_OUTSIDE | LOAD_HIGH,
                    100,
                    -4124.61, -759.17
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a3_gemini", 3, new double[][]{ 
                new double[]{ // Slaugtherspine node override (via saves)
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | SAVETGL,
                    2,
                    -338.63, -278.94,
                    321, 325
                },
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    -374.48, -417.82,
                    326, 330
                },
                new double[]{ // Flashbang ports the position to Tilda already
                    BOUNDSTYPE_CIRC | BOUNDS_OUTSIDE | SKIP_FLAGS,
                    150,
                    -374.48, -417.82
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a3_regalla", 3, new double[][]{ 
                new double[]{ // end of phase 1, because of unique position
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    -737.66, -673.45,
                    425, 427
                },
                new double[]{ // Sylens holo talk
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    4,
                    -652.03, -726.97,
                    423, 427
                },
                new double[]{ // FT
                    BOUNDSTYPE_CIRC | BOUNDS_OUTSIDE | LOAD_HIGH,
                    150,
                    -652.03, -726.97
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a3_sing_start", 2, new double[][]{ 
                new double[]{ // Singularity campfire
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    -1155.37, -2664.07
                },
                new double[]{ // port to island
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_LOW,
                    20,
                    -1218.0, -3076.25
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a3_fz_skip", 2, new double[][]{ 
                new double[]{ // Singularity campfire
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    -1155.37, -2664.07
                },
                new double[]{ // split during load
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | LOAD_HIGH,
                    5,
                    -1640.05, -3209.68
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a3_erik", 2, new double[][]{ 
                new double[]{ // start of Eric kill CS
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    -1749.26, -2938.77,
                    274, 280
                },
                new double[]{
                    INVUL_LOW
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ngp_a3_tilda", 3, new double[][]{ 
                new double[]{ // CS killing Specter Prime
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    -1811.02, -2885.18,
                    378, 382
                },
                new double[]{
                    INVUL_LOW
                },
                new double[]{ // Tilda pod
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    7,
                    -1771.62, -2921.04,
                    378, 385
                }
            }
        ),
        // Any% additional
        new Tuple<string, uint, double[][]>(
            "ng_frost_sling", 2, new double[][]{ 
                new double[]{ // holo start
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    6188.75, -3084.71
                },
                new double[]{
                    INVUL_LOW
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ng_fake_gaia", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    6749.64, -3000.88
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "ng_cable_car", 2, new double[][]{ 
                new double[]{ // last CS
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    4128.66, 1017.12
                },
                new double[]{
                    INVUL_LOW
                }
            }
        ),
        // BS Main
        new Tuple<string, uint, double[][]>(
            "bs_start_split", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    30,
                    -2720.46, -2700.25,
                    360, 388
                },
                new double[]{
                    INVUL_LOW
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_skiff1_fight", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    3,
                    582.10, -4785.80
                },
                new double[]{
                    INVUL_LOW
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_skiff1_skiff", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    1,
                    550.20, -4888.74
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_skiff1_skiff_move", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    1,
                    550.20, -4888.74
                },
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_OUTSIDE | SKIP_FLAGS,
                    0.07,
                    550.20, -4888.74
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_skiff1_fleets_end", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    1,
                    550.20, -4888.74
                },
                new double[]{ // Porting of skipping the CS in Fleet's
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    865.12, -5278.45,
                    285, 288
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_bilegut", 2, new double[][]{ 
                new double[]{ // Killing the Bilegut
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | SAVETGL,
                    200,
                    1280, -5149.47
                },
                new double[]{
                    BOUNDSTYPE_XYRBB | BOUNDS_INSIDE | SKIP_FLAGS,
                    0.1400560224, 0.1400560224, 525.4580, -0.3928371007, 0.3928371007, 2530.3609,
                    314, 319
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_tower_seyka", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    1,
                    1316.51, -5084.84,
                    375, 378
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_tower_ft", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    1,
                    1316.51, -5084.84,
                    375, 378
                },
                new double[]{ // 1316.51, -5084.84 | 1409.93, -4989.53
                    BOUNDSTYPE_CIRC | BOUNDS_OUTSIDE | LOAD_HIGH,
                    80,
                    1363, -5038
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_observatory", 2, new double[][]{ 
                new double[]{ // Mural door
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    1700.38, -4453.37,
                    342, 346
                },
                new double[]{ // Console typing is from that one place
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | SKIP_FLAGS,
                    0.02,
                    1690.85, -4462.15, 347.19
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_transmitter_ft", 2, new double[][]{ 
                new double[]{ // end of transmitter investigation
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | SAVETGL,
                    2,
                    1701.49, -4333.08,
                    335, 340
                },
                new double[]{ // CS is 1702.06, -4354.69
                    BOUNDSTYPE_CIRC | BOUNDS_OUTSIDE | LOAD_HIGH,
                    40,
                    1700, -4344
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_control_nodes", 3, new double[][]{ 
                new double[]{ // door scan CS
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    674.55, -4240.54
                },
                new double[]{ 
                    // Horus CF: 708.34, -4295.87, 349.02
                    // Node N: 850.94, -4247.56, 334.18
                    // Node S: 791.94, -4334.13, 336.35
                    // Door CF: 650.79, -4244.39, 365.00
                    BOUNDSTYPE_AABB | BOUNDS_INSIDE | SKIP_FLAGS,
                    700, -4350, 0,
                    900, -4200, 1000
                },
                new double[]{
                    BOUNDSTYPE_AABB | BOUNDS_OUTSIDE | LOAD_HIGH,
                    700, -4350, 0,
                    900, -4200, 1000
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_acension_hall", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    375.76,-4031.15,
                    346, 349
                },
                new double[]{
                    INVUL_LOW
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_heavens_rest", 3, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    490.88, -4035.19,
                    356, 359
                },
                new double[]{
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | SAVETGL,
                    5,
                    684.80, -4235.73, 366.18
                },
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_OUTSIDE | LOAD_HIGH,
                    10,
                    684.80, -4235.73
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_beach", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    1673.95, -5513.40
                },
                new double[]{
                    INVUL_LOW
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_ww_override", 1, new double[][]{ 
                new double[]{ // Quest item crafting creates save while paused
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | PAUSE_HIGH | SAVETGL,
                    3,
                    811.02, -5228.06
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_pangea_crossing", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    1914.54, -5906.44
                },
                new double[]{
                    INVUL_LOW
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_pangea_nova", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    1,
                    2415.04, -5630.00,
                    270, 273
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_pangea_slaugtherspine_ft", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    2451.54, -5516.71
                },
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_OUTSIDE | LOAD_HIGH,
                    100,
                    2451.54, -5516.71
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_horus_cooling", 2, new double[][]{ 
                new double[]{ // cooling CS
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    554.78, -4215.25
                },
                new double[]{
                    INVUL_LOW
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_horus_sink1", 1, new double[][]{ 
                new double[]{ // spawn point of RFS
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | LOAD_HIGH,
                    1,
                    -226.37, -4541.37
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_horus_sink2", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | LOAD_HIGH,
                    1,
                    -284.42, -4744.33
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_horus_arms", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    -296.63, -4802.59, 256.52
                },
                new double[]{
                    INVUL_LOW
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_londra", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    -292.41, -5321.89, 301.79
                },
                new double[]{ // load high because invul stays high through the load
                    LOAD_HIGH
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_seyka", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    511.67, -4755.88
                }
            }
        ),
        // BS 100% additional
        new Tuple<string, uint, double[][]>(
            "bs_aerial_ne_save", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | SAVETGL,
                    3,
                    1812.04, -4415.36, 339.80
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_aerial_ne_load", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | SAVETGL,
                    3,
                    1812.04, -4415.36, 339.80
                },
                new double[]{
                    LOAD_HIGH
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_trinket_pot_save", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | SAVETGL,
                    2,
                    1921.03, -4051.32
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_trinket_pot_load", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | SAVETGL,
                    2,
                    1921.03, -4051.32
                },
                new double[]{
                    LOAD_HIGH
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_transmitter_cs", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    1702.06, -4354.69
                },
                new double[]{
                    INVUL_LOW
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_aerial_n_save", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | SAVETGL,
                    3,
                    1148.68, -4628.44, 296.73
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_aerial_n_load", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | SAVETGL,
                    3,
                    1148.68, -4628.44, 296.73
                },
                new double[]{
                    LOAD_HIGH
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_trinket_music_box_save", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | SAVETGL,
                    2,
                    1253.06, -4306.27,
                    270, 273
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_trinket_music_box_load", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | SAVETGL,
                    2,
                    1253.06, -4306.27,
                    270, 273
                },
                new double[]{
                    LOAD_HIGH
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_aerial_nw_save", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | SAVETGL,
                    3,
                    681.60, -4317.26, 359.26
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_aerial_nw_load", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | SAVETGL,
                    3,
                    681.60, -4317.26, 359.26
                },
                new double[]{
                    LOAD_HIGH
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_theta_entry", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | SAVETGL,
                    20,
                    2323.49, -5035.73, 282.95
                },
                new double[]{
                    BOUNDSTYPE_XYRBB | BOUNDS_INSIDE | SKIP_FLAGS,
                    0.0568106524, -0.0413043632, -339.7093, 0.2940277636, 0.4044102796, 1338.3697,
                    252, 262
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_theta_override", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | SAVETGL,
                    20,
                    2323.49, -5035.73, 282.95
                },
                new double[]{ 
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | SKIP_FLAGS,
                    0.2,
                    2582.83, -4720.77, 200.86
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_theta_completion", 3, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    2753.74, -5070.88, 120
                },
                new double[]{ // top spawn pos: 2460.59, -4921.22, 384.29
                    INVUL_LOW
                },
                new double[]{ // to 2083.51, -5056.41
                    BOUNDSTYPE_CIRC | BOUNDS_OUTSIDE | LOAD_HIGH,
                    400,
                    2607.17, -4996.0
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_figure_parking_lot", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | SAVETGL,
                    2,
                    1559.90, -5262.01,
                    270, 274
                },
                new double[]{
                    LOAD_HIGH
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_trinket_flask", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | SAVETGL,
                    2,
                    1768.39, -5220.57,
                    261, 265
                },
                new double[]{
                    LOAD_HIGH
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_trinket_bellowback", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | SAVETGL,
                    2,
                    1301.96, -5596.25,
                    333, 336
                },
                new double[]{
                    LOAD_HIGH
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_trinket_clamberjaws", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | SAVETGL,
                    2,
                    1000.14, -5804.86,
                    259, 264
                },
                new double[]{
                    LOAD_HIGH
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_mh_door", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    1447.81, -5524.30,
                    327, 331
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_mh_friend_completion", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    1,
                    1335.81, -5563.90,
                    305, 309
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_mh_gildun", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    1,
                    1335.81, -5563.90,
                    305, 309
                },
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_OUTSIDE | LOAD_HIGH,
                    20,
                    1335.81, -5563.90,
                    300, 320
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_pangea_slaugtherspine_cs", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    2451.54, -5516.71
                },
                new double[]{
                    INVUL_LOW
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_aerial_e_save", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | SAVETGL,
                    3,
                    2013.83, -5661.43, 344.95
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_aerial_e_load", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | SAVETGL,
                    3,
                    2013.83, -5661.43, 344.95
                },
                new double[]{
                    LOAD_HIGH
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_seyka_ft", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    511.67, -4755.88
                },
                new double[]{ // post credits: 557.66, -4760.38
                    BOUNDSTYPE_CIRC | BOUNDS_OUTSIDE | LOAD_HIGH,
                    50,
                    535, -4760
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_sb_air", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | SAVETGL,
                    50,
                    -28.50, -5184.49, 587.82
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_sb_kill", 1, new double[][]{ 
                new double[]{ // Fighting area: RFS: -2.10, -5167.65 -> Delver -100, -5185.05
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | SAVETGL,
                    70,
                    -50, -5175,
                    250, 280
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_sb_aerial_door", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    -25.89, -5196.26,
                    260, 264
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_aerial_w_save", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | SAVETGL,
                    3,
                    77.24, -5336.12, 289.00
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_aerial_w_load", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | SAVETGL,
                    3,
                    77.24, -5336.12, 289.00
                },
                new double[]{
                    LOAD_HIGH
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_trinket_hammer", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | SAVETGL,
                    2,
                    398.17, -5700.51,
                    281, 285
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_splinter_tower", 4, new double[][]{ 
                new double[]{ // stabbed Quen save point
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | SAVETGL,
                    30,
                    58.80, -6083.76
                },
                new double[]{ // Boat marks
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | SKIP_FLAGS,
                    5,
                    41.15, -6105.67
                },
                new double[]{
                    SAVETGL
                },
                new double[]{
                    BOUNDSTYPE_CIRC | BOUNDS_OUTSIDE | LOAD_HIGH,
                    80,
                    41.15, -6105.67
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_splinter_rokomo", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    482.51, -6019.49,
                    273, 276
                },
                new double[]{
                    INVUL_LOW
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_splinter_focus_ft", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | SAVETGL,
                    70,
                    762, -5988,
                    200, 253
                },
                new double[]{
                    LOAD_HIGH
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_wake_outside", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    354.57, -5430.50,
                    278, 281
                },
                new double[]{
                    INVUL_LOW
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_wake_dig", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    457.72, -5425.77,
                    284, 288
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_wake_lan_cs", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    1,
                    563.33, -5377.89,
                    303, 307
                },
                new double[]{
                    INVUL_LOW
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_wake_lan_ft", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    1,
                    563.33, -5377.89,
                    303, 307
                },
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_OUTSIDE | LOAD_HIGH,
                    5,
                    563.33, -5377.89,
                    290, 320
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_aerial_s_save", 1, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | SAVETGL,
                    3,
                    1042.01, -4880.48, 399.72
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_aerial_s_load", 2, new double[][]{ 
                new double[]{
                    BOUNDSTYPE_SPHERE | BOUNDS_INSIDE | SAVETGL,
                    3,
                    1042.01, -4880.48, 399.72
                },
                new double[]{
                    LOAD_HIGH
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_leaving", 2, new double[][]{ 
                new double[]{ // Sekya
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    511.67, -4755.88
                },
                new double[]{ // BB around the BS; Ymax is the most important
                    BOUNDSTYPE_AABB | BOUNDS_OUTSIDE | LOAD_HIGH,
                    -2000, -8000, -1000,
                    3500, -3500, 2000
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_arena", 3, new double[][]{ 
                new double[]{ // Sekya
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    511.67, -4755.88
                },
                new double[]{ // Victory / Fail scene final BS challenge
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    0.5,
                    -708.50, -615.36
                },
                new double[]{ // front of arena: -643.34, -638.87
                    BOUNDSTYPE_CIRC | BOUNDS_OUTSIDE | LOAD_HIGH,
                    120,
                    -675, -630
                }
            }
        ),
        new Tuple<string, uint, double[][]>(
            "bs_epilogue", 2, new double[][]{ 
                new double[]{ // Sekya
                    BOUNDSTYPE_CIRC | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    511.67, -4755.88
                },
                new double[]{
                    BOUNDSTYPE_CYL | BOUNDS_INSIDE | INVUL_HIGH,
                    2,
                    1143.48, -114.49,
                    594, 599
                }
            }
        )
        /*
        new Tuple<string, uint, double[][]>(
            "id", NUM_OF_STEPS, new double[][]{ 
                new double[]{},
                new double[]{}
            }
        ),
        */
    };

    vars.memoryDB = new List<MemoryWatcher>();
    Action<int, int> FillMemoryDB = (offsetSceneManagerGame, offsetGameModule) => {
        // 0
        vars.memoryDB.Add(new MemoryWatcher<byte>(new DeepPointer("HorizonForbiddenWest.exe", offsetSceneManagerGame, 0xE8, 0x1770, 0x1140, 0x16E1))); // NG+ Start

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

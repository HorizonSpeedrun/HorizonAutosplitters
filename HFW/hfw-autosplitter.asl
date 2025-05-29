// Created by Driver and ISO2768mK
// Version detection from the Death Stranding and Alan Wake ASL

state("HorizonForbiddenWest", "v1.5.80.0-Steam")
{
    ulong worldPtr : 0x08983150;
    uint loading : 0x08983150, 0x4B4;
    // toggles between 0 and 1 on every save (quick or auto)
    byte saveToggle : 0x08983150, 0x3F8;
    // Aloy's position:
    byte24 aobPosition : 0x8982DA0, 0x1C10, 0x0, 0x10, 0xD8;
    // Aloy's invulnerable flag:
    byte invulnerable : 0x8982DA0, 0x1C10, 0x0, 0x10, 0xD0, 0x70;
}
state("HorizonForbiddenWest", "v1.5.80.0-Epic")
{
    ulong worldPtr : 0x0895EF50;
    uint loading : 0x0895EF50, 0x4B4;
    byte saveToggle : 0x0895EF50, 0x3F8;
    byte24 aobPosition : 0x0895EBC8, 0x1C10, 0x0, 0x10, 0xD8;
    byte invulnerable :  0x0895EBC8, 0x1C10, 0x0, 0x10, 0xD0, 0x70;
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
        return vars.BoundsCheckCircLat(pos, dataVec, 0, chkForInside);
    };
    vars.BoundsCheckCyl = BoundsCheckCyl;

    const ushort MEMORYCHECK = (1<<15);
    const ushort MEMORY_RISING = (1<<14);
    const ushort MEMORY_FALLING = (0<<14);

    const ushort BOUNDSTYPE_MASK = (7<<11);
    const ushort BOUNDSTYPE_AABB = (1<<11);
    const ushort BOUNDSTYPE_CIRC = (2<<11);
    const ushort BOUNDSTYPE_CYL = (3<<11);
    const ushort BOUNDSTYPE_SPHERE = (4<<11);
    const ushort BOUNDS_IO_MASK = (1<<10);
    const ushort BOUNDS_INSIDE = (1<<10);
    const ushort BOUNDS_OUTSIDE = (0<<10);

    const ushort SKIP_FLAGS = (1<<9);
    const ushort SAVETGL = (1<<8);
    const ushort LOAD_FLANK_RISING = (1<<7);
    const ushort LOAD_FLANK_FALLING = (1<<6);
    const ushort LOAD_HIGH = (1<<5);
    const ushort LOAD_LOW = (1<<4);
    const ushort LOAD_MASK = 0x00F0;
    const ushort INVUL_FLANK_RISING = (1<<3);
    const ushort INVUL_FLANK_FALLING = (1<<2);
    const ushort INVUL_HIGH = (1<<1);
    const ushort INVUL_LOW = (1<<0);
    const ushort INVUL_MASK = 0x000F;

    Func<ushort, ushort, bool> CheckFlags = (flagFunctionSetting, flagsCurrent) => {
        if((flagFunctionSetting & SKIP_FLAGS) > 0) { return true; }
        return ((flagFunctionSetting & flagsCurrent) > 0);
    };
    vars.CheckFlags = CheckFlags;

    Func<uint, uint, byte, byte, byte, byte, ushort> CalcFlags = (oldLoad, curLoad, oldInvuln, curInvuln, oldSaveTgl, curSaveTgl) => {
        ushort ret = 0;
        if (curLoad > 0) { ret |= LOAD_HIGH; }
        else { ret |= LOAD_LOW; }
        if ((curLoad > 0) != (oldLoad > 0)) {
            // one of the flanks is active
            if (curLoad > 0) { ret |= LOAD_FLANK_RISING; }
            else { ret |= LOAD_FLANK_FALLING; }
        }

        if (curInvuln > 0) { ret |= INVUL_HIGH; }
        else { ret |= INVUL_LOW; }
        if ((curInvuln > 0) != (oldInvuln > 0)) {
            // one of the flanks is active
            if (curInvuln > 0) { ret |= INVUL_FLANK_RISING; }
            else { ret |= INVUL_FLANK_FALLING; }
        }

        if ((curSaveTgl > 0) != (oldSaveTgl > 0)) {
            ret |= SAVETGL;
        }
        return ret;
    };
    vars.CalcFlags = CalcFlags;

    Func<double[], bool> CheckSingleGameCondition = (dataVec) => {
        ushort type = (ushort)(dataVec[0]);
        if (!vars.CheckFlags(type, vars.currentFlags)) { return false; }
        bool passedMem = true;
        if ((type & MEMORYCHECK) > 0)
        {
            uint idxMemList = (uint)(dataVec[1]);
            passedMem = false;
            if (idxMemList < vars.memoryDB.Count && vars.memoryDB[idxMemList].Update(game))
            {
                if((vars.memoryDB[idxMemList].Old > 0) != (vars.memoryDB[idxMemList].Current > 0))
                {
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
        else
        {
            return true;
        }
    };
    vars.CheckSingleGameCondition = CheckSingleGameCondition;

    vars.positionVec = new double[3];
    vars.positionVec[0] = -8000; // initialize somewhere outside
    vars.positionVec[1] = 0;
    vars.positionVec[2] = 0;

    vars.currentFlags = (ushort)0;

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
    settings.Add("ngp_overall", true, "NG+ Run");
    settings.Add("any_additional", false, "Any% additional");
    settings.Add("ngp_bs", false, "NG+ Burning Shores");
    settings.Add("100_bs", false, "100% Burning Shores (NG+) additional");


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

    vars.memoryDB = new MemoryWatcherList();
    Action<uint, uint> FillMemoryDB = (offsetSceneManagerGame, offsetGameModule) => {
        // 0
        //vars.memoryDB.Add()

        vars.DebugOutput("FillMemoryDB: " + vars.memoryDB.Count.ToString() + " memory watchers entered.");
    };
    vars.FillMemoryDB = FillMemoryDB;

    // ------------------------------------------------------------------
    // Data definition end
    // ------------------------------------------------------------------


    vars.splittingData = new List<Tuple<uint,int>>();
    vars.splittingData.Capacity = vars.splittingDB.Length;
    Action ArmSplittingData = () => {
        vars.splittingData.Clear();
        for ( uint i = 0 ; i < vars.splittingDB ; ++i )
        {
            if (!settings[vars.splittingDB[i].Item1]) { continue; }
            vars.splittingData.Add(
                new Tuple<uint,int>(i, 0)
            );
        }
        vars.DebugOutput("ArmSplittingData: " + vars.splittingData.Count.ToString() + " splits active");
    };
    vars.ArmSplittingData = ArmSplittingData;

}

init
{
    var module = modules.Single(x => String.Equals(x.ModuleName, "HorizonForbiddenWest.exe", StringComparison.OrdinalIgnoreCase));
    // No need to catch anything here because LiveSplit wouldn't have attached itself to the process if the name wasn't present

    var moduleSize = module.ModuleMemorySize;
    var hash = vars.CalcModuleHash(module);
    vars.DebugOutput(module.ModuleName + ": Module Size " + moduleSize + ", SHA256 Hash " + hash);

    uint offsetGameModule = 0x08983150;
    uint offsetSceneManagerGame = 0x08982DD0;

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
}


update{
    if (current.aobPosition != null) // positions retain their old value on RFS to not trigger out of bounds checks for some splits
    {
        Buffer.BlockCopy(current.aobPosition, 0, vars.positionVec, 0, 24);
    }
    vars.currentFlags = vars.CalcFlags(old.loading, current.loading, old.invulnerable, current.invulnerable, old.saveToggle, current.saveToggle);
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
    for (int i = 0 ; i < vars.startingDB.Count ; ++i)
    {
        if (settings[vars.startingDB[i].Item1])
        {
            if (vars.CheckSingleGameCondition(vars.startingDB[i].Item2))
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
            if (vars.CheckSingleGameCondition(vars.splittingDB[idxDB].Item3[j]))
            {
                vars.DebugOutput("Subsplit: " + vars.splittingDB[idxDB].Item1 + " , condition " + j.ToString());
                vars.splittingData[i].Item2++;
            }
        }
        if (j == vars.splittingDB[idxDB].Item2)
        {
            vars.splittingData[i].Item2 = -1;
            vars.InfoOutput("SPLIT: " + vars.splittingDB[idxDB].Item1);
            retVal = true;
        }
    }
    return retVal;
}

onStart{
    vars.ArmSplittingData();
}

onReset{
    vars.splittingData.Clear();
}

isLoading
{
    return (current.loading > 0);
}

exit
{
    timer.IsGameTimePaused = false;
    vars.memoryDB.Clear();
}

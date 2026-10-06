/**
 * FALLBACK FindFile path helper for DayZ 1.29 + 1.30 (server side), for mods WITHOUT a Community Framework
 * dependency. If your mod uses CF, call CF.FindFileEx instead (CF-Test now, part of CF from 1.30).
 *
 * This is a port of CF-Test's CF.FindFileEx / CF.ResolvePath (Workshop 1625463737, built 2026-10-06), so mods with
 * and without CF behave the same. Copy into your mod's 3_Game folder and replace YOURMOD with your mod's prefix.
 * Wrap every FindFile() pattern with it:
 *
 *     string fileName;
 *     FileAttr attr;
 *     FindFileHandle h = FindFile(YOURMOD_FindFilePath("$profile:YOURMOD/*.json"), fileName, attr, FindFileFlags.ALL);
 *
 * Behavior (identical to CF-Test):
 * - Backslashes are always turned into forward slashes (1.30 FindFile finds nothing with backslashes).
 * - 1.29 (DAYZ_1_29): nothing else changes, the pattern is passed through.
 * - 1.30: bug DZEXP-134 makes FindFile ignore "$profile:", "$mission:", "$storage:", "$saves:" and list the server's
 *   working directory instead. On the first call the helper writes "$profile:yourmod_findfile_dz130_test" once and
 *   tries to FindFile it; only if that fails are the placeholders resolved. A fixed engine needs no workaround.
 * - Resolved paths are relative to the server folder, so the profile folder (-profiles=<dir>), the mission folder
 *   and a -storage=<dir> must be INSIDE the server executable's folder (a symlink there works). An absolute
 *   -profiles=/x/y is reduced to its last component ("y") and looked up in the server folder. Start the server with
 *   -profiles=<folder in the server folder>.
 * - "$profile:" <- -profiles; "$saves:" <- <profile>/Users/Server; "$mission:" <- mission path, else -mission=,
 *   else the "Missions DayZ template" of -config=, else a guess from the world name (mpmissions/dayzOffline.<world>...);
 *   "$storage:" <- (-storage= else the mission folder)/storage_<instanceId>; "$currentdir:" is stripped.
 * - OpenFile, FileExist, MakeDirectory, CopyFile, DeleteFile and JsonFileLoader still accept the placeholders
 *   (and either slash) on 1.30. Only FindFile needs this helper.
 *
 * Difference to CF on purpose: problems are reported with Print(), not ErrorEx(), because on diag builds (every
 * experimental server) an Error() becomes a Virtual Machine Exception.
 */

class YOURMOD_FindFileState
{
	static bool s_Tested;
	static bool s_Resolve;
	static string s_MissionFolder;
	static string s_ProfileFolder;
	static string s_SavesFolder;
	static string s_StorageFolder;
}

//! Value of a directory CLI parameter (-profiles, -storage) as CF reads it: forward slashes, no trailing slash,
//! an absolute path reduced to its last component.
static string YOURMOD_CliDir(string param)
{
	string dir;
	if (!GetCLIParam(param, dir))
		return "";
	dir.Replace("\\", "/");
	while (dir.Length() > 1 && dir.Get(dir.Length() - 1) == "/")
		dir = dir.Substring(0, dir.Length() - 1);

	bool absolute = dir.Length() > 0 && dir.Get(0) == "/";
	if (dir.Length() > 1 && dir.Get(1) == ":")
		absolute = true;	//! drive letter
	if (absolute)
	{
		int idx = dir.LastIndexOf("/");
		dir = dir.Substring(idx + 1, dir.Length() - idx - 1);
	}
	return dir;
}

static string YOURMOD_ResolveMissionFolder()
{
	//! GetMissionPath() is "" during early init (the engine sets it at mission creation).
	//! Not GetMissionFolderPath(): it only splits on '\' and returns "" on both 1.29 and 1.30 servers.
	string folder = g_Game.GetMissionPath();
	if (folder != "")
	{
		folder.Replace("\\", "/");
		int idx = folder.LastIndexOf("/");	//! strip "/mission.c"
		if (idx > -1)
			folder = folder.Substring(0, idx);
		return folder;
	}

	if (GetCLIParam("mission", folder))
	{
		folder.Replace("\\", "/");
		while (folder.Length() > 1 && folder.Get(folder.Length() - 1) == "/")
			folder = folder.Substring(0, folder.Length() - 1);
		return folder;
	}

	string configParam;
	if (GetCLIParam("config", configParam) && FileExist(configParam))
	{
		//! No ConfigFile in vanilla 3_Game (CF ships its own parser): read the template="..."; line ourselves
		FileHandle cfg = OpenFile(configParam, FileMode.READ);
		if (cfg)
		{
			string line;
			while (FGets(cfg, line) >= 0)
			{
				int eq = line.IndexOf("template");
				int q1 = line.IndexOf("\"");
				if (eq < 0 || q1 < eq)
					continue;
				string rest = line.Substring(q1 + 1, line.Length() - q1 - 1);
				int q2 = rest.IndexOf("\"");
				if (q2 > 0)
				{
					folder = rest.Substring(0, q2);
					break;
				}
			}
			CloseFile(cfg);
		}
		//! The template is a bare folder name; CF uses it as is (and then misses the folder), we add mpmissions/
		if (folder != "" && folder.IndexOf("/") < 0)
			folder = "mpmissions/" + folder;
		if (folder != "")
			return folder;
	}

	//! Best guess from the world name
	string worldName;
	g_Game.GetWorldName(worldName);
	TStringArray candidates = {"dayzOffline", "empty", "hardcore", "main", "offline", "regular", "summer"};
	foreach (string candidate: candidates)
	{
		string path = string.Format("mpmissions/%1.%2", candidate, worldName);
		if (FileExist(path))
			return path;
	}
	return "";
}

//! Prefix resolver, equivalent to CF.ResolvePath. Result is relative to the server folder.
static string YOURMOD_ResolvePath(string path)
{
	path.Replace("\\", "/");

	string lower = path;
	lower.ToLower();

	if (lower.IndexOf("$currentdir:") == 0)
		return path.Substring(12, path.Length() - 12);

	if (lower.IndexOf("$profile:") == 0 || lower.IndexOf("$saves:") == 0)
	{
		if (YOURMOD_FindFileState.s_ProfileFolder == "")
		{
			string profile = YOURMOD_CliDir("profiles");
			if (profile == "")
				Print("[YOURMOD] WARNING: could not determine the profile folder, please use the -profiles parameter");
			else if (!FileExist(profile))
				Print("[YOURMOD] WARNING: profile folder " + profile + " does not exist inside the server folder");
			YOURMOD_FindFileState.s_ProfileFolder = profile;
		}

		string profileRoot = YOURMOD_FindFileState.s_ProfileFolder;
		if (profileRoot == "")
			return path;

		if (lower.IndexOf("$profile:") == 0)
			return profileRoot + "/" + path.Substring(9, path.Length() - 9);

		if (YOURMOD_FindFileState.s_SavesFolder == "")
			YOURMOD_FindFileState.s_SavesFolder = profileRoot + "/Users/Server";
		return YOURMOD_FindFileState.s_SavesFolder + "/" + path.Substring(7, path.Length() - 7);
	}

	if (lower.IndexOf("$mission:") == 0 || lower.IndexOf("$storage:") == 0)
	{
		if (YOURMOD_FindFileState.s_MissionFolder == "")
		{
			string mission = YOURMOD_ResolveMissionFolder();
			if (mission == "")
				Print("[YOURMOD] WARNING: could not determine the mission folder, please use the -mission parameter");
			else if (!FileExist(mission))
				Print("[YOURMOD] WARNING: mission folder " + mission + " does not exist inside the server folder");
			YOURMOD_FindFileState.s_MissionFolder = mission;
		}

		string missionRoot = YOURMOD_FindFileState.s_MissionFolder;
		if (missionRoot == "")
			return path;

		if (lower.IndexOf("$mission:") == 0)
			return missionRoot + "/" + path.Substring(9, path.Length() - 9);

		if (YOURMOD_FindFileState.s_StorageFolder == "")
		{
			string storageRoot = YOURMOD_CliDir("storage");
			if (storageRoot == "")
				storageRoot = missionRoot;
			YOURMOD_FindFileState.s_StorageFolder = string.Format("%1/storage_%2", storageRoot, g_Game.ServerConfigGetInt("instanceId"));
		}
		return YOURMOD_FindFileState.s_StorageFolder + "/" + path.Substring(9, path.Length() - 9);
	}

	return path;
}

//! Use as the pattern argument of FindFile(), like CF.FindFileEx does internally.
static string YOURMOD_FindFilePath(string pattern)
{
	pattern.Replace("\\", "/");

#ifndef DAYZ_1_29
	if (!YOURMOD_FindFileState.s_Tested)
	{
		//! Is FindFile fixed? Test with a file we create in the profile.
		string testName = "yourmod_findfile_dz130_test";
		string testPath = "$profile:" + testName;
		if (!FileExist(testPath))
		{
			FileHandle testFile = OpenFile(testPath, FileMode.WRITE);
			if (testFile)
				CloseFile(testFile);
		}

		string foundName;
		FileAttr foundAttr;
		FindFileHandle testHandle = FindFile(testPath, foundName, foundAttr, FindFileFlags.ALL);
		if (!testHandle || foundName != testName)
			YOURMOD_FindFileState.s_Resolve = true;
		if (testHandle)
			CloseFindFile(testHandle);

		YOURMOD_FindFileState.s_Tested = true;
	}

	if (YOURMOD_FindFileState.s_Resolve)
		pattern = YOURMOD_ResolvePath(pattern);
#endif

	return pattern;
}

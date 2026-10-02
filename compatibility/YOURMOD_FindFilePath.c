/**
 * FindFile path helper for DayZ 1.29 + 1.30 (server side).
 *
 * Copy into your mod's 3_Game folder and replace YOURMOD with your mod's unique prefix.
 * Wrap every FindFile() pattern with it:
 *
 *     string fileName;
 *     FileAttr attr;
 *     FindFileHandle h = FindFile(YOURMOD_FindFilePath("$profile:YOURMOD/*.json"), fileName, attr, FindFileFlags.ALL);
 *
 * Why (verified on 1.29.163709 and 1.30.164014 experimental servers, see version-130.md):
 * - 1.30 FindFile ignores "$profile:", "$mission:", "$storage:", "$saves:" and silently searches the
 *   server's working directory instead (bug DZEXP-134). It also finds nothing when the path uses
 *   backslashes. Relative and absolute paths with forward slashes work.
 * - "$storage:" never worked with FindFile on a server, not even on 1.29, so it is resolved on both.
 * - OpenFile, FileExist, MakeDirectory, CopyFile, DeleteFile and JsonFileLoader still accept the
 *   placeholders (and either slash) on 1.30. Only FindFile needs this helper.
 *
 * Limits: "$profile:" is resolved from -profiles=<dir>; without that parameter it cannot be resolved
 * on 1.30. "$saves:" cannot be resolved at all. "$storage:" with an absolute -storage=<dir> does not
 * work on 1.29, where FindFile rejects absolute paths.
 *
 * Based on lava76's YOURMOD_FindFile_DZEXP134_Helper gist, minus its serverDZ.cfg parsing (which
 * broke on the stock config's trailing comment) and its Error() calls (VM exceptions on diag builds).
 */

//! "mpmissions/dayzOffline.chernarusplus/mission.c" -> "mpmissions/dayzOffline.chernarusplus".
//! Not g_Game.GetMissionFolderPath(): it only splits on '\' and returns "" on both 1.29 and 1.30 servers.
static string YOURMOD_MissionFolder()
{
	string path = g_Game.GetMissionPath();
	path.Replace("\\", "/");
	int idx = path.LastIndexOf("/");
	if (idx < 0)
		return "";
	return path.Substring(0, idx);
}

static string YOURMOD_FindFilePath(string pattern)
{
	pattern.Replace("\\", "/");

	string lower = pattern;
	lower.ToLower();

	string root;
	int cut = -1;
	if (lower.IndexOf("$storage:") == 0)
	{
		cut = 9;
		//! -storage=<dir> moves the storage_<instanceId> folder out of the mission folder
		if (!GetCLIParam("storage", root))
			root = YOURMOD_MissionFolder();
		if (root != "")
			root = string.Format("%1/storage_%2", root, g_Game.ServerConfigGetInt("instanceId"));
	}
#ifndef DAYZ_1_29
	else if (lower.IndexOf("$profile:") == 0)
	{
		cut = 9;
		GetCLIParam("profiles", root);
	}
	else if (lower.IndexOf("$mission:") == 0)
	{
		cut = 9;
		root = YOURMOD_MissionFolder();
	}
	else if (lower.IndexOf("$currentdir:") == 0)
	{
		return pattern.Substring(12, pattern.Length() - 12);
	}
#endif

	if (cut < 0)
		return pattern;

	if (root == "")
	{
		//! Not ErrorEx/Error: on diag builds (every experimental server) those become VM exceptions
		Print("[YOURMOD] WARNING: cannot resolve " + pattern + " for FindFile (start the server with -profiles=<dir>)");
		return pattern;
	}

	root.Replace("\\", "/");
	if (root.Length() > 0 && root.Get(root.Length() - 1) == "/")
		root = root.Substring(0, root.Length() - 1);

	return root + "/" + pattern.Substring(cut, pattern.Length() - cut);
}

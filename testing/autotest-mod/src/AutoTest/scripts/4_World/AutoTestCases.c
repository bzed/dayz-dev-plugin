// One test = one class. The same PBO is loaded on server and client, so both sides know every
// test by name. The server drives the order; the client only runs what it is told to.
class AutoTestCase
{
	string Name() { return ""; }

	// Server half: runs first, on the server, before the client is asked to check anything.
	void ServerSetup(PlayerBase player) {}

	// Client half: runs on the client. Return false to be retried for a few seconds (server-side
	// changes need a moment to replicate), then reported as a failure with msg.
	bool ClientCheck(out string msg)
	{
		msg = "";
		return true;
	}
}

// Client half only: the local player exists and is the right class.
class AutoTestClientHasPlayer : AutoTestCase
{
	override string Name() { return "client_has_player"; }

	override bool ClientCheck(out string msg)
	{
		PlayerBase p = PlayerBase.Cast(GetGame().GetPlayer());
		if (!p)
		{
			msg = "no local player";
			return false;
		}
		msg = "local player " + p.GetType();
		return true;
	}
}

// Server half changes the world, client half sees it: the item the server creates has to show up
// in the inventory the client has replicated.
class AutoTestServerItemSynced : AutoTestCase
{
	override string Name() { return "server_item_synced"; }

	override void ServerSetup(PlayerBase player)
	{
		player.GetInventory().CreateInInventory("Chemlight_Red");
	}

	override bool ClientCheck(out string msg)
	{
		PlayerBase p = PlayerBase.Cast(GetGame().GetPlayer());
		if (!p)
		{
			msg = "no local player";
			return false;
		}
		array<EntityAI> items = new array<EntityAI>;
		p.GetInventory().EnumerateInventory(InventoryTraversalType.PREORDER, items);
		foreach (EntityAI e : items)
		{
			if (e.GetType() == "Chemlight_Red")
			{
				msg = "Chemlight_Red replicated to the client";
				return true;
			}
		}
		msg = "Chemlight_Red not in the client's inventory";
		return false;
	}
}

class AutoTestRegistry
{
	static ref array<ref AutoTestCase> s_Cases;

	// Order matters: the server runs them in this order. Add new tests here.
	static array<ref AutoTestCase> All()
	{
		if (!s_Cases)
		{
			s_Cases = new array<ref AutoTestCase>;
			s_Cases.Insert(new AutoTestClientHasPlayer());
			s_Cases.Insert(new AutoTestServerItemSynced());
		}
		return s_Cases;
	}

	static AutoTestCase Find(string name)
	{
		array<ref AutoTestCase> all = All();
		for (int i = 0; i < all.Count(); i++)
		{
			if (all.Get(i).Name() == name)
				return all.Get(i);
		}
		return null;
	}
}

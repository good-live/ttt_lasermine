
/* /////////////////////////////////
// ______________  ___________ 
// \______   \   \/  /  _____/ 
//  |       _/\     /   \  ___ 
//  |    |   \/     \    \_\  \
//  |____|_  /___/\  \______  /
//         \/      \_/      \/
//     R E F L E X  -  G A M E R S
*/

#include <sourcemod>
#include <sdktools>
#include <ttt>

#pragma semicolon 1

//
// Changelog:
// 15:27 PM 03/10/2016 - 1.0.5
//	 Converting to 1.7 Syntax and adding it to TTT - good_live
// 11:48 PM 11/30/2012 - 1.0.4
//   default mines to 3
//   team filtering option
//   finer laser texture (less aliasing)
// 1:23 PM 10/30/2012 - 1.0.3beta
//   silent defusal
//   reduced defuse time (3->2 seconds)
// 5:29 PM 10/29/2012 - 1.0.2beta
//   mine defusal
// 10:37 PM 10/28/2012 - 1.0.1beta
//   reduced explosion sound volume
//   throttled explosion sounds (1 per 0.1 seconds)
//   proper explosion sound panning
//   placement on windows
// 4:12 PM 10/27/2012 - 1.0.0beta
//   initial release

//----------------------------------------------------------------------------------------------------------------------

#define SOUND_PLACE		"weapons/g3sg1/g3sg1_slideback.wav"
#define SOUND_ARMING	"weapons/c4/c4_beep1.wav"     // UI/beep07.wav
#define SOUND_ARMED		"items/nvg_on.wav"
#define SOUND_DEFUSE	"weapons/c4/c4_disarm.wav"

//----------------------------------------------------------------------------------------------------------------------

#define MODEL_MINE		"models/tripmine/tripmine.mdl" 
#define MODEL_BEAM		"materials/sprites/purplelaser1.vmt"

#define LASER_WIDTH		0.6//0.12

//#define LASER_COLOR_T	"254 218 92"
//#define LASER_COLOR_T	"128 109 46"
#define LASER_COLOR_T	"104 167 72"
#define LASER_COLOR_CT	"38 75 251"
#define LASER_COLOR_D	"38 251 42"

//----------------------------------------------------------------------------------------------------------------------

//
// the distances for the placement traceray from the client's eyes
//
#define TRACE_START		1.0
#define TRACE_LENGTH	80.0

//----------------------------------------------------------------------------------------------------------------------

#define COMMAND			"mine"
#define ALTCOMMAND		"buyammo2"

//----------------------------------------------------------------------------------------------------------------------
public Plugin myinfo =  {
	name = "TTT - Tripmines", 
	author = "good_live (reflex-gaming)", 
	description = "Tripmines for the TTT mod from Bara", 
	version = "1.0.5", 
	url = "painlessgaming.eu"
};

//----------------------------------------------------------------------------------------------------------------------
ConVar sm_pp_minedmg; // damage of the mines
ConVar sm_pp_minerad; // radius override for explosion (0=disable)
ConVar sm_pp_minefilter; // detonation mode
ConVar sm_pp_name; // name of the tripmines in the Traitor Shop
ConVar sm_pp_price; // price of the tripmines in the Traitor Shop
ConVar sm_pp_mode;

int g_iMines[MAXPLAYERS + 1]; // number of mines per player

int g_iMine_counter = 0;

bool explosion_sound_enable = true;

int g_iLast_Mine;

int g_iDefuse_Time[MAXPLAYERS + 1];
int g_iDefuse_Target[MAXPLAYERS + 1];
float g_fDefuse_Position[MAXPLAYERS + 1][3];
float g_fDefuse_Angles[MAXPLAYERS + 1][3];
bool g_bDefuse_Cancelled[MAXPLAYERS + 1];
int g_iDefuse_Userid[MAXPLAYERS + 1];

#define DEFUSE_ANGLE_THRESHOLD 5.0  // 5 degrees
#define DEFUSE_POSITION_THRESHOLD 1.0 // 1 unit

int minefilter;

//----------------------------------------------------------------------------------------------------------------------
public OnPluginStart() {
	
	TTT_IsGameCSGO();
	
	sm_pp_minedmg = CreateConVar("tp_minedmg", "100", "damage (magnitude) of the tripmines", FCVAR_PLUGIN);
	sm_pp_minerad = CreateConVar("tp_minerad", "0", "override for explosion damage radius", FCVAR_PLUGIN);
	sm_pp_minefilter = CreateConVar("tp_minefilter", "0", "0 = detonate when laser touches anyone, 1 = enemies and owner only, 2 = enemies only", FCVAR_PLUGIN);
	
	sm_pp_name = CreateConVar("tp_name", "Tripmine", "Name of the Tripmines in the shop."); // name of the tripmines in the Traitor Shop
	sm_pp_price = CreateConVar("tp_price", "5000", "Price of the Tipmines in the shop set it to 0 to disable"); // price of the tripmines in the Traitor Shop
	sm_pp_mode = CreateConVar("tp_mode", "1", "Mode of the Tripmines 0 = Everybody, 1 = T Only, 2 = D Only, 3 = T and D");
	
	HookEvent("round_start", Event_RoundStart);
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("player_use", Event_PlayerUse);
	
	HookConVarChange(sm_pp_minefilter, CVarChanged_minefilter);
	
	RegConsoleCmd(COMMAND, Command_Mine);
	
	if (strlen(ALTCOMMAND) != 0) {
		RegConsoleCmd(ALTCOMMAND, Command_Mine);
	}
	
	minefilter = sm_pp_minefilter.IntValue;
	
	
}

public void OnAllPluginsLoaded()
{
	if (sm_pp_price.IntValue == 0)
		return;
	
	char sName[32];
	sm_pp_name.GetString(sName, sizeof(sName));
	
	if (strlen(sName) <= 0)
		return;
	
	if (sm_pp_mode.IntValue == 0)
	{
		TTT_RegisterCustomItem("tripmine_i", sName, sm_pp_price.IntValue, TTT_TEAM_INNOCENT);
		TTT_RegisterCustomItem("tripmine_t", sName, sm_pp_price.IntValue, TTT_TEAM_TRAITOR);
		TTT_RegisterCustomItem("tripmine_d", sName, sm_pp_price.IntValue, TTT_TEAM_DETECTIVE);
	} else if (sm_pp_mode.IntValue == 1) {
		TTT_RegisterCustomItem("tripmine_t", sName, sm_pp_price.IntValue, TTT_TEAM_TRAITOR);
	} else if (sm_pp_mode.IntValue == 2) {
		TTT_RegisterCustomItem("tripmine_d", sName, sm_pp_price.IntValue, TTT_TEAM_DETECTIVE);
	} else if (sm_pp_mode.IntValue == 3) {
		TTT_RegisterCustomItem("tripmine_t", sName, sm_pp_price.IntValue, TTT_TEAM_TRAITOR);
		TTT_RegisterCustomItem("tripmine_d", sName, sm_pp_price.IntValue, TTT_TEAM_DETECTIVE);
	}
	
}

public Action TTT_OnItemPurchased(int client, const char[] itemshort)
{
	if (TTT_IsClientValid(client) && IsPlayerAlive(client))
	{
		if ((strcmp(itemshort, "tripmine_d", false) == 0) || (strcmp(itemshort, "tripmine_t", false) == 0) || (strcmp(itemshort, "tripmine_i", false) == 0))
			g_iMines[client]++;
	}
	return Plugin_Continue;
}

public Action TTT_OnRoundStart_Pre()
{
	ResetMines();
	return Plugin_Continue;
}

public void TTT_OnRoundStartFailed(int p, int r, int d)
{
	ResetMines();
}

public void TTT_OnRoundStart(int i, int t, int d)
{
	ResetMines();
}

public void TTT_OnClientDeath(int v, int a)
{
	g_iMines[v] = 0;
}

public void Event_RoundEnd(Handle event, const char[] name, bool dontBroadcast) {
	ResetMines();
}

public void ResetMines()
{
	LoopValidClients(i) {
		g_iMines[i] = 0;
	}
}

//----------------------------------------------------------------------------------------------------------------------
//
// precache models and sounds during map load
//
public OnMapStart() {
	
	// PRECACHE SOUNDS
	PrecacheSound(SOUND_PLACE, true);
	PrecacheSound(SOUND_ARMING, true);
	PrecacheSound(SOUND_ARMED, true);
	PrecacheSound(SOUND_DEFUSE, true);
	
	// PRECACHE MODELS
	PrecacheModel(MODEL_MINE);
	PrecacheModel(MODEL_BEAM, true);
	
	AddFileToDownloadsTable("models/tripmine/tripmine.dx90.vtx");
	AddFileToDownloadsTable("models/tripmine/tripmine.mdl");
	AddFileToDownloadsTable("models/tripmine/tripmine.phy");
	AddFileToDownloadsTable("models/tripmine/tripmine.vvd");
	
	AddFileToDownloadsTable("materials/models/tripmine/minetexture.vmt");
	AddFileToDownloadsTable("materials/models/tripmine/minetexture.vtf");
	
	PrecacheSound("weapons/hegrenade/explode3.wav");
	PrecacheSound("weapons/hegrenade/explode4.wav");
	PrecacheSound("weapons/hegrenade/explode5.wav");
}

//----------------------------------------------------------------------------------------------------------------------
public bool IsValidClient(client) {
	return (client > 0 && client <= MaxClients && IsClientInGame(client));
}


public void CVarChanged_minefilter(Handle cvar, const char[] oldval, const char[] newval) {
	if (strcmp(oldval, newval) == 0)return;
	
	minefilter = sm_pp_minefilter.IntValue;
}


//----------------------------------------------------------------------------------------------------------------------
//
// restore mines on round start
//
public void Event_RoundStart(Handle event, const char[] name, bool dontBroadcast) {
	g_iMine_counter = 0;
	explosion_sound_enable = true;
}

//----------------------------------------------------------------------------------------------------------------------
public void OnClientDisconnect(int client) {
	DeletePlacedMines(client);
}

//----------------------------------------------------------------------------------------------------------------------
public void DeletePlacedMines(int client) {
	int ent = -1;
	char name[32];
	while ((ent = FindEntityByClassname(ent, "prop_physics_override")) != -1) {
		GetEntPropString(ent, Prop_Data, "m_iName", name, 32);
		if (strncmp(name, "rxgtripmine", 11, true) == 0) {
			if (GetEntPropEnt(ent, Prop_Data, "m_hLastAttacker") == client) {  // slight hack here, cant use owner entity because it wont allow the owner to destroy his own mines.
				AcceptEntityInput(ent, "Kill");
			}
		}
	}
	
	while ((ent = FindEntityByClassname(ent, "env_beam")) != -1) {
		GetEntPropString(ent, Prop_Data, "m_iName", name, 32);
		if (strncmp(name, "rxgtripmine", 11, true) == 0) {
			if (GetEntPropEnt(ent, Prop_Data, "m_hOwnerEntity") == client) {
				AcceptEntityInput(ent, "Kill");
			}
		}
	}
}

//----------------------------------------------------------------------------------------------------------------------
public Action Command_Mine(int client, int args) {
	if (IsClientConnected(client)) {
		if (IsPlayerAlive(client)) {
			if (g_iMines[client] > 0) {
				PlaceMine(client);
			}
		}
	}
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------------------------
public void PlaceMine(int client) {
	
	
	float trace_start[3], trace_angle[3], trace_end[3], trace_normal[3];
	GetClientEyePosition(client, trace_start);
	GetClientEyeAngles(client, trace_angle);
	GetAngleVectors(trace_angle, trace_end, NULL_VECTOR, NULL_VECTOR);
	NormalizeVector(trace_end, trace_end); // end = normal
	
	// offset start by near point
	for (int i = 0; i < 3; i++)
	trace_start[i] += trace_end[i] * TRACE_START;
	
	for (int i = 0; i < 3; i++)
	trace_end[i] = trace_start[i] + trace_end[i] * TRACE_LENGTH;
	
	TR_TraceRayFilter(trace_start, trace_end, CONTENTS_SOLID | CONTENTS_WINDOW, RayType_EndPoint, TraceFilter_All, 0);
	
	if (TR_DidHit(INVALID_HANDLE)) {
		g_iMines[client]--;
		
		if (g_iMines[client] != 0) {
			PrintCenterText(client, "You have %d mines left!", g_iMines[client]);
		} else {
			PrintCenterText(client, "That was your last mine!");
		}
		
		TR_GetEndPosition(trace_end, INVALID_HANDLE);
		TR_GetPlaneNormal(INVALID_HANDLE, trace_normal);
		
		SetupMine(client, trace_end, trace_normal);
		
	} else {
		PrintCenterText(client, "Invalid mine position.");
	}
}

//----------------------------------------------------------------------------------------------------------------------
//
// filter out mine placement on anything but the map
//
public bool TraceFilter_All(entity, contentsMask) {
	return false;
}

//----------------------------------------------------------------------------------------------------------------------
public void MineLaser_OnTouch(const char[] output, caller, activator, float delay) {
	
	AcceptEntityInput(caller, "TurnOff");
	AcceptEntityInput(caller, "TurnOn");
	
	if (!IsValidClient(activator))
		return;
	
	if (!IsPlayerAlive(activator))
		return;
	
	bool detonate = false;
	
	
	if (minefilter == 1 || minefilter == 2) {
		// detonate if enemy or owner
		int owner = GetEntPropEnt(caller, Prop_Data, "m_hOwnerEntity");
		
		if (!IsValidClient(owner)) {
			// something went wrong, bypass test
			detonate = true;
		} else {
			int team = GetClientTeam(owner);
			if (GetClientTeam(activator) != team || (owner == activator && minefilter == 1)) {
				detonate = true;
			}
		}
	} else if (minefilter == 0) {
		// detonate always
		detonate = true;
	}
	
	
	if (TTT_GetClientRole(activator) == TTT_TEAM_TRAITOR)
		detonate = false;
	
	if (detonate) {
		char targetname[64];
		GetEntPropString(caller, Prop_Data, "m_iName", targetname, sizeof(targetname));
		
		char buffers[2][32];
		
		ExplodeString(targetname, "_", buffers, 2, 32);
		
		int ent_mine = StringToInt(buffers[1]);
		
		AcceptEntityInput(ent_mine, "break");
		
	}
	
	return;
}

//----------------------------------------------------------------------------------------------------------------------
public void SetupMine(int client, float position[3], float normal[3]) {
	
	char mine_name[64];
	char beam_name[64];
	char str[128];
	
	Format(mine_name, 64, "rxgtripmine%d", g_iMine_counter);
	
	
	float angles[3];
	GetVectorAngles(normal, angles);
	
	
	int ent = CreateEntityByName("prop_physics_override");
	
	Format(beam_name, 64, "rxgtripmine%d_%d", g_iMine_counter, ent);
	
	DispatchKeyValue(ent, "model", MODEL_MINE);
	DispatchKeyValue(ent, "physdamagescale", "0.0"); // enable this to destroy via physics?
	DispatchKeyValue(ent, "health", "1"); // use the set entity health function instead ?
	DispatchKeyValue(ent, "targetname", mine_name);
	DispatchKeyValue(ent, "spawnflags", "256"); // set "usable" flag
	DispatchSpawn(ent);
	
	SetEntityMoveType(ent, MOVETYPE_NONE);
	SetEntProp(ent, Prop_Data, "m_takedamage", 2);
	SetEntPropEnt(ent, Prop_Data, "m_hLastAttacker", client); // use this to identify the owner (see below)
	//SetEntPropEnt(ent, Prop_Data, "m_hOwnerEntity",client); //Set the owner of the mine (cant, it stops the owner from destroying it)
	SetEntityRenderColor(ent, 255, 255, 255, 255);
	SetEntProp(ent, Prop_Send, "m_CollisionGroup", 2); // set non-collidable
	
	
	
	// when the mine is broken, delete the laser beam
	Format(str, sizeof(str), "%s,Kill,,0,-1", beam_name);
	DispatchKeyValue(ent, "OnBreak", str);
	
	// hook to explosion function
	HookSingleEntityOutput(ent, "OnBreak", MineBreak, true);
	
	HookSingleEntityOutput(ent, "OnPlayerUse", MineUsed, false);
	
	// offset placement slightly so it is on the wall's surface
	for (new i = 0; i < 3; i++) {
		position[i] += normal[i] * 0.5;
	}
	TeleportEntity(ent, position, angles, NULL_VECTOR); //angles, NULL_VECTOR );
	
	// trace ray for laser (allow passage through windows)
	TR_TraceRayFilter(position, angles, CONTENTS_SOLID, RayType_Infinite, TraceFilter_All);
	
	float beamend[3];
	TR_GetEndPosition(beamend, INVALID_HANDLE);
	
	// create beam
	int ent_laser = CreateLaser(beamend, position, beam_name, GetClientTeam(client));
	
	// when touched, activate/break the mine
	
	HookSingleEntityOutput(ent_laser, "OnTouchedByEntity", MineLaser_OnTouch);
	
	
	
	SetEntPropEnt(ent_laser, Prop_Data, "m_hOwnerEntity", client); //Set the owner of the mine's beam
	
	// timer for activating
	DataPack data = new DataPack();
	CreateDataTimer(1.0, ActivateTimer, data, TIMER_REPEAT);
	data.Reset();
	data.WriteCell(0);
	data.WriteCell(ent);
	data.WriteCell(ent_laser);
	
	PlayMineSound(ent, SOUND_PLACE);
	
	g_iMine_counter++;
}

//----------------------------------------------------------------------------------------------------------------------
public Action ActivateTimer(Handle timer, DataPack data) {
	data.Reset();
	
	int counter = data.ReadCell();
	int ent = data.ReadCell();
	int ent_laser = data.ReadCell();
	
	if (!IsValidEntity(ent)) {  // mine was broken (gunshot/grenade) before it was armed
		return Plugin_Stop;
	}
	
	if (counter < 3) {
		PlayMineSound(ent, SOUND_ARMING);
		counter++;
		ResetPack(data);
		WritePackCell(data, counter);
	} else {
		PlayMineSound(ent, SOUND_ARMED);
		
		// enable touch trigger and increase brightness
		DispatchKeyValue(ent_laser, "TouchType", "4");
		DispatchKeyValue(ent_laser, "renderamt", "220");
		
		
		return Plugin_Stop;
	}
	
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------------------------
public void PlayMineSound(entity, const char[] sound) {
	EmitSoundToAll(sound, entity);
}

//----------------------------------------------------------------------------------------------------------------------
public void MineBreak(const char[] output, caller, activator, float delay)
{
	float pos[3];
	GetEntPropVector(caller, Prop_Send, "m_vecOrigin", pos);
	
	// create explosion
	CreateExplosionDelayed(pos, GetEntPropEnt(caller, Prop_Data, "m_hLastAttacker"));
	
}

//----------------------------------------------------------------------------------------------------------------------
public Action DefuseTimer(Handle timer, any client) {
	int userid = g_iDefuse_Userid[client];
	int old_client = GetClientOfUserId(userid);
	
	if (!IsValidClient(old_client) || old_client != client)
		return Plugin_Stop; //Somebody else is defusing???
	
	
	if (g_bDefuse_Cancelled[client]) {
		g_iDefuse_Userid[client] = 0;
		return Plugin_Stop;
	}
	
	if (!IsValidEntity(g_iDefuse_Target[client])) {
		g_iDefuse_Userid[client] = 0;
		return Plugin_Stop;
	}
	
	bool player_moved = false;
	// VERIFY ANGLES
	float angles[3];
	
	
	GetClientEyeAngles(client, angles);
	for (new i = 0; i < 3; i++) {
		if (FloatAbs(angles[i] - g_fDefuse_Angles[client][i]) > DEFUSE_ANGLE_THRESHOLD) {
			player_moved = true;
			break;
		}
	}
	
	if (!player_moved) {
		float pos[3];
		GetClientAbsOrigin(client, pos);
		
		for (new i = 0; i < 3; i++) {
			pos[i] -= g_fDefuse_Position[client][i];
			pos[i] *= pos[i];
		}
		
		float dist = pos[0] + pos[1] + pos[2];
		
		if (dist >= (DEFUSE_POSITION_THRESHOLD * DEFUSE_POSITION_THRESHOLD)) {
			player_moved = true;
		}
	}
	
	if (player_moved) {
		PrintHintText(client, "Defusal Interrupted.");
		g_iDefuse_Userid[client] = 0;
		return Plugin_Stop;
	}
	
	
	g_iDefuse_Time[client]++;
	if (g_iDefuse_Time[client] < 5) {
		char message[16] = "Defusing.";
		
		for (new i = 0; i < g_iDefuse_Time[client]; i++)
		StrCat(message, 16, ".");
		
		PrintHintText(client, message);
	} else {
		
		EmitSoundToClient(client, SOUND_PLACE); //
		
		UnhookSingleEntityOutput(g_iDefuse_Target[client], "OnBreak", MineBreak);
		AcceptEntityInput(g_iDefuse_Target[client], "Break");
		
		g_iDefuse_Userid[client] = 0;
		return Plugin_Stop;
	}
	
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------------------------
public void StartDefusal(int client, int target) {
	if (g_iDefuse_Userid[client] != 0)return; // defusal already in progress
	
	PrintHintText(client, "Defusing.");
	
	g_iDefuse_Time[client] = 0;
	g_iDefuse_Target[client] = target;
	GetClientAbsOrigin(client, g_fDefuse_Position[client]);
	GetClientEyeAngles(client, g_fDefuse_Angles[client]);
	g_bDefuse_Cancelled[client] = false;
	g_iDefuse_Userid[client] = GetClientUserId(client);
	CreateTimer(1.0, DefuseTimer, client, TIMER_REPEAT);
	
	EmitSoundToClient(client, SOUND_DEFUSE);
}

//----------------------------------------------------------------------------------------------------------------------
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon) {
	
	if (!IsValidClient(client))return Plugin_Continue;
	
	if ((buttons & IN_USE) == 0) {
		
		if (g_iDefuse_Userid[client] && !g_bDefuse_Cancelled[client]) {  // is defuse in progress?
			g_bDefuse_Cancelled[client] = true;
			PrintHintText(client, "Defusal Cancelled.");
		}
	}
	
	if (!IsValidEntity(weapon))return Plugin_Continue;
	
	if (buttons & IN_ATTACK2 && g_iMines[client] > 0)
		Command_Mine(client, 0);
	
	return Plugin_Continue;
}

//----------------------------------------------------------------------------------------------------------------------
public void MineUsed(const char[] output, int caller, int activator, float delay)
{
	// register last mine touched
	g_iLast_Mine = caller;
}

//----------------------------------------------------------------------------------------------------------------------
public void Event_PlayerUse(Handle event, const char[] name, bool dontBroadcast) {
	
	int id = GetEventInt(event, "userid");
	int target = GetEventInt(event, "entity");
	
	if (g_iLast_Mine == target)
	{
		int client = GetClientOfUserId(id);
		if (client == 0) // client has disconnected
			return;
		
		StartDefusal(client, target);
	}
}

//----------------------------------------------------------------------------------------------------------------------
public CreateLaser(float start[3], float end[3], char[] name, int team)
{
	int ent = CreateEntityByName("env_beam");
	if (ent != -1)
	{
		
		char color[16];
		if (team == 2)color = LASER_COLOR_T;
		else if (team == 3)color = LASER_COLOR_CT;
		else color = LASER_COLOR_D;
		
		TeleportEntity(ent, start, NULL_VECTOR, NULL_VECTOR);
		SetEntityModel(ent, MODEL_BEAM); // This is where you would put the texture, ie "sprites/laser.vmt" or whatever.
		SetEntPropVector(ent, Prop_Data, "m_vecEndPos", end);
		DispatchKeyValue(ent, "targetname", name);
		DispatchKeyValue(ent, "rendercolor", color);
		DispatchKeyValue(ent, "renderamt", "80");
		DispatchKeyValue(ent, "decalname", "Bigshot");
		DispatchKeyValue(ent, "life", "0");
		DispatchKeyValue(ent, "TouchType", "0");
		DispatchSpawn(ent);
		SetEntPropFloat(ent, Prop_Data, "m_fWidth", LASER_WIDTH);
		SetEntPropFloat(ent, Prop_Data, "m_fEndWidth", LASER_WIDTH);
		ActivateEntity(ent);
		AcceptEntityInput(ent, "TurnOn");
	}
	
	return ent;
}

//----------------------------------------------------------------------------------------------------------------------
public void CreateExplosionDelayed(float vec[3], int owner) {
	
	DataPack data = new DataPack();
	CreateDataTimer(0.1, CreateExplosionDelayedTimer, data);
	
	data.Reset();
	data.WriteCell(owner);
	data.WriteFloat(vec[0]);
	data.WriteFloat(vec[1]);
	data.WriteFloat(vec[2]);
	
}

//----------------------------------------------------------------------------------------------------------------------
public Action CreateExplosionDelayedTimer(Handle timer, DataPack data) {
	
	data.Reset();
	int owner = data.ReadCell();
	
	float vec[3];
	vec[0] = data.ReadFloat();
	vec[1] = data.ReadFloat();
	vec[2] = data.ReadFloat();
	
	CreateExplosion(vec, owner);
	
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------------------------
public Action EnableExplosionSound(Handle timer) {
	explosion_sound_enable = true;
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------------------------
public CreateExplosion(float vec[3], owner) {
	int ent = CreateEntityByName("env_explosion");
	DispatchKeyValue(ent, "classname", "env_explosion");
	SetEntPropEnt(ent, Prop_Data, "m_hOwnerEntity", owner); //Set the owner of the explosion
	
	int mag = sm_pp_minedmg.IntValue;
	int rad = sm_pp_minerad.IntValue;
	SetEntProp(ent, Prop_Data, "m_iMagnitude", mag);
	if (rad != 0) {
		SetEntProp(ent, Prop_Data, "m_iRadiusOverride", rad);
	}
	
	DispatchSpawn(ent);
	ActivateEntity(ent);
	
	char exp_sample[64];
	
	Format(exp_sample, 64, ")weapons/hegrenade/explode%d.wav", GetRandomInt(3, 5));
	
	if (explosion_sound_enable) {
		explosion_sound_enable = false;
		EmitAmbientSound(exp_sample, vec, _, SNDLEVEL_GUNFIRE);
		CreateTimer(0.1, EnableExplosionSound);
	}
	
	TeleportEntity(ent, vec, NULL_VECTOR, NULL_VECTOR);
	AcceptEntityInput(ent, "explode");
	AcceptEntityInput(ent, "kill");
} 